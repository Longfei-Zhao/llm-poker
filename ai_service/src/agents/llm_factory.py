from typing import Dict, Type, Any, Optional, List
import logging

from .base_agent import BaseAgent
from .local_llm_agent import LocalLLMAgent
from ..exceptions import ProviderError
from ..config.agent_config import (
    PROVIDER_ALIASES,
    REVERSE_ALIASES,
    get_default_model,
    openai_compatible_providers,
)

logger = logging.getLogger(__name__)

try:
    from .openai_compatible_agent import OpenAICompatibleAgent
    openai_compatible_support = True
except ImportError as e:
    openai_compatible_support = False
    logger.warning("OpenAI兼容代理模块导入失败，禁用OpenAI兼容集成: %s", e)

try:
    from .anthropic_agent import AnthropicAgent
    anthropic_support = True
except ImportError as e:
    anthropic_support = False
    logger.warning("Anthropic代理模块导入失败，禁用anthropic集成: %s", e)

try:
    from .gemini_agent import GeminiAgent
    gemini_support = True
except ImportError as e:
    gemini_support = False
    logger.warning("Gemini代理模块导入失败，禁用gemini集成: %s", e)


class LLMFactory:
    """
    LLM工厂类，用于创建不同提供商的LLM代理。
    """

    # 注册可用的LLM代理类
    _agents: Dict[str, Type[BaseAgent]] = {
        'local': LocalLLMAgent,
    }

    @classmethod
    def init(cls) -> None:
        """初始化工厂，注册可用的LLM代理类"""
        # 注册OpenAI兼容代理（处理多种提供商）
        if openai_compatible_support:
            for provider in openai_compatible_providers():
                cls._agents[provider] = OpenAICompatibleAgent

        # 注册Anthropic专用代理
        if anthropic_support:
            cls._agents['anthropic'] = AnthropicAgent

        if gemini_support:
            cls._agents['gemini'] = GeminiAgent

        logger.info("LLM工厂初始化完成，支持的提供商: %s", ', '.join(cls._agents.keys()))

    @classmethod
    def supported_providers(cls) -> List[str]:
        """
        获取所有支持的提供商名称（含别名）

        Returns:
            List[str]: 提供商名称列表
        """
        return list(cls._agents.keys()) + [
            alias for alias, target in PROVIDER_ALIASES.items() if target in cls._agents
        ]

    @classmethod
    def resolve_provider(cls, provider: str) -> str:
        """
        将（可能是别名的）提供商名称解析为内部规范名称

        Args:
            provider: 提供商名称或别名

        Returns:
            str: 内部规范的提供商名称

        Raises:
            ProviderError: 提供商不支持
        """
        resolved = PROVIDER_ALIASES.get(provider, provider)
        if resolved not in cls._agents:
            raise ProviderError(
                f"不支持的LLM提供商: {provider}",
                details={"supported": cls.supported_providers()}
            )
        return resolved

    @classmethod
    def display_provider(cls, provider: str) -> str:
        """
        获取面向用户显示的提供商名称（如内部gemini显示为google）

        Args:
            provider: 内部提供商名称

        Returns:
            str: 用户友好的提供商名称
        """
        return REVERSE_ALIASES.get(provider, provider)

    @classmethod
    def create_agent(
        cls,
        provider: str,
        player_id: str,
        name: str,
        api_key: str,
        model: Optional[str] = None,
        temperature: float = 0.7,
        **kwargs: Any
    ) -> BaseAgent:
        """
        创建LLM代理实例

        Args:
            provider: 提供商名称 (anthropic, openai, deepseek, gemini/google, local, aliyun, xai, perplexity)
            player_id: 玩家ID
            name: 玩家名称
            api_key: API密钥
            model: 模型名称，如果为None则使用默认模型
            temperature: 温度参数
            **kwargs: 额外参数

        Returns:
            BaseAgent: LLM代理实例

        Raises:
            ProviderError: 提供商不支持
        """
        # 解析别名并检查提供商是否支持
        provider = cls.resolve_provider(provider)

        # 使用默认模型或指定模型
        model_name = model if model is not None else get_default_model(provider)
        logger.info("创建%s代理实例 - 玩家ID: %s, 名称: %s, 模型: %s", provider, player_id, name, model_name)

        # 创建代理实例
        agent_cls = cls._agents[provider]

        if provider == 'local':
            # 本地模型不需要API key
            agent = agent_cls(
                player_id=player_id,
                name=name,
                model=model_name,
                temperature=temperature,
                **kwargs
            )
        elif provider in openai_compatible_providers():
            # OpenAI兼容提供商，传递provider参数
            agent = agent_cls(
                player_id=player_id,
                name=name,
                api_key=api_key,
                model=model_name,
                temperature=temperature,
                provider=provider,  # 传递提供商标识
                **kwargs
            )
        else:
            # 其他特殊API模型
            agent = agent_cls(
                player_id=player_id,
                name=name,
                api_key=api_key,
                model=model_name,
                temperature=temperature,
                **kwargs
            )

        logger.info("代理创建成功 - 类型: %s", agent.__class__.__name__)
        return agent

    @classmethod
    def get_user_facing_providers(cls) -> List[str]:
        """
        获取面向用户显示的提供商列表

        Returns:
            List[str]: 提供商列表，使用用户友好的名称
        """
        return [cls.display_provider(provider) for provider in cls._agents.keys()]


# 初始化工厂
LLMFactory.init()
