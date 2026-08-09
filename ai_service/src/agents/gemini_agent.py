from typing import Dict, List, Optional, Tuple
import google.generativeai as genai
import logging
from .base_agent import BaseAgent
from ..exceptions import APIError, DecisionError
from ..config.agent_config import get_default_model
from ..prompts.prompt_utils import build_prompt, parse_response

# 设置日志记录器
logger = logging.getLogger(__name__)

class GeminiAgent(BaseAgent):
    """Gemini代理类"""

    def __init__(
        self,
        player_id: str,
        name: str,
        api_key: str,
        model: Optional[str] = None,
        temperature: float = 0.7
    ):
        """初始化Gemini代理

        Args:
            player_id: 玩家ID
            name: 玩家名称
            api_key: API密钥
            model: 模型名称，默认使用配置表中的默认模型
            temperature: 采样温度
        """
        super().__init__(player_id, name)
        self.api_key = api_key
        self.model = model or get_default_model("gemini")
        self.temperature = temperature
        self.provider = "gemini"
        self.decision_history = []
        logger.info("初始化Gemini代理: 玩家ID=%s, 名称=%s, 模型=%s", player_id, name, self.model)

        # 只在初始化时配置一次API并创建模型实例，避免每次决策都重复配置
        genai.configure(api_key=self.api_key)
        self._model = genai.GenerativeModel(model_name=self.model)

    async def make_decision(self, game_state: Dict, valid_actions: List[str], min_bet: Optional[int] = None, max_bet: Optional[int] = None) -> Tuple[str, Optional[int], Optional[str]]:
        """根据游戏状态做出决策

        Args:
            game_state: 游戏状态
            valid_actions: 有效的行动列表
            min_bet: 最小下注额
            max_bet: 最大下注额

        Returns:
            Tuple[str, Optional[int], Optional[str]]: (行动类型, 下注金额, 思考过程)

        Raises:
            APIError: API调用失败
        """
        player_id = self._get_player_id(game_state)
        if not player_id:
            player_id = self.player_id

        # 构建提示词
        prompt = build_prompt(game_state, player_id, valid_actions, min_bet, max_bet)

        try:
            # 生成内容
            response = await self._model.generate_content_async(
                prompt,
                generation_config={
                    "temperature": self.temperature,
                    "max_output_tokens": 1024,
                }
            )

            response_text = response.text
            logger.debug("Gemini模型响应: %s", response_text)

            # 解析响应，传入有效动作和下注范围以钳制金额
            action, amount, thought_process = parse_response(
                response_text, valid_actions, min_bet, max_bet
            )

            # 验证决策，无效时回退为默认动作
            action, amount = self._sanitize_decision(action, amount, valid_actions, min_bet, max_bet)

            # 记录决策
            self.decision_history.append({
                "prompt": prompt,
                "response": response_text,
                "action": action,
                "amount": amount,
                "timestamp": None  # 可以添加时间戳
            })

            return action, amount, thought_process

        except DecisionError:
            # 重新抛出决策错误
            raise
        except Exception as e:
            # 将其他异常包装为APIError
            logger.error("Gemini API调用失败: %s", e)
            raise APIError(f"Gemini API调用失败: {str(e)}")

    def _get_player_cards(self, game_state: Dict, player_id: str) -> List[str]:
        """获取玩家手牌

        Args:
            game_state: 游戏状态
            player_id: 玩家ID

        Returns:
            List[str]: 玩家手牌，找不到玩家时返回空列表
        """
        for player in game_state.get("players", []):
            if player.get("id") == player_id:
                return player.get("cards", [])
        return []
