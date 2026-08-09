# 项目架构设计文档

## 1. 系统架构

### 1.1 前端架构（Flutter）

```
frontend/
├── lib/
│   ├── components/           # UI组件
│   │   ├── game_table.dart      # 游戏桌面
│   │   ├── player_view.dart     # 玩家视图
│   │   ├── card_view.dart       # 扑克牌视图
│   │   └── action_panel.dart    # 操作面板
│   ├── models/              # 数据模型
│   │   ├── game_state.dart      # 游戏状态
│   │   ├── player.dart          # 玩家模型
│   │   └── poker_card.dart      # 扑克牌模型
│   ├── services/            # 服务
│   │   ├── websocket_service.dart  # WebSocket通信
│   │   ├── game_service.dart      # 游戏逻辑
│   │   └── animation_service.dart  # 动画服务
│   └── utils/               # 工具类
│       ├── card_utils.dart      # 扑克牌工具
│       └── math_utils.dart      # 数学计算工具
```

### 1.2 后端架构（Node.js）

```
backend/
├── src/
│   ├── controllers/         # 控制器
│   │   ├── game.controller.js    # 游戏控制
│   │   ├── player.controller.js  # 玩家控制
│   │   └── ws.controller.js      # WebSocket控制
│   ├── models/             # 数据模型
│   │   ├── game.model.js        # 游戏模型
│   │   ├── player.model.js      # 玩家模型
│   │   └── card.model.js        # 扑克牌模型
│   ├── services/           # 服务层
│   │   ├── game.service.js      # 游戏服务
│   │   ├── ai.service.js        # AI服务
│   │   └── ws.service.js        # WebSocket服务
│   └── utils/              # 工具类
│       ├── poker.utils.js       # 扑克牌工具
│       └── validator.utils.js   # 验证工具
└── tests/                  # 测试文件
```

### 1.3 AI服务架构

```
ai_service/
├── src/
│   ├── agents/             # AI代理
│   │   ├── base_agent.py       # 基础代理类
│   │   └── llm_agent.py        # LLM代理实现
│   ├── prompts/            # 提示词模板
│   │   ├── game_state.py       # 游戏状态提示
│   │   └── decision.py         # 决策提示
│   └── utils/              # 工具类
│       ├── probability.py      # 概率计算
│       └── card_eval.py        # 牌型评估
└── tests/                  # 测试文件
```

## 2. 关键技术实现

### 2.1 游戏引擎
- 使用状态机管理游戏流程
- 实现标准德州扑克规则
- 处理所有游戏逻辑和状态转换

### 2.2 AI决策系统
- 使用大模型API进行决策
- 设计合适的提示词模板
- 实现概率计算和策略评估

### 2.3 实时通信
- 使用WebSocket进行实时数据传输
- 实现游戏状态同步
- 处理断线重连

### 2.4 前端渲染
- 使用Flutter实现跨平台UI
- 实现流畅的动画效果
- 优化性能和用户体验

## 3. 数据流

### 3.1 游戏状态更新流程
```
[游戏引擎] → [状态更新] → [WebSocket广播] → [前端更新] → [UI渲染]
```

### 3.2 AI决策流程
```
[游戏状态] → [AI代理] → [LLM API] → [决策结果] → [游戏引擎]
```

## 4. 开发计划

1. 环境搭建
   - 设置Flutter开发环境
   - 配置Node.js后端
   - 准备AI服务环境

2. 核心功能开发
   - 实现基础游戏引擎
   - 开发AI决策系统
   - 构建实时通信模块

3. 前端开发
   - 设计UI界面
   - 实现动画效果
   - 优化用户体验

4. 测试和优化
   - 单元测试
   - 集成测试
   - 性能优化

## 5. 技术栈选择

- **前端**: Flutter (Dart)
- **后端**: Node.js (Express)
- **AI服务**: Python
- **数据库**: MongoDB（可选）
- **通信**: WebSocket
- **AI模型**: OpenAI API / Anthropic API 