from typing import Optional

class AIServiceError(Exception):
    """AI服务基础异常类"""

    # 映射到HTTP响应的状态码，子类覆盖
    status_code: int = 500

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
    """配置相关错误（如缺少API密钥）"""

    status_code = 400

    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "CONFIG_ERROR", details)

class ProviderError(AIServiceError):
    """LLM提供商相关错误（如不支持的提供商）"""

    status_code = 400

    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "PROVIDER_ERROR", details)

class PlayerError(AIServiceError):
    """玩家相关错误（如找不到玩家的代理）"""

    status_code = 404

    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "PLAYER_ERROR", details)

class APIError(AIServiceError):
    """上游LLM API调用相关错误"""

    status_code = 502

    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "API_ERROR", details)

class DecisionError(AIServiceError):
    """决策相关错误"""

    status_code = 500

    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "DECISION_ERROR", details)
