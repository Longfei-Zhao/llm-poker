import pytest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from src.agents.anthropic_agent import AnthropicAgent
from src.exceptions import APIError, DecisionError

GAME_STATE = {
    "smallBlind": 5, "bigBlind": 10, "pot": 15, "currentBet": 10, "dealerIndex": 0,
    "communityCards": [], "actionHistory": [],
    "players": [
        {"id": "p1", "name": "克劳德爵士", "position": 1, "chips": 1000, "bet": 5, "isActive": True, "cards": ["Ah", "Kd"]},
        {"id": "p2", "name": "狂客", "position": 2, "chips": 1000, "bet": 10, "isActive": True, "cards": []},
    ],
}


def reply(text, stop_reason="end_turn"):
    content = [SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text=text)]
    return SimpleNamespace(content=content, stop_reason=stop_reason, stop_details=None, model_extra={})


def make_agent():
    with patch("anthropic.AsyncAnthropic"):
        agent = AnthropicAgent(player_id="p1", name="克劳德爵士", api_key="test", model="claude-fable-5-1")
    agent.client = SimpleNamespace(messages=SimpleNamespace(create=AsyncMock()))
    return agent


@pytest.mark.asyncio
async def test_reads_text_block_after_thinking_and_sends_no_temperature():
    agent = make_agent()
    agent.client.messages.create.return_value = reply('{"inner": "AK同花", "speech": "恕我直言", "action": "call"}')
    action, amount, thinking = await agent.make_decision(GAME_STATE, ["fold", "call", "raise"], 20, 1005)
    assert (action, thinking, agent.last_speech) == ("call", "AK同花", "恕我直言")
    kwargs = agent.client.messages.create.call_args.kwargs
    assert "temperature" not in kwargs
    assert kwargs["extra_body"]["output_config"] == {"effort": "medium"}


@pytest.mark.asyncio
async def test_refusal_retries_on_fallback_model():
    agent = make_agent()
    agent.client.messages.create.side_effect = [reply("", "refusal"), reply('{"inner": "跟", "speech": "请", "action": "call"}')]
    action, _, _ = await agent.make_decision(GAME_STATE, ["fold", "call", "raise"], 20, 1005)
    assert action == "call"
    models = [c.kwargs["model"] for c in agent.client.messages.create.call_args_list]
    assert models == ["claude-fable-5-1", "claude-opus-5-5"]


@pytest.mark.asyncio
async def test_refusal_on_every_model_raises():
    agent = make_agent()
    agent.client.messages.create.side_effect = [reply("", "refusal"), reply("", "refusal")]
    with pytest.raises((DecisionError, APIError)):
        await agent.make_decision(GAME_STATE, ["fold", "call", "raise"], 20, 1005)


@pytest.mark.asyncio
async def test_finds_itself_by_acting_player_id_when_agent_id_has_table_prefix():
    """多桌并行时代理ID是 t2-p1 这种，靠 actingPlayerId 找到牌桌上的自己"""
    agent = make_agent()
    agent.player_id = "t2-p1"
    agent.client.messages.create.return_value = reply('{"inner": "AK同花", "speech": "请", "action": "call"}')
    state = {**GAME_STATE, "actingPlayerId": "p1"}
    action, _, _ = await agent.make_decision(state, ["fold", "call", "raise"], 20, 1005)
    assert action == "call"
    assert "name: 克劳德爵士" in agent.client.messages.create.call_args.kwargs["messages"][0]["content"]
