import pytest
from src.agents.llm_factory import LLMFactory
from src.agents.anthropic_agent import AnthropicAgent
from src.agents.openai_compatible_agent import OpenAICompatibleAgent
from src.config.agent_config import get_default_model
from src.exceptions import ProviderError

def test_create_agent_with_valid_provider():
    """测试使用有效的提供商创建代理"""
    agent = LLMFactory.create_agent(
        provider='anthropic',
        player_id='test_player',
        name='Test Player',
        api_key='test_key'
    )
    assert isinstance(agent, AnthropicAgent)
    assert agent.player_id == 'test_player'
    assert agent.name == 'Test Player'
    assert agent.provider == 'anthropic'
    assert agent.model == get_default_model('anthropic')

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
    assert agent.model == 'gpt-4-turbo'
    assert agent.provider == 'openai'

def test_create_agent_with_invalid_provider():
    """测试使用无效的提供商创建代理"""
    with pytest.raises(ProviderError) as exc_info:
        LLMFactory.create_agent(
            provider='invalid',
            player_id='test_player',
            name='Test Player',
            api_key='test_key'
        )
    assert '不支持的LLM提供商' in str(exc_info.value)

def test_supported_providers():
    """测试公开的提供商列表接口"""
    providers = LLMFactory.supported_providers()
    assert 'anthropic' in providers
    assert 'openai' in providers
    assert 'deepseek' in providers
    assert 'gemini' in providers
    assert 'local' in providers
    # 别名也应包含在内
    assert 'google' in providers

def test_resolve_provider():
    """测试提供商别名解析"""
    assert LLMFactory.resolve_provider('google') == 'gemini'
    assert LLMFactory.resolve_provider('anthropic') == 'anthropic'
    with pytest.raises(ProviderError):
        LLMFactory.resolve_provider('nonexistent')

def test_display_provider():
    """测试面向用户的提供商名称转换"""
    assert LLMFactory.display_provider('gemini') == 'google'
    assert LLMFactory.display_provider('openai') == 'openai'

def test_default_models():
    """测试默认模型来自配置表"""
    assert get_default_model('anthropic') == 'claude-3-7-sonnet-20250219'
    assert get_default_model('openai') == 'gpt-4o'
    assert get_default_model('invalid') is None
