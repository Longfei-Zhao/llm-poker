from typing import Dict, Type, Any, Optional, List
from .base_agent import BaseAgent
from .local_llm_agent import LocalLLMAgent

# 导入新的统一OpenAI兼容代理类
try:
    from .openai_compatible_agent import OpenAICompatibleAgent
    openai_compatible_support = True
    print("✅ OpenAI兼容代理模块导入成功")
except ImportError as e:
    openai_compatible_support = False
    print(f"⚠️ OpenAI兼容代理模块导入失败，原因: {str(e)}")
    print("⚠️ 禁用OpenAI兼容集成")

# 弃用LLMAgent，改为使用专门的AnthropicAgent
try:
    from .anthropic_agent import AnthropicAgent
    anthropic_support = True
    print("✅ Anthropic代理模块导入成功")
except ImportError as e:
    anthropic_support = False
    print(f"⚠️ Anthropic代理模块导入失败，原因: {str(e)}")
    print("⚠️ 禁用anthropic集成")

try:
    from .gemini_agent import GeminiAgent
    gemini_support = True
    print("✅ Gemini代理模块导入成功")
except ImportError:
    gemini_support = False
    print("⚠️ Gemini代理模块导入失败，禁用gemini集成")

# 为了向后兼容，保留LLMAgent的导入
try:
    from .llm_agent import LLMAgent
    llm_legacy_support = True
    print("⚠️ LLMAgent模块已弃用，但为了兼容性已导入")
except ImportError:
    llm_legacy_support = False
    print("⚠️ 弃用的LLMAgent模块导入失败")

# 移除不再单独使用的代理导入
# try:
#     from .openai_agent import OpenAIAgent
#     openai_support = True
#     print("✅ OpenAI代理模块导入成功")
# except ImportError:
#     openai_support = False
#     print("⚠️ OpenAI代理模块导入失败，禁用openai集成")

# try:
#     from .deepseek_agent import DeepseekAgent
#     deepseek_support = True
#     print("✅ DeepSeek代理模块导入成功")
# except ImportError:
#     deepseek_support = False
#     print("⚠️ DeepSeek代理模块导入失败，禁用deepseek集成")

# try:
#     from .xai_agent import XAIAgent
#     xai_support = True
#     print("✅ XAI代理模块导入成功")
# except ImportError:
#     xai_support = False
#     print("⚠️ XAI代理模块导入失败，禁用xai集成")


class LLMFactory:
    """
    LLM工厂类，用于创建不同提供商的LLM代理。
    """
    
    # 注册可用的LLM代理类
    _agents: Dict[str, Type[BaseAgent]] = {
        'local': LocalLLMAgent,
    }
    
    # OpenAI兼容的提供商列表
    _openai_compatible_providers = ['openai', 'deepseek', 'aliyun', 'xai', 'perplexity']
    
    # 提供商别名映射（支持多种名称指向同一提供商）
    _provider_aliases = {
        'google': 'gemini',  # Google的Gemini模型
    }
    
    # 反向别名映射（用于显示）
    _reverse_aliases = {
        'gemini': 'google',  # 将内部的gemini显示为google
    }
    
    # 默认模型映射
    _default_models = {
        'anthropic': 'claude-3-7-sonnet-20250219', 
        'openai': 'gpt-4o',
        'deepseek': 'deepseek-chat',
        'gemini': 'gemini-2.0-pro-exp-02-05',
        'local': 'Qwen/Qwen2.5-32B-Instruct-AWQ',
        'aliyun': 'qwen-plus',
        'xai': 'grok-2',
    }
    
    @classmethod
    def init(cls) -> None:
        """初始化工厂，注册可用的LLM代理类"""
        print("🏭 初始化LLM工厂")
        
        # 注册OpenAI兼容代理（处理多种提供商）
        if openai_compatible_support:
            for provider in cls._openai_compatible_providers:
                cls._agents[provider] = OpenAICompatibleAgent
                print(f"✅ 注册{provider}提供商到OpenAI兼容代理类")
        
        # 注册Anthropic专用代理
        if anthropic_support:
            cls._agents['anthropic'] = AnthropicAgent
            print("✅ 注册Anthropic专用代理类")
            
        if gemini_support:
            cls._agents['gemini'] = GeminiAgent
            print("✅ 注册Gemini代理类")
        
        print(f"📋 支持的提供商: {', '.join(cls._agents.keys())}")
    
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
            provider: 提供商名称 (anthropic, openai, deepseek, gemini/google, local, aliyun, xai)
            player_id: 玩家ID
            name: 玩家名称
            api_key: API密钥
            model: 模型名称，如果为None则使用默认模型
            temperature: 温度参数
            **kwargs: 额外参数
            
        Returns:
            BaseAgent: LLM代理实例
        """
        print(f"🔍 创建{provider}代理实例 - 玩家ID: {player_id}, 名称: {name}")
        
        # 检查提供商别名映射
        if provider in cls._provider_aliases:
            original_provider = provider
            provider = cls._provider_aliases[provider]
            print(f"📝 提供商别名: {original_provider} → {provider}")
        
        # 检查提供商是否支持
        if provider not in cls._agents:
            print(f"❌ 不支持的提供商: {provider}, 可用: {list(cls._agents.keys())}")
            raise ValueError(f"不支持的提供商: {provider}")
        
        # 使用默认模型或指定模型
        model_name = model if model is not None else cls._default_models.get(provider)
        print(f"🤖 使用模型: {model_name or '未指定'} ({provider}提供商)")
        
        # 创建代理实例
        agent_cls = cls._agents[provider]
        
        if provider == 'local':
            # 本地模型不需要API key
            print(f"🔄 创建本地代理，模型: {model_name}")
            agent = agent_cls(
                player_id=player_id,
                name=name,
                model=model_name,
                temperature=temperature,
                **kwargs
            )
        elif provider in cls._openai_compatible_providers:
            # OpenAI兼容提供商，传递provider参数
            print(f"🔄 创建OpenAI兼容代理，提供商: {provider}, API Key长度: {len(api_key)} 字符")
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
            print(f"🔄 创建{provider}代理，API Key长度: {len(api_key)} 字符")
            agent = agent_cls(
                player_id=player_id,
                name=name,
                api_key=api_key,
                model=model_name,
                temperature=temperature,
                **kwargs
            )
        
        print(f"✅ 代理创建成功 - 类型: {agent.__class__.__name__}")
        return agent

    @classmethod
    def get_user_facing_providers(cls) -> List[str]:
        """
        获取面向用户显示的提供商列表
        
        Returns:
            List[str]: 提供商列表，使用用户友好的名称
        """
        # 将内部提供商名称转换为面向用户的名称
        user_providers = []
        for provider in cls._agents.keys():
            # 如果有反向别名，使用别名
            if provider in cls._reverse_aliases:
                user_providers.append(cls._reverse_aliases[provider])
            else:
                user_providers.append(provider)
        return user_providers


# 初始化工厂
LLMFactory.init() 