import pytest
from unittest.mock import patch, AsyncMock, MagicMock
import os
import json
from src.agents.local_llm_agent import LocalLLMAgent

@pytest.fixture
def agent():
    """创建Local LLM代理实例"""
    with patch.dict(os.environ, {"LOCAL_LLM_API_BASE": "http://localhost:8000"}):
        return LocalLLMAgent("test_player", "Test Player")

@pytest.fixture
def game_state():
    """创建测试用的游戏状态"""
    return {
        "state": "preflop",
        "pot": 30,
        "currentBet": 20,
        "communityCards": [],
        "players": [
            {
                "id": "test_player",
                "name": "Test Player",
                "cards": ["AS", "KS"],
                "chips": 1000,
                "bet": 0,
                "position": 0,
                "isActive": True
            },
            {
                "id": "player2",
                "name": "Player 2",
                "chips": 900,
                "bet": 20,
                "position": 1,
                "isActive": True
            }
        ]
    }

@pytest.mark.asyncio
async def test_make_decision_success(agent, game_state):
    """测试成功做出决策"""
    # 模拟API响应
    mock_response = MagicMock()
    mock_response.raise_for_status = MagicMock()
    mock_response.json.return_value = {
        "choices": [
            {
                "message": {
                    "content": '{"action": "raise", "amount": 60}'
                }
            }
        ]
    }
    
    # 模拟httpx客户端
    mock_client = AsyncMock()
    mock_client.post.return_value = mock_response
    agent.client = mock_client
    
    # 调用决策方法
    decision = await agent.make_decision(
        game_state,
        ["fold", "call", "raise"],
        40,
        1000
    )
    
    # 验证结果
    assert decision["action"] == "raise"
    assert decision["amount"] == 60
    
    # 验证API调用
    mock_client.post.assert_called_once()
    call_args = mock_client.post.call_args
    assert call_args[0][0] == "http://localhost:8000/v1/chat/completions"
    assert call_args[1]["json"]["model"] == "Qwen/Qwen2.5-32B-Instruct-AWQ"
    
@pytest.mark.asyncio
async def test_make_decision_invalid_action(agent, game_state):
    """测试处理无效动作"""
    # 模拟API返回无效动作
    mock_response = MagicMock()
    mock_response.raise_for_status = MagicMock()
    mock_response.json.return_value = {
        "choices": [
            {
                "message": {
                    "content": '{"action": "invalid"}'
                }
            }
        ]
    }
    
    mock_client = AsyncMock()
    mock_client.post.return_value = mock_response
    agent.client = mock_client
    
    # 调用决策方法
    decision = await agent.make_decision(
        game_state,
        ["fold", "call", "raise"],
        40,
        1000
    )
    
    # 验证结果（应该默认fold）
    assert decision["action"] == "fold"

@pytest.mark.asyncio
async def test_make_decision_api_error(agent, game_state):
    """测试API错误处理"""
    # 模拟API错误
    mock_client = AsyncMock()
    mock_client.post.side_effect = Exception("API Error")
    agent.client = mock_client
    
    # 调用决策方法
    decision = await agent.make_decision(
        game_state,
        ["fold", "call", "raise"],
        40,
        1000
    )
    
    # 验证结果（应该默认fold）
    assert decision["action"] == "fold"

def test_format_game_state(agent, game_state):
    """测试游戏状态格式化"""
    formatted_state = agent._format_game_state(game_state)
    
    # 验证格式化结果包含关键信息
    assert "游戏阶段: preflop" in formatted_state
    assert "底池: 30" in formatted_state
    assert "当前最大下注: 20" in formatted_state
    assert "手牌: AS, KS" in formatted_state
    assert "Player 2" in formatted_state

def test_build_prompt(agent, game_state):
    """测试提示词构建"""
    prompt = agent._build_prompt(
        game_state,
        ["fold", "call", "raise"],
        40,
        1000
    )
    
    # 验证提示词包含必要信息
    assert "游戏阶段: preflop" in prompt
    assert "你可以采取的动作" in prompt
    assert "fold, call, raise" in prompt
    assert "最小: 40" in prompt
    assert "最大: 1000" in prompt
    assert "必须是一个JSON字符串" in prompt

def test_format_game_state_player_not_found(agent):
    """测试找不到玩家的情况"""
    invalid_state = {
        "state": "preflop",
        "pot": 30,
        "currentBet": 20,
        "communityCards": [],
        "players": [
            {
                "id": "other_player",
                "name": "Other Player",
                "chips": 1000,
                "bet": 0,
                "position": 0,
                "isActive": True
            }
        ]
    }
    
    with pytest.raises(ValueError) as exc_info:
        agent._format_game_state(invalid_state)
    assert "在游戏状态中找不到当前玩家" in str(exc_info.value) 