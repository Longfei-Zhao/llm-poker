import sys
from pathlib import Path

import pytest

# 添加项目根目录到Python路径，确保可以导入src包
project_root = str(Path(__file__).parent.parent)
if project_root not in sys.path:
    sys.path.insert(0, project_root)

@pytest.fixture
def full_game_state():
    """构建符合build_prompt要求的完整游戏状态"""
    return {
        "smallBlind": 10,
        "bigBlind": 20,
        "pot": 30,
        "currentBet": 20,
        "dealerIndex": 0,
        "communityCards": [],
        "actionHistory": [],
        "players": [
            {
                "id": "test_player",
                "name": "Test Player",
                "cards": ["As", "Ks"],
                "chips": 1000,
                "bet": 0,
                "position": 1,
                "isActive": True
            },
            {
                "id": "player2",
                "name": "Player 2",
                "cards": [],
                "chips": 900,
                "bet": 20,
                "position": 2,
                "isActive": True
            }
        ]
    }
