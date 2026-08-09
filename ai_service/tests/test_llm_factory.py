import pytest
from src.agents.llm_factory import LLMFactory
from src.agents.base_agent import BaseAgent
from src.agents.llm_agent import LLMAgent
from src.agents.openai_compatible_agent import OpenAICompatibleAgent

def test_create_agent_with_valid_provider():
    """测试使用有效的提供商创建代理"""
    agent = LLMFactory.create_agent(
        provider='anthropic',
        player_id='test_player',
        name='Test Player',
        api_key='test_key'
    )
    assert isinstance(agent, LLMAgent)
    assert agent.player_id == 'test_player'
    assert agent.name == 'Test Player'
    assert agent.model == 'claude-3-sonnet-20240229'

def test_create_agent_with_custom_model():
    """测试使用自定义模型创建代理"""
    agent = LLMFactory.create_agent(
        provider='openai',
        player_id='test_player',
        name='Test Player',
        api_key='test_key',
        model='gpt-4-turbo'
    )
    assert isinstance(agent, OpenAICompatibleAgent)
    assert agent.model_name == 'gpt-4-turbo'

def test_create_agent_with_invalid_provider():
    """测试使用无效的提供商创建代理"""
    with pytest.raises(ValueError) as exc_info:
        LLMFactory.create_agent(
            provider='invalid',
            player_id='test_player',
            name='Test Player',
            api_key='test_key'
        )
    assert '不支持的LLM提供商' in str(exc_info.value)

def test_get_default_model():
    """测试获取默认模型名称"""
    assert LLMFactory._get_default_model('anthropic') == 'claude-3-sonnet-20240229'
    assert LLMFactory._get_default_model('openai') == 'gpt-4'
    assert LLMFactory._get_default_model('invalid') == '' 