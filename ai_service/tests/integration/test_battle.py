import pytest
import unittest.mock
import os
import json
from src.agents.llm_factory import LLMFactory
from src.agents.base_agent import BaseAgent
from src.exceptions import APIError, DecisionError

@pytest.fixture
def agent_factory():
    """创建代理工厂实例"""
    factory = LLMFactory()
    return factory

@pytest.fixture
def game_state():
    """模拟游戏状态"""
    return {
        "players": [
            {"id": "p1", "name": "Claude", "chips": 1000, "cards": ["As", "Kh"]},
            {"id": "p2", "name": "GPT4", "chips": 1000, "cards": ["Qd", "Jc"]},
            {"id": "p3", "name": "DeepSeek", "chips": 1000, "cards": ["Ts", "9s"]}
        ],
        "community_cards": ["7h", "8d", "9h"],
        "pot": 300,
        "current_bet": 100,
        "min_raise": 100
    }

@pytest.mark.asyncio
async def test_three_player_battle(agent_factory, game_state):
    """测试三人对战场景"""
    # 创建代理
    claude = agent_factory.create_agent("anthropic", "p1", "Claude", api_key="test_key")
    gpt4 = agent_factory.create_agent("openai", "p2", "GPT4", api_key="test_key")
    deepseek = agent_factory.create_agent("deepseek", "p3", "DeepSeek", api_key="test_key")
    
    # 模拟API响应
    with unittest.mock.patch.object(claude, "make_decision") as mock_claude, \
         unittest.mock.patch.object(gpt4, "make_decision") as mock_gpt4, \
         unittest.mock.patch.object(deepseek, "make_decision") as mock_deepseek:
        
        mock_claude.return_value = {"action": "raise", "amount": 200}
        mock_gpt4.return_value = {"action": "call", "amount": 200}
        mock_deepseek.return_value = {"action": "fold", "amount": 0}
        
        # 执行决策
        claude_decision = await claude.make_decision(game_state)
        gpt4_decision = await gpt4.make_decision(game_state)
        deepseek_decision = await deepseek.make_decision(game_state)
        
        # 验证决策
        assert claude_decision["action"] == "raise"
        assert claude_decision["amount"] == 200
        assert gpt4_decision["action"] == "call"
        assert gpt4_decision["amount"] == 200
        assert deepseek_decision["action"] == "fold"
        assert deepseek_decision["amount"] == 0
        
        # 验证API调用次数
        assert mock_claude.call_count == 1
        assert mock_gpt4.call_count == 1
        assert mock_deepseek.call_count == 1

@pytest.mark.asyncio
async def test_heads_up_battle(agent_factory):
    """测试单挑场景"""
    # 创建代理
    gemini = agent_factory.create_agent("gemini", "p1", "Gemini", api_key="test_key")
    qwen = agent_factory.create_agent("local", "p2", "Qwen", api_key="test_key")
    
    game_state = {
        "players": [
            {"id": "p1", "name": "Gemini", "chips": 1000, "cards": ["Ah", "Ad"]},
            {"id": "p2", "name": "Qwen", "chips": 1000, "cards": ["Ks", "Kc"]}
        ],
        "community_cards": ["7h", "8d", "9h"],
        "pot": 200,
        "current_bet": 100,
        "min_raise": 100
    }
    
    # 模拟API响应
    with unittest.mock.patch.object(gemini, "make_decision") as mock_gemini, \
         unittest.mock.patch.object(qwen, "make_decision") as mock_qwen:
        
        mock_gemini.return_value = {"action": "raise", "amount": 300}
        mock_qwen.return_value = {"action": "call", "amount": 300}
        
        # 执行决策
        gemini_decision = await gemini.make_decision(game_state)
        qwen_decision = await qwen.make_decision(game_state)
        
        # 验证决策
        assert gemini_decision["action"] == "raise"
        assert gemini_decision["amount"] == 300
        assert qwen_decision["action"] == "call"
        assert qwen_decision["amount"] == 300
        
        # 验证API调用次数
        assert mock_gemini.call_count == 1
        assert mock_qwen.call_count == 1

@pytest.mark.asyncio
async def test_error_handling(agent_factory, game_state):
    """测试错误处理"""
    agent = agent_factory.create_agent("anthropic", "p1", "Claude", api_key="test_key")
    
    # 模拟API错误
    with unittest.mock.patch.object(agent, "make_decision") as mock_decision:
        mock_decision.side_effect = APIError("API调用失败")
        
        # 验证是否抛出异常
        with pytest.raises(APIError) as exc_info:
            await agent.make_decision(game_state)
        
        assert str(exc_info.value) == "API调用失败"
        assert mock_decision.call_count == 1

@pytest.mark.asyncio
async def test_invalid_response(agent_factory, game_state):
    """测试无效响应处理"""
    agent = agent_factory.create_agent("anthropic", "p1", "Claude", api_key="test_key")
    
    # 模拟无效响应
    with unittest.mock.patch.object(agent, "make_decision") as mock_decision:
        mock_decision.return_value = {"action": "invalid", "amount": -100}
        
        # 验证是否抛出异常
        with pytest.raises(DecisionError) as exc_info:
            await agent.make_decision(game_state)
        
        assert "无效的决策" in str(exc_info.value)
        assert mock_decision.call_count == 1 