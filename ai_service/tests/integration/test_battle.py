import pytest
from unittest.mock import AsyncMock, patch

from src.agents.llm_factory import LLMFactory
from src.agents.anthropic_agent import AnthropicAgent
from src.agents.openai_compatible_agent import OpenAICompatibleAgent
from src.exceptions import APIError

@pytest.fixture
def game_state():
    """模拟游戏状态"""
    return {
        "smallBlind": 10,
        "bigBlind": 20,
        "pot": 300,
        "currentBet": 100,
        "dealerIndex": 0,
        "communityCards": ["7h", "8d", "9h"],
        "actionHistory": [],
        "players": [
            {"id": "p1", "name": "Claude", "chips": 1000, "cards": ["As", "Kh"], "bet": 0, "position": 1, "isActive": True},
            {"id": "p2", "name": "GPT4", "chips": 1000, "cards": ["Qd", "Jc"], "bet": 0, "position": 2, "isActive": True},
            {"id": "p3", "name": "DeepSeek", "chips": 1000, "cards": ["Ts", "9s"], "bet": 100, "position": 3, "isActive": True}
        ],
    }

@pytest.mark.asyncio
async def test_three_player_battle(game_state):
    """测试三人对战场景：工厂创建三种代理并按3元组契约返回决策"""
    claude = LLMFactory.create_agent("anthropic", "p1", "Claude", api_key="test_key")
    gpt4 = LLMFactory.create_agent("openai", "p2", "GPT4", api_key="test_key")
    deepseek = LLMFactory.create_agent("deepseek", "p3", "DeepSeek", api_key="test_key")

    assert isinstance(claude, AnthropicAgent)
    assert isinstance(gpt4, OpenAICompatibleAgent)
    assert isinstance(deepseek, OpenAICompatibleAgent)
    assert deepseek.provider == "deepseek"

    valid_actions = ["fold", "call", "raise"]

    # 模拟API响应（3元组契约: action, amount, thinking）
    with patch.object(claude, "make_decision", new=AsyncMock(return_value=("raise", 200, "价值加注"))), \
         patch.object(gpt4, "make_decision", new=AsyncMock(return_value=("call", None, "跟注"))), \
         patch.object(deepseek, "make_decision", new=AsyncMock(return_value=("fold", None, "弃牌"))):

        claude_action, claude_amount, _ = await claude.make_decision(game_state, valid_actions, 200, 1000)
        gpt4_action, gpt4_amount, _ = await gpt4.make_decision(game_state, valid_actions, 200, 1000)
        deepseek_action, deepseek_amount, _ = await deepseek.make_decision(game_state, valid_actions, 200, 1000)

    assert claude_action == "raise"
    assert claude_amount == 200
    assert gpt4_action == "call"
    assert gpt4_amount is None
    assert deepseek_action == "fold"
    assert deepseek_amount is None

@pytest.mark.asyncio
async def test_error_handling(game_state):
    """测试底层API失败时代理抛出APIError"""
    agent = LLMFactory.create_agent("anthropic", "p1", "Claude", api_key="test_key")

    with patch.object(agent.client.messages, "create", new_callable=AsyncMock) as mock_create:
        mock_create.side_effect = Exception("API调用失败")

        with pytest.raises(APIError):
            await agent.make_decision(game_state, ["fold", "call"], 40, 1000)

@pytest.mark.asyncio
async def test_invalid_response_falls_back(game_state):
    """测试无效响应时回退为默认动作而不是崩溃"""
    agent = LLMFactory.create_agent("anthropic", "p1", "Claude", api_key="test_key")

    with patch.object(agent.client.messages, "create", new_callable=AsyncMock) as mock_create:
        response = mock_create.return_value
        content_block = type("ContentBlock", (), {"text": '{"action": "invalid", "amount": -100}'})()
        response.content = [content_block]

        action, amount, thinking = await agent.make_decision(game_state, ["fold", "call"], 40, 1000)

    # 无check时回退到call
    assert action == "call"
    assert amount is None
