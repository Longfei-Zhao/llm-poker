import pytest

# 设置异步测试的事件循环
@pytest.fixture(scope="session")
def event_loop():
    """创建一个实例级别的事件循环"""
    import asyncio
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close() 