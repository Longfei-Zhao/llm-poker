import pytest
from unittest.mock import patch
import os
from src.config.agent_config import AgentConfig, LLMConfig

@pytest.fixture
def config():
    """创建代理配置管理实例"""
    with patch.dict(os.environ, {
        "ANTHROPIC_API_KEY": "test_anthropic_key",
        "OPENAI_API_KEY": "test_openai_key",
        "DEEPSEEK_API_KEY": "test_deepseek_key",
        "GOOGLE_API_KEY": "test_google_key",
        "LOCAL_LLM_API_BASE": "http://localhost:8000"
    }):
        return AgentConfig()

def test_get_config_success(config):
    """测试成功获取配置"""
    # 测试Anthropic配置
    anthropic_config = config.get_config("anthropic")
    assert isinstance(anthropic_config, LLMConfig)
    assert anthropic_config.api_key == "test_anthropic_key"
    assert anthropic_config.model == "claude-3-sonnet-20240229"
    
    # 测试OpenAI配置
    openai_config = config.get_config("openai")
    assert isinstance(openai_config, LLMConfig)
    assert openai_config.api_key == "test_openai_key"
    assert openai_config.model == "gpt-4"
    
    # 测试DeepSeek配置
    deepseek_config = config.get_config("deepseek")
    assert isinstance(deepseek_config, LLMConfig)
    assert deepseek_config.api_key == "test_deepseek_key"
    assert deepseek_config.api_base == "https://api.deepseek.com/v1"
    assert deepseek_config.model == "deepseek-chat"
    
    # 测试Gemini配置
    gemini_config = config.get_config("gemini")
    assert isinstance(gemini_config, LLMConfig)
    assert gemini_config.api_key == "test_google_key"
    assert gemini_config.model == "gemini-pro"
    
    # 测试Local LLM配置
    local_config = config.get_config("local")
    assert isinstance(local_config, LLMConfig)
    assert local_config.api_base == "http://localhost:8000"
    assert local_config.model == "Qwen/Qwen2.5-32B-Instruct-AWQ"

def test_get_config_invalid_provider(config):
    """测试获取无效提供商的配置"""
    with pytest.raises(ValueError) as exc_info:
        config.get_config("invalid")
    assert "不支持的LLM提供商" in str(exc_info.value)

def test_get_config_missing_api_key():
    """测试缺少API密钥的情况"""
    with patch.dict(os.environ, clear=True):
        config = AgentConfig()
        
        # 测试Anthropic
        with pytest.raises(ValueError) as exc_info:
            config.get_config("anthropic")
        assert "未配置anthropic的API密钥" in str(exc_info.value)
        
        # 测试OpenAI
        with pytest.raises(ValueError) as exc_info:
            config.get_config("openai")
        assert "未配置openai的API密钥" in str(exc_info.value)
        
        # 测试DeepSeek
        with pytest.raises(ValueError) as exc_info:
            config.get_config("deepseek")
        assert "未配置deepseek的API密钥" in str(exc_info.value)
        
        # 测试Gemini
        with pytest.raises(ValueError) as exc_info:
            config.get_config("gemini")
        assert "未配置gemini的API密钥" in str(exc_info.value)
        
        # 测试Local LLM（不需要API密钥）
        local_config = config.get_config("local")
        assert isinstance(local_config, LLMConfig)

def test_update_config(config):
    """测试更新配置"""
    # 更新OpenAI配置
    config.update_config(
        "openai",
        api_key="new_key",
        model="gpt-4-turbo",
        temperature=0.8,
        max_tokens=200
    )
    
    openai_config = config.get_config("openai")
    assert openai_config.api_key == "new_key"
    assert openai_config.model == "gpt-4-turbo"
    assert openai_config.temperature == 0.8
    assert openai_config.max_tokens == 200

def test_update_config_invalid_provider(config):
    """测试更新无效提供商的配置"""
    with pytest.raises(ValueError) as exc_info:
        config.update_config("invalid", api_key="new_key")
    assert "不支持的LLM提供商" in str(exc_info.value)

def test_list_providers(config):
    """测试获取提供商列表"""
    providers = config.list_providers()
    assert isinstance(providers, list)
    assert len(providers) == 5
    assert "anthropic" in providers
    assert "openai" in providers
    assert "deepseek" in providers
    assert "gemini" in providers
    assert "local" in providers

def test_validate_config(config):
    """测试验证配置"""
    # 测试有效配置
    assert config.validate_config("anthropic") is True
    assert config.validate_config("openai") is True
    assert config.validate_config("deepseek") is True
    assert config.validate_config("gemini") is True
    assert config.validate_config("local") is True
    
    # 测试无效配置
    assert config.validate_config("invalid") is False
    
    # 测试缺少API密钥的配置
    with patch.dict(os.environ, clear=True):
        config = AgentConfig()
        assert config.validate_config("anthropic") is False
        assert config.validate_config("openai") is False
        assert config.validate_config("deepseek") is False
        assert config.validate_config("gemini") is False
        assert config.validate_config("local") is True  # 本地LLM不需要API密钥

def test_llm_config_validation():
    """测试LLM配置验证"""
    # 测试有效配置
    config = LLMConfig(
        api_key="test_key",
        model="test_model",
        temperature=0.7,
        max_tokens=100
    )
    assert config.temperature == 0.7
    assert config.max_tokens == 100
    
    # 测试无效的temperature
    with pytest.raises(ValueError):
        LLMConfig(
            api_key="test_key",
            model="test_model",
            temperature=1.5
        )
    
    # 测试无效的max_tokens
    with pytest.raises(ValueError):
        LLMConfig(
            api_key="test_key",
            model="test_model",
            max_tokens=0
        ) 