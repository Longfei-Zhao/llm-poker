from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Dict, List, Optional
import json
import logging
import os
import time
from dotenv import load_dotenv

from .agents.llm_factory import LLMFactory
from .agents.base_agent import BaseAgent
from .config.agent_config import get_api_key, get_provider_config
from .exceptions import AIServiceError, ConfigError, PlayerError

# 加载环境变量
load_dotenv()

# 配置日志：只在这里配置一次
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

# 决策日志：每个决策输出一行结构化JSON到decisions.log（同时经root logger输出到控制台），
# 作为后续"哪个LLM赢"分析的数据集
decision_logger = logging.getLogger("decisions")
if not decision_logger.handlers:
    _decisions_file = logging.FileHandler(
        os.getenv("DECISIONS_LOG_FILE", "decisions.log"), encoding="utf-8"
    )
    _decisions_file.setFormatter(logging.Formatter("%(message)s"))
    decision_logger.addHandler(_decisions_file)
decision_logger.setLevel(logging.INFO)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动：初始化LLM工厂
    LLMFactory.init()
    providers = LLMFactory.get_user_facing_providers()
    logger.info("扑克AI服务启动，支持的LLM提供商: %s", ", ".join(providers))
    yield
    # 关闭：清理代理实例
    logger.info("扑克AI服务关闭，清理 %d 个代理实例", len(agents))
    agents.clear()

app = FastAPI(title="扑克AI服务", lifespan=lifespan)

# 配置CORS：本服务只被Node后端服务端调用，无需cookie凭证；
# 浏览器来源通过环境变量配置，默认仅允许本地开发地址
cors_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:3000,http://localhost:8080").split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 创建AI代理实例池
agents: Dict[str, BaseAgent] = {}

@app.exception_handler(AIServiceError)
async def ai_service_error_handler(request: Request, exc: AIServiceError) -> JSONResponse:
    """将AIServiceError异常层次映射为对应的HTTP状态码"""
    logger.error("%s %s 失败: [%s] %s", request.method, request.url.path, exc.error_code, exc.message)
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.message, **exc.to_dict()},
    )

class CreateAgentRequest(BaseModel):
    """创建代理请求模型"""
    player_id: str
    name: str
    provider: str
    model: Optional[str] = None
    temperature: Optional[float] = 0.7

class CreateAgentResponse(BaseModel):
    """创建代理响应模型"""
    player_id: str
    name: str
    provider: str
    model: str

class DecisionRequest(BaseModel):
    """决策请求模型"""
    player_id: str
    game_state: Dict
    valid_actions: List[str]
    min_bet: int
    max_bet: int

class DecisionResponse(BaseModel):
    """决策响应"""
    action: str
    amount: Optional[int] = None
    thinking: Optional[str] = None

class AgentInfo(BaseModel):
    """代理信息响应模型"""
    player_id: str
    name: str
    provider: str
    model: str
    status: str

@app.post("/api/agents", response_model=CreateAgentResponse)
async def create_agent(request: CreateAgentRequest) -> CreateAgentResponse:
    """
    创建AI代理。

    Args:
        request: 创建代理请求

    Returns:
        CreateAgentResponse: 创建代理响应
    """
    logger.info("收到创建AI代理请求 - 玩家ID: %s, 名称: %s, 提供商: %s, 模型: %s",
                request.player_id, request.name, request.provider, request.model or "默认")

    # 解析提供商（含别名），不支持时抛ProviderError → 400
    actual_provider = LLMFactory.resolve_provider(request.provider)

    # 从配置表读取对应提供商的API密钥
    api_key = get_api_key(actual_provider) or ""
    if not api_key and get_provider_config(actual_provider).api_key_env is not None:
        raise ConfigError(f"未配置{actual_provider}的API密钥")

    # 创建代理实例
    agent = LLMFactory.create_agent(
        provider=actual_provider,
        player_id=request.player_id,
        name=request.name,
        api_key=api_key,
        model=request.model,
        temperature=request.temperature
    )

    # 保存到代理池
    agents[request.player_id] = agent
    logger.info("代理创建成功 - 玩家ID: %s, 当前代理池大小: %d", request.player_id, len(agents))

    agent_model = getattr(agent, 'model', None) or getattr(agent, 'model_name', 'unknown')

    return CreateAgentResponse(
        player_id=agent.player_id,
        name=agent.name,
        provider=LLMFactory.display_provider(actual_provider),
        model=agent_model
    )

@app.post("/api/decision", response_model=DecisionResponse)
async def make_decision(request: DecisionRequest) -> DecisionResponse:
    """
    获取AI决策

    参数:
        request: 决策请求

    返回:
        DecisionResponse: 决策响应
    """
    logger.info("获取AI决策: 玩家%s, 有效动作: %s", request.player_id, ", ".join(request.valid_actions))

    # 获取AI代理，不存在时抛PlayerError → 404
    agent = agents.get(request.player_id)
    if not agent:
        raise PlayerError(f"找不到玩家{request.player_id}的AI代理")

    # 获取决策
    start_time = time.time()
    action, amount, thinking = await agent.make_decision(
        game_state=request.game_state,
        valid_actions=request.valid_actions,
        min_bet=request.min_bet,
        max_bet=request.max_bet
    )
    latency_ms = int((time.time() - start_time) * 1000)

    # 输出结构化决策日志（JSONL），用于后续对局数据分析
    decision_logger.info(json.dumps({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "player_id": request.player_id,
        "provider": getattr(agent, "provider", "unknown"),
        "model": getattr(agent, "model", None) or getattr(agent, "model_name", "unknown"),
        "action": action,
        "amount": amount,
        "latency_ms": latency_ms,
    }, ensure_ascii=False))

    return DecisionResponse(action=action, amount=amount, thinking=thinking)

@app.delete("/api/agents/{player_id}")
async def delete_agent(player_id: str):
    """
    删除AI代理。

    Args:
        player_id: 玩家ID
    """
    if player_id in agents:
        del agents[player_id]
        logger.info("代理删除成功 - 玩家ID: %s, 当前代理池大小: %d", player_id, len(agents))
    else:
        logger.warning("要删除的代理不存在 - 玩家ID: %s", player_id)
    return {"status": "ok"}

@app.delete("/api/agents")
async def delete_all_agents():
    """
    删除所有AI代理。

    Returns:
        删除状态
    """
    count = len(agents)
    agents.clear()
    logger.info("所有代理删除成功 - 删除数量: %d", count)
    return {"status": "ok", "message": f"已删除所有{count}个AI代理", "deleted_count": count}

@app.get("/api/health")
async def health_check():
    """健康检查接口"""
    return {"status": "ok"}

@app.get("/api/agents", response_model=List[AgentInfo])
async def list_agents() -> List[AgentInfo]:
    """
    获取所有注册的AI代理列表。

    Returns:
        List[AgentInfo]: 代理信息列表
    """
    logger.info("收到列出所有AI代理请求 - 当前代理数量: %d", len(agents))
    agent_list = []
    for player_id, agent in agents.items():
        model = getattr(agent, 'model', None) or getattr(agent, 'model_name', 'unknown')

        # 代理实例上存储了提供商标识，直接读取并转换为用户友好名称
        provider = LLMFactory.display_provider(agent.provider)

        agent_list.append(AgentInfo(
            player_id=agent.player_id,
            name=agent.name,
            provider=provider,
            model=model,
            status="active"
        ))

    return agent_list
