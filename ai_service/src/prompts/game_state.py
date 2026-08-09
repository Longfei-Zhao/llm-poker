from typing import Dict, List

def format_game_state(
    game_state: Dict,
    player_id: str,
    win_probability: float,
    hand_strength: int
) -> str:
    """
    将游戏状态格式化为提示词。
    
    Args:
        game_state: 游戏状态
        player_id: 玩家ID
        win_probability: 获胜概率
        hand_strength: 手牌强度
        
    Returns:
        str: 格式化后的游戏状态描述
    """
    # 获取玩家信息
    player = next(p for p in game_state['players'] if p['id'] == player_id)
    active_players = [p for p in game_state['players'] if p['isActive']]
    
    # 构建状态描述
    description = f"""
当前游戏状态：
- 游戏阶段：{game_state['state']}
- 底池：{game_state['pot']}
- 当前最大下注：{game_state['currentBet']}

你的信息：
- 手牌：{' '.join(player['cards'])}
- 筹码：{player['chips']}
- 已下注：{player['bet']}
- 位置：{player['position']}
- 获胜概率：{win_probability:.2%}
- 手牌强度：{hand_strength}/100

公共牌：{' '.join(game_state['communityCards']) if game_state['communityCards'] else '无'}

其他玩家（{len(active_players) - 1}人）：
"""
    print(description)
    # 添加其他玩家信息
    for p in active_players:
        if p['id'] != player_id:
            description += f"""
- 玩家 {p['name']}:
  * 筹码：{p['chips']}
  * 已下注：{p['bet']}
  * 位置：{p['position']}
"""
    
    return description 