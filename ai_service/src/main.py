from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, List, Optional
import os
import json
from dotenv import load_dotenv

from .agents.llm_factory import LLMFactory
from .agents.base_agent import BaseAgent

# 加载环境变量
load_dotenv()
print("🔧 环境变量加载完成")

app = FastAPI(title="扑克AI服务")

# 配置CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 在生产环境中应该设置具体的源
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
print("🚀 FastAPI应用已初始化，CORS已配置")

# 创建AI代理实例池
agents: Dict[str, BaseAgent] = {}
print(f"📋 AI代理实例池初始化完成，当前数量: {len(agents)}")

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
    print(f"📥 收到创建AI代理请求 - 玩家ID: {request.player_id}, 名称: {request.name}, 提供商: {request.provider}, 模型: {request.model or '默认'}")
    try:
        # 获取所有支持的提供商（包括别名）
        supported_providers = list(LLMFactory._agents.keys()) + list(LLMFactory._provider_aliases.keys())
        
        # 检查提供商是否支持
        if request.provider not in supported_providers:
            print(f"❌ 不支持的LLM提供商: {request.provider}")
            raise ValueError(f"不支持的LLM提供商: {request.provider}")
            
        # 获取实际的提供商名称（处理别名）
        actual_provider = request.provider
        if request.provider in LLMFactory._provider_aliases:
            actual_provider = LLMFactory._provider_aliases[request.provider]
            print(f"📝 提供商别名转换: {request.provider} → {actual_provider}")
            
        # 获取对应提供商的API密钥
        api_key = os.getenv(f"{actual_provider.upper()}_API_KEY", "")
        # 特殊处理perplexity，使用PPLX_API_KEY
        if actual_provider == "perplexity":
            api_key = os.getenv("PPLX_API_KEY", "")
        if actual_provider == "aliyun":
            api_key = os.getenv("DASHSCOPE_API_KEY", "")
        if not api_key and actual_provider not in ["local"]:
            print(f"❌ 未配置{actual_provider}的API密钥")
            raise ValueError(f"未配置{actual_provider}的API密钥")
        
        print(f"✅ API密钥已找到: {actual_provider}")    
        
        # 创建代理实例
        print(f"🔄 正在创建代理实例 - 提供商: {actual_provider}, 模型: {request.model or '默认'}")
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
        print(f"✅ 代理创建成功 - 玩家ID: {request.player_id}, 当前代理池大小: {len(agents)}")
        
        agent_model = agent.model_name if hasattr(agent, 'model_name') else agent.model
        
        # 获取用户友好的提供商名称，用于返回
        user_provider = actual_provider
        if actual_provider in LLMFactory._reverse_aliases:
            user_provider = LLMFactory._reverse_aliases[actual_provider]
            print(f"📝 提供商显示转换: {actual_provider} → {user_provider}")
        
        print(f"📤 返回代理信息 - 玩家ID: {agent.player_id}, 名称: {agent.name}, 提供商: {user_provider}, 模型: {agent_model}")
        
        return CreateAgentResponse(
            player_id=agent.player_id,
            name=agent.name,
            provider=user_provider,
            model=agent_model
        )
        
    except Exception as e:
        print(f"❌ 创建代理失败 - {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/decision", response_model=DecisionResponse)
async def make_decision(request: DecisionRequest) -> DecisionResponse:
    """
    获取AI决策
    
    参数:
        request: 决策请求
        
    返回:
        DecisionResponse: 决策响应
    """
    try:
        print(f"获取AI决策: 玩家{request.player_id}, 有效动作: {', '.join(request.valid_actions)}")
        
        # 获取AI代理
        agent = agents.get(request.player_id)
        if not agent:
            print(f"❌ 找不到玩家{request.player_id}的AI代理")
            raise ValueError(f"找不到玩家{request.player_id}的AI代理")
        
        print(f"✅ 找到代理实例 - 玩家ID: {request.player_id}, 名称: {agent.name}")
        
        # 获取决策
        action, amount, thinking = await agent.make_decision(
            game_state=request.game_state,
            valid_actions=request.valid_actions,
            min_bet=request.min_bet,
            max_bet=request.max_bet
        )
        
        return DecisionResponse(action=action, amount=amount, thinking=thinking)
        
    except Exception as e:
        print(f"获取AI决策失败: {str(e)}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/agents/{player_id}")
async def delete_agent(player_id: str):
    """
    删除AI代理。
    
    Args:
        player_id: 玩家ID
    """
    print(f"📥 收到删除AI代理请求 - 玩家ID: {player_id}")
    try:
        if player_id in agents:
            del agents[player_id]
            print(f"✅ 代理删除成功 - 玩家ID: {player_id}, 当前代理池大小: {len(agents)}")
        else:
            print(f"⚠️ 要删除的代理不存在 - 玩家ID: {player_id}")
        return {"status": "ok"}
    except Exception as e:
        print(f"❌ 删除代理失败 - {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/agents")
async def delete_all_agents():
    """
    删除所有AI代理。
    
    Returns:
        删除状态
    """
    print(f"📥 收到删除所有AI代理请求 - 当前代理数量: {len(agents)}")
    try:
        count = len(agents)
        agents.clear()
        print(f"✅ 所有代理删除成功 - 删除数量: {count}, 当前代理池大小: {len(agents)}")
        return {"status": "ok", "message": f"已删除所有{count}个AI代理", "deleted_count": count}
    except Exception as e:
        print(f"❌ 删除所有代理失败 - {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/health")
async def health_check():
    """健康检查接口"""
    print(f"📥 收到健康检查请求 - 当前代理池大小: {len(agents)}")
    return {"status": "ok"}

@app.get("/api/agents", response_model=List[AgentInfo])
async def list_agents() -> List[AgentInfo]:
    """
    获取所有注册的AI代理列表。
    
    Returns:
        List[AgentInfo]: 代理信息列表
    """
    print(f"📥 收到列出所有AI代理请求 - 当前代理数量: {len(agents)}")
    agent_list = []
    for player_id, agent in agents.items():
        # 使用getattr获取模型名称，支持不同的属性名
        model = getattr(agent, 'model_name', None) or getattr(agent, 'model', 'unknown')
        
        # 从agent实例获取提供商名称
        provider = agent.__class__.__name__.lower()
        if provider.endswith('agent'):
            provider = provider[:-5]  # 移除'agent'后缀
        if provider == 'llm':
            provider = 'anthropic'  # 特殊处理LLMAgent

        # 如果有特殊类处理，记录
        if hasattr(agent, 'provider'):
            provider = agent.provider
        
        # 获取用户友好的提供商名称
        if provider in LLMFactory._reverse_aliases:
            display_provider = LLMFactory._reverse_aliases[provider]
            print(f"📝 提供商显示转换: {provider} → {display_provider}")
            provider = display_provider
        
        agent_info = AgentInfo(
            player_id=agent.player_id,
            name=agent.name,
            provider=provider,
            model=model,
            status="active"
        )
        agent_list.append(agent_info)
        print(f"✅ 代理信息 - 玩家ID: {agent.player_id}, 名称: {agent.name}, 提供商: {provider}, 模型: {model}")

    print(f"📤 返回代理列表 - 数量: {len(agent_list)}")
    return agent_list

# 启动时输出信息
@app.on_event("startup")
async def startup_event():
    print("=" * 50)
    print("🚀 扑克AI服务启动")
    # 初始化LLM工厂
    LLMFactory.init()
    # 获取用户友好的提供商列表
    providers = LLMFactory.get_user_facing_providers()
    providers_str = ", ".join(providers)
    print(f"📌 支持的LLM提供商: {providers_str}")
    print(f"📌 本地端点: http://localhost:8000")
    print("=" * 50)

# 关闭时输出信息
@app.on_event("shutdown")
async def shutdown_event():
    print("=" * 50)
    print("👋 扑克AI服务关闭")
    print(f"📌 清理 {len(agents)} 个代理实例")
    agents.clear()
    print("=" * 50) 