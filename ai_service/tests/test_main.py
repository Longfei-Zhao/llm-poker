import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, AsyncMock
import os

from src.main import app, agents
from src.agents.anthropic_agent import AnthropicAgent
from src.config.agent_config import get_default_model

@pytest.fixture
def client():
    """使用上下文管理器触发lifespan"""
    agents.clear()
    with TestClient(app) as test_client:
        yield test_client
    agents.clear()

def test_health_check(client):
    """测试健康检查接口"""
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_create_agent_success(client):
    """测试成功创建代理"""
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
        assert data["model"] == get_default_model("anthropic")

def test_create_agent_missing_api_key(client):
    """测试缺少API密钥的情况 - 应返回400"""
    with patch.dict(os.environ, clear=True):
        response = client.post(
            "/api/agents",
            json={
                "player_id": "test_player",
                "name": "Test Player",
                "provider": "anthropic"
            }
        )

        assert response.status_code == 400
        assert "未配置anthropic的API密钥" in response.json()["detail"]

def test_create_agent_invalid_provider(client):
    """测试无效的提供商 - 应返回400"""
    response = client.post(
        "/api/agents",
        json={
            "player_id": "test_player",
            "name": "Test Player",
            "provider": "invalid"
        }
    )

    assert response.status_code == 400
    assert "不支持的LLM提供商" in response.json()["detail"]

def test_create_agent_with_alias(client):
    """测试提供商别名google→gemini"""
    with patch.dict(os.environ, {'GEMINI_API_KEY': 'test_key'}):
        response = client.post(
            "/api/agents",
            json={
                "player_id": "gemini_player",
                "name": "Gemini Player",
                "provider": "google"
            }
        )

        assert response.status_code == 200
        data = response.json()
        # 内部gemini显示为google
        assert data["provider"] == "google"
        assert data["model"] == get_default_model("gemini")

def test_make_decision_success(client, full_game_state):
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

    # 模拟代理决策，避免真实API调用
    with patch.object(AnthropicAgent, 'make_decision',
                      new=AsyncMock(return_value=('call', None, '底池赔率合适，跟注'))):
        response = client.post(
            "/api/decision",
            json={
                "player_id": "test_player",
                "game_state": full_game_state,
                "valid_actions": ["fold", "call", "raise"],
                "min_bet": 40,
                "max_bet": 1000
            }
        )

    assert response.status_code == 200
    data = response.json()
    assert data["action"] == "call"
    assert data["amount"] is None
    assert data["thinking"] == '底池赔率合适，跟注'

def test_make_decision_player_not_found(client):
    """测试找不到玩家的情况 - 应返回404"""
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

    assert response.status_code == 404
    assert "找不到玩家" in response.json()["detail"]

def test_delete_agent_success(client):
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

    assert response.status_code == 404
    assert "找不到玩家" in response.json()["detail"]

def test_delete_agent_not_found(client):
    """测试删除不存在的代理"""
    response = client.delete("/api/agents/invalid_player")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_delete_all_agents(client):
    """测试删除所有代理"""
    with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'test_key'}):
        client.post(
            "/api/agents",
            json={
                "player_id": "p1",
                "name": "P1",
                "provider": "anthropic"
            }
        )

    response = client.delete("/api/agents")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["deleted_count"] == 1

def test_list_agents(client):
    """测试列出所有代理"""
    with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'test_key'}):
        client.post(
            "/api/agents",
            json={
                "player_id": "test_player",
                "name": "Test Player",
                "provider": "anthropic"
            }
        )

    response = client.get("/api/agents")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["player_id"] == "test_player"
    assert data[0]["provider"] == "anthropic"
    assert data[0]["model"] == get_default_model("anthropic")
    assert data[0]["status"] == "active"

def test_chat_returns_agent_text(client):
    """赛后感言：代理只说一句话，不做决策"""
    with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'test_key'}):
        client.post("/api/agents", json={"player_id": "p1", "name": "P1", "provider": "anthropic"})
    with patch.object(AnthropicAgent, "chat", new=AsyncMock(return_value="这把牌你命好")):
        response = client.post("/api/chat", json={"player_id": "p1", "prompt": "说一句"})
    assert response.status_code == 200
    assert response.json() == {"text": "这把牌你命好"}

def test_chat_player_not_found(client):
    response = client.post("/api/chat", json={"player_id": "nobody", "prompt": "说一句"})
    assert response.status_code == 404
