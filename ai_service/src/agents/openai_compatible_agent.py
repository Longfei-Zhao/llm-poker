from typing import Dict, List, Optional, Tuple, Any
import logging
import time
from openai import AsyncOpenAI
from openai import AuthenticationError, RateLimitError, APIError as OpenAIAPIError
from .base_agent import BaseAgent
from ..exceptions import APIError, DecisionError
from ..config.agent_config import DEFAULT_EFFORT, LLM_TIMEOUT, get_api_base, get_default_model
from ..prompts.prompt_utils import build_prompt, extract_speech, parse_response
import re

# 设置日志
logger = logging.getLogger(__name__)

class OpenAICompatibleAgent(BaseAgent):
    """
    统一处理所有兼容OpenAI API的LLM服务的代理类。
    支持以下提供商：
    - OpenAI (GPT系列)
    - DeepSeek
    - 阿里云通义千问
    - X.ai (Grok)
    - Perplexity
    """

    def __init__(
        self,
        player_id: str,
        name: str,
        api_key: str = "",
        model: Optional[str] = None,
        temperature: float = 0.7,
        provider: str = "openai",
        effort: Optional[str] = None,
        **kwargs: Any
    ):
        """
        初始化OpenAI兼容代理。

        Args:
            player_id: 玩家ID
            name: 玩家名称
            api_key: API密钥
            model: 模型名称
            temperature: 采样温度
            provider: 提供商名称，如"openai"、"deepseek"、"aliyun"等
            **kwargs: 其他参数，如api_base等
        """
        super().__init__(player_id, name)
        self.api_key = api_key
        self.model = model or get_default_model(provider) or get_default_model("openai")
        self.provider = provider
        self.temperature = temperature
        self.effort = effort or DEFAULT_EFFORT

        # 根据提供商配置API基础URL（配置表提供默认值，环境变量可覆盖）
        self.api_base = kwargs.get('api_base') or get_api_base(provider) or get_api_base("openai")

        # 初始化OpenAI客户端
        logger.info("初始化%s代理 - 玩家ID: %s, 名称: %s, 模型: %s, API基础URL: %s",
                    provider, player_id, name, self.model, self.api_base)

        # fal的网关用 Authorization: Key <FAL_KEY> 认证，而不是OpenAI默认的Bearer
        client_kwargs = {}
        if provider == "fal":
            client_kwargs["default_headers"] = {"Authorization": f"Key {api_key}"}

        try:
            # 重试交给客户端内置机制处理（指数退避），不再手动写重试循环
            self.client = AsyncOpenAI(
                api_key=api_key or "not-needed",
                base_url=self.api_base,
                timeout=LLM_TIMEOUT,
                max_retries=1,
                **client_kwargs,
            )
        except Exception as e:
            logger.error("%s客户端初始化失败: %s", provider, e)
            raise APIError(f"{provider}客户端初始化失败: {str(e)}")

        self.decision_history = []

    async def make_decision(
        self,
        game_state: Dict,
        valid_actions: List[str],
        min_bet: Optional[int] = None,
        max_bet: Optional[int] = None
    ) -> Tuple[str, Optional[int], Optional[str]]:
        """
        使用OpenAI兼容API生成决策

        Args:
            game_state: 游戏状态
            valid_actions: 有效动作列表
            min_bet: 最小下注额
            max_bet: 最大下注额

        Returns:
            Tuple[str, Optional[int], Optional[str]]: 行动、下注额和思考过程组成的元组

        Raises:
            APIError: API调用失败
            DecisionError: 无法确定当前玩家时
        """
        logger.info("%s代理开始生成决策 - 模型: %s", self.provider, self.model)

        try:
            # 获取玩家ID
            player_id = self._get_player_id(game_state)
            if not player_id:
                logger.error("无法确定当前玩家ID")
                raise DecisionError("无法确定当前玩家ID")

            # 构建提示词
            prompt = build_prompt(
                game_state=game_state,
                player_id=player_id,
                valid_actions=valid_actions,
                min_bet=min_bet,
                max_bet=max_bet
            )

            # 针对DeepSeek-Reasoner模型修改提示词
            is_reasoner_model = self.provider == "deepseek" and "reasoner" in self.model.lower()

            if is_reasoner_model:
                # 为推理模型添加特殊的提示词后缀
                prompt += """
策略指导：
1. 如果'check'(让牌)是你的有效行动选项之一，应优先选择check而不是fold(弃牌)，除非你的牌非常弱且没有改善可能。
2. 只有当你认为你的牌赢的机会很小，且需要投入更多筹码(不能check)时，才考虑fold。
3. 做决策时要考虑你的位置、底池赔率和潜在的牌力。

请详细展示你的思考过程，包括对当前牌局的分析、胜率估计和策略考虑。
在思考过程结束后，请在最后一行明确指出你的决策，格式如下：

最终决策：[fold/call/raise] [金额，仅在raise情况下需要]
"""
                logger.info("检测到DeepSeek-Reasoner模型，使用推理专用提示词")
                logger.debug("DeepSeek-Reasoner模型接收到的完整提示词:\n%s", prompt)

            # 构建OpenAI API请求参数
            kwargs = {
                "model": self.model,
                "messages": [
                    {"role": "user", "content": prompt}
                ],
            }

            # 针对不同提供商使用不同参数
            if self.provider == "openai":
                # OpenAI当前模型：不接受temperature，用max_completion_tokens（推理token也计入），思考深度用reasoning_effort
                kwargs["max_completion_tokens"] = 16000
                kwargs["reasoning_effort"] = self.effort
                kwargs["response_format"] = {"type": "json_object"}
            elif self.provider == "perplexity":
                # Perplexity API不支持response_format参数
                kwargs["max_tokens"] = 2048
                kwargs["temperature"] = self.temperature
            else:
                # 其他模型的通用处理；推理模型的思考也算在max_tokens里，留足空间
                # 豆包、DeepSeek这类推理模型一次可能想一万多token，上限给足，避免正文被截断成空
                kwargs["max_tokens"] = 32000
                kwargs["temperature"] = self.temperature
                kwargs["response_format"] = {"type": "json_object"}
                if self.provider == "fal":
                    # 经OpenRouter控制推理强度，不设的话部分模型会想很久
                    kwargs["extra_body"] = {"reasoning": {"effort": self.effort}}

            # 调用OpenAI兼容API
            logger.info("调用%s API - 模型: %s, URL: %s", self.provider, self.model, self.api_base)

            # 推理模型偶尔把输出额度全用在思考上、返回空内容，重试一次
            response_content = None
            for attempt in range(2):
                start_time = time.time()
                response = await self.client.chat.completions.create(**kwargs)
                response_time = time.time() - start_time
                response_content = response.choices[0].message.content
                if response_content:
                    break
                logger.warning("%s %s 返回空内容(finish_reason=%s)，耗时%.2f秒，第%d次",
                               self.provider, self.model, response.choices[0].finish_reason, response_time, attempt + 1)
            if not response_content:
                raise APIError(f"{self.provider} {self.model} 连续返回空内容")
            logger.info("%s代理成功生成决策，耗时: %.2f秒", self.provider, response_time)

            # 解析响应
            logger.debug("%s %s 的原始响应:\n%s", self.provider, self.model, response_content)

            # 针对DeepSeek-Reasoner等推理模型的特殊处理
            if is_reasoner_model:
                # 从推理模型响应中提取决策（查找最后一行的决策）
                action, amount, thinking = self._parse_reasoner_response(response_content, valid_actions, min_bet, max_bet)
            else:
                # 使用标准解析逻辑
                action, amount, thinking = parse_response(response_content, valid_actions, min_bet, max_bet)

            self.last_speech = extract_speech(response_content)

            logger.info("决策结果: action=%s, amount=%s", action, amount)

            # 验证决策，无效时回退为默认动作
            action, amount = self._sanitize_decision(action, amount, valid_actions, min_bet, max_bet)

            # 如果thinking为None，提供默认值
            if thinking is None:
                if is_reasoner_model:
                    # 对于推理模型，将整个响应内容设为thinking
                    thinking = response_content
                else:
                    thinking = f"我决定{action}。" + (f"下注金额为{amount}。" if amount is not None else "")

            # 存储决策历史
            self.decision_history.append({
                "prompt": prompt,
                "response": response_content,
                "action": action,
                "amount": amount
            })

            return action, amount, thinking

        except AuthenticationError as e:
            logger.error("%s API认证错误: %s", self.provider, e)
            raise APIError(f"{self.provider} API认证错误: API密钥可能无效")
        except RateLimitError as e:
            logger.error("%s API速率限制错误: %s", self.provider, e)
            raise APIError(f"{self.provider} API速率限制错误: 已超过API调用限制")
        except OpenAIAPIError as e:
            error_details = f"提供商: {self.provider}, 模型: {self.model}, URL: {self.api_base}"
            logger.error("%s API错误: %s (%s)", self.provider, e, error_details)
            raise APIError(f"{self.provider} API调用失败: {str(e)}. {error_details}")
        except DecisionError:
            raise
        except Exception as e:
            logger.error("意外错误: %s", e)
            raise APIError(f"{self.provider} API调用失败: {str(e)}")

    async def list_available_models(self) -> List[Dict]:
        """
        获取可用模型列表，用于诊断模型可用性问题

        Returns:
            List[Dict]: 可用模型列表，包含模型ID、拥有者等信息

        Raises:
            APIError: API调用失败
        """
        try:
            logger.info("正在获取%s可用模型列表...", self.provider)

            # 一些提供商可能不支持列出模型
            if self.provider in ["aliyun", "xai", "perplexity"]:
                logger.info("%s可能不支持列出模型API，将返回默认模型信息", self.provider)

                # 提供默认模型信息
                default_models = []
                if self.provider == "aliyun":
                    default_models = [
                        {"id": "qwen-plus", "owned_by": "Alibaba", "created": None},
                        {"id": "qwen-max", "owned_by": "Alibaba", "created": None},
                        {"id": "qwen-max-1201", "owned_by": "Alibaba", "created": None},
                        {"id": "qwen-max-longcontext", "owned_by": "Alibaba", "created": None},
                        {"id": "qwen-turbo", "owned_by": "Alibaba", "created": None}
                    ]
                elif self.provider == "xai":
                    default_models = [
                        {"id": "grok-1", "owned_by": "xAI", "created": None},
                        {"id": "grok-2", "owned_by": "xAI", "created": None}
                    ]
                elif self.provider == "perplexity":
                    default_models = [
                        {"id": "sonar-small-chat", "owned_by": "Perplexity", "created": None},
                        {"id": "sonar-medium-chat", "owned_by": "Perplexity", "created": None},
                        {"id": "sonar-small-online", "owned_by": "Perplexity", "created": None},
                        {"id": "sonar-medium-online", "owned_by": "Perplexity", "created": None}
                    ]

                return default_models

            # 使用OpenAI兼容的API获取模型列表
            models_response = await self.client.models.list()
            models = [{"id": model.id, "owned_by": model.owned_by, "created": model.created}
                     for model in models_response.data]

            logger.info("成功获取%s的可用模型列表，共%d个模型", self.provider, len(models))
            return models

        except Exception as e:
            logger.error("获取%s可用模型列表失败: %s", self.provider, e)
            raise APIError(f"获取{self.provider}可用模型列表失败: {str(e)}")

    @classmethod
    async def test_connection(cls, api_key: str, provider: str = "openai", model: str = None) -> Dict:
        """
        测试与API的连接情况

        Args:
            api_key: API密钥
            provider: 提供商名称
            model: 模型名称，如果不提供则使用默认模型

        Returns:
            Dict: 连接测试结果，包含状态和可用模型列表
        """
        try:
            logger.info("开始测试与%s的连接...", provider)

            # 使用配置表中的默认模型
            if not model:
                model = get_default_model(provider) or get_default_model("openai")

            # 创建临时代理
            agent = cls(
                player_id="test",
                name="测试代理",
                api_key=api_key,
                model=model,
                provider=provider
            )

            # 获取可用模型列表
            models = await agent.list_available_models()

            # 返回测试结果
            result = {
                "status": "success",
                "provider": provider,
                "model_count": len(models),
                "api_base": agent.api_base,
                "models": models[:10] if len(models) > 10 else models  # 只返回前10个模型
            }

            logger.info("%s连接测试通过", provider)
            return result

        except Exception as e:
            logger.error("%s连接测试失败: %s", provider, e)
            return {
                "status": "error",
                "provider": provider,
                "error": str(e)
            }

    def _parse_reasoner_response(self, response_text: str, valid_actions: List[str], min_bet: Optional[int], max_bet: Optional[int]) -> Tuple[str, Optional[int], Optional[str]]:
        """
        专门解析推理模型的响应，从中提取决策和保留完整思考过程

        Args:
            response_text: 推理模型返回的文本
            valid_actions: 有效动作列表
            min_bet: 最小下注额
            max_bet: 最大下注额

        Returns:
            Tuple[str, Optional[int], Optional[str]]: 行动、金额和思考过程
        """
        # 默认使用整个响应作为思考过程
        thinking = response_text
        action = None
        amount = None

        # 查找最终决策行（通常在最后）
        # 尝试多种模式匹配最终决策
        patterns = [
            r"最终决策[:：]\s*([a-z]+)(?:\s+(\d+))?",  # 最终决策: fold 或 最终决策: raise 100
            r"我(?:决定|选择)([a-z]+)(?:\s+(\d+))?",   # 我决定fold 或 我决定raise 100
            r"决策[:：]\s*([a-z]+)(?:\s+(\d+))?",      # 决策: fold 或 决策: raise 100
            r"([a-z]+)(?:\s+(\d+))?\s*$"               # 最后一行只有fold 或 raise 100
        ]

        # 从文本的最后一部分开始查找，因为决策通常在最后
        for pattern in patterns:
            matches = list(re.finditer(pattern, response_text, re.MULTILINE))
            if not matches:
                continue

            # 使用最后一个匹配项
            match = matches[-1]
            action_text = match.group(1)
            logger.debug("推理模型决策模式'%s'匹配到: '%s'", pattern, action_text)

            # 找到最匹配的有效动作
            for valid_action in valid_actions:
                if valid_action in action_text or action_text in valid_action:
                    action = valid_action
                    break

            # 提取金额（如果有）
            if action == "raise" and match.lastindex and match.lastindex >= 2:
                amount_group = match.group(2)
                if amount_group and amount_group.isdigit():
                    amount = int(amount_group)

            # 找到了有效动作，退出循环
            if action:
                break

        # 如果以上模式都没匹配到，尝试在文本中查找有效动作的出现
        if not action:
            logger.debug("未找到明确的决策行，尝试统计文本中动作关键词的出现频率")
            action_mentions = {}

            # 统计每个有效动作在文本中的出现次数
            for valid_action in valid_actions:
                count = len(re.findall(r'\b' + valid_action + r'\b', response_text.lower()))
                action_mentions[valid_action] = count

            # 选择出现最多的动作
            if action_mentions and max(action_mentions.values()) > 0:
                action = max(action_mentions.items(), key=lambda x: x[1])[0]
                logger.debug("基于出现频率选择动作: %s (出现%d次)", action, action_mentions[action])

                # 如果选择了raise，尝试寻找附近的数字作为金额
                if action == "raise":
                    amount_matches = re.findall(r'raise\s+(\d+)', response_text.lower())
                    if amount_matches:
                        # 使用最后一个raise金额
                        amount = int(amount_matches[-1])

        # 兜底处理 - 如果仍然没有找到动作，使用默认动作
        if not action:
            action = self._get_default_action(valid_actions)
            logger.warning("未能从推理模型响应中提取有效动作，使用默认动作: %s", action)

        # 如果是raise但没有金额，使用最小下注额
        if action == "raise" and amount is None and min_bet is not None:
            amount = min_bet

        # 钳制金额到有效范围
        if action == "raise" and amount is not None:
            if min_bet is not None and amount < min_bet:
                amount = min_bet
            if max_bet is not None and amount > max_bet:
                amount = max_bet

        logger.debug("推理模型解析结果: 动作=%s, 金额=%s", action, amount)
        return action, amount, thinking
