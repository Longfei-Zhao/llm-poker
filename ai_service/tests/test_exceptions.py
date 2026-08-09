import pytest
from src.exceptions import (
    AIServiceError,
    ConfigError,
    ProviderError,
    APIError,
    ValidationError,
    PlayerError,
    DecisionError,
    TimeoutError,
    RetryError,
    StateError
)

def test_ai_service_error():
    """测试基础异常类"""
    error = AIServiceError("测试错误", "TEST_ERROR", {"key": "value"})
    
    # 测试属性
    assert str(error) == "测试错误"
    assert error.message == "测试错误"
    assert error.error_code == "TEST_ERROR"
    assert error.details == {"key": "value"}
    
    # 测试转换为字典
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "TEST_ERROR"
    assert error_dict["message"] == "测试错误"
    assert error_dict["details"] == {"key": "value"}
    
    # 测试默认details
    error = AIServiceError("测试错误", "TEST_ERROR")
    assert error.details == {}

def test_config_error():
    """测试配置错误"""
    error = ConfigError("配置错误", {"config": "invalid"})
    
    assert str(error) == "配置错误"
    assert error.error_code == "CONFIG_ERROR"
    assert error.details == {"config": "invalid"}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "CONFIG_ERROR"
    assert error_dict["message"] == "配置错误"
    assert error_dict["details"] == {"config": "invalid"}

def test_provider_error():
    """测试提供商错误"""
    error = ProviderError("提供商错误", {"provider": "invalid"})
    
    assert str(error) == "提供商错误"
    assert error.error_code == "PROVIDER_ERROR"
    assert error.details == {"provider": "invalid"}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "PROVIDER_ERROR"
    assert error_dict["message"] == "提供商错误"
    assert error_dict["details"] == {"provider": "invalid"}

def test_api_error():
    """测试API错误"""
    error = APIError("API错误", {"status": 500})
    
    assert str(error) == "API错误"
    assert error.error_code == "API_ERROR"
    assert error.details == {"status": 500}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "API_ERROR"
    assert error_dict["message"] == "API错误"
    assert error_dict["details"] == {"status": 500}

def test_validation_error():
    """测试验证错误"""
    error = ValidationError("验证错误", {"field": "invalid"})
    
    assert str(error) == "验证错误"
    assert error.error_code == "VALIDATION_ERROR"
    assert error.details == {"field": "invalid"}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "VALIDATION_ERROR"
    assert error_dict["message"] == "验证错误"
    assert error_dict["details"] == {"field": "invalid"}

def test_player_error():
    """测试玩家错误"""
    error = PlayerError("玩家错误", {"player_id": "not_found"})
    
    assert str(error) == "玩家错误"
    assert error.error_code == "PLAYER_ERROR"
    assert error.details == {"player_id": "not_found"}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "PLAYER_ERROR"
    assert error_dict["message"] == "玩家错误"
    assert error_dict["details"] == {"player_id": "not_found"}

def test_decision_error():
    """测试决策错误"""
    error = DecisionError("决策错误", {"action": "invalid"})
    
    assert str(error) == "决策错误"
    assert error.error_code == "DECISION_ERROR"
    assert error.details == {"action": "invalid"}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "DECISION_ERROR"
    assert error_dict["message"] == "决策错误"
    assert error_dict["details"] == {"action": "invalid"}

def test_timeout_error():
    """测试超时错误"""
    error = TimeoutError("超时错误", {"timeout": 30})
    
    assert str(error) == "超时错误"
    assert error.error_code == "TIMEOUT_ERROR"
    assert error.details == {"timeout": 30}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "TIMEOUT_ERROR"
    assert error_dict["message"] == "超时错误"
    assert error_dict["details"] == {"timeout": 30}

def test_retry_error():
    """测试重试错误"""
    error = RetryError("重试错误", {"attempts": 3})
    
    assert str(error) == "重试错误"
    assert error.error_code == "RETRY_ERROR"
    assert error.details == {"attempts": 3}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "RETRY_ERROR"
    assert error_dict["message"] == "重试错误"
    assert error_dict["details"] == {"attempts": 3}

def test_state_error():
    """测试状态错误"""
    error = StateError("状态错误", {"state": "invalid"})
    
    assert str(error) == "状态错误"
    assert error.error_code == "STATE_ERROR"
    assert error.details == {"state": "invalid"}
    
    error_dict = error.to_dict()
    assert error_dict["error_code"] == "STATE_ERROR"
    assert error_dict["message"] == "状态错误"
    assert error_dict["details"] == {"state": "invalid"}

def test_error_inheritance():
    """测试异常继承关系"""
    # 测试所有异常类都继承自AIServiceError
    assert issubclass(ConfigError, AIServiceError)
    assert issubclass(ProviderError, AIServiceError)
    assert issubclass(APIError, AIServiceError)
    assert issubclass(ValidationError, AIServiceError)
    assert issubclass(PlayerError, AIServiceError)
    assert issubclass(DecisionError, AIServiceError)
    assert issubclass(TimeoutError, AIServiceError)
    assert issubclass(RetryError, AIServiceError)
    assert issubclass(StateError, AIServiceError)
    
    # 测试所有异常类都继承自Exception
    assert issubclass(AIServiceError, Exception)
    assert issubclass(ConfigError, Exception)
    assert issubclass(ProviderError, Exception)
    assert issubclass(APIError, Exception)
    assert issubclass(ValidationError, Exception)
    assert issubclass(PlayerError, Exception)
    assert issubclass(DecisionError, Exception)
    assert issubclass(TimeoutError, Exception)
    assert issubclass(RetryError, Exception)
    assert issubclass(StateError, Exception) 