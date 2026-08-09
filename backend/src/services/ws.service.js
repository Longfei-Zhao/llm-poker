/**
 * WebSocket服务 - 简化版
 * 只处理单一前端连接，专注于游戏状态同步
 */

const aiService = require('./ai.service');
const { GameService } = require('./game.service'); // 修改导入方式，使用解构赋值

class WebSocketService {
  constructor() {
    this.frontendConnection = null; // 只保存一个前端连接
    this.isGameRunning = false;
    this.currentGameState = null;
    this.gameService = new GameService(); // 初始化GameService实例
  }

  initialize(wss) {
    console.log('WebSocket服务初始化');
    
    wss.on('connection', (ws) => {
      console.log('前端已连接');
      this.frontendConnection = ws;
      
      // 发送欢迎消息
      this.sendMessage({
        type: 'connection',
        message: '连接成功',
        timestamp: new Date().toISOString()
      });
      
      // 处理接收到的消息
      ws.on('message', (message) => {
        try {
          const data = JSON.parse(message);
          console.log('收到消息:', data);
          this.handleMessage(data);
        } catch (error) {
          console.error('消息解析错误:', error);
          this.sendError('消息格式不正确');
        }
      });
      
      // 处理连接关闭
      ws.on('close', () => {
        console.log('前端断开连接');
        this.frontendConnection = null;
      });
      
      // 处理错误
      ws.on('error', (error) => {
        console.error('WebSocket错误:', error);
        this.frontendConnection = null;
      });
      
      // 发送心跳包保持连接
      this.startHeartbeat(ws);
    });
  }
  
  // 处理接收到的消息
  handleMessage(data) {
    switch (data.type) {
      case 'ping':
        // 响应ping消息，用于连接测试
        this.sendMessage({
          type: 'pong',
          timestamp: new Date().toISOString()
        });
        break;
      case 'createGame':
        // 创建游戏，传递players数组
        this.handleCreateGame(data.players || []);
        break;
      case 'startGame':
        // 将正确的gameId参数传递给startGame方法
        console.log('收到消息:', data);
        this.startGame(data.gameId);
        break;
      case 'nextStep':
        // 进行游戏的下一步
        this.handleNextStep();
        break;
      case 'playerAction':
        this.handlePlayerAction(data.playerId, data.action, data.amount);
        break;
      case 'resetGame':
        this.resetGame();
        break;
      case 'getGameState':
        this.sendGameState();
        break;
      case 'addPlayer':
        this.handleAddPlayer(data.player);
        break;
      default:
        console.log('未处理的消息类型:', data.type);
    }
  }
  
  // 开始游戏
  startGame(initialGameState) {
    console.log('游戏开始请求已接收', initialGameState);
    this.isGameRunning = true;

    try {
      // 获取游戏ID，支持多种格式
      const gameId = typeof initialGameState === 'object' 
        ? (initialGameState.gameId || initialGameState.id) 
        : initialGameState;
      
      // 检查游戏ID是否存在
      if (!gameId) {
        const errorMsg = '游戏ID为空，无法开始游戏';
        console.error(errorMsg);
        this.sendMessage({
          type: 'error',
          message: errorMsg,
          timestamp: new Date().toISOString()
        });
        return;
      }
      
      console.log(`尝试开始游戏，ID: ${gameId}`);

      // 保存原始玩家数据，以保留aiModel和position等属性
      const originalPlayers = this.currentGameState && this.currentGameState.players ?
                             [...this.currentGameState.players] : [];

      let gameState = null;

      // 尝试通过游戏服务开始游戏
      if (this.gameService && typeof this.gameService.startGame === 'function') {
        try {
          console.log(`调用gameService.startGame(${gameId})`);
          gameState = this.gameService.startGame(gameId);
      
      if (gameState) {
            console.log('游戏通过gameService成功初始化');
            
            // 保存原始players中的aiModel和其他前端设置的属性
            if (gameState.players && Array.isArray(gameState.players) && originalPlayers.length > 0) {
              gameState.players = gameState.players.map(player => {
                // 查找原始玩家数据
                const originalPlayer = originalPlayers.find(p => p.id === player.id);
                if (originalPlayer) {
                  // 保留原始玩家的aiModel和其他前端设置的属性
                  player.aiModel = originalPlayer.aiModel || player.aiModel;
                  player.position = originalPlayer.position || player.position;
                }
                return player;
              });
            }
            
            // 确保同时提供state和stage字段，保持前后端一致性
            gameState.stage = gameState.state || 'preflop';
            gameState.state = gameState.state || gameState.stage || 'preflop';
            
            // 确保同时提供id和gameId字段
            gameState.id = gameState.id || gameId;
            gameState.gameId = gameState.gameId || gameState.id;
          }
        } catch (e) {
          console.error(`gameService.startGame发生错误:`, e);
          // 错误会在下面处理
        }
      } else {
        console.log('gameService不可用或没有startGame方法');
      }

      // 如果游戏服务没有返回有效的游戏状态，使用当前状态或创建新状态
      if (!gameState) {
        console.log(`使用备用游戏状态初始化`);
        
        if (this.currentGameState) {
          // 使用当前状态
          gameState = { ...this.currentGameState };
          console.log(`使用现有游戏状态: ${gameState.id}`);
        } else {
          // 创建新状态
          gameState = {
            id: gameId,
            gameId: gameId,
            dealerIndex: 0,
            players: originalPlayers,
            communityCards: [],
            pot: 0,
            currentBet: 0,
            smallBlind: 10,
            bigBlind: 20
          };
          console.log(`创建新游戏状态: ${gameId}`);
        }
        
        // 设置游戏阶段
        gameState.state = 'preflop';
        gameState.stage = 'preflop';
      }

      // 更新当前游戏状态
      this.currentGameState = gameState;
      
      // 发送游戏开始消息
      this.sendMessage({
        type: 'gameStarted',
        gameState: this.currentGameState,
        timestamp: new Date().toISOString()
      });
      
      console.log(`游戏${gameId}已成功开始，当前阶段: ${gameState.state}`);
      
    } catch (error) {
      const errorMsg = `开始游戏失败: ${error.message}`;
      console.error(errorMsg);
      this.sendMessage({
        type: 'error',
        message: errorMsg,
        timestamp: new Date().toISOString()
      });
    }
  }
  
  // 处理游戏下一步
  handleNextStep() {
    if (!this.isGameRunning || !this.currentGameState) {
      this.sendError('游戏尚未开始');
      return;
    }
    
    console.log('处理游戏下一步');
    
    // 执行游戏的下一步操作
    // 获取当前玩家索引
    const currentPlayerIndex = this.currentGameState.currentPlayerIndex;
    const players = this.currentGameState.players;
    
    if (currentPlayerIndex < 0 || currentPlayerIndex >= players.length) {
      this.sendError('当前没有活跃玩家');
      return;
    }
    
    // 获取当前玩家
    const currentPlayer = players[currentPlayerIndex];
    
    // 检查游戏是否已经处于摊牌或结束状态
    if (this.currentGameState.state === 'showdown' || this.currentGameState.state === 'finished') {
      console.log(`游戏处于${this.currentGameState.state}状态，直接进入下一个阶段`);
      
      // 如果是结束状态，直接开始新一轮
      if (this.currentGameState.state === 'finished') {
        console.log('游戏已结束，开始新一轮');
        // 开始新一轮，接收游戏对象而不是gameId
        this.gameService.startNewRound(this.currentGameState);
        
        // 重新开始游戏，自动发牌
        setTimeout(() => {
          console.log('自动开始新一轮发牌');
          this.gameService.startGame(this.currentGameState.id);
          const updatedGame = this.gameService.getGameState(this.currentGameState.id);
          this.updateGameState(updatedGame);
          
          // 发送游戏阶段变化通知
          this.sendMessage({
            type: 'gameStageChanged',
            oldStage: 'finished',
            newStage: updatedGame.state,
            timestamp: new Date().toISOString()
          });
        }, 500);
      } else {
        // 如果是摊牌阶段，处理结算并进入新一轮
        // moveToNextRound接收game对象而不是gameId
        const updatedGame = this.gameService.moveToNextRound(this.currentGameState);
        this.updateGameState(updatedGame);
        
        // 发送游戏阶段变化通知
        this.sendMessage({
          type: 'gameStageChanged',
          oldStage: 'showdown',
          newStage: updatedGame.state,
          timestamp: new Date().toISOString()
        });
      }
      
      return;
    }
    
    // 在本项目中，所有玩家都是AI玩家
    console.log(`当前玩家: ${currentPlayer.name}, 模型: ${currentPlayer.aiModel || '未指定，将作为AI处理'}`);
    
    // 确保玩家有AI模型属性
    if (!currentPlayer.aiModel) {
      console.log(`玩家${currentPlayer.name}没有指定AI模型，默认使用claude-3-7-sonnet-20250219`);
      currentPlayer.aiModel = 'Claude';
    }
    
    // 调用AI服务进行决策
    this.processAIDecision(currentPlayer);
  }
  
  // 处理AI玩家决策
  async processAIDecision(player) {
    try {
      console.log(`处理AI玩家${player.name}(${player.aiModel})的决策`);
      
      // 获取有效的动作列表
      const validActions = this.calculateValidActions(player);
      
      if (validActions.length === 0) {
        throw new Error(`没有有效的动作可供玩家${player.name}选择`);
      }
      
      // 计算下注范围
      let minBet, maxBet;
      
      // 最小加注额计算
      if (this.currentGameState.currentBet === 0) {
        // 如果没有当前下注，最小下注为大盲注
        minBet = this.currentGameState.bigBlind;
      } else if (this.currentGameState.lastRaiseAmount > 0) {
        // 如果已经有加注，最小加注是当前下注加上最后一次加注增量
        minBet = this.currentGameState.currentBet + this.currentGameState.lastRaiseAmount;
      } else {
        // 如果是第一次加注，最小加注是当前下注的两倍
        minBet = this.currentGameState.currentBet * 2;
      }
      
      // 确保最小加注不超过玩家的筹码总量(已下注+剩余筹码)
      const playerTotalChips = player.bet + player.chips;
      minBet = Math.min(minBet, playerTotalChips);
      
      // 最大加注就是玩家的全部筹码加上已经下注的部分
      maxBet = playerTotalChips;
      
      console.log(`有效动作列表: ${validActions.join(', ')}, 下注范围: ${minBet}-${maxBet}`);
      
      // 通知前端AI正在思考
      this.sendMessage({
        type: 'aiThinking',
        playerId: player.id,
        model: player.aiModel,
        timestamp: new Date().toISOString()
      });
      
      // 调用AI服务获取决策
      const decision = await aiService.getDecision(
        player.id,
        this.currentGameState,
        validActions,
        minBet,
        maxBet
      );
      
      console.log(`AI决策结果: ${decision.action}, 金额: ${decision.amount || 'N/A'}, 思考过程长度: ${decision.thinking ? decision.thinking.length : 0}字符`);
      
      // 创建思考记录
      if (decision.thinking) {
        this.addThinkingRecord(player, decision.thinking, decision.action);
      }
      
      // 验证决策合法性
      if (!validActions.includes(decision.action)) {
        console.warn(`AI返回的动作${decision.action}不在有效动作列表中，使用默认动作`);
        // 根据策略选择默认动作：优先check，其次call，最后才fold
        if (validActions.includes('check')) {
          decision.action = 'check';
          console.log(`将无效动作转换为'check'`);
        } else if (validActions.includes('call')) {
          decision.action = 'call';
          console.log(`将无效动作转换为'call'`);
        } else {
          decision.action = 'fold';
          console.log(`将无效动作转换为'fold'`);
        }
      }
      
      // 如果是加注动作，验证金额是否合法
      if (decision.action === 'raise' && (decision.amount < minBet || decision.amount > maxBet)) {
        console.warn(`AI返回的加注金额${decision.amount}不在有效范围内，调整到有效值`);
        decision.amount = Math.max(minBet, Math.min(maxBet, decision.amount || minBet));
      }
      
      // 处理AI决策
      this.handlePlayerAction(player.id, decision.action, decision.amount);
      
    } catch (error) {
      console.error(`处理AI决策出错:`, error);
      
      // 发送错误消息到前端
      this.sendMessage({
        type: 'aiAgentError',
        playerId: player.id,
        error: error.message,
        timestamp: new Date().toISOString()
      });
      
      // 获取有效的动作列表
      const validActions = this.calculateValidActions(player);
      
      // 根据策略选择默认动作：优先check，其次call，最后才fold
      let defaultAction = 'fold';
      if (validActions.includes('check')) {
        defaultAction = 'check';
        console.log(`错误情况下，AI玩家${player.name}使用'check'作为默认操作`);
      } else if (validActions.includes('call') && player.chips >= this.currentGameState.currentBet - player.bet) {
        defaultAction = 'call';
        console.log(`错误情况下，AI玩家${player.name}使用'call'作为默认操作`);
      } else {
        console.log(`错误情况下，AI玩家${player.name}使用'fold'作为默认操作`);
      }
      
      // 执行默认动作
      this.handlePlayerAction(player.id, defaultAction, defaultAction === 'call' ? this.currentGameState.currentBet : 0);
    }
  }
  
  // 创建思考记录并添加到游戏状态
  addThinkingRecord(player, thinking, action) {
    if (!this.currentGameState || !player) return;
    
    // 创建思考记录
    const thinkingRecord = {
      playerId: player.id,
      playerName: player.name,
      aiModel: player.aiModel,
      content: thinking,
      gameStage: this.currentGameState.state || 'unknown',
      action: action,
      timestamp: new Date().toISOString()
    };
    
    // 确保thinkingHistory存在
    if (!this.currentGameState.thinkingHistory) {
      this.currentGameState.thinkingHistory = [];
    }
    
    // 添加记录
    this.currentGameState.thinkingHistory.push(thinkingRecord);
    
    // 发送思考记录更新
    this.sendMessage({
      type: 'thinkingUpdated',
      record: thinkingRecord,
      timestamp: new Date().toISOString()
    });
    
    // 更新游戏状态
    this.sendGameStateUpdate();
  }
  
  // 计算玩家可用的动作列表
  calculateValidActions(player) {
    // 这是一个示例实现，实际逻辑应根据游戏规则定制
    const validActions = [];
    
    // 基本上，玩家总是可以弃牌
    validActions.push('fold');
    
    // 如果当前下注为0，玩家可以check
    if (this.currentGameState.currentBet === 0) {
      validActions.push('check');
    }
    
    // 如果玩家有筹码，总是可以全押
    if (player.chips > 0) {
      validActions.push('allin');
    }
    
    // 如果当前下注大于0且小于等于玩家筹码，玩家可以call
    if (this.currentGameState.currentBet > 0 && this.currentGameState.currentBet <= player.chips) {
      validActions.push('call');
    }
    
    // 计算最小加注额
    let minRaiseBet;
    if (this.currentGameState.currentBet === 0) {
      // 如果没有当前下注，最小下注为大盲注
      minRaiseBet = this.currentGameState.bigBlind;
    } else if (this.currentGameState.lastRaiseAmount > 0) {
      // 如果已经有加注，最小加注是当前下注加上最后一次加注增量
      minRaiseBet = this.currentGameState.currentBet + this.currentGameState.lastRaiseAmount;
    } else {
      // 如果是第一次加注，最小加注是当前下注的两倍
      minRaiseBet = this.currentGameState.currentBet * 2;
    }
    
    // 计算玩家需要额外投入的筹码
    const additionalChipsNeeded = minRaiseBet - player.bet;
    
    // 如果玩家有足够的筹码进行最小加注，可以raise
    if (player.chips >= additionalChipsNeeded && minRaiseBet > this.currentGameState.currentBet) {
      validActions.push('raise');
    }
    
    return validActions;
  }
  
  // 发送更新的游戏状态
  sendGameStateUpdate() {
    if (this.currentGameState) {
      this.sendMessage({
        type: 'gameStateUpdate',
        gameState: this.currentGameState,
        timestamp: new Date().toISOString()
      });
    }
  }
  
  // 重置游戏
  resetGame() {
    this.isGameRunning = false;
    this.currentGameState = null;
    console.log('游戏重置');
    
    // 如果有AI服务的实例，尝试清理所有AI代理
    // 注意：后端不主动删除AI代理，这一步由前端完成
    // 前端会在调用resetGame后自行处理AI代理的删除
    
    this.sendMessage({
      type: 'gameReset',
      timestamp: new Date().toISOString()
    });
  }
  
  // 处理玩家行动
  handlePlayerAction(playerId, action, amount) {
    console.log(`玩家${playerId}执行${action}操作，金额:${amount}`);
    
    try {
      if (!this.currentGameState) {
        throw new Error('游戏尚未开始');
      }
      
      // 调用游戏服务处理玩家行动
      const updatedGame = this.gameService.handlePlayerAction(
        this.currentGameState.id, 
        playerId, 
        action, 
        amount
      );
      
      // 更新并广播游戏状态
      this.updateGameState(updatedGame);
      
      // 广播玩家行动已处理的消息
      this.sendMessage({
        type: 'playerActionProcessed',
        playerId,
        action,
        amount,
        timestamp: new Date().toISOString()
      });
      
      // 检查游戏是否已进入新阶段
      if (updatedGame.state !== this.currentGameState.state) {
        this.sendMessage({
          type: 'gameStageChanged',
          oldStage: this.currentGameState.state,
          newStage: updatedGame.state,
          timestamp: new Date().toISOString()
        });
      }
      
      // 如果游戏已经进入摊牌或结束阶段，等待用户点击"下一步"
      if (updatedGame.state === 'showdown' || updatedGame.state === 'finished') {
        console.log(`游戏进入${updatedGame.state}阶段，等待用户点击"下一步"`);
      } else {
        // 在开发测试阶段，不自动处理下一个玩家的行动
        // 而是等待用户点击"下一步"按钮
        console.log(`玩家${playerId}的行动已处理，等待用户点击"下一步"处理下一个玩家`);
        
        // 获取下一个玩家信息用于日志
        const nextPlayer = updatedGame.players[updatedGame.currentPlayerIndex];
        console.log(`下一个玩家是: ${nextPlayer.name}(${nextPlayer.id}), 模型: ${nextPlayer.aiModel || '未指定'}`);
      }
    } catch (error) {
      console.error('处理玩家行动出错:', error);
      
      // 获取玩家信息
      const player = this.currentGameState.players.find(p => p.id === playerId);
      if (player) {
        console.warn(`玩家${player.name}(${playerId})的${action}操作失败，自动转为fold处理：${error.message}`);
        
        // 对于AI玩家的无效操作，自动转为fold处理
        if (player.isAI) {
          try {
            // 执行fold操作
            const updatedGame = this.gameService.handlePlayerAction(
              this.currentGameState.id,
              playerId,
              'fold',
              0
            );
            
            // 更新并广播游戏状态
            this.updateGameState(updatedGame);
            
            // 广播玩家行动已处理的消息
            this.sendMessage({
              type: 'playerActionProcessed',
              playerId,
              action: 'fold',
              amount: 0,
              timestamp: new Date().toISOString()
            });
            
            return; // 成功处理，不发送错误消息
          } catch (foldError) {
            console.error('执行自动fold操作失败:', foldError);
          }
        }
      }
      
      // 如果自动fold操作失败或者不是AI玩家，发送错误消息
      this.sendError(`处理玩家行动失败: ${error.message}`);
    }
  }
  
  // 发送游戏状态
  sendGameState() {
    if (this.currentGameState) {
      this.sendMessage({
        type: 'gameState',
        gameState: this.currentGameState,
        timestamp: new Date().toISOString()
      });
    } else {
      this.sendError('游戏尚未开始');
    }
  }
  
  // 更新并广播游戏状态
  updateGameState(newGameState) {
    this.currentGameState = newGameState;
    
    this.sendMessage({
      type: 'gameStateUpdate',
      gameState: this.currentGameState,
      timestamp: new Date().toISOString()
    });
  }
  
  // 发送消息给前端
  sendMessage(data) {
    if (this.frontendConnection && this.frontendConnection.readyState === 1) {
      this.frontendConnection.send(JSON.stringify(data));
    }
  }
  
  // 发送错误消息
  sendError(errorMessage) {
    this.sendMessage({
      type: 'error',
      message: errorMessage,
      timestamp: new Date().toISOString()
    });
  }
  
  // 启动心跳检测
  startHeartbeat(ws) {
    const interval = setInterval(() => {
      if (ws.readyState === 1) {
        ws.ping();
      } else {
        clearInterval(interval);
      }
    }, 30000); // 每30秒发送一次ping
    
    ws.on('close', () => {
      clearInterval(interval);
    });
  }
  
  // 处理添加玩家
  async handleAddPlayer(player) {
    console.log('收到添加玩家请求:', player);
    
    // 更新游戏状态中的玩家列表
    if (!this.currentGameState) {
      this.currentGameState = {
        id: 'game1',
        players: [],
        stage: 'waiting',
        state: 'waiting',
        pot: 0,
        currentBet: 0,
        smallBlind: 10,
        bigBlind: 20,
        communityCards: [],
        currentPlayerIndex: -1,
        dealerIndex: 0
      };
    }
    
    // 在添加玩家前，根据名称推断AI模型
    if (!player.aiModel) {
      // 尝试从名称中推断AI模型
      const playerName = player.name.toLowerCase();
      if (playerName.includes('gpt') || playerName.includes('chatgpt')) {
        if (playerName.includes('o1')) {
          player.aiModel = 'ChatGPT-O1';
        } else {
          player.aiModel = 'ChatGPT-4O';
        }
      } else if (playerName.includes('claude')) {
        player.aiModel = 'Claude';
      } else if (playerName.includes('grok')) {
        player.aiModel = 'Grok';
      } else if (playerName.includes('gemini')) {
        player.aiModel = 'Gemini';
      } else if (playerName.includes('deepseek')) {
        if (playerName.includes('r1')) {
          player.aiModel = 'DeepSeek-R1';
        } else {
          player.aiModel = 'DeepSeek';
        }
      } else if (playerName.includes('qwen')) {
        player.aiModel = 'Qwen';
      } else {
        // 默认使用Claude
        player.aiModel = 'Claude';
      }
      
      console.log(`为玩家${player.name}推断AI模型: ${player.aiModel}`);
    }
    
    // 添加玩家
    this.currentGameState.players.push(player);
    
    // 在本项目中，所有玩家都是AI玩家
    // 如果玩家没有指定AI模型，设置默认值
    if (!player.aiModel) {
      console.log(`玩家${player.name}没有指定AI模型，默认使用claude-3-7-sonnet-20250219`);
      player.aiModel = 'Claude';
      
      // 更新刚刚添加的玩家
      const playerIndex = this.currentGameState.players.length - 1;
      this.currentGameState.players[playerIndex].aiModel = 'Claude';
    }
    
      try {
        console.log(`为玩家${player.id}创建AI代理, 模型: ${player.aiModel}`);
        
        // 将模型名称映射到提供商和模型
        const modelMapping = this.mapModelToProvider(player.aiModel);
        
        // 调用AI服务创建代理
        const agentResult = await aiService.createAgent(
          player.id,
          player.name,
          modelMapping.provider,
          modelMapping.model
        );
        
        console.log(`AI代理创建成功:`, agentResult);
        
        // 更新玩家状态，标记为已创建AI代理
        const playerIndex = this.currentGameState.players.findIndex(p => p.id === player.id);
        if (playerIndex !== -1) {
          this.currentGameState.players[playerIndex].aiAgentCreated = true;
          
          // 明确发送AI代理创建成功的消息
          this.sendMessage({
            type: 'aiAgentCreated',
            playerId: player.id,
            timestamp: new Date().toISOString()
          });
        }
      } catch (error) {
        console.error(`为玩家${player.id}创建AI代理失败:`, error.message);
        
        // 发送错误消息到前端
        this.sendMessage({
          type: 'aiAgentError',
          playerId: player.id,
          error: error.message,
          timestamp: new Date().toISOString()
        });
    }
    
    // 广播更新的游戏状态
    this.updateGameState(this.currentGameState);
  }
  
  // 根据AI模型名称获取对应的提供商和模型
  mapModelToProvider(aiModel) {
    switch (aiModel) {
      case 'ChatGPT-Mini':
        return {
          provider: 'openai',
          model: 'gpt-4o-mini'
        };
      case 'ChatGPT-4O':
        return {
          provider: 'openai',
          model: 'gpt-4o'
        };
      case 'Claude':
        return {
          provider: 'anthropic',
          model: 'claude-3-7-sonnet-20250219'
        };
      case 'Grok':
        return {
          provider: 'xai',
          model: 'grok-2'
        };
      case 'Gemini':
        return {
          provider: 'google',
          model: 'gemini-2.0-pro-exp-02-05'
        };
      case 'DeepSeek':
        return {
          provider: 'deepseek',
          model: 'deepseek-chat'
        };
      case 'Sonar':
        return {
          provider: 'perplexity',
          model: 'sonar'
        };
      case 'Qwen':
        return {
          provider: 'aliyun',
          model: 'qwen-plus'
        };
      default:
        return {
          provider: 'openai',
          model: 'gpt-4o'
        };
    }
  }

  // 处理创建游戏请求
  async handleCreateGame(players) {
    console.log('收到创建游戏请求, 玩家数量:', players.length);
    
    try {
      // 统一使用gameService创建游戏
      let gameState = null;
      if (this.gameService) {
        // 检查gameService是否有createGame方法，如果有则使用
        if (typeof this.gameService.createGame === 'function') {
          const game = await this.gameService.createGame(players);
          
          // 更新当前游戏状态
          gameState = {
            id: game.id,
            gameId: game.id, // 同时提供id和gameId
            players: game.players,
            state: game.state,
            stage: game.state, // 同时提供state和stage
            pot: game.pot,
            currentBet: game.currentBet,
            smallBlind: game.smallBlind,
            bigBlind: game.bigBlind,
            communityCards: game.communityCards,
            currentPlayerIndex: game.currentPlayerIndex,
            dealerIndex: game.dealerIndex
          };
          
          // 确保每个玩家都有正确的position属性
          if (gameState.players && Array.isArray(gameState.players)) {
            // 跟踪已使用的位置
            const usedPositions = new Set();
            
            gameState.players = gameState.players.map((player, index) => {
              // 如果没有position或position无效，分配新的position
              if (!player.position || player.position <= 0 || player.position > 8) {
                let newPosition = index + 1;
                // 如果位置已被使用，寻找下一个可用位置
                while (usedPositions.has(newPosition) && newPosition <= 8) {
                  newPosition++;
                }
                // 如果所有位置都用完了，从1开始重新分配
                if (newPosition > 8) {
                  newPosition = 1;
                  while (usedPositions.has(newPosition)) {
                    newPosition++;
                  }
                }
                
                console.log(`玩家${player.name}(${player.id})没有有效position，分配为${newPosition}`);
                player.position = newPosition;
              }
              
              // 确保aiModel属性正确设置
              if (!player.aiModel && player.model) {
                // 从model字段映射到标准的aiModel名称
                const modelLower = player.model.toLowerCase();
                if (modelLower.includes('gpt-4o-mini')) {
                  player.aiModel = 'ChatGPT-Mini';
                } else if (modelLower.includes('gpt-4o')) {
                  player.aiModel = 'ChatGPT-4O';
                } else if (modelLower.includes('claude')) {
                  player.aiModel = 'Claude';
                } else if (modelLower.includes('grok')) {
                  player.aiModel = 'Grok';
                } else if (modelLower.includes('gemini')) {
                  player.aiModel = 'Gemini';
                } else if (modelLower.includes('deepseek')) {
                  player.aiModel = 'DeepSeek';
                } else if (modelLower.includes('sonar')) {
                  player.aiModel = 'Sonar';
                } else if (modelLower.includes('qwen')) {
                  player.aiModel = 'Qwen';
                }
              }
              
              usedPositions.add(player.position);
              return player;
            });
          }
        } else {
          console.log('警告: gameService 没有 createGame 方法，使用备选方案');
          // 调用备选方案
          const { v4: uuidv4 } = require('uuid');
          const gameId = uuidv4();
          gameState = {
            id: gameId,
            gameId: gameId, // 同时提供id和gameId
            players: players,
            state: 'waiting',
            stage: 'waiting', // 同时提供state和stage
            pot: 0,
            currentBet: 0,
            smallBlind: 10,
            bigBlind: 20,
            communityCards: [],
            currentPlayerIndex: -1,
            dealerIndex: 0
          };
          
          // 同样确保每个玩家都有正确的position属性
          if (gameState.players && Array.isArray(gameState.players)) {
            const usedPositions = new Set();
            
            gameState.players = gameState.players.map((player, index) => {
              if (!player.position || player.position <= 0 || player.position > 8) {
                let newPosition = index + 1;
                while (usedPositions.has(newPosition) && newPosition <= 8) {
                  newPosition++;
                }
                if (newPosition > 8) {
                  newPosition = 1;
                  while (usedPositions.has(newPosition)) {
                    newPosition++;
                  }
                }
                
                console.log(`玩家${player.name}(${player.id})没有有效position，分配为${newPosition}`);
                player.position = newPosition;
              }
              
              // 确保aiModel属性正确设置
              if (!player.aiModel && player.model) {
                // 从model字段映射到标准的aiModel名称
                const modelLower = player.model.toLowerCase();
                if (modelLower.includes('gpt-4o-mini')) {
                  player.aiModel = 'ChatGPT-Mini';
                } else if (modelLower.includes('gpt-4o')) {
                  player.aiModel = 'ChatGPT-4O';
                } else if (modelLower.includes('claude')) {
                  player.aiModel = 'Claude';
                } else if (modelLower.includes('grok')) {
                  player.aiModel = 'Grok';
                } else if (modelLower.includes('gemini')) {
                  player.aiModel = 'Gemini';
                } else if (modelLower.includes('deepseek')) {
                  player.aiModel = 'DeepSeek';
                } else if (modelLower.includes('sonar')) {
                  player.aiModel = 'Sonar';
                } else if (modelLower.includes('qwen')) {
                  player.aiModel = 'Qwen';
                }
              }
              
              usedPositions.add(player.position);
              return player;
            });
          }
          
          // 将此游戏状态保存到gameService中，确保startGame可以找到它
          if (typeof this.gameService.saveGame === 'function') {
            this.gameService.saveGame(gameState);
          }
        }
      } else {
        // 如果gameService不可用，创建一个基本的游戏对象
        const { v4: uuidv4 } = require('uuid');
        const gameId = uuidv4();
        gameState = {
          id: gameId,
          gameId: gameId, // 同时提供id和gameId
          players: players,
          state: 'waiting',
          stage: 'waiting', // 同时提供state和stage
          pot: 0,
          currentBet: 0,
          smallBlind: 10,
          bigBlind: 20,
          communityCards: [],
          currentPlayerIndex: -1,
          dealerIndex: 0
        };
        
        // 同样确保每个玩家都有正确的position属性
        if (gameState.players && Array.isArray(gameState.players)) {
          const usedPositions = new Set();
          
          gameState.players = gameState.players.map((player, index) => {
            if (!player.position || player.position <= 0 || player.position > 8) {
              let newPosition = index + 1;
              while (usedPositions.has(newPosition) && newPosition <= 8) {
                newPosition++;
              }
              if (newPosition > 8) {
                newPosition = 1;
                while (usedPositions.has(newPosition)) {
                  newPosition++;
                }
              }
              
              console.log(`玩家${player.name}(${player.id})没有有效position，分配为${newPosition}`);
              player.position = newPosition;
            }
            
            // 确保aiModel属性正确设置
            if (!player.aiModel && player.model) {
              // 从model字段映射到标准的aiModel名称
              const modelLower = player.model.toLowerCase();
              if (modelLower.includes('gpt-4o-mini')) {
                player.aiModel = 'ChatGPT-Mini';
              } else if (modelLower.includes('gpt-4o')) {
                player.aiModel = 'ChatGPT-4O';
              } else if (modelLower.includes('claude')) {
                player.aiModel = 'Claude';
              } else if (modelLower.includes('grok')) {
                player.aiModel = 'Grok';
              } else if (modelLower.includes('gemini')) {
                player.aiModel = 'Gemini';
              } else if (modelLower.includes('deepseek')) {
                player.aiModel = 'DeepSeek';
              } else if (modelLower.includes('sonar')) {
                player.aiModel = 'Sonar';
              } else if (modelLower.includes('qwen')) {
                player.aiModel = 'Qwen';
              }
            }
            
            usedPositions.add(player.position);
            return player;
          });
        }
      }
      
      // 记录一些有用的调试信息
      console.log(`游戏创建成功: ID=${gameState.id}, 玩家数量=${gameState.players ? gameState.players.length : 0}`);
      if (gameState.players && gameState.players.length > 0) {
        console.log('玩家位置分配:');
        gameState.players.forEach(player => {
          console.log(`  ${player.name}(${player.id}): 位置=${player.position}`);
        });
      }
      
      // 更新当前游戏状态
      this.currentGameState = gameState;
      
      // 向前端发送游戏创建成功消息
      this.sendMessage({
        type: 'gameCreated',
        gameState: this.currentGameState,
        timestamp: new Date().toISOString()
      });
      
      // 游戏已创建，但不自动开始，等待前端发送startGame命令
      console.log('游戏创建成功，等待开始命令');
      
    } catch (error) {
      console.error('创建游戏失败:', error.message);
      this.sendMessage({
        type: 'error',
        message: `创建游戏失败: ${error.message}`,
        timestamp: new Date().toISOString()
      });
    }
  }
}

module.exports = { WebSocketService }; 