from typing import Dict, List, Optional, Tuple, Any
import json
import os
import logging
import time
from openai import OpenAI, AsyncOpenAI
from openai.types.chat import ChatCompletion
from openai import BadRequestError, AuthenticationError, PermissionDeniedError, NotFoundError, RateLimitError, APIError as OpenAIAPIError
from .base_agent import BaseAgent
from ..exceptions import APIError, DecisionError
from ..prompts.prompt_utils import build_prompt, parse_response
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
        model: str = "gpt-4o",
        temperature: float = 0.7,
        provider: str = "openai",
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
        self.model = model
        self.provider = provider
        self.temperature = temperature
        
        # 根据提供商配置API基础URL
        self.api_base = kwargs.get('api_base') or self._get_api_base(provider)
        
        # 初始化OpenAI客户端
        logger.info(f"🔧 初始化{provider}代理 - 玩家ID: {player_id}, 名称: {name}")
        logger.info(f"📦 模型: {model}, API基础URL: {self.api_base}")
        
        # 根据提供商设置不同的超时时间
        timeout = 30.0  # 默认超时时间
        # if provider == "aliyun":
        #     timeout = 60.0  # 阿里云API响应较慢，设置更长的超时时间
        # elif provider == "deepseek":
        #     timeout = 45.0  # DeepSeek API也需要较长时间
            
        try:
            self.client = AsyncOpenAI(
                api_key=api_key,
                base_url=self.api_base,
                timeout=timeout,  # 设置超时时间
                max_retries=3,    # 设置最大重试次数
            )
            logger.info(f"✅ {provider}客户端初始化成功 (超时={timeout}秒, 最大重试次数=3)")
        except Exception as e:
            logger.error(f"❌ {provider}客户端初始化失败: {str(e)}")
            raise APIError(f"{provider}客户端初始化失败: {str(e)}")
        
        self.decision_history = []
    
    def _get_api_base(self, provider: str) -> str:
        """
        根据提供商获取适当的API基础URL
        
        Args:
            provider: 提供商名称
            
        Returns:
            str: API基础URL
        """
        # 各提供商的默认基础URL
        bases = {
            "openai": "https://api.openai.com/v1",
            "deepseek": "https://api.deepseek.com/v1",
            "aliyun": "https://dashscope.aliyuncs.com/compatible-mode/v1",  # 阿里云通义千问的OpenAI兼容模式API
            "xai": "https://api.x.ai/v1",
            "perplexity": "https://api.perplexity.ai"  # Perplexity的API基础URL
        }
        
        # 从环境变量获取自定义基础URL
        env_var_name = f"{provider.upper()}_API_BASE"
        custom_base = os.getenv(env_var_name)
        
        if custom_base:
            logger.info(f"✓ 使用环境变量'{env_var_name}'中的自定义API基础URL: {custom_base}")
            return custom_base
        
        # 使用默认URL或OpenAI URL作为后备选项
        base_url = bases.get(provider, bases["openai"])
        
        # 记录使用的API基础URL
        if provider == "aliyun":
            logger.info(f"🔍 使用阿里云通义千问OpenAI兼容模式API: {base_url}")
        elif provider == "perplexity":
            logger.info(f"🔍 使用Perplexity API: {base_url}")
            
        return base_url
    
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
            DecisionError: 决策无效
        """
        # 显示当前API信息
        logger.info(f"🎮 {self.provider}代理开始生成决策 - 模型: {self.model}, API基础URL: {self.api_base}")
        
        # 最大重试次数
        max_retries = 2
        current_retry = 0
        
        while current_retry <= max_retries:
            try:
                # 获取玩家ID
                player_id = self._get_player_id(game_state)
                if not player_id:
                    logger.error("❌ 无法确定当前玩家ID")
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
                    logger.info("🧠 检测到DeepSeek-Reasoner模型，使用推理专用提示词")
                    
                    # 打印推理模型的完整提示词
                    print("\n" + "="*50)
                    print("🧠 DeepSeek-Reasoner模型接收到的完整提示词:")
                    print("="*50)
                    print(prompt)
                    print("="*50 + "\n")
                
                # 构建OpenAI API请求参数
                kwargs = {
                "model": self.model,
                "messages": [
                        {"role": "user", "content": prompt}
                    ],
                }
                
                # 针对不同模型使用特殊参数
                if self.model == "gpt-4o-mini":
                    # GPT-4O-Mini模型的特殊处理
                    # 注意：GPT-4O-Mini模型有以下特殊要求：
                    # 1. 使用max_completion_tokens而不是max_tokens参数
                    # 2. 不支持temperature参数（只接受默认值1）
                    # 3. 不支持response_format参数
                    kwargs["max_completion_tokens"] = 1000
                    # GPT-4O-Mini不支持temperature参数和response_format参数
                elif self.provider == "perplexity":
                    # Perplexity API不支持response_format参数
                    logger.info("🔍 检测到Perplexity提供商，不使用response_format参数")
                    kwargs["max_tokens"] = 1000
                    kwargs["temperature"] = self.temperature
                else:
                    # 其他模型的通用处理
                    kwargs["max_tokens"] = 1000
                    kwargs["temperature"] = self.temperature
                    kwargs["response_format"] = {"type": "json_object"}
                
                # 调用OpenAI兼容API
                logger.info(f"📤 调用{self.provider} API...")
                
                # 添加详细的请求信息日志
                logger.info(f"🔍 请求详情: 模型={self.model}, 提供商={self.provider}, URL={self.api_base}")
                
                # 记录开始时间
                start_time = time.time()
                
                response = await self.client.chat.completions.create(**kwargs)
                
                # 记录响应时间
                response_time = time.time() - start_time
                logger.info(f"✅ {self.provider}代理成功生成决策，耗时: {response_time:.2f}秒")
                
                # 解析响应
                response_content = response.choices[0].message.content
                
                # 打印LLM的原始响应
                print("\n" + "="*50)
                print(f"⭐️ {self.provider} {self.model} 的原始响应:")
                print("="*50)
                print(response_content)
                print("="*50 + "\n")
                
                # 针对DeepSeek-Reasoner等推理模型的特殊处理
                if is_reasoner_model:
                    logger.info("🧩 使用推理模型专用响应解析逻辑")
                    # 从推理模型响应中提取决策（查找最后一行的决策）
                    action, amount, thinking = self._parse_reasoner_response(response_content, valid_actions, min_bet, max_bet)
                else:
                    # 使用标准解析逻辑
                    action, amount, thinking = parse_response(response_content, valid_actions, min_bet, max_bet)
                
                logger.info(f"📊 决策结果: action={action}, amount={amount}")
                
                # 验证决策
                self._validate_action(action, amount, valid_actions, min_bet, max_bet)
                
                # 如果thinking为None，提供默认值
                if thinking is None:
                    if is_reasoner_model:
                        # 对于推理模型，将整个响应内容设为thinking
                        thinking = response_content
                        logger.info("🧠 使用推理模型的完整响应作为思考过程")
                    else:
                        thinking = f"我决定{action}。" + (f"下注金额为{amount}。" if amount is not None else "")
                        logger.info(f"⚠️ 未提取到思考过程，使用默认值: {thinking}")
                
                # 打印解析后的结果
                print("\n" + "="*50)
                print("📊 解析后的决策结果:")
                print("="*50)
                print(f"动作: {action}")
                print(f"金额: {amount}")
                print(f"思考过程: {thinking[:200]}..." if len(thinking) > 200 else f"思考过程: {thinking}")
                print("="*50 + "\n")
                
                # 存储决策历史
                self.decision_history.append({
                    "prompt": prompt,
                    "response": response_content,
                    "action": action,
                    "amount": amount
                })
                
                return action, amount, thinking
                
            except (OpenAIAPIError, BadRequestError, AuthenticationError, PermissionDeniedError, 
                    NotFoundError, RateLimitError) as e:
                message = f"{self.provider} API错误: {str(e)}"
                logger.error(f"❌ {message}")
                
                # 检查是否需要重试
                if current_retry < max_retries and ("Connection" in str(e) or "timeout" in str(e).lower()):
                    current_retry += 1
                    retry_wait = 2 ** current_retry  # 指数退避
                    logger.info(f"⏱️ 连接错误，将在{retry_wait}秒后进行第{current_retry}次重试...")
                    time.sleep(retry_wait)
                    continue
                
                # 根据错误类型进行特定处理
                if isinstance(e, AuthenticationError):
                    raise APIError(f"{self.provider} API认证错误: API密钥可能无效")
                elif isinstance(e, RateLimitError):
                    raise APIError(f"{self.provider} API速率限制错误: 已超过API调用限制")
                else:
                    # 添加更详细的错误信息
                    error_details = f"提供商: {self.provider}, 模型: {self.model}, URL: {self.api_base}"
                    raise APIError(f"{self.provider} API调用失败: {str(e)}. {error_details}")
                
            except Exception as e:
                logger.error(f"❌ 意外错误: {str(e)}")
                
                # 特别处理连接错误
                if "Connection" in str(e) or "timeout" in str(e).lower():
                    if current_retry < max_retries:
                        current_retry += 1
                        retry_wait = 2 ** current_retry
                        logger.info(f"⏱️ 连接错误，将在{retry_wait}秒后进行第{current_retry}次重试...")
                        time.sleep(retry_wait)
                        continue
                    else:
                        raise APIError(f"{self.provider} API连接错误: {str(e)}. 请检查网络连接和API配置。")
                
                # 其他错误
                raise APIError(f"{self.provider} API调用失败: {str(e)}")
                
        # 所有重试都失败
        raise APIError(f"{self.provider} API调用失败: 达到最大重试次数")
        
    async def list_available_models(self) -> List[Dict]:
        """
        获取可用模型列表，用于诊断模型可用性问题
        
        Returns:
            List[Dict]: 可用模型列表，包含模型ID、拥有者等信息
            
        Raises:
            APIError: API调用失败
        """
        try:
            logger.info(f"🔍 正在获取{self.provider}可用模型列表...")
            
            # 一些提供商可能不支持列出模型
            if self.provider in ["aliyun", "xai", "perplexity"]:
                logger.info(f"⚠️ {self.provider}可能不支持列出模型API，将返回默认模型信息")
                
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
            
            logger.info(f"✅ 成功获取{self.provider}的可用模型列表，共{len(models)}个模型")
            
            # 记录前5个模型
            if models:
                logger.info("📋 可用模型示例:")
                for i, model in enumerate(models[:5]):
                    logger.info(f"  {i+1}. {model['id']} (拥有者: {model['owned_by'] or '未知'})")
            
            return models
            
        except Exception as e:
            logger.error(f"❌ 获取{self.provider}可用模型列表失败: {str(e)}")
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
            
        Raises:
            APIError: API调用失败
        """
        try:
            logger.info(f"🔍 开始测试与{provider}的连接...")
            
            # 使用默认模型
            if not model:
                model_map = {
                    "openai": "gpt-4o",
                    "deepseek": "deepseek-chat",
                    "aliyun": "qwen-plus",
                    "xai": "grok-2",
                    "perplexity": "sonar"  # Perplexity的Sonar模型
                }
                model = model_map.get(provider, "gpt-4o")
            
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
            
            logger.info(f"✅ {provider}连接测试通过!")
            return result
            
        except Exception as e:
            logger.error(f"❌ {provider}连接测试失败: {str(e)}")
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
        
        print("\n" + "="*50)
        print("🧠 DeepSeek-Reasoner响应解析过程:")
        print("="*50)
        
        # 查找最终决策行（通常在最后）
        decision_line = None
        
        # 尝试多种模式匹配最终决策
        patterns = [
            r"最终决策[:：]\s*([a-z]+)(?:\s+(\d+))?",  # 最终决策: fold 或 最终决策: raise 100
            r"我(决定|选择)([a-z]+)(?:\s+(\d+))?",     # 我决定fold 或 我决定raise 100
            r"决策[:：]\s*([a-z]+)(?:\s+(\d+))?",      # 决策: fold 或 决策: raise 100
            r"([a-z]+)(?:\s+(\d+))?\s*$"               # 最后一行只有fold 或 raise 100
        ]
        
        print(f"🔍 尝试{len(patterns)}种模式匹配最终决策...")
        
        # 从文本的最后一部分开始查找，因为决策通常在最后
        for i, pattern in enumerate(patterns):
            print(f"  模式{i+1}: {pattern}")
            matches = list(re.finditer(pattern, response_text, re.MULTILINE))
            if matches:
                # 使用最后一个匹配项
                match = matches[-1]
                match_text = response_text[match.start():match.end()]
                print(f"  ✓ 匹配成功: '{match_text}'")
                
                if len(match.groups()) >= 1:
                    action_text = match.group(1)
                    # 处理第二种模式，动作在第二个分组
                    if pattern == patterns[1]:
                        action_text = match.group(2)
                    
                    print(f"  提取的动作文本: '{action_text}'")
                    
                    # 找到最匹配的有效动作
                    for valid_action in valid_actions:
                        if valid_action in action_text or action_text in valid_action:
                            action = valid_action
                            print(f"  匹配到有效动作: {action}")
                            break
                    
                    # 提取金额（如果有）
                    if action == "raise" and len(match.groups()) >= 2:
                        amount_group = match.group(2) if pattern != patterns[1] else match.group(3)
                        if amount_group and amount_group.isdigit():
                            amount = int(amount_group)
                            print(f"  提取的金额: {amount}")
                    
                    # 找到了有效动作，退出循环
                    if action:
                        break
            else:
                print(f"  ✗ 无匹配")
        
        # 如果以上模式都没匹配到，尝试在文本中查找有效动作的出现
        if not action:
            print("⚠️ 未找到明确的决策行，尝试从文本中提取动作")
            action_mentions = {}
            
            # 统计每个有效动作在文本中的出现次数
            for valid_action in valid_actions:
                count = len(re.findall(r'\b' + valid_action + r'\b', response_text.lower()))
                action_mentions[valid_action] = count
                print(f"  '{valid_action}' 出现了 {count} 次")
            
            # 选择出现最多的动作
            if action_mentions:
                action = max(action_mentions.items(), key=lambda x: x[1])[0]
                print(f"📊 基于出现频率选择动作: {action} (出现{action_mentions[action]}次)")
                
                # 如果选择了raise，尝试寻找附近的数字作为金额
                if action == "raise":
                    amount_matches = re.findall(r'raise\s+(\d+)', response_text.lower())
                    if amount_matches:
                        # 使用最后一个raise金额
                        amount = int(amount_matches[-1])
                        print(f"💰 找到raise金额: {amount}")
        
        # 兜底处理 - 如果仍然没有找到动作，使用优先级最高的动作
        if not action:
            print("⚠️ 未能从响应中提取有效动作，默认使用优先级最高的动作")
            # 按优先级选择默认动作：check > call > fold
            if 'check' in valid_actions:
                action = 'check'
                print(f"选择'check'作为默认动作")
            elif 'call' in valid_actions:
                action = 'call'
                print(f"选择'call'作为默认动作")
            elif 'fold' in valid_actions:
                action = 'fold'
                print(f"选择'fold'作为默认动作")
            else:
                action = valid_actions[0] if valid_actions else 'fold'
                print(f"使用第一个有效动作'{action}'作为默认")
        
        # 如果是raise但没有金额，使用最小下注额
        if action == "raise" and amount is None and min_bet is not None:
            print(f"⚠️ raise动作没有指定金额，使用最小下注额: {min_bet}")
            amount = min_bet
            
        print(f"✅ 最终结果: 动作={action}, 金额={amount}")
        print("="*50 + "\n")
        
        return action, amount, thinking 