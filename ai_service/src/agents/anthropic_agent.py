import os
from typing import Dict, Any, List, Tuple, Optional
import anthropic
import logging
from .base_agent import BaseAgent
from ..exceptions import APIError, DecisionError
import json
from ..prompts.prompt_utils import build_prompt, parse_response

# 设置日志
logger = logging.getLogger(__name__)

class AnthropicAgent(BaseAgent):
    """专门处理Anthropic API (Claude系列模型)的代理类"""
    
    def __init__(
        self,
        player_id: str,
        name: str,
        api_key: str,
        model: str = "claude-3-7-sonnet-20250219",
        temperature: float = 0.7
    ):
        """初始化Anthropic代理
        
        Args:
            player_id: 玩家ID
            name: 玩家名称
            api_key: Anthropic API密钥
            model: 模型名称，默认为claude-3-7-sonnet-20250219
            temperature: 采样温度，默认为0.7
        """
        super().__init__(player_id, name)
        
        self.api_key = api_key
        self.model = model
        self.temperature = temperature
        self.provider = "anthropic"  # 显式设置提供商标识
        
        try:
            # 初始化Anthropic客户端
            logger.info(f"🔧 初始化Anthropic代理 - 玩家ID: {player_id}, 名称: {name}")
            logger.info(f"📦 模型: {model}, 温度: {temperature}")
            self.client = anthropic.Anthropic(api_key=self.api_key)
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
        """使用Anthropic Claude API生成决策
        
        Args:
            game_state: 游戏状态字典
            valid_actions: 有效行动列表
            min_bet: 最小下注金额
            max_bet: 最大下注金额
        
        Returns:
            Tuple[str, Optional[int], Optional[str]]: 行动、下注额和思考过程组成的元组
        
        Raises:
            DecisionError: 当决策无效或解析失败时
            APIError: 当API调用失败时
        """
        try:
            # 获取玩家ID
            player_id = self._get_player_id(game_state)
            if not player_id:
                logger.error("❌ 无法确定当前玩家ID")
                raise DecisionError("无法确定当前玩家ID")
                
            # 构建提示词
            logger.info(f"🎮 Anthropic代理开始生成决策...")
            prompt = build_prompt(
                game_state=game_state, 
                player_id=player_id,
                valid_actions=valid_actions, 
                min_bet=min_bet, 
                max_bet=max_bet
            )
            
            # 调用Anthropic API - 移除await关键字，使用同步调用
            logger.info(f"📤 调用Anthropic API (版本0.46.0)...")
            response = self.client.messages.create(
                model=self.model,
                max_tokens=1000,
                temperature=self.temperature,
                messages=[
                    {"role": "user", "content": prompt}
                ]
            )
            response_content = response.content[0].text
            logger.info(f"✅ Anthropic代理成功生成决策")
            
            # 解析响应内容 - 修复解包问题
            action, amount, thinking = parse_response(response_content, valid_actions, min_bet, max_bet)
            logger.info(f"📊 决策结果: action={action}, amount={amount}")
            
            # 验证决策
            self._validate_action(action, amount, valid_actions, min_bet, max_bet)
            
            # 确保thinking不为None
            if thinking is None:
                thinking = f"我决定{action}。" + (f"下注金额为{amount}。" if amount is not None else "")
                logger.info(f"⚠️ 未提取到思考过程，使用默认值: {thinking}")
            
            return action, amount, thinking
            
        except json.JSONDecodeError as e:
            logger.error(f"❌ 解析响应失败: {str(e)}")
            raise DecisionError(f"解析响应失败: {str(e)}")
        except anthropic.APIError as e:
            logger.error(f"❌ Anthropic API调用错误: {str(e)}")
            raise APIError(f"Anthropic API调用失败: {str(e)}")
        except anthropic.APITimeoutError as e:
            logger.error(f"❌ Anthropic API超时: {str(e)}")
            raise APIError(f"Anthropic API调用超时: {str(e)}")
        except anthropic.APIConnectionError as e:
            logger.error(f"❌ Anthropic API连接错误: {str(e)}")
            raise APIError(f"Anthropic API连接错误: {str(e)}")
        except anthropic.AuthenticationError as e:
            logger.error(f"❌ Anthropic API认证错误: {str(e)}")
            raise APIError(f"Anthropic API认证错误: {str(e)}")
        except anthropic.BadRequestError as e:
            logger.error(f"❌ Anthropic API请求错误: {str(e)}")
            raise APIError(f"Anthropic API请求错误: {str(e)}")
        except DecisionError as e:
            # 重新抛出DecisionError
            raise
        except Exception as e:
            logger.error(f"❌ 意外错误: {str(e)}")
            raise APIError(f"Anthropic API调用失败: {str(e)}") 