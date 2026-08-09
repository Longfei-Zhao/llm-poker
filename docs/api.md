# LLM-Poker API文档

本文档描述了多LLM德州扑克对决系统的API接口，包括简化版后端WebSocket服务API和AI服务API。

## 1. 后端WebSocket服务

后端服务主要通过WebSocket提供简化的实时通信功能，专门为单一前端连接设计，用于游戏状态同步和简单的游戏控制。

### 1.1 基础API接口

#### 健康检查
- **接口**: `GET /api/health`
- **描述**: 检查后端服务的健康状态
- **响应**:
```json
{
  "status": "ok",
  "message": "后端服务运行正常"
}
```

#### 服务信息
- **接口**: `GET /api/info`
- **描述**: 获取后端服务的基本信息
- **响应**:
```json
{
  "name": "LLM Poker Backend",
  "version": "1.0.0",
  "description": "为大模型德州扑克游戏提供后端支持"
}
```

### 1.2 WebSocket通信

WebSocket连接用于前端和后端之间的实时通信，主要传递游戏状态更新和游戏控制命令。

#### 连接WebSocket

```javascript
// 创建WebSocket连接
const socket = new WebSocket('ws://localhost:3000');

// 连接打开事件
socket.onopen = () => {
  console.log('WebSocket连接已建立');
};

// 接收消息事件
socket.onmessage = (event) => {
  const message = JSON.parse(event.data);
  console.log('收到消息:', message);
  
  // 根据消息类型处理不同的响应
  switch(message.type) {
    case 'connection':
      console.log('连接成功:', message.message);
      break;
    case 'gameStarted':
      console.log('游戏已开始');
      // 处理游戏开始逻辑
      break;
    case 'gamePaused':
      console.log('游戏已暂停');
      // 处理游戏暂停逻辑
      break;
    case 'gameResumed':
      console.log('游戏已恢复');
      // 处理游戏恢复逻辑
      break;
    case 'gameReset':
      console.log('游戏已重置');
      // 处理游戏重置逻辑
      break;
    case 'playerActionProcessed':
      console.log('玩家动作已处理:', message.playerId, message.action);
      // 处理玩家动作结果
      break;
    case 'gameStateUpdate':
      console.log('游戏状态更新');
      // 更新游戏界面
      break;
    case 'error':
      console.error('错误消息:', message.message);
      // 显示错误提示
      break;
  }
};

// 连接关闭事件
socket.onclose = () => {
  console.log('WebSocket连接已关闭');
};

// 连接错误事件
socket.onerror = (error) => {
  console.error('WebSocket错误:', error);
};
```

#### 前端发送消息

前端可以通过WebSocket发送以下类型的消息：

##### 开始游戏
```javascript
socket.send(JSON.stringify({
  type: 'startGame',
  gameState: {
    // 初始游戏状态
    stage: 'preflop',
    players: [/* 玩家列表 */],
    communityCards: [],
    pot: 15,
    currentBet: 10,
    smallBlind: 5,
    bigBlind: 10,
    dealerIndex: 0,
    currentPlayerIndex: 2
  }
}));
```

##### 暂停游戏
```javascript
socket.send(JSON.stringify({
  type: 'pauseGame'
}));
```

##### 恢复游戏
```javascript
socket.send(JSON.stringify({
  type: 'resumeGame'
}));
```

##### 玩家操作
```javascript
socket.send(JSON.stringify({
  type: 'playerAction',
  playerId: 'player1',
  action: 'raise',
  amount: 50
}));
```

##### 重置游戏
```javascript
socket.send(JSON.stringify({
  type: 'resetGame'
}));
```

##### 获取游戏状态
```javascript
socket.send(JSON.stringify({
  type: 'getGameState'
}));
```

#### 后端发送消息

后端会通过WebSocket发送以下类型的消息：

##### 连接成功
```json
{
  "type": "connection",
  "message": "连接成功",
  "timestamp": "2023-06-01T12:00:00.000Z"
}
```

##### 游戏开始
```json
{
  "type": "gameStarted",
  "gameState": {
    "stage": "preflop",
    "players": [],
    "communityCards": [],
    "pot": 15,
    "currentBet": 10,
    "smallBlind": 5,
    "bigBlind": 10,
    "dealerIndex": 0,
    "currentPlayerIndex": 2
  },
  "timestamp": "2023-06-01T12:01:00.000Z"
}
```

##### 游戏暂停
```json
{
  "type": "gamePaused",
  "timestamp": "2023-06-01T12:02:00.000Z"
}
```

##### 游戏恢复
```json
{
  "type": "gameResumed",
  "timestamp": "2023-06-01T12:03:00.000Z"
}
```

##### 游戏重置
```json
{
  "type": "gameReset",
  "timestamp": "2023-06-01T12:04:00.000Z"
}
```

##### 玩家操作处理
```json
{
  "type": "playerActionProcessed",
  "playerId": "player1",
  "action": "raise",
  "amount": 50,
  "timestamp": "2023-06-01T12:05:00.000Z"
}
```

##### 游戏状态更新
```json
{
  "type": "gameStateUpdate",
  "gameState": {
    "stage": "flop",
    "players": [],
    "communityCards": ["2H", "7S", "JD"],
    "pot": 100,
    "currentBet": 0,
    "smallBlind": 5,
    "bigBlind": 10,
    "dealerIndex": 0,
    "currentPlayerIndex": 1
  },
  "timestamp": "2023-06-01T12:06:00.000Z"
}
```

##### 错误消息
```json
{
  "type": "error",
  "message": "操作失败：无效的玩家动作",
  "timestamp": "2023-06-01T12:07:00.000Z"
}
```

## 2. AI服务API

AI服务提供了用于创建AI代理和获取决策的API接口，支持多种LLM提供商。

### 2.1 代理管理API

#### 创建代理
- **接口**: `POST /api/agents`
- **描述**: 创建一个AI代理
- **请求参数**:
```json
{
  "player_id": "ai1",
  "name": "AI玩家1",
  "provider": "anthropic",  // anthropic, openai, deepseek, gemini, local, xai
  "model": "claude-3-sonnet-20240229",  // 可选，每个提供商有默认值
  "temperature": 0.7  // 可选，默认0.7
}
```
- **响应**:
```json
{
  "player_id": "ai1",
  "name": "AI玩家1",
  "provider": "anthropic",
  "model": "claude-3-sonnet-20240229"
}
```
- **示例**:
```python
import requests

# 创建Anthropic Claude代理
response = requests.post(
    "http://localhost:8000/api/agents",
    json={
        "player_id": "claude_player",
        "name": "Claude玩家",
        "provider": "anthropic",
        "model": "claude-3-sonnet-20240229",
        "temperature": 0.7
    }
)

print(response.json())

# 创建OpenAI GPT代理
response = requests.post(
    "http://localhost:8000/api/agents",
    json={
        "player_id": "gpt_player",
        "name": "GPT玩家",
        "provider": "openai",
        "model": "gpt-4"
    }
)

print(response.json())
```

#### 批量创建代理
- **接口**: `POST /api/agents/batch`
- **描述**: 批量创建多个AI代理
- **请求参数**:
```json
[
  {
    "player_id": "claude_player",
    "name": "Claude玩家",
    "provider": "anthropic",
    "model": "claude-3-sonnet-20240229"
  },
  {
    "player_id": "gpt_player",
    "name": "GPT玩家",
    "provider": "openai",
    "model": "gpt-4"
  }
]
```
- **响应**:
```json
{
  "created": 2,
  "failed": 0,
  "details": [
    {
      "player_id": "claude_player",
      "status": "success"
    },
    {
      "player_id": "gpt_player",
      "status": "success"
    }
  ]
}
```

#### 获取所有代理
- **接口**: `GET /api/agents`
- **描述**: 获取所有已创建的AI代理
- **响应**:
```json
[
  {
    "player_id": "claude_player",
    "name": "Claude玩家",
    "provider": "anthropic",
    "model": "claude-3-sonnet-20240229",
    "status": "active"
  },
  {
    "player_id": "gpt_player",
    "name": "GPT玩家",
    "provider": "openai",
    "model": "gpt-4",
    "status": "active"
  }
]
```

#### 删除代理
- **接口**: `DELETE /api/agents/{player_id}`
- **描述**: 删除指定的AI代理
- **响应**:
```json
{
  "status": "ok"
}
```

### 2.2 决策API

#### 获取决策
- **接口**: `POST /api/decision`
- **描述**: 基于当前游戏状态获取AI代理的决策
- **请求参数**:
```json
{
  "player_id": "ai1",
  "game_state": {
    "state": "preflop",
    "pot": 15,
    "currentBet": 10,
    "communityCards": [],
    "players": [
      {
        "id": "ai1",
        "name": "AI玩家1",
        "cards": ["AS", "KS"],  // A♠ K♠
        "chips": 990,
        "bet": 10,
        "position": 1,
        "isActive": true
      },
      {
        "id": "player2",
        "name": "玩家2",
        "chips": 995,
        "bet": 5,
        "position": 2,
        "isActive": true
      }
    ]
  },
  "valid_actions": ["fold", "call", "raise"],
  "min_bet": 20,
  "max_bet": 990
}
```
- **响应**:
```json
{
  "action": "raise",
  "amount": 50
}
```
- **示例**:
```python
import requests

# 获取AI决策
response = requests.post(
    "http://localhost:8000/api/decision",
    json={
        "player_id": "claude_player",
        "game_state": {
            "state": "preflop",
            "pot": 15,
            "currentBet": 10,
            "communityCards": [],
            "players": [
                {
                    "id": "claude_player",
                    "name": "Claude玩家",
                    "cards": ["AS", "KS"],
                    "chips": 990,
                    "bet": 10,
                    "position": 1,
                    "isActive": true
                },
                {
                    "id": "player2",
                    "name": "AI玩家2",
                    "chips": 995,
                    "bet": 5,
                    "position": 2,
                    "isActive": true
                }
            ]
        },
        "valid_actions": ["fold", "call", "raise"],
        "min_bet": 20,
        "max_bet": 990
    }
)

decision = response.json()
print(f"AI决定: {decision['action']}")
if decision.get('amount'):
    print(f"下注金额: {decision['amount']}")
```

### 2.3 健康检查API

#### 健康检查
- **接口**: `GET /api/health`
- **描述**: 检查AI服务的健康状态
- **响应**:
```json
{
  "status": "ok"
}
```

## 3. 前端与后端集成示例

以下是一个前端与后端集成的示例，展示了如何连接WebSocket服务并处理游戏流程：

```javascript
// 创建WebSocket连接
const socket = new WebSocket('ws://localhost:3000');
let gameState = null;

// 连接成功后的初始化
socket.onopen = () => {
  console.log('WebSocket连接已建立');
  
  // 可以在这里发送初始化命令，例如获取当前游戏状态
  socket.send(JSON.stringify({
    type: 'getGameState'
  }));
};

// 处理接收到的消息
socket.onmessage = (event) => {
  const message = JSON.parse(event.data);
  console.log('收到消息:', message);
  
  switch(message.type) {
    case 'gameStateUpdate':
    case 'gameStarted':
      // 更新本地游戏状态
      gameState = message.gameState;
      // 更新UI显示
      updateGameUI(gameState);
      break;
      
    case 'playerActionProcessed':
      // 处理玩家动作结果
      console.log(`玩家 ${message.playerId} ${message.action} 操作已处理`);
      // 如果需要可以播放相应的动画效果
      break;
      
    case 'gamePaused':
      // 显示游戏暂停状态
      showPauseOverlay();
      break;
      
    case 'gameResumed':
      // 移除暂停显示
      hidePauseOverlay();
      break;
      
    case 'gameReset':
      // 重置游戏状态和UI
      gameState = null;
      resetGameUI();
      break;
      
    case 'error':
      // 显示错误消息
      showError(message.message);
      break;
  }
};

// 游戏控制函数示例
function startGame() {
  // 创建初始游戏状态
  const initialGameState = {
    stage: 'preflop',
    players: currentPlayers, // 当前已添加的玩家
    communityCards: [],
    pot: 15,
    currentBet: 10,
    smallBlind: 5,
    bigBlind: 10,
    dealerIndex: 0,
    currentPlayerIndex: 2
  };
  
  // 发送开始游戏命令
  socket.send(JSON.stringify({
    type: 'startGame',
    gameState: initialGameState
  }));
}

function pauseGame() {
  socket.send(JSON.stringify({
    type: 'pauseGame'
  }));
}

function resumeGame() {
  socket.send(JSON.stringify({
    type: 'resumeGame'
  }));
}

function resetGame() {
  socket.send(JSON.stringify({
    type: 'resetGame'
  }));
}

// 玩家动作函数示例
function playerAction(playerId, action, amount = null) {
  const message = {
    type: 'playerAction',
    playerId,
    action
  };
  
  if (amount !== null && action === 'raise') {
    message.amount = amount;
  }
  
  socket.send(JSON.stringify(message));
}
```

## 4. 常见问题解答

### 如何处理WebSocket连接断开？

当WebSocket连接断开时，前端应该实现自动重连机制：

```javascript
function connectWebSocket() {
  const socket = new WebSocket('ws://localhost:3000');
  
  socket.onopen = () => {
    console.log('WebSocket连接已建立');
    // 重置重连计数器
    reconnectAttempts = 0;
  };
  
  socket.onclose = () => {
    console.log('WebSocket连接已断开，尝试重新连接...');
    // 延迟一段时间后重新连接
    setTimeout(() => {
      if (reconnectAttempts < maxReconnectAttempts) {
        reconnectAttempts++;
        connectWebSocket();
      } else {
        console.error('达到最大重连次数，停止尝试');
        showConnectionError();
      }
    }, 2000 * Math.min(reconnectAttempts, 10)); // 指数退避策略
  };
  
  // 其他事件处理...
  
  return socket;
}

// 初始化
let reconnectAttempts = 0;
const maxReconnectAttempts = 10;
let socket = connectWebSocket();
```

### 如何检查服务健康状态？

可以定期使用HTTP请求检查后端和AI服务的健康状态：

```javascript
// 检查后端服务健康状态
async function checkBackendHealth() {
  try {
    const response = await fetch('http://localhost:3000/api/health');
    const data = await response.json();
    return data.status === 'ok';
  } catch (error) {
    console.error('后端服务健康检查失败:', error);
    return false;
  }
}

// 检查AI服务健康状态
async function checkAIServiceHealth() {
  try {
    const response = await fetch('http://localhost:8000/api/health');
    const data = await response.json();
    return data.status === 'ok';
  } catch (error) {
    console.error('AI服务健康检查失败:', error);
    return false;
  }
}

// 定期检查服务状态
setInterval(async () => {
  const backendHealthy = await checkBackendHealth();
  const aiServiceHealthy = await checkAIServiceHealth();
  
  updateServiceStatusUI(backendHealthy, aiServiceHealthy);
}, 30000); // 每30秒检查一次
```

### 如何选择合适的LLM提供商？

根据需求选择不同的提供商:
- **Anthropic Claude**: 擅长理解复杂指令，决策更具逻辑性
- **OpenAI GPT**: 通用性强，策略灵活
- **DeepSeek**: 中文支持更好，适合中文环境
- **Gemini**: Google的模型，具有独特的思维方式
- **Local LLM**: 私有部署，无需联网，更快的响应时间
