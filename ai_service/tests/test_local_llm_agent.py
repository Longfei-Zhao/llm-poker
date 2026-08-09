import pytest
from unittest.mock import patch, MagicMock

import src.agents.local_llm_agent as local_llm_module
from src.agents.local_llm_agent import LocalLLMAgent
from src.exceptions import ConfigError

@pytest.fixture
def agent():
    """创建Local LLM代理实例（跳过transformers依赖检查，不加载模型）"""
    with patch.object(local_llm_module, "has_transformers", True):
        return LocalLLMAgent("test_player", "Test Player", model="test-model")

@pytest.fixture
def game_state():
    """创建测试用的游戏状态"""
    return {
        "stage": "preflop",
        "pot": 30,
        "currentBet": 20,
        "currentPlayerId": "test_player",
        "communityCards": [],
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
                "chips": 900,
                "bet": 20,
                "position": 2,
                "isActive": True
            }
        ]
    }

def test_init_without_transformers():
    """测试transformers未安装时给出明确错误"""
    with patch.object(local_llm_module, "has_transformers", False):
        with pytest.raises(ConfigError) as exc_info:
            LocalLLMAgent("test_player", "Test Player")
        assert "torch" in str(exc_info.value)

def test_factory_importable_without_transformers():
    """测试工厂在没有transformers时仍可导入并注册local提供商"""
    from src.agents.llm_factory import LLMFactory
    assert "local" in LLMFactory.supported_providers()

@pytest.mark.asyncio
async def test_make_decision_returns_three_tuple(agent, game_state):
    """测试make_decision返回3元组 (action, amount, thinking)"""
    agent._is_model_loaded = True
    with patch.object(agent, "_generate_response",
                      return_value='{"action": "raise", "amount": 60}'):
        result = await agent.make_decision(
            game_state, ["fold", "call", "raise"], 40, 1000
        )

    assert len(result) == 3
    action, amount, thinking = result
    assert action == "raise"
    assert amount == 60
    assert isinstance(thinking, str)

@pytest.mark.asyncio
async def test_make_decision_invalid_action(agent, game_state):
    """测试无效动作时回退为默认动作"""
    agent._is_model_loaded = True
    with patch.object(agent, "_generate_response",
                      return_value='{"action": "invalid"}'):
        action, amount, thinking = await agent.make_decision(
            game_state, ["fold", "call", "raise"], 40, 1000
        )

    # 没有check时默认call
    assert action == "call"
    assert amount is None

@pytest.mark.asyncio
async def test_make_decision_inference_error(agent, game_state):
    """测试推理失败时返回默认动作的3元组"""
    agent._is_model_loaded = True
    with patch.object(agent, "_generate_response", side_effect=Exception("模型错误")):
        action, amount, thinking = await agent.make_decision(
            game_state, ["fold", "check", "call"], 40, 1000
        )

    # check优先于fold
    assert action == "check"
    assert amount is None
    assert "失败" in thinking

def test_parse_decision_json(agent):
    """测试JSON决策解析"""
    action, amount = agent._parse_decision(
        '决策如下：{"action": "raise", "amount": 100}',
        ["fold", "call", "raise"], 40, 1000
    )
    assert action == "raise"
    assert amount == 100

def test_parse_decision_clamps_amount(agent):
    """测试金额钳制"""
    action, amount = agent._parse_decision(
        '{"action": "raise", "amount": 5}',
        ["fold", "call", "raise"], 40, 1000
    )
    assert action == "raise"
    assert amount == 40

def test_parse_text_decision(agent):
    """测试自由文本决策解析"""
    action, amount = agent._parse_text_decision(
        "我决定call跟注", ["fold", "call", "raise"], 40, 1000
    )
    assert action == "call"
    assert amount is None

def test_parse_text_decision_fallback(agent):
    """测试文本中无动作关键词时使用默认动作"""
    action, amount = agent._parse_text_decision(
        "无法判断", ["fold", "check"], 40, 1000
    )
    assert action == "check"
    assert amount is None

def test_no_duplicate_state_fields(agent):
    """测试状态字段继承自BaseAgent（不再重复声明）"""
    agent.update_state(["As", "Ks"], ["7h"], "BTN", 500)
    assert agent.hand_cards == ["As", "Ks"]
    assert agent.community_cards == ["7h"]
    assert agent.position == "BTN"
    assert agent.chips == 500
