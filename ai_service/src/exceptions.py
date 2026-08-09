from typing import Optional

class AIServiceError(Exception):
    """AI服务基础异常类"""
    
    def __init__(self, message: str, error_code: str, details: Optional[dict] = None):
        """初始化异常
        
        Args:
            message: 错误消息
            error_code: 错误代码
            details: 错误详情
        """
        super().__init__(message)
        self.message = message
        self.error_code = error_code
        self.details = details or {}
        
    def to_dict(self) -> dict:
        """转换为字典格式
        
        Returns:
            dict: 包含错误信息的字典
        """
        return {
            "error_code": self.error_code,
            "message": self.message,
            "details": self.details
        }

class ConfigError(AIServiceError):
    """配置相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "CONFIG_ERROR", details)

class ProviderError(AIServiceError):
    """LLM提供商相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "PROVIDER_ERROR", details)

class APIError(AIServiceError):
    """API调用相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "API_ERROR", details)

class ValidationError(AIServiceError):
    """输入验证相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "VALIDATION_ERROR", details)

class PlayerError(AIServiceError):
    """玩家相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "PLAYER_ERROR", details)

class DecisionError(AIServiceError):
    """决策相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "DECISION_ERROR", details)

class TimeoutError(AIServiceError):
    """超时相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "TIMEOUT_ERROR", details)

class RetryError(AIServiceError):
    """重试相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "RETRY_ERROR", details)

class StateError(AIServiceError):
    """状态相关错误"""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "STATE_ERROR", details) 