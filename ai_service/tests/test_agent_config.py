import pytest
from unittest.mock import patch
import os
from src.config.agent_config import (
    PROVIDERS,
    PROVIDER_ALIASES,
    REVERSE_ALIASES,
    get_provider_config,
    get_default_model,
    get_api_key,
    get_api_base,
    openai_compatible_providers,
)

def test_provider_table_completeness():
    """测试提供商配置表包含所有已知提供商"""
    for provider in ["anthropic", "openai", "deepseek", "gemini", "aliyun", "xai", "perplexity", "local"]:
        assert provider in PROVIDERS
        assert PROVIDERS[provider].default_model

def test_get_provider_config():
    """测试获取提供商配置"""
    config = get_provider_config("anthropic")
    assert config.default_model == "claude-sonnet-5-5"
    assert config.api_key_env == "ANTHROPIC_API_KEY"

    with pytest.raises(KeyError):
        get_provider_config("invalid")

def test_get_default_model():
    """测试获取默认模型"""
    assert get_default_model("openai") == "gpt-4o"
    assert get_default_model("deepseek") == "deepseek-chat"
    assert get_default_model("invalid") is None

def test_get_api_key():
    """测试从环境变量读取API密钥"""
    with patch.dict(os.environ, {
        "ANTHROPIC_API_KEY": "test_anthropic_key",
        "DASHSCOPE_API_KEY": "test_aliyun_key",
        "PPLX_API_KEY": "test_pplx_key",
    }):
        assert get_api_key("anthropic") == "test_anthropic_key"
        # 阿里云和perplexity使用特殊的环境变量名
        assert get_api_key("aliyun") == "test_aliyun_key"
        assert get_api_key("perplexity") == "test_pplx_key"

    # local不需要API密钥
    assert get_api_key("local") is None
    # 未知提供商返回None
    assert get_api_key("invalid") is None

def test_get_api_key_missing():
    """测试环境变量缺失时返回空字符串"""
    with patch.dict(os.environ, clear=True):
        assert get_api_key("anthropic") == ""

def test_get_api_base():
    """测试API基础URL及环境变量覆盖"""
    with patch.dict(os.environ, clear=True):
        assert get_api_base("deepseek") == "https://api.deepseek.com/v1"
        assert get_api_base("openai") == "https://api.openai.com/v1"
        # anthropic不使用OpenAI兼容URL
        assert get_api_base("anthropic") is None

    with patch.dict(os.environ, {"DEEPSEEK_API_BASE": "http://proxy.example.com/v1"}):
        assert get_api_base("deepseek") == "http://proxy.example.com/v1"

def test_openai_compatible_providers():
    """测试OpenAI兼容提供商列表"""
    providers = openai_compatible_providers()
    assert set(providers) == {"openai", "deepseek", "aliyun", "xai", "perplexity", "moonshot", "doubao"}

def test_aliases():
    """测试别名映射"""
    assert PROVIDER_ALIASES["google"] == "gemini"
    assert REVERSE_ALIASES["gemini"] == "google"
