import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from src.agents.openai_compatible_agent import OpenAICompatibleAgent

@pytest.fixture
def agent():
    """创建OpenAI代理实例"""
    return OpenAICompatibleAgent(
        player_id='test_player',
        name='Test Player',
        api_key='test_key',
        model='gpt-4',
        temperature=0.7,
        provider='openai'
    )

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

@pytest.mark.asyncio
async def test_make_decision_success(agent, game_state):
    """测试成功获取决策"""
    # 模拟OpenAI API响应
    mock_response = MagicMock()
    mock_response.choices = [
        MagicMock(
            message=MagicMock(
                content='{"action": "raise", "amount": 100}'
            )
        )
    ]
    
    # 模拟OpenAI客户端
    with patch.object(agent.client.chat.completions, 'create', new_callable=AsyncMock) as mock_create:
        mock_create.return_value = mock_response
        
        action, amount = await agent.make_decision(
            game_state=game_state,
            valid_actions=['fold', 'call', 'raise'],
            min_bet=40,
            max_bet=1000
        )
        
        assert action == 'raise'
        assert amount == 100
        assert len(agent.decision_history) == 1
        assert agent.decision_history[0]['decision']['action'] == 'raise'
        assert agent.decision_history[0]['decision']['amount'] == 100

@pytest.mark.asyncio
async def test_make_decision_invalid_action(agent, game_state):
    """测试处理无效的行动"""
    # 模拟OpenAI API响应无效的行动
    mock_response = MagicMock()
    mock_response.choices = [
        MagicMock(
            message=MagicMock(
                content='{"action": "invalid", "amount": 100}'
            )
        )
    ]
    
    # 模拟OpenAI客户端
    with patch.object(agent.client.chat.completions, 'create', new_callable=AsyncMock) as mock_create:
        mock_create.return_value = mock_response
        
        action, amount = await agent.make_decision(
            game_state=game_state,
            valid_actions=['fold', 'call', 'raise'],
            min_bet=40,
            max_bet=1000
        )
        
        # 应该返回默认行动（fold）
        assert action == 'fold'
        assert amount is None

@pytest.mark.asyncio
async def test_make_decision_api_error(agent, game_state):
    """测试处理API错误"""
    # 模拟OpenAI API错误
    with patch.object(agent.client.chat.completions, 'create', new_callable=AsyncMock) as mock_create:
        mock_create.side_effect = Exception('API Error')
        
        action, amount = await agent.make_decision(
            game_state=game_state,
            valid_actions=['fold', 'call', 'raise'],
            min_bet=40,
            max_bet=1000
        )
        
        # 应该返回保守策略（fold）
        assert action == 'fold'
        assert amount is None

def test_format_game_state(agent, game_state):
    """测试游戏状态格式化"""
    description = agent._format_game_state(game_state)
    
    # 验证关键信息是否包含在描述中
    assert '游戏阶段：preflop' in description
    assert '底池：30' in description
    assert '当前最大下注：20' in description
    assert '手牌：AS KS' in description
    assert '筹码：1000' in description
    assert '位置：0' in description
    assert 'Player 2' in description
    assert '筹码：900' in description

def test_build_prompt(agent):
    """测试提示词构建"""
    prompt = agent._build_prompt(
        state_description='测试状态',
        valid_actions=['fold', 'call', 'raise'],
        min_bet=40,
        max_bet=1000
    )
    
    # 验证提示词内容
    assert '测试状态' in prompt
    assert 'fold（弃牌）' in prompt
    assert 'call（跟注）' in prompt
    assert 'raise（加注，范围：40-1000）' in prompt
    assert 'JSON格式的决策' in prompt
    assert '手牌强度和潜在价值' in prompt 