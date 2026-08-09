# 大模型德州扑克对决

本项目是一个使用大语言模型(LLM)进行德州扑克博弈的应用。多个AI模型可以在同一张牌桌上进行对决，展示它们在策略博弈中的能力。

## 系统架构

系统由三个主要部分组成：

1. **前端** (Flutter)：提供游戏界面和用户交互
2. **后端** (Node.js)：处理游戏逻辑和通信
3. **AI服务** (Python/FastAPI)：管理大模型代理

通信流程如下：
```
前端 <--WebSocket--> 后端 <--HTTP API--> AI服务 <--> 大语言模型
```

## 开始使用

### 1. 启动服务

可以使用提供的脚本一键启动所有服务：

```
# Windows PowerShell
./start-services.ps1

# 或使用批处理文件
start-all.bat
```

或者分别启动各服务：

```
# 启动AI服务
cd ai_service
venv\Scripts\python -m uvicorn src.main:app --host 0.0.0.0 --port 8000

# 启动后端服务
cd backend
node src/index.js

# 启动前端
cd frontend
flutter run -d chrome
```

### 2. 访问应用

前端界面将自动打开，或访问：
- 游戏界面：http://localhost
- 后端API：http://localhost:3000/api
- AI服务API：http://localhost:8000/api

## 主要功能

1. **多模型对决**：支持8个不同的大语言模型同时参与游戏
2. **随机入座**：一键随机分配AI到座位
3. **游戏状态面板**：显示当前游戏状态和玩家信息
4. **实时决策**：AI模型根据当前牌局状态实时做出决策

## 支持的AI模型

- OpenAI: GPT-4o
- Anthropic: Claude-3
- xAI: Grok-1
- Google: Gemini
- DeepSeek: DeepSeek-Chat
- 百度: 文心一言
- 更多模型可通过配置添加

## 系统要求

- Node.js v16+
- Python 3.8+
- Flutter SDK

## 项目架构

本项目由三个主要模块组成：

1. **前端** (Flutter)：提供游戏界面，显示玩家、卡牌和游戏状态
2. **后端** (Node.js)：处理简化版游戏逻辑和WebSocket通信，专注于单一前端连接
3. **AI服务** (Python)：管理AI模型连接和决策生成

## 环境要求

- **Node.js**: v16.14.0或更高版本（推荐v16.20.1+）
- **Python**: 3.8或更高版本
- **Flutter**: 最新稳定版
- **操作系统**: Windows/MacOS/Linux

## 运行指南

### 1. AI服务

AI服务负责创建和管理AI代理，使用大模型API进行决策。

```bash
# 进入AI服务目录
cd ai_service

# 创建虚拟环境
python -m venv venv

# 激活虚拟环境
# Windows:
venv\Scripts\activate
# MacOS/Linux:
# source venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 配置环境变量（可选）
# 创建.env文件并添加以下内容：
# OPENAI_API_KEY=your_api_key
# ANTHROPIC_API_KEY=your_api_key
# DEEPSEEK_API_KEY=your_api_key
# GEMINI_API_KEY=your_api_key

# 启动服务
python -m uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
```

服务将在 http://localhost:8000 上运行，并提供以下API:
- POST /api/agents - 创建AI代理
- GET /api/agents - 列出所有AI代理
- POST /api/decision - 获取AI决策
- GET /api/health - 健康检查

### 2. 后端服务

后端服务提供WebSocket通信和基本的游戏状态同步功能。该服务已优化为只处理单一前端连接，简化了通信结构。

```bash
# 进入后端目录
cd backend

# 安装依赖
npm install

# 配置环境变量（可选）
# 创建.env文件并添加以下内容：
# AI_SERVICE_URL=http://localhost:8000/api
# PORT=3000

# 启动服务
node src/index.js
```

服务将在 http://localhost:3000 上运行，提供以下功能:
- WebSocket连接: ws://localhost:3000
- 健康检查: http://localhost:3000/api/health
- 服务信息: http://localhost:3000/api/info

### 3. 前端应用

前端是使用Flutter开发的用户界面，展示游戏状态并允许玩家互动。

```bash
# 进入前端目录
cd frontend

# 获取Flutter依赖
flutter pub get

# 运行应用（Web模式）
flutter run -d chrome

# 或者运行在其他平台
flutter run -d windows  # Windows
flutter run -d macos    # MacOS
flutter run -d linux    # Linux
flutter run             # 连接的移动设备或模拟器
```

## 功能特点

- 随机入座功能：一键分配8个AI模型到不同位置
- 游戏状态面板：显示当前游戏阶段、底池、玩家等信息
- 实时AI连接状态：监控AI模型的连接和思考状态
- 游戏控制：开始/暂停游戏，重置游戏
- 支持的AI模型：ChatGPT-Mini, ChatGPT-4O, Claude, Grok, Gemini, DeepSeek, Sonar, Qwen

## 架构说明

本项目采用简化架构，专注于AI对战场景：

1. **前端负责游戏UI和状态管理**：
   - 游戏状态和逻辑主要在前端处理
   - 直接与AI服务通信创建代理和获取决策
   - 提供完整的游戏界面和交互

2. **后端承担轻量通信角色**：
   - 使用简化的WebSocket服务处理单一前端连接
   - 不再管理多用户会话和复杂游戏逻辑
   - 主要作为游戏状态的同步通道

3. **AI服务专注于模型决策**：
   - 处理AI代理的创建和管理
   - 根据游戏状态生成AI的决策
   - 支持多种大模型API

## 常见问题

### AI服务无法连接

1. 确保您已经配置了正确的API密钥
2. 检查AI服务是否在运行
3. 确认网络连接和防火墙设置

### 后端服务启动失败

1. 确保Node.js版本兼容（v16.14.0+）
2. 检查端口3000是否被占用
3. 确认依赖安装完整
4. 检查`services`目录是否存在，内部是否有`ws.service.js`文件

### 前端应用显示异常

1. 尝试重新运行`flutter pub get`获取最新依赖
2. 清除缓存：`flutter clean`
3. 确认Flutter版本是最新稳定版

## 开发者指南

- 添加新的AI模型：修改`ai_service.dart`中的`_mapModelToProvider`方法
- 自定义界面样式：调整`game_screen.dart`中的UI组件
- 扩展游戏逻辑：更新前端的游戏状态管理或修改后端的WebSocket通信

## 许可证

MIT