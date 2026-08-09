from typing import Dict, List, Any, Optional, Tuple
import json
import warnings
import logging
from anthropic import Anthropic
import openai
from .base_agent import BaseAgent
from ..exceptions import APIError, DecisionError
from ..prompts.prompt_utils import build_prompt, parse_response

# 设置日志
logger = logging.getLogger(__name__)

class LLMAgent(BaseAgent):
    """
    使用大模型API进行决策的扑克AI代理。
    
    警告:
        此类已弃用，将在未来版本中移除。
        请使用专门的代理类：
        - 对于Claude模型，请使用AnthropicAgent
        - 对于OpenAI模型，请使用OpenAICompatibleAgent
    """
    
    def __init__(
        self,
        player_id: str,
        name: str,
        api_key: str,
        model: str,
        temperature: float = 0.7
    ):
        """
        初始化LLM代理。
        
        Args:
            player_id: 玩家ID
            name: 玩家名称
            api_key: API密钥
            model: 模型名称
            temperature: 采样温度
        """
        super().__init__(player_id, name)
        
        # 发出弃用警告
        warnings.warn(
            "LLMAgent类已弃用，将在未来版本中移除。请使用AnthropicAgent代替。",
            DeprecationWarning,
            stacklevel=2
        )
        
        self.api_key = api_key
        self.model = model
        self.temperature = temperature
        
        # 添加provider属性，将LLMAgent视为Anthropic提供商
        self.provider = "anthropic"
        
        try:
            # 初始化Anthropic客户端
            logger.info(f"🔧 初始化Anthropic客户端 (LLMAgent - 已弃用) - 玩家ID: {player_id}, 名称: {name}")
            self.client = Anthropic(api_key=api_key)
            logger.info(f"✅ Anthropic客户端初始化成功")
        except Exception as e:
            logger.error(f"❌ Anthropic客户端初始化失败: {str(e)}")
            raise APIError(f"Anthropic客户端初始化失败: {str(e)}")

    async def make_decision(
        self, 
        game_state: Dict, 
        valid_actions: List[str], 
        min_bet: Optional[int] = None, 
        max_bet: Optional[int] = None
    ) -> Tuple[str, Optional[int], Optional[str]]:
        """
        基于游戏状态做出决策
        
        Args:
            game_state: 游戏状态
            valid_actions: 有效行动列表
            min_bet: 最小下注金额
            max_bet: 最大下注金额
        
        Returns:
            Tuple[str, Optional[int], Optional[str]]: 行动、下注额和思考过程组成的元组
        """
        warnings.warn(
            "LLMAgent.make_decision方法已弃用，请使用AnthropicAgent代替。",
            DeprecationWarning,
            stacklevel=2
        )
        
        try:
            # 获取玩家ID
            player_id = self._get_player_id(game_state)
            
            # 构建提示词
            logger.info(f"🎮 LLMAgent(已弃用)开始生成决策...")
            prompt = build_prompt(
                game_state=game_state, 
                player_id=player_id,
                valid_actions=valid_actions, 
                min_bet=min_bet, 
                max_bet=max_bet
            )
            
            # 调用Anthropic API - 移除await关键字，使用同步调用
            logger.info(f"📤 调用Anthropic API (版本0.46.0 - 通过LLMAgent弃用类)...")
            response = self.client.messages.create(
                model=self.model,
                max_tokens=1000,
                temperature=self.temperature,
                messages=[
                    {'role': 'user', 'content': prompt}
                ]
            )
            response_content = response.content[0].text
            logger.info(f"✅ LLMAgent(已弃用)成功生成决策")
            
            # 解析响应内容 - 修复解包问题
            action, amount, thinking = parse_response(response_content, valid_actions, min_bet, max_bet)
            
            return action, amount, thinking
            
        except json.JSONDecodeError as e:
            logger.error(f"❌ 解析响应失败: {str(e)}")
            raise DecisionError(f"解析响应失败: {str(e)}")
        except Exception as e:
            logger.error(f"❌ API调用失败: {str(e)}")
            raise APIError(f"API调用失败: {str(e)}")
            
    # 保留旧的make_decision方法，标记为弃用
    async def make_decision_old(self, game_state: Dict, valid_actions: List[str], min_bet: Optional[int] = None, max_bet: Optional[int] = None) -> Tuple[str, Optional[int], Optional[str]]:
        """
        弃用的方法，保留用于兼容性。
        请使用新的make_decision方法。
        
        返回:
            Tuple[str, Optional[int], Optional[str]]: 行动、下注额和思考过程组成的元组
        """
        warnings.warn(
            "LLMAgent.make_decision_old方法已弃用，将在未来版本中移除。",
            DeprecationWarning,
            stacklevel=2
        )
        return await self.make_decision(game_state, valid_actions, min_bet, max_bet) 