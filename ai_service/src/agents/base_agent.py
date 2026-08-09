from abc import ABC, abstractmethod
from typing import Dict, List, Optional, Tuple, Union, Any
from ..exceptions import DecisionError

class BaseAgent(ABC):
    """
    扑克AI代理的基类，定义了基本接口和功能。
    """
    
    def __init__(self, player_id: str, name: str):
        """
        初始化代理。
        
        Args:
            player_id: 玩家ID
            name: 玩家名称
        """
        self.player_id = player_id
        self.name = name
        self.hand_cards: List[str] = []  # 手牌
        self.community_cards: List[str] = []  # 公共牌
        self.chips: int = 0  # 当前筹码
        self.position: int = 0  # 位置（0为庄家）
        
    def _validate_action(
        self,
        action: str,
        amount: Optional[int],
        valid_actions: List[str],
        min_bet: int,
        max_bet: int
    ) -> bool:
        """
        验证决策是否有效。
        
        Args:
            action: 行动类型
            amount: 下注金额
            valid_actions: 有效的行动列表
            min_bet: 最小下注额
            max_bet: 最大下注额
            
        Returns:
            bool: 决策是否有效
        """
        # 检查行动类型是否有效
        if action not in valid_actions:
            return False
            
        # 对于allin，不需要指定金额，使用所有剩余筹码
        if action == 'allin':
            # 不需要验证金额，因为使用的是玩家所有的筹码
            return True
            
        # 检查下注金额
        if action == 'raise':
            if amount is None:
                return False
            if not isinstance(amount, (int, float)):
                return False
            if amount < min_bet or amount > max_bet:
                return False
        elif amount is not None:
            # 对于fold, check和call，不应该有下注金额
            return False
            
        return True
        
    def _get_default_action(self, valid_actions: List[str]) -> str:
        """
        根据策略选择默认动作，按优先级：check > call > fold
        
        Args:
            valid_actions: 有效动作列表
            
        Returns:
            str: 默认动作
        """
        # 优先选择check，其次call，最后才fold
        if 'check' in valid_actions:
            return 'check'
        elif 'call' in valid_actions:
            return 'call'
        elif 'fold' in valid_actions:
            return 'fold'
        # 如果上面都没有，返回第一个有效动作
        return valid_actions[0] if valid_actions else 'fold'
    
    def update_state(self, hand_cards: List[str], community_cards: List[str], position: str, chips: int) -> None:
        """
        更新代理状态。
        
        Args:
            hand_cards: 手牌
            community_cards: 公共牌
            position: 位置
            chips: 筹码
        """
        self.hand_cards = hand_cards
        self.community_cards = community_cards
        self.position = position
        self.chips = chips
        
    def _get_player_id(self, game_state: Dict) -> str:
        """
        从游戏状态中获取当前玩家ID。
        
        Args:
            game_state: 游戏状态
            
        Returns:
            str: 当前玩家ID
        """
        # 如果已知玩家ID，直接返回
        if self.player_id:
            return self.player_id
            
        # 尝试从游戏状态中获取当前玩家ID
        if 'currentPlayerId' in game_state:
            return game_state['currentPlayerId']
            
        # 尝试找到标记为当前玩家的玩家
        for player in game_state.get('players', []):
            if player.get('isCurrent', False):
                return player.get('id', '')
        
        # 如果都找不到，返回空字符串
        return ''
    
    @abstractmethod
    async def make_decision(
        self,
        game_state: Dict,
        valid_actions: List[str],
        min_bet: Optional[int] = None,
        max_bet: Optional[int] = None
    ) -> Tuple[str, Optional[int], Optional[str]]:
        """
        根据游戏状态做出决策。
        
        Args:
            game_state: 游戏状态
            valid_actions: 有效的行动列表
            min_bet: 最小下注额
            max_bet: 最大下注额
            
        Returns:
            Tuple[str, Optional[int], Optional[str]]: 行动类型、下注金额和思考过程
            
        Raises:
            DecisionError: 决策无效
        """
        pass 