from typing import Dict, Optional
import os
from pydantic import BaseModel, Field

class LLMConfig(BaseModel):
    """LLM配置类"""
    api_key: Optional[str] = None
    api_base: Optional[str] = None
    model: str
    temperature: float = Field(default=0.7, ge=0.0, le=1.0)
    max_tokens: int = Field(default=100, gt=0)

class AgentConfig:
    """代理配置管理类"""
    
    def __init__(self):
        """初始化代理配置"""
        self.configs: Dict[str, LLMConfig] = {
            "anthropic": LLMConfig(
                api_key=os.getenv("ANTHROPIC_API_KEY"),
                model="claude-3-7-sonnet-20250219"
            ),
            "openai": LLMConfig(
                api_key=os.getenv("OPENAI_API_KEY"),
                model="gpt-4"
            ),
            "deepseek": LLMConfig(
                api_key=os.getenv("DEEPSEEK_API_KEY"),
                api_base=os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1"),
                model="deepseek-chat"
            ),
            "gemini": LLMConfig(
                api_key=os.getenv("GOOGLE_API_KEY"),
                model="gemini-pro"
            ),
            "local": LLMConfig(
                api_base=os.getenv("LOCAL_LLM_API_BASE", "http://localhost:8000"),
                model="Qwen/Qwen2.5-32B-Instruct-AWQ"
            )
        }
        
    def get_config(self, provider: str) -> LLMConfig:
        """获取指定提供商的配置
        
        Args:
            provider: LLM提供商名称
            
        Returns:
            LLMConfig: LLM配置对象
            
        Raises:
            ValueError: 如果提供商不存在或配置无效
        """
        if provider not in self.configs:
            raise ValueError(f"不支持的LLM提供商: {provider}")
            
        config = self.configs[provider]
        
        # 验证API密钥（本地LLM除外）
        if provider != "local" and not config.api_key:
            raise ValueError(f"未配置{provider}的API密钥")
            
        return config
        
    def update_config(self, provider: str, **kwargs) -> None:
        """更新指定提供商的配置
        
        Args:
            provider: LLM提供商名称
            **kwargs: 要更新的配置项
            
        Raises:
            ValueError: 如果提供商不存在
        """
        if provider not in self.configs:
            raise ValueError(f"不支持的LLM提供商: {provider}")
            
        config = self.configs[provider]
        for key, value in kwargs.items():
            if hasattr(config, key):
                setattr(config, key, value)
                
    def list_providers(self) -> list[str]:
        """获取所有支持的提供商列表
        
        Returns:
            list[str]: 提供商名称列表
        """
        return list(self.configs.keys())
        
    def validate_config(self, provider: str) -> bool:
        """验证指定提供商的配置是否有效
        
        Args:
            provider: LLM提供商名称
            
        Returns:
            bool: 配置是否有效
        """
        try:
            self.get_config(provider)
            return True
        except ValueError:
            return False 