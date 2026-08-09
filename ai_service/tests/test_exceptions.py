from src.exceptions import (
    AIServiceError,
    ConfigError,
    ProviderError,
    APIError,
    PlayerError,
    DecisionError,
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

def test_error_codes_and_status():
    """测试各异常类的错误代码和HTTP状态码映射"""
    cases = [
        (ConfigError("配置错误"), "CONFIG_ERROR", 400),
        (ProviderError("提供商错误"), "PROVIDER_ERROR", 400),
        (PlayerError("玩家错误"), "PLAYER_ERROR", 404),
        (APIError("API错误"), "API_ERROR", 502),
        (DecisionError("决策错误"), "DECISION_ERROR", 500),
    ]
    for error, expected_code, expected_status in cases:
        assert error.error_code == expected_code
        assert error.status_code == expected_status

def test_error_details():
    """测试异常详情传递"""
    error = ProviderError("提供商错误", {"provider": "invalid"})
    assert error.details == {"provider": "invalid"}
    assert error.to_dict()["details"] == {"provider": "invalid"}

def test_error_inheritance():
    """测试异常继承关系"""
    for cls in (ConfigError, ProviderError, APIError, PlayerError, DecisionError):
        assert issubclass(cls, AIServiceError)
        assert issubclass(cls, Exception)
