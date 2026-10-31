from typing import Dict, List, Optional
import os
from pydantic import BaseModel

# 提供商配置表——所有默认模型、API密钥环境变量、API基础URL的唯一来源。
# llm_factory、各代理类和main.py都从这里读取，避免多处维护。

class ProviderConfig(BaseModel):
    """单个LLM提供商的静态配置"""
    default_model: str
    api_key_env: Optional[str] = None  # 为None表示不需要API密钥（如本地模型）
    api_base: Optional[str] = None  # 仅OpenAI兼容提供商需要
    openai_compatible: bool = False

# 提供商配置表
PROVIDERS: Dict[str, ProviderConfig] = {
    "anthropic": ProviderConfig(
        default_model="claude-sonnet-5-5",
        api_key_env="ANTHROPIC_API_KEY",
    ),
    "openai": ProviderConfig(
        default_model="gpt-4o",
        api_key_env="OPENAI_API_KEY",
        api_base="https://api.openai.com/v1",
        openai_compatible=True,
    ),
    "deepseek": ProviderConfig(
        default_model="deepseek-chat",
        api_key_env="DEEPSEEK_API_KEY",
        api_base="https://api.deepseek.com/v1",
        openai_compatible=True,
    ),
    "gemini": ProviderConfig(
        default_model="gemini-2.0-pro-exp-02-05",
        api_key_env="GEMINI_API_KEY",
    ),
    "aliyun": ProviderConfig(
        default_model="qwen-plus",
        api_key_env="DASHSCOPE_API_KEY",
        # 阿里云通义千问的OpenAI兼容模式API
        api_base="https://dashscope.aliyuncs.com/compatible-mode/v1",
        openai_compatible=True,
    ),
    "xai": ProviderConfig(
        default_model="grok-2",
        api_key_env="XAI_API_KEY",
        api_base="https://api.x.ai/v1",
        openai_compatible=True,
    ),
    "perplexity": ProviderConfig(
        default_model="sonar",
        api_key_env="PPLX_API_KEY",
        api_base="https://api.perplexity.ai",
        openai_compatible=True,
    ),
    "moonshot": ProviderConfig(
        default_model="kimi-latest",
        api_key_env="MOONSHOT_API_KEY",
        api_base="https://api.moonshot.cn/v1",
        openai_compatible=True,
    ),
    # 火山方舟（豆包）：模型名要用方舟控制台里开通的模型或接入点ID，可在请求的model里指定
    "doubao": ProviderConfig(
        default_model="doubao-seed-1-6-250615",
        api_key_env="ARK_API_KEY",
        api_base="https://ark.cn-beijing.volces.com/api/v3",
        openai_compatible=True,
    ),
    "local": ProviderConfig(
        default_model="Qwen/Qwen2.5-32B-Instruct-AWQ",
        api_key_env=None,
    ),
}

# 提供商别名映射（支持多种名称指向同一提供商）
PROVIDER_ALIASES: Dict[str, str] = {
    "google": "gemini",  # Google的Gemini模型
    "kimi": "moonshot",
}

# 反向别名映射（用于显示）
REVERSE_ALIASES: Dict[str, str] = {
    "gemini": "google",  # 将内部的gemini显示为google
}

def get_provider_config(provider: str) -> ProviderConfig:
    """获取提供商配置，不存在时抛出KeyError"""
    return PROVIDERS[provider]

def get_default_model(provider: str) -> Optional[str]:
    """获取提供商的默认模型名称"""
    config = PROVIDERS.get(provider)
    return config.default_model if config else None

def get_api_key(provider: str) -> Optional[str]:
    """从环境变量读取提供商的API密钥；不需要密钥的提供商返回None"""
    config = PROVIDERS.get(provider)
    if config is None or config.api_key_env is None:
        return None
    return os.getenv(config.api_key_env, "")

def get_api_base(provider: str) -> Optional[str]:
    """获取提供商的API基础URL，环境变量{PROVIDER}_API_BASE可覆盖默认值"""
    custom_base = os.getenv(f"{provider.upper()}_API_BASE")
    if custom_base:
        return custom_base
    config = PROVIDERS.get(provider)
    return config.api_base if config else None

def openai_compatible_providers() -> List[str]:
    """获取所有OpenAI兼容的提供商名称"""
    return [name for name, cfg in PROVIDERS.items() if cfg.openai_compatible]
