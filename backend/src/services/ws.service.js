/**
 * WebSocket服务 - 简化版
 * 只处理单一前端连接，专注于游戏状态同步
 */

const aiService = require('./ai.service');
const { GameService } = require('./game.service');
const { buildPlayerView, sanitizeDecision } = require('./player-view');
const config = require('../config');
const logger = require('../utils/logger');

const VALID_PLAYER_ACTIONS = ['fold', 'check', 'call', 'raise', 'allin'];
// 每次状态更新都会下发思考记录，只保留最近的N条，避免消息体随对局无限增长
const MAX_THINKING_RECORDS = 100;

class WebSocketService {
  constructor() {
    this.frontendConnection = null; // 只保存一个前端连接
    this.isGameRunning = false;
    this.currentGameState = null;
    this.gameService = new GameService();
    this.decisionInFlight = false; // 同一时间只允许一个AI决策请求
  }

  initialize(wss) {
    logger.info('WebSocket服务初始化');

    wss.on('connection', (ws) => {
      logger.info('前端已连接');
      this.frontendConnection = ws;

      // 心跳存活标记：收到pong说明连接仍然存活
      ws.isAlive = true;
      ws.on('pong', () => {
        ws.isAlive = true;
      });

      // 发送欢迎消息
      this.sendMessage({
        type: 'connection',
        message: '连接成功',
        timestamp: new Date().toISOString()
      });

      // 如果有正在进行的游戏（例如前端重连），立即同步当前状态
      if (this.isGameRunning && this.currentGameState) {
        this.sendGameState();
      }

      // 处理接收到的消息
      ws.on('message', (message) => {
        try {
          const data = JSON.parse(message);
          logger.info('收到消息:', data && data.type);
          logger.debug('消息内容:', data);
          this.handleMessage(data);
        } catch (error) {
          logger.error('消息解析错误:', error.message);
          this.sendError('消息格式不正确');
        }
      });

      // 处理连接关闭：只有关闭的是当前连接时才清空引用，避免重连竞态
      ws.on('close', () => {
        logger.info('前端断开连接');
        if (ws === this.frontendConnection) {
          this.frontendConnection = null;
        }
      });

      // 处理错误
      ws.on('error', (error) => {
        logger.error('WebSocket错误:', error.message);
        if (ws === this.frontendConnection) {
          this.frontendConnection = null;
        }
      });

      // 发送心跳包保持连接
      this.startHeartbeat(ws);
    });
  }

  // 处理接收到的消息（按消息类型校验消息结构）
  handleMessage(data) {
    if (!data || typeof data.type !== 'string') {
      this.sendError('消息缺少type字段');
      return;
    }

    switch (data.type) {
      case 'ping':
        // 响应ping消息，用于连接测试
        this.sendMessage({
          type: 'pong',
          timestamp: new Date().toISOString()
        });
        break;
      case 'createGame':
        if (data.players !== undefined && !Array.isArray(data.players)) {
          this.sendError('createGame消息的players必须是数组');
          return;
        }
        this.handleCreateGame(data.players || []);
        break;
      case 'startGame':
        if (typeof data.gameId !== 'string' || !data.gameId) {
          this.sendError('startGame消息缺少gameId');
          return;
        }
        this.startGame(data.gameId);
        break;
      case 'nextStep':
        this.handleNextStep();
        break;
      case 'playerAction':
        if (typeof data.playerId !== 'string' || !data.playerId) {
          this.sendError('playerAction消息缺少playerId');
          return;
        }
        if (typeof data.action !== 'string' || !VALID_PLAYER_ACTIONS.includes(data.action)) {
          this.sendError(`playerAction消息的action无效: ${data.action}`);
          return;
        }
        if (data.amount !== undefined && (!Number.isInteger(data.amount) || data.amount < 0)) {
          this.sendError('playerAction消息的amount必须是非负整数');
          return;
        }
        this.handlePlayerAction(data.playerId, data.action, data.amount || 0);
        break;
      case 'resetGame':
        this.resetGame();
        break;
      case 'getGameState':
        this.sendGameState();
        break;
      case 'addPlayer':
        if (!data.player || typeof data.player !== 'object' || !data.player.id || !data.player.name) {
          this.sendError('addPlayer消息缺少player（需要id和name）');
          return;
        }
        this.handleAddPlayer(data.player);
        break;
      default:
        logger.warn('未知的消息类型:', data.type);
        this.sendError(`未知的消息类型: ${data.type}`);
    }
  }

  // 开始游戏
  startGame(gameId) {
    logger.info(`尝试开始游戏，ID: ${gameId}`);

    try {
      // 保存前端此前设置的玩家属性（aiModel、position）
      const originalPlayers = this.currentGameState && this.currentGameState.players
        ? [...this.currentGameState.players]
        : [];

      const gameState = this.gameService.startGame(gameId);

      // 保留原始玩家的aiModel和position等前端设置的属性
      if (originalPlayers.length > 0) {
        gameState.players.forEach(player => {
          const originalPlayer = originalPlayers.find(p => p.id === player.id);
          if (originalPlayer) {
            player.aiModel = originalPlayer.aiModel || player.aiModel;
            player.position = originalPlayer.position || player.position;
          }
        });
      }

      // 保持前后端字段一致性
      gameState.stage = gameState.state;
      gameState.gameId = gameState.id;

      this.currentGameState = gameState;
      this.isGameRunning = true;

      this.sendMessage({
        type: 'gameStarted',
        gameState: this.sanitizeForClient(gameState),
        timestamp: new Date().toISOString()
      });
      this.sendHandResultIfFinished(gameState);

      logger.info(`游戏${gameId}已成功开始，当前阶段: ${gameState.state}`);
    } catch (error) {
      // 引擎报错时直接告知前端，不再伪造游戏状态
      logger.error('开始游戏失败:', error.message);
      this.sendError(`开始游戏失败: ${error.message}`);
    }
  }

  // 处理游戏下一步
  handleNextStep() {
    if (!this.isGameRunning || !this.currentGameState) {
      this.sendError('游戏尚未开始');
      return;
    }

    // AI还在思考时重复点击"下一步"会对同一玩家发起第二次决策请求
    if (this.decisionInFlight) {
      logger.info('AI决策进行中，忽略重复的下一步请求');
      return;
    }

    if (this.currentGameState.state === 'waiting') {
      this.sendError('游戏尚未开始');
      return;
    }

    logger.info('处理游戏下一步');

    // 检查游戏是否已经处于摊牌或结束状态
    if (this.currentGameState.state === 'showdown' || this.currentGameState.state === 'finished') {
      const prevState = this.currentGameState.state;
      logger.info(`游戏处于${prevState}状态，直接进入下一个阶段`);

      if (prevState === 'finished') {
        // 开始新一轮
        const newRound = this.gameService.startNewRound(this.currentGameState);
        if (!newRound || newRound.state === 'finished') {
          // 剩余玩家不足，整局游戏结束
          logger.info('剩余玩家不足，游戏结束');
          this.updateGameState(newRound || this.currentGameState);
          return;
        }

        // 立即发新一手牌；不能延迟，否则延迟期间的"下一步"会在waiting状态下触发AI决策
        try {
          logger.info('自动开始新一轮发牌');
          this.gameService.startGame(this.currentGameState.id);
          const updatedGame = this.gameService.getGameState(this.currentGameState.id);
          this.updateGameState(updatedGame);

          this.sendMessage({
            type: 'gameStageChanged',
            oldStage: 'finished',
            newStage: updatedGame.state,
            timestamp: new Date().toISOString()
          });
          this.sendHandResultIfFinished(updatedGame);
        } catch (error) {
          logger.error('自动开始新一轮失败:', error.message);
          this.sendError(`自动开始新一轮失败: ${error.message}`);
        }
      } else {
        // 摊牌阶段：结算并进入新一轮
        const updatedGame = this.gameService.moveToNextRound(this.currentGameState);
        this.updateGameState(updatedGame);

        this.sendMessage({
          type: 'gameStageChanged',
          oldStage: prevState,
          newStage: updatedGame.state,
          timestamp: new Date().toISOString()
        });
      }

      return;
    }

    const currentPlayerIndex = this.currentGameState.currentPlayerIndex;
    const players = this.currentGameState.players;

    if (currentPlayerIndex < 0 || currentPlayerIndex >= players.length) {
      this.sendError('当前没有活跃玩家');
      return;
    }

    const currentPlayer = players[currentPlayerIndex];

    // 在本项目中，所有玩家都是AI玩家
    logger.info(`当前玩家: ${currentPlayer.name}, 模型: ${currentPlayer.aiModel || '未指定，将作为AI处理'}`);

    if (!currentPlayer.aiModel) {
      logger.info(`玩家${currentPlayer.name}没有指定AI模型，默认使用Claude`);
      currentPlayer.aiModel = 'Claude';
    }

    // 调用AI服务进行决策
    return this.processAIDecision(currentPlayer);
  }

  // 构建发送给AI服务的游戏视图：只包含该玩家自己的手牌，隐藏他人手牌与牌堆
  buildAIView(actingPlayer) {
    return buildPlayerView(this.currentGameState, actingPlayer);
  }

  // 处理AI玩家决策
  async processAIDecision(player) {
    this.decisionInFlight = true;
    const gameId = this.currentGameState.id;
    try {
      logger.info(`处理AI玩家${player.name}(${player.aiModel})的决策`);

      const legal = this.gameService.getLegalActions(this.currentGameState, player);
      const { validActions, minBet, maxBet } = legal;

      logger.info(`有效动作列表: ${validActions.join(', ')}, 下注范围: ${minBet}-${maxBet}`);

      // 通知前端AI正在思考
      this.sendMessage({
        type: 'aiThinking',
        playerId: player.id,
        model: player.aiModel,
        timestamp: new Date().toISOString()
      });

      // 调用AI服务获取决策（只发送该玩家可见的信息）
      const decision = await aiService.getDecision(
        player.id,
        this.buildAIView(player),
        validActions,
        minBet,
        maxBet
      );

      logger.info(`AI决策结果: ${decision.action}, 金额: ${decision.amount || 'N/A'}`);

      // 等待期间游戏可能已被重置或重建，过期的决策直接丢弃
      if (!this.isStillActing(gameId, player.id)) {
        logger.warn(`玩家${player.name}的决策返回时已不再轮到他行动，丢弃该决策`);
        return;
      }

      // 创建思考记录
      if (decision.thinking) {
        this.addThinkingRecord(player, decision.thinking, decision.action);
      }

      // 非法动作换成默认动作，加注金额钳制到合法范围
      const checked = sanitizeDecision(decision, legal);
      if (checked.corrected) {
        logger.warn(`AI返回的动作${decision.action}不在有效动作列表中，使用默认动作${checked.action}`);
      }
      decision.action = checked.action;
      decision.amount = checked.amount;

      // 处理AI决策
      this.handlePlayerAction(player.id, decision.action, decision.action === 'raise' ? decision.amount : 0);

    } catch (error) {
      logger.error('处理AI决策出错:', error.message);

      if (!this.isStillActing(gameId, player.id)) {
        return;
      }

      // 发送错误消息到前端
      this.sendMessage({
        type: 'aiAgentError',
        playerId: player.id,
        error: error.message,
        timestamp: new Date().toISOString()
      });

      // 根据策略选择默认动作：优先check，其次call，最后才fold
      const validActions = this.calculateValidActions(player);
      let defaultAction = 'fold';
      if (validActions.includes('check')) {
        defaultAction = 'check';
      } else if (validActions.includes('call')) {
        defaultAction = 'call';
      }
      logger.info(`错误情况下，AI玩家${player.name}使用'${defaultAction}'作为默认操作`);

      // 执行默认动作
      this.handlePlayerAction(player.id, defaultAction, 0);
    } finally {
      this.decisionInFlight = false;
    }
  }

  // 判断某玩家是否仍是指定游戏中当前该行动的人
  isStillActing(gameId, playerId) {
    const game = this.currentGameState;
    if (!game || game.id !== gameId) return false;
    const current = game.players[game.currentPlayerIndex];
    return !!current && current.id === playerId && current.isCurrent;
  }

  // 一手牌刚结束时单独推送结果（赢家、牌型），前端据此只提示一次
  sendHandResultIfFinished(game) {
    if (!game || game.state !== 'finished' || !game.lastHandResult) return;
    this.sendMessage({
      type: 'handResult',
      result: game.lastHandResult,
      timestamp: new Date().toISOString()
    });
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
    if (this.currentGameState.thinkingHistory.length > MAX_THINKING_RECORDS) {
      this.currentGameState.thinkingHistory.splice(
        0, this.currentGameState.thinkingHistory.length - MAX_THINKING_RECORDS
      );
    }

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
    return this.gameService.getLegalActions(this.currentGameState, player).validActions;
  }

  // 发送更新的游戏状态
  sendGameStateUpdate() {
    if (this.currentGameState) {
      this.sendMessage({
        type: 'gameStateUpdate',
        gameState: this.sanitizeForClient(this.currentGameState),
        timestamp: new Date().toISOString()
      });
    }
  }

  // 重置游戏
  resetGame() {
    this.isGameRunning = false;
    this.currentGameState = null;
    logger.info('游戏重置');

    // 后端不主动删除AI代理，这一步由前端完成

    this.sendMessage({
      type: 'gameReset',
      timestamp: new Date().toISOString()
    });
  }

  // 处理玩家行动
  handlePlayerAction(playerId, action, amount) {
    logger.info(`玩家${playerId}执行${action}操作，金额:${amount}`);

    try {
      if (!this.currentGameState) {
        throw new Error('游戏尚未开始');
      }

      // 先记录旧阶段，用于检测阶段变化
      const prevState = this.currentGameState.state;

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
      if (updatedGame.state !== prevState) {
        this.sendMessage({
          type: 'gameStageChanged',
          oldStage: prevState,
          newStage: updatedGame.state,
          timestamp: new Date().toISOString()
        });
        this.sendHandResultIfFinished(updatedGame);
      }

      if (updatedGame.state === 'showdown' || updatedGame.state === 'finished') {
        logger.info(`游戏进入${updatedGame.state}阶段，等待用户点击"下一步"`);
      } else {
        logger.info(`玩家${playerId}的行动已处理，等待用户点击"下一步"处理下一个玩家`);
      }
    } catch (error) {
      logger.error('处理玩家行动出错:', error.message);

      // 获取玩家信息
      const player = this.currentGameState && this.currentGameState.players
        ? this.currentGameState.players.find(p => p.id === playerId)
        : null;

      // 对于AI玩家的无效操作，替换为合法的默认动作（优先check，否则fold）
      if (player && player.isAI) {
        const fallbackActions = this.calculateValidActions(player);
        const fallback = fallbackActions.includes('check') ? 'check' : 'fold';
        if (fallback !== action) {
          logger.warn(`玩家${player.name}(${playerId})的${action}操作失败，自动转为${fallback}处理：${error.message}`);
          try {
            const updatedGame = this.gameService.handlePlayerAction(
              this.currentGameState.id,
              playerId,
              fallback,
              0
            );

            this.updateGameState(updatedGame);

            this.sendMessage({
              type: 'playerActionProcessed',
              playerId,
              action: fallback,
              amount: 0,
              timestamp: new Date().toISOString()
            });
            this.sendHandResultIfFinished(updatedGame);

            return; // 成功处理，不发送错误消息
          } catch (fallbackError) {
            logger.error(`执行自动${fallback}操作失败:`, fallbackError.message);
          }
        }
      }

      this.sendError(`处理玩家行动失败: ${error.message}`);
    }
  }

  // 发送游戏状态
  sendGameState() {
    if (this.currentGameState) {
      this.sendMessage({
        type: 'gameState',
        gameState: this.sanitizeForClient(this.currentGameState),
        timestamp: new Date().toISOString()
      });
    } else {
      this.sendError('游戏尚未开始');
    }
  }

  // 更新并广播游戏状态
  updateGameState(newGameState) {
    this.currentGameState = newGameState;
    if (this.currentGameState) {
      this.currentGameState.stage = this.currentGameState.state;
    }

    this.sendMessage({
      type: 'gameStateUpdate',
      gameState: this.sanitizeForClient(this.currentGameState),
      timestamp: new Date().toISOString()
    });
  }

  // 构建发给前端的游戏状态：前端是观战视角，保留所有玩家手牌，但绝不下发牌堆
  sanitizeForClient(gameState) {
    if (!gameState) return gameState;
    const { deck, ...clientState } = gameState;
    // 前端靠isDealer画庄家按钮，dealerIndex是数组下标，前端无法自己从座位号推出来
    if (Array.isArray(clientState.players)) {
      clientState.players = clientState.players.map((p, index) => ({
        ...p,
        isDealer: index === clientState.dealerIndex
      }));
    }
    return clientState;
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

  // 启动心跳检测：发送ping并检查上一轮是否收到pong，未响应则断开
  startHeartbeat(ws) {
    const interval = setInterval(() => {
      if (ws.readyState !== 1) {
        clearInterval(interval);
        return;
      }
      if (ws.isAlive === false) {
        logger.warn('心跳超时，终止连接');
        clearInterval(interval);
        ws.terminate();
        return;
      }
      ws.isAlive = false;
      ws.ping();
    }, 30000); // 每30秒发送一次ping

    ws.on('close', () => {
      clearInterval(interval);
    });
  }

  // 处理添加玩家
  async handleAddPlayer(player) {
    logger.info('收到添加玩家请求:', player.id, player.name);

    // 没有当前游戏时，先在引擎中创建一个空游戏
    if (!this.currentGameState) {
      const game = this.gameService.createGame([]);
      game.gameId = game.id;
      game.stage = game.state;
      this.currentGameState = game;
    }

    // 在添加玩家前，根据名称推断AI模型
    if (!player.aiModel) {
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

      logger.info(`为玩家${player.name}推断AI模型: ${player.aiModel}`);
    }

    // 添加玩家（补全游戏引擎所需字段）
    this.currentGameState.players.push({
      ...player,
      position: Number.isInteger(player.position) && player.position > 0
        ? player.position
        : this.currentGameState.players.length + 1,
      isActive: true,
      isCurrent: false,
      isAllIn: false,
      isAI: true,
      cards: [],
      bet: 0,
      chips: Number.isInteger(player.chips) && player.chips > 0 ? player.chips : 1000,
      totalContribution: 0,
      hasActed: false,
      action: null
    });

    try {
      logger.info(`为玩家${player.id}创建AI代理, 模型: ${player.aiModel}`);

      // 将模型名称映射到提供商和模型
      const modelMapping = this.mapModelToProvider(player.aiModel);

      // 调用AI服务创建代理
      await aiService.createAgent(
        player.id,
        player.name,
        modelMapping.provider,
        modelMapping.model
      );

      logger.info(`AI代理创建成功: ${player.id}`);

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
      logger.error(`为玩家${player.id}创建AI代理失败:`, error.message);

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

  // 从model字段映射到标准的aiModel名称
  mapModelName(model) {
    const modelLower = String(model).toLowerCase();
    if (modelLower.includes('gpt-4o-mini')) return 'ChatGPT-Mini';
    if (modelLower.includes('gpt-4o')) return 'ChatGPT-4O';
    if (modelLower.includes('claude')) return 'Claude';
    if (modelLower.includes('grok')) return 'Grok';
    if (modelLower.includes('gemini')) return 'Gemini';
    if (modelLower.includes('deepseek')) return 'DeepSeek';
    if (modelLower.includes('sonar')) return 'Sonar';
    if (modelLower.includes('qwen')) return 'Qwen';
    return undefined;
  }

  // 统一补全玩家的position与aiModel属性
  normalizePlayers(players) {
    const usedPositions = new Set();

    players.forEach((player, index) => {
      // 如果没有position或position无效，分配新的position
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

        logger.debug(`玩家${player.name}(${player.id})没有有效position，分配为${newPosition}`);
        player.position = newPosition;
      }

      // 确保aiModel属性正确设置
      if (!player.aiModel && player.model) {
        player.aiModel = this.mapModelName(player.model);
      }

      player.isAI = true;
      usedPositions.add(player.position);
    });

    return players;
  }

  // 处理创建游戏请求
  handleCreateGame(players) {
    logger.info('收到创建游戏请求, 玩家数量:', players.length);

    try {
      const game = this.gameService.createGame(players);
      this.normalizePlayers(game.players);

      // 保持前后端字段一致性
      game.gameId = game.id;
      game.stage = game.state;

      logger.info(`游戏创建成功: ID=${game.id}, 玩家数量=${game.players.length}`);
      game.players.forEach(player => {
        logger.debug(`  ${player.name}(${player.id}): 位置=${player.position}`);
      });

      // 更新当前游戏状态
      this.currentGameState = game;

      // 向前端发送游戏创建成功消息
      this.sendMessage({
        type: 'gameCreated',
        gameState: this.sanitizeForClient(game),
        timestamp: new Date().toISOString()
      });

      // 游戏已创建，但不自动开始，等待前端发送startGame命令
      logger.info('游戏创建成功，等待开始命令');

    } catch (error) {
      logger.error('创建游戏失败:', error.message);
      this.sendError(`创建游戏失败: ${error.message}`);
    }
  }
}

module.exports = { WebSocketService };
