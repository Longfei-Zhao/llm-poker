from typing import Dict, List, Tuple, Optional
import anthropic
import logging
import os
from .base_agent import BaseAgent
from ..exceptions import APIError, DecisionError
from ..config.agent_config import DEFAULT_EFFORT, LLM_TIMEOUT, get_default_model
from ..prompts.prompt_utils import build_prompt, extract_speech, parse_response

# 设置日志
logger = logging.getLogger(__name__)

class AnthropicAgent(BaseAgent):
    """专门处理Anthropic API (Claude系列模型)的代理类"""

    def __init__(
        self,
        player_id: str,
        name: str,
        api_key: str,
        model: Optional[str] = None,
        temperature: float = 0.7,
        effort: Optional[str] = None
    ):
        """初始化Anthropic代理

        Args:
            player_id: 玩家ID
            name: 玩家名称
            api_key: Anthropic API密钥
            model: 模型名称，默认使用配置表中的默认模型
            temperature: 采样温度，默认为0.7
        """
        super().__init__(player_id, name)

        self.api_key = api_key
        self.model = model or get_default_model("anthropic")
        self.temperature = temperature  # 当前Claude模型不再接受temperature，仅保留字段
        self.effort = effort or DEFAULT_EFFORT
        self.provider = "anthropic"  # 显式设置提供商标识

        try:
            # 初始化异步Anthropic客户端，避免同步调用阻塞事件循环
            logger.info("初始化Anthropic代理 - 玩家ID: %s, 名称: %s, 模型: %s, 温度: %s",
                        player_id, name, self.model, temperature)
            self.client = anthropic.AsyncAnthropic(api_key=self.api_key, timeout=LLM_TIMEOUT, max_retries=1)
        except Exception as e:
            logger.error("Anthropic客户端初始化失败: %s", e)
            raise APIError(f"Anthropic客户端初始化失败: {str(e)}")

    def _models_to_try(self) -> List[str]:
        """主模型，加上被拒答时重试用的备用模型（ANTHROPIC_FALLBACK_MODEL，默认Opus 5.5）"""
        fallback = os.getenv("ANTHROPIC_FALLBACK_MODEL", "claude-opus-5-5")
        return [self.model] if not fallback or fallback == self.model else [self.model, fallback]

    async def make_decision(
        self,
        game_state: Dict,
        valid_actions: List[str],
        min_bet: Optional[int] = None,
        max_bet: Optional[int] = None
    ) -> Tuple[str, Optional[int], Optional[str]]:
        """使用Anthropic Claude API生成决策

        Args:
            game_state: 游戏状态字典
            valid_actions: 有效行动列表
            min_bet: 最小下注金额
            max_bet: 最大下注金额

        Returns:
            Tuple[str, Optional[int], Optional[str]]: 行动、下注额和思考过程组成的元组

        Raises:
            DecisionError: 无法确定当前玩家时
            APIError: 当API调用失败时
        """
        try:
            # 获取玩家ID
            player_id = self._get_player_id(game_state)
            if not player_id:
                logger.error("无法确定当前玩家ID")
                raise DecisionError("无法确定当前玩家ID")

            # 构建提示词
            logger.info("Anthropic代理开始生成决策 - 玩家: %s, 模型: %s", player_id, self.model)
            prompt = build_prompt(
                game_state=game_state,
                player_id=player_id,
                valid_actions=valid_actions,
                min_bet=min_bet,
                max_bet=max_bet
            )

            # 当前Claude模型不接受temperature，思考深度用effort控制；思考也计入max_tokens，所以留足空间。
            # fallbacks="default"：被安全分类器拒答时服务端自动换模型重试；仍被拒的话，再用备用模型重试一次
            for model in self._models_to_try():
                response = await self.client.messages.create(
                    model=model,
                    max_tokens=16000,
                    messages=[
                        {"role": "user", "content": prompt}
                    ],
                    extra_body={"output_config": {"effort": self.effort}, "fallbacks": "default"},
                    extra_headers={"anthropic-beta": "server-side-fallback-2026-07-01"},
                )
                if response.stop_reason != "refusal":
                    break
                details = getattr(response, "stop_details", None) or (response.model_extra or {}).get("stop_details")
                logger.warning("%s拒绝回答本次决策: %s", model, details)
            if response.stop_reason == "refusal":
                raise DecisionError("Claude拒绝回答本次决策")
            # 响应里可能先有thinking块，只取文本块
            response_content = "".join(
                getattr(block, "text", "") for block in response.content if getattr(block, "type", "") == "text"
            )
            logger.debug("Anthropic原始响应: %s", response_content)

            # 解析响应内容
            action, amount, thinking = parse_response(response_content, valid_actions, min_bet, max_bet)
            self.last_speech = extract_speech(response_content)
            logger.info("决策结果: action=%s, amount=%s", action, amount)

            # 验证决策，无效时回退为默认动作
            action, amount = self._sanitize_decision(action, amount, valid_actions, min_bet, max_bet)

            # 确保thinking不为None
            if thinking is None:
                thinking = f"我决定{action}。" + (f"下注金额为{amount}。" if amount is not None else "")

            return action, amount, thinking

        except anthropic.APITimeoutError as e:
            logger.error("Anthropic API超时: %s", e)
            raise APIError(f"Anthropic API调用超时: {str(e)}")
        except anthropic.APIConnectionError as e:
            logger.error("Anthropic API连接错误: %s", e)
            raise APIError(f"Anthropic API连接错误: {str(e)}")
        except anthropic.AuthenticationError as e:
            logger.error("Anthropic API认证错误: %s", e)
            raise APIError(f"Anthropic API认证错误: {str(e)}")
        except anthropic.BadRequestError as e:
            logger.error("Anthropic API请求错误: %s", e)
            raise APIError(f"Anthropic API请求错误: {str(e)}")
        except anthropic.APIError as e:
            logger.error("Anthropic API调用错误: %s", e)
            raise APIError(f"Anthropic API调用失败: {str(e)}")
        except DecisionError:
            # 重新抛出DecisionError
            raise
        except Exception as e:
            logger.error("意外错误: %s", e)
            raise APIError(f"Anthropic API调用失败: {str(e)}")

    async def chat(self, prompt: str) -> str:
        """不打牌，只按提示说一句话（比如一手结束后的赛后感言），返回纯文本"""
        try:
            response = await self.client.messages.create(
                model=self.model,
                max_tokens=4000,
                messages=[{"role": "user", "content": prompt}],
                extra_body={"output_config": {"effort": "low"}, "fallbacks": "default"},
                extra_headers={"anthropic-beta": "server-side-fallback-2026-07-01"},
            )
        except anthropic.APIError as e:
            raise APIError(f"Anthropic API调用失败: {str(e)}")
        if response.stop_reason == "refusal":
            raise DecisionError("Claude拒绝回答")
        return "".join(getattr(b, "text", "") for b in response.content if getattr(b, "type", "") == "text").strip()
