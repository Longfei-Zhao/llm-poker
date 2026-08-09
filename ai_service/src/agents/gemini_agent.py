from typing import Dict, List, Optional, Any, Tuple
import json
import os
import google.generativeai as genai
import logging
from .base_agent import BaseAgent
from ..exceptions import APIError, DecisionError
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
        model: str = "gemini-2.0-pro-exp-02-05",  # 使用原本指定的模型
        temperature: float = 0.7
    ):
        """初始化Gemini代理
        
        Args:
            player_id: 玩家ID
            name: 玩家名称
            api_key: API密钥
            model: 模型名称
            temperature: 采样温度
        """
        super().__init__(player_id, name)
        self.api_key = api_key
        self.model = model
        self.temperature = temperature
        self.decision_history = []
        logger.info(f"初始化Gemini代理: 玩家ID={player_id}, 名称={name}, 模型={model}")
        
        # 初始化时不配置API或创建模型实例
        # 这些操作将在make_decision方法中执行
        # 避免在初始化时可能发生的API错误
    
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
            DecisionError: 决策无效
        """
        player_id = self._get_player_id(game_state)
        if not player_id:
            player_id = self.player_id
            
        # 构建提示词
        prompt = build_prompt(game_state, player_id, valid_actions, min_bet, max_bet)
        
        try:
            # 配置API (在方法内部配置，而不是构造函数中)
            genai.configure(api_key=self.api_key)
            
            # 诊断: 列出可用模型，帮助调试
            try:
                available_models = [m.name for m in genai.list_models()]
                logger.info(f"可用的Gemini模型: {available_models}")
            except Exception as e:
                logger.warning(f"无法列出可用模型: {str(e)}")
            
            # 使用model_name参数初始化模型，确保兼容性
            model = genai.GenerativeModel(model_name=self.model)
            
            # 生成内容
            response = await model.generate_content_async(
                prompt,
                generation_config={
                    "temperature": self.temperature,
                    "max_output_tokens": 1024,
                }
            )
            
            response_text = response.text
            logger.debug(f"Gemini模型响应: {response_text}")
            
            # 解析响应
            action, amount, thought_process = parse_response(response_text)
            
            # 记录决策
            self.decision_history.append({
                "prompt": prompt,
                "response": response_text,
                "action": action,
                "amount": amount,
                "timestamp": None  # 可以添加时间戳
            })
            
            # 检查行动是否有效
            if action not in valid_actions:
                raise DecisionError(f"无效的行动: {action}，有效行动: {valid_actions}")
                
            return action, amount, thought_process
            
        except DecisionError as e:
            # 重新抛出决策错误
            raise e
        except Exception as e:
            # 将其他异常包装为APIError
            logger.error(f"Gemini API调用失败: {str(e)}")
            raise APIError(f"Gemini API调用失败: {str(e)}")
    
    def _get_player_cards(self, game_state: Dict, player_id: str) -> List[str]:
        """获取玩家手牌
        
        Args:
            game_state: 游戏状态
            player_id: 玩家ID
            
        Returns:
            List[str]: 玩家手牌
        """
        for player in game_state["players"]:
            if player["id"] == player_id:
                return player.get("cards", []) 