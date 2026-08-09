# 项目架构

三个独立服务，职责清晰分离：

```
Flutter Web 前端  <--WebSocket-->  Node.js 后端  <--HTTP-->  FastAPI AI 服务  <-->  各 LLM API
   （观战界面）                     （德扑引擎）              （模型代理）
```

## backend/ — 游戏引擎（Node.js）

```
src/
├── index.js               # HTTP + WebSocket 服务器入口，健康检查，优雅关闭
├── config/index.js        # 端口、盲注（SMALL_BLIND/BIG_BLIND）、日志级别，均可用环境变量覆盖
├── services/
│   ├── game.service.js    # 无限注德扑规则引擎：发牌、下注轮、全下、边池、最小加注、摊牌（pokersolver）
│   ├── ws.service.js      # 前端 WebSocket 协议 + AI 决策编排；按接收方过滤状态（AI 视角不含对手底牌与牌堆）
│   └── ai.service.js      # AI 服务 HTTP 客户端（axios）
└── utils/logger.js        # 分级日志
```

引擎与传输层分离：`game.service.js` 不知道 WebSocket 的存在，所有规则可用纯单元测试覆盖（含边池分配与筹码守恒）。

## ai_service/ — 模型代理（Python / FastAPI）

```
src/
├── main.py                        # FastAPI 端点：POST /api/agents、POST /api/decision、GET /api/health 等
├── config/agent_config.py         # 提供商配置表（默认模型、密钥环境变量、API base）——唯一来源
├── exceptions.py                  # AIServiceError 层级，统一映射为 HTTP 状态码
├── agents/
│   ├── base_agent.py              # 抽象基类：make_decision 契约、动作校验、安全默认动作
│   ├── llm_factory.py             # 按提供商注册/创建代理，支持别名（google -> gemini）
│   ├── openai_compatible_agent.py # OpenAI、DeepSeek、Qwen、Grok、Sonar 共用（OpenAI 兼容协议）
│   ├── anthropic_agent.py         # Claude（AsyncAnthropic）
│   ├── gemini_agent.py            # Google Gemini
│   └── local_llm_agent.py         # 本地 transformers 模型（可选依赖，未装 torch 时报配置错误）
└── prompts/
    ├── prompt_utils.py            # 提示词构建（位置、行动历史）+ 多层降级解析（JSON -> 代码块 -> 正则 -> 默认动作）
    └── card_formatter.py          # 卡牌的人类可读表示
```

所有代理均为异步实现，多个模型的决策请求不会互相阻塞。每次决策写入一行结构化 JSONL 日志（提供商、模型、动作、金额、延迟），作为后续胜率分析的数据集。

## frontend/ — 观战界面（Flutter Web）

```
lib/
├── main.dart                      # 入口，直接进入 GameScreen
├── constants.dart                 # 游戏常量与服务地址（--dart-define 可覆盖）
├── screens/game_screen.dart       # 主界面：牌桌、控制按钮、状态面板
├── components/
│   ├── game_table.dart            # 赛道形牌桌绘制、卡牌渲染、下注显示
│   └── player_view.dart           # 单个玩家席位
├── models/                        # GameState / Player / PokerCard / ThinkingRecord，容错的 fromJson
├── services/
│   ├── websocket_service.dart     # 纯传输层：指数退避重连、心跳、类型化连接状态
│   └── ai_service.dart            # AI 服务健康检查等直连接口
└── utils/player_merge.dart        # 状态更新时保留本地已知的模型/座位信息
```

## 关键设计决策

- **信息隔离**：后端向 AI 服务发送的决策请求只包含行动玩家自己的底牌 + 公共信息；牌堆从不离开引擎。前端作为观战视角显示所有底牌（刻意为之）。
- **容错解析**：LLM 输出不可靠，解析链逐层降级，最终落到最安全的合法动作，保证任何模型的幻觉都不会中断牌局。
- **单一事实来源**：盲注等规则常量只在 `backend/src/config/index.js` 定义；提供商信息只在 `agent_config.py` 定义。
- **可测试性**：三端共 181 个测试（backend 53 / ai_service 80 / frontend 48），CI 每次 push 全量运行。
