import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from src.exceptions import APIError

@pytest.fixture
def mock_genai():
    """模拟google.generativeai模块，避免真实API配置和调用"""
    with patch("src.agents.gemini_agent.genai") as genai_mock:
        model_mock = MagicMock()
        model_mock.generate_content_async = AsyncMock()
        genai_mock.GenerativeModel.return_value = model_mock
        yield genai_mock, model_mock

def _make_agent(mock_genai):
    from src.agents.gemini_agent import GeminiAgent
    return GeminiAgent(
        player_id="test_player",
        name="Test Player",
        api_key="test_key",
        model="gemini-2.0-pro-exp-02-05",
        temperature=0.7
    )

def test_init_configures_once(mock_genai):
    """测试初始化时只配置一次API并创建模型实例"""
    genai_mock, model_mock = mock_genai
    agent = _make_agent(mock_genai)

    genai_mock.configure.assert_called_once_with(api_key="test_key")
    genai_mock.GenerativeModel.assert_called_once_with(model_name="gemini-2.0-pro-exp-02-05")
    assert agent.provider == "gemini"
    assert agent.model == "gemini-2.0-pro-exp-02-05"

@pytest.mark.asyncio
async def test_make_decision_success(mock_genai, full_game_state):
    """测试成功获取决策"""
    genai_mock, model_mock = mock_genai
    agent = _make_agent(mock_genai)

    response = MagicMock()
    response.text = '{"thinking": "牌力很强，加注", "action": "raise", "amount": 100}'
    model_mock.generate_content_async.return_value = response

    action, amount, thinking = await agent.make_decision(
        game_state=full_game_state,
        valid_actions=["fold", "call", "raise"],
        min_bet=40,
        max_bet=1000
    )

    assert action == "raise"
    assert amount == 100
    assert "牌力很强" in thinking
    # 每次决策不应重复调用configure
    genai_mock.configure.assert_called_once()
    assert len(agent.decision_history) == 1

@pytest.mark.asyncio
async def test_make_decision_amount_clamped(mock_genai, full_game_state):
    """测试金额超出范围时被钳制（修复原来不传min/max的问题）"""
    genai_mock, model_mock = mock_genai
    agent = _make_agent(mock_genai)

    response = MagicMock()
    response.text = '{"action": "raise", "amount": 99999, "thinking": "全力加注"}'
    model_mock.generate_content_async.return_value = response

    action, amount, thinking = await agent.make_decision(
        game_state=full_game_state,
        valid_actions=["fold", "call", "raise"],
        min_bet=40,
        max_bet=1000
    )

    assert action == "raise"
    assert amount == 1000

@pytest.mark.asyncio
async def test_make_decision_invalid_action_falls_back(mock_genai, full_game_state):
    """测试无效动作时回退为默认动作而不是抛异常"""
    genai_mock, model_mock = mock_genai
    agent = _make_agent(mock_genai)

    response = MagicMock()
    response.text = '{"action": "allin", "thinking": "全下"}'
    model_mock.generate_content_async.return_value = response

    action, amount, thinking = await agent.make_decision(
        game_state=full_game_state,
        valid_actions=["fold", "check"],
        min_bet=40,
        max_bet=1000
    )

    assert action == "check"
    assert amount is None

@pytest.mark.asyncio
async def test_make_decision_api_error(mock_genai, full_game_state):
    """测试API调用失败时抛出APIError"""
    genai_mock, model_mock = mock_genai
    agent = _make_agent(mock_genai)

    model_mock.generate_content_async.side_effect = Exception("network error")

    with pytest.raises(APIError) as exc_info:
        await agent.make_decision(
            game_state=full_game_state,
            valid_actions=["fold", "call"],
            min_bet=40,
            max_bet=1000
        )

    assert "Gemini API调用失败" in str(exc_info.value)

def test_get_player_cards_not_found(mock_genai):
    """测试找不到玩家时返回空列表而不是None"""
    agent = _make_agent(mock_genai)
    game_state = {"players": [{"id": "someone_else", "cards": ["As", "Ks"]}]}

    assert agent._get_player_cards(game_state, "missing_player") == []
    assert agent._get_player_cards({}, "test_player") == []
    assert agent._get_player_cards(game_state, "someone_else") == ["As", "Ks"]
