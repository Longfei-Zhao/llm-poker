import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from src.agents.openai_compatible_agent import OpenAICompatibleAgent
from src.exceptions import APIError

@pytest.fixture
def agent():
    """创建OpenAI代理实例"""
    return OpenAICompatibleAgent(
        player_id='test_player',
        name='Test Player',
        api_key='test_key',
        model='gpt-4o',
        temperature=0.7,
        provider='openai'
    )

def _mock_response(content: str):
    mock_response = MagicMock()
    mock_response.choices = [
        MagicMock(message=MagicMock(content=content))
    ]
    return mock_response

@pytest.mark.asyncio
async def test_make_decision_success(agent, full_game_state):
    """测试成功获取决策"""
    mock_response = _mock_response('{"thinking": "有同花听牌", "action": "raise", "amount": 100}')

    with patch.object(agent.client.chat.completions, 'create', new_callable=AsyncMock) as mock_create:
        mock_create.return_value = mock_response

        action, amount, thinking = await agent.make_decision(
            game_state=full_game_state,
            valid_actions=['fold', 'call', 'raise'],
            min_bet=40,
            max_bet=1000
        )

        assert action == 'raise'
        assert amount == 100
        assert thinking == '有同花听牌'
        assert len(agent.decision_history) == 1
        assert agent.decision_history[0]['action'] == 'raise'
        assert agent.decision_history[0]['amount'] == 100

@pytest.mark.asyncio
async def test_make_decision_invalid_action(agent, full_game_state):
    """测试处理无效的行动 - 应回退为默认动作"""
    mock_response = _mock_response('{"action": "invalid", "amount": 100}')

    with patch.object(agent.client.chat.completions, 'create', new_callable=AsyncMock) as mock_create:
        mock_create.return_value = mock_response

        action, amount, thinking = await agent.make_decision(
            game_state=full_game_state,
            valid_actions=['fold', 'call', 'raise'],
            min_bet=40,
            max_bet=1000
        )

        # 没有check时默认call
        assert action == 'call'
        assert amount is None

@pytest.mark.asyncio
async def test_make_decision_amount_out_of_range(agent, full_game_state):
    """测试金额超出范围时被钳制"""
    mock_response = _mock_response('{"action": "raise", "amount": 99999}')

    with patch.object(agent.client.chat.completions, 'create', new_callable=AsyncMock) as mock_create:
        mock_create.return_value = mock_response

        action, amount, thinking = await agent.make_decision(
            game_state=full_game_state,
            valid_actions=['fold', 'call', 'raise'],
            min_bet=40,
            max_bet=1000
        )

        assert action == 'raise'
        assert amount == 1000

@pytest.mark.asyncio
async def test_make_decision_api_error(agent, full_game_state):
    """测试API错误时抛出APIError"""
    with patch.object(agent.client.chat.completions, 'create', new_callable=AsyncMock) as mock_create:
        mock_create.side_effect = Exception('API Error')

        with pytest.raises(APIError) as exc_info:
            await agent.make_decision(
                game_state=full_game_state,
                valid_actions=['fold', 'call', 'raise'],
                min_bet=40,
                max_bet=1000
            )

        assert 'API' in str(exc_info.value)

def test_api_base_from_config(agent):
    """测试API基础URL来自配置表"""
    assert agent.api_base == 'https://api.openai.com/v1'

def test_reasoner_response_parsing():
    """测试DeepSeek-Reasoner响应解析"""
    agent = OpenAICompatibleAgent(
        player_id='test_player',
        name='Test Player',
        api_key='test_key',
        model='deepseek-reasoner',
        provider='deepseek'
    )

    response_text = """让我分析一下当前局面。
我持有口袋对子，翻牌没有超牌，是不错的情况。
考虑到对手的下注模式，加注是最优选择。

最终决策：raise 200"""

    action, amount, thinking = agent._parse_reasoner_response(
        response_text, ['fold', 'call', 'raise'], 40, 1000
    )
    assert action == 'raise'
    assert amount == 200
    assert thinking == response_text

def test_reasoner_response_fallback():
    """测试Reasoner响应无法解析时回退默认动作"""
    agent = OpenAICompatibleAgent(
        player_id='test_player',
        name='Test Player',
        api_key='test_key',
        model='deepseek-reasoner',
        provider='deepseek'
    )

    action, amount, thinking = agent._parse_reasoner_response(
        "完全无关的文本内容", ['fold', 'check'], 40, 1000
    )
    assert action == 'check'
    assert amount is None
