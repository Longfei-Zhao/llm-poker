"""
卡片格式化模块

此模块提供了将扑克牌简写转换为更可读的文本格式的功能。
例如，将 "7h" 转换为 "7 of Hearts"，将 "As" 转换为 "Ace of Spades"。
"""

from typing import List, Union, Optional


def format_card_readable(card_code: str) -> str:
    """
    将扑克牌简写转换为可读文本格式
    
    参数:
        card_code: 扑克牌简写，如 "7h", "As"
        
    返回:
        可读的扑克牌文本，如 "7 of Hearts", "Ace of Spades"
    """
    if not card_code or len(card_code) < 2:
        return card_code
    
    # 处理简写格式，如"7h"，牌面值在前，花色在后
    rank = card_code[0]
    suit = card_code[1]
    
    # 转换牌面值
    rank_map = {
        '2': '2', '3': '3', '4': '4', '5': '5', '6': '6', 
        '7': '7', '8': '8', '9': '9', 'T': '10', 't': '10',
        'J': 'Jack', 'j': 'Jack', 
        'Q': 'Queen', 'q': 'Queen', 
        'K': 'King', 'k': 'King', 
        'A': 'Ace', 'a': 'Ace'
    }
    
    # 转换花色 - 仅使用英文文本表示，不使用Unicode符号
    suit_map = {
        's': 'Spades', 'S': 'Spades',
        'h': 'Hearts', 'H': 'Hearts',
        'd': 'Diamonds', 'D': 'Diamonds',
        'c': 'Clubs', 'C': 'Clubs'
    }
    
    rank_text = rank_map.get(rank, rank)
    suit_text = suit_map.get(suit, suit)
    
    return f"{rank_text} of {suit_text}"


def format_hand_readable(hand: Union[List[str], str]) -> Union[List[str], str]:
    """
    将整个手牌转换为可读格式
    
    参数:
        hand: 手牌列表如 ["7h", "5d"] 或 手牌字符串如 "7h5d"
        
    返回:
        格式化后的手牌，如 ["7 of Hearts", "5 of Diamonds"] 或 "7 of Hearts, 5 of Diamonds"
    """
    # 处理列表格式的手牌
    if isinstance(hand, list):
        return [format_card_readable(card) for card in hand]
    
    # 处理字符串格式的手牌，如 "7h5d"
    elif isinstance(hand, str):
        # 检查是否是单张牌
        if len(hand) == 2:
            return format_card_readable(hand)
        
        # 每两个字符解析一张牌（标准格式）
        if any(c in "shdcSHDC" for c in hand):
            cards = []
            for i in range(0, len(hand), 2):
                if i+1 < len(hand):
                    cards.append(format_card_readable(hand[i:i+2]))
            return ", ".join(cards)
    
    # 无法解析，返回原始内容
    return hand 