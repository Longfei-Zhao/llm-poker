import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from src.agents.openai_compatible_agent import OpenAICompatibleAgent
from src.config.agent_config import get_default_model

@pytest.fixture
def agent():
    """创建DeepSeek代理实例"""
    return OpenAICompatibleAgent(
        player_id="test_player",
        name="Test Player",
        api_key="test_key",
        provider="deepseek",
        model="deepseek-chat"
    )

def test_deepseek_api_base(agent):
    """测试DeepSeek使用配置表中的API基础URL"""
    assert agent.api_base == "https://api.deepseek.com/v1"
    assert agent.provider == "deepseek"

def test_deepseek_default_model():
    """测试不指定模型时使用配置表默认模型"""
    agent = OpenAICompatibleAgent(
        player_id="test_player",
        name="Test Player",
        api_key="test_key",
        provider="deepseek"
    )
    assert agent.model == get_default_model("deepseek")

@pytest.mark.asyncio
async def test_make_decision_success(agent, full_game_state):
    """测试成功做出决策"""
    mock_response = MagicMock()
    mock_response.choices = [
        MagicMock(message=MagicMock(content='{"thinking": "跟注看翻牌", "action": "call"}'))
    ]

    with patch.object(agent.client.chat.completions, "create", new_callable=AsyncMock) as mock_create:
        mock_create.return_value = mock_response

        action, amount, thinking = await agent.make_decision(
            full_game_state, ["fold", "call", "raise"], 40, 1000
        )

    assert action == "call"
    assert amount is None
    assert thinking == "跟注看翻牌"

@pytest.mark.asyncio
async def test_reasoner_model_uses_special_parser(full_game_state):
    """测试deepseek-reasoner模型走推理专用解析逻辑"""
    agent = OpenAICompatibleAgent(
        player_id="test_player",
        name="Test Player",
        api_key="test_key",
        provider="deepseek",
        model="deepseek-reasoner"
    )

    reasoner_output = """分析当前局面：我的手牌较强，位置有利。
对手的下注模式显示其范围偏弱。

最终决策：raise 80"""

    mock_response = MagicMock()
    mock_response.choices = [
        MagicMock(message=MagicMock(content=reasoner_output))
    ]

    with patch.object(agent.client.chat.completions, "create", new_callable=AsyncMock) as mock_create:
        mock_create.return_value = mock_response

        action, amount, thinking = await agent.make_decision(
            full_game_state, ["fold", "call", "raise"], 40, 1000
        )

    assert action == "raise"
    assert amount == 80
    # 推理模型保留完整响应作为思考过程
    assert thinking == reasoner_output
