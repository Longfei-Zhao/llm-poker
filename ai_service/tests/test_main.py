import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
import os
from src.main import app

client = TestClient(app)

@pytest.fixture
def game_state():
    """创建测试用的游戏状态"""
    return {
        'state': 'preflop',
        'pot': 30,
        'currentBet': 20,
        'communityCards': [],
        'players': [
            {
                'id': 'test_player',
                'name': 'Test Player',
                'cards': ['AS', 'KS'],
                'chips': 1000,
                'bet': 0,
                'position': 0,
                'isActive': True
            },
            {
                'id': 'player2',
                'name': 'Player 2',
                'chips': 900,
                'bet': 20,
                'position': 1,
                'isActive': True
            }
        ]
    }

def test_health_check():
    """测试健康检查接口"""
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_create_agent_success():
    """测试成功创建代理"""
    # 模拟环境变量
    with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'test_key'}):
        response = client.post(
            "/api/agents",
            json={
                "player_id": "test_player",
                "name": "Test Player",
                "provider": "anthropic"
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["player_id"] == "test_player"
        assert data["name"] == "Test Player"
        assert data["provider"] == "anthropic"
        assert data["model"] == "claude-3-sonnet-20240229"

def test_create_agent_missing_api_key():
    """测试缺少API密钥的情况"""
    # 确保环境变量中没有API密钥
    with patch.dict(os.environ, clear=True):
        response = client.post(
            "/api/agents",
            json={
                "player_id": "test_player",
                "name": "Test Player",
                "provider": "anthropic"
            }
        )
        
        assert response.status_code == 500
        assert "未配置anthropic的API密钥" in response.json()["detail"]

def test_create_agent_invalid_provider():
    """测试无效的提供商"""
    response = client.post(
        "/api/agents",
        json={
            "player_id": "test_player",
            "name": "Test Player",
            "provider": "invalid"
        }
    )
    
    assert response.status_code == 500
    assert "不支持的LLM提供商" in response.json()["detail"]

def test_make_decision_success(game_state):
    """测试成功获取决策"""
    # 先创建代理
    with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'test_key'}):
        client.post(
            "/api/agents",
            json={
                "player_id": "test_player",
                "name": "Test Player",
                "provider": "anthropic"
            }
        )
    
    # 获取决策
    response = client.post(
        "/api/decision",
        json={
            "player_id": "test_player",
            "game_state": game_state,
            "valid_actions": ["fold", "call", "raise"],
            "min_bet": 40,
            "max_bet": 1000
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert "action" in data
    assert data["action"] in ["fold", "call", "raise"]
    if data["action"] == "raise":
        assert "amount" in data
        assert isinstance(data["amount"], int)

def test_make_decision_player_not_found():
    """测试找不到玩家的情况"""
    response = client.post(
        "/api/decision",
        json={
            "player_id": "invalid_player",
            "game_state": {},
            "valid_actions": ["fold", "call", "raise"],
            "min_bet": 40,
            "max_bet": 1000
        }
    )
    
    assert response.status_code == 500
    assert "找不到玩家" in response.json()["detail"]

def test_delete_agent_success():
    """测试成功删除代理"""
    # 先创建代理
    with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'test_key'}):
        client.post(
            "/api/agents",
            json={
                "player_id": "test_player",
                "name": "Test Player",
                "provider": "anthropic"
            }
        )
    
    # 删除代理
    response = client.delete("/api/agents/test_player")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    
    # 验证代理已被删除
    response = client.post(
        "/api/decision",
        json={
            "player_id": "test_player",
            "game_state": {},
            "valid_actions": ["fold", "call", "raise"],
            "min_bet": 40,
            "max_bet": 1000
        }
    )
    
    assert response.status_code == 500
    assert "找不到玩家" in response.json()["detail"]

def test_delete_agent_not_found():
    """测试删除不存在的代理"""
    response = client.delete("/api/agents/invalid_player")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"} 