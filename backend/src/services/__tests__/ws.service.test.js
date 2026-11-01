process.env.LOG_LEVEL = 'silent'; // 测试中静默日志

jest.mock('../ai.service', () => ({
  createAgent: jest.fn().mockResolvedValue({ status: 'ok' }),
  getDecision: jest.fn(),
  deleteAgent: jest.fn().mockResolvedValue(undefined)
}));

const aiService = require('../ai.service');
const { WebSocketService } = require('../ws.service');
const config = require('../../config');

// 构造模拟的WebSocket连接
function createMockWs() {
  const handlers = {};
  const ws = {
    readyState: 1,
    sent: [],
    on: jest.fn((event, cb) => {
      handlers[event] = handlers[event] || [];
      handlers[event].push(cb);
    }),
    send: jest.fn((data) => {
      ws.sent.push(JSON.parse(data));
    }),
    ping: jest.fn(),
    terminate: jest.fn(),
    emit: (event, ...args) => {
      (handlers[event] || []).forEach(cb => cb(...args));
    }
  };
  return ws;
}

function connect(wsService, wss, ws) {
  const connectionHandler = wss.on.mock.calls.find(call => call[0] === 'connection')[1];
  connectionHandler(ws);
}

const testPlayers = [
  { id: 'p1', name: 'Claude-A', model: 'claude-3-7-sonnet' },
  { id: 'p2', name: 'GPT-B', model: 'gpt-4o' },
  { id: 'p3', name: 'Qwen-C', model: 'qwen-plus' }
];

describe('WebSocketService', () => {
  let wsService;
  let wss;
  let ws;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
    wsService = new WebSocketService();
    wss = { on: jest.fn() };
    wsService.initialize(wss);
    ws = createMockWs();
    connect(wsService, wss, ws);
  });

  afterEach(() => {
    jest.clearAllTimers();
    jest.useRealTimers();
  });

  // 通过消息通道创建并开始一局游戏
  function createAndStartGame() {
    ws.emit('message', JSON.stringify({ type: 'createGame', players: testPlayers }));
    const created = ws.sent.find(m => m.type === 'gameCreated');
    ws.emit('message', JSON.stringify({ type: 'startGame', gameId: created.gameState.id }));
    return created.gameState.id;
  }

  describe('连接管理', () => {
    test('连接建立后应注册消息处理并发送欢迎消息', () => {
      expect(wss.on).toHaveBeenCalledWith('connection', expect.any(Function));
      expect(ws.on).toHaveBeenCalledWith('message', expect.any(Function));
      expect(ws.on).toHaveBeenCalledWith('close', expect.any(Function));
      expect(ws.on).toHaveBeenCalledWith('pong', expect.any(Function));
      expect(ws.sent.some(m => m.type === 'connection')).toBe(true);
    });

    test('旧连接关闭不应清空新连接的引用', () => {
      const ws2 = createMockWs();
      connect(wsService, wss, ws2);
      expect(wsService.frontendConnection).toBe(ws2);

      ws.emit('close'); // 旧连接关闭
      expect(wsService.frontendConnection).toBe(ws2);

      ws2.emit('close'); // 当前连接关闭才清空
      expect(wsService.frontendConnection).toBeNull();
    });

    test('游戏进行中新连接应自动收到当前游戏状态', () => {
      createAndStartGame();

      const ws2 = createMockWs();
      connect(wsService, wss, ws2);

      const stateMsg = ws2.sent.find(m => m.type === 'gameState');
      expect(stateMsg).toBeDefined();
      expect(stateMsg.gameState.state).toBe('preflop');
    });

    test('心跳应检测pong响应，未响应时终止连接', () => {
      // 第一轮：标记isAlive=false并发送ping
      jest.advanceTimersByTime(30000);
      expect(ws.ping).toHaveBeenCalledTimes(1);
      expect(ws.isAlive).toBe(false);

      // 模拟收到pong
      ws.emit('pong');
      expect(ws.isAlive).toBe(true);

      // 第二轮正常ping
      jest.advanceTimersByTime(30000);
      expect(ws.ping).toHaveBeenCalledTimes(2);

      // 不再回应pong：第三轮应终止连接
      jest.advanceTimersByTime(30000);
      expect(ws.terminate).toHaveBeenCalled();
    });
  });

  describe('消息校验', () => {
    test('无效JSON应返回错误', () => {
      ws.emit('message', 'not valid json');
      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('消息格式不正确'))).toBe(true);
    });

    test('未知消息类型应返回错误', () => {
      ws.emit('message', JSON.stringify({ type: 'bogusType' }));
      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('bogusType'))).toBe(true);
    });

    test('缺少type字段应返回错误', () => {
      ws.emit('message', JSON.stringify({ foo: 'bar' }));
      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('type'))).toBe(true);
    });

    test('playerAction缺少必要字段或金额非法应被拒绝', () => {
      createAndStartGame();

      ws.emit('message', JSON.stringify({ type: 'playerAction', action: 'call' }));
      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('playerId'))).toBe(true);

      ws.emit('message', JSON.stringify({ type: 'playerAction', playerId: 'p1', action: 'steal' }));
      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('action无效'))).toBe(true);

      ws.emit('message', JSON.stringify({ type: 'playerAction', playerId: 'p1', action: 'raise', amount: 'lots' }));
      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('非负整数'))).toBe(true);
    });

    test('startGame缺少gameId应返回错误', () => {
      ws.emit('message', JSON.stringify({ type: 'startGame' }));
      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('gameId'))).toBe(true);
    });
  });

  describe('游戏创建与开始', () => {
    test('createGame应创建游戏并广播gameCreated（不含牌堆）', () => {
      ws.emit('message', JSON.stringify({ type: 'createGame', players: testPlayers }));

      const created = ws.sent.find(m => m.type === 'gameCreated');
      expect(created).toBeDefined();
      expect(created.gameState.players).toHaveLength(3);
      expect(created.gameState.deck).toBeUndefined();
      expect(created.gameState.smallBlind).toBe(config.SMALL_BLIND);
      expect(created.gameState.bigBlind).toBe(config.BIG_BLIND);
      // model字段应被映射为aiModel
      expect(created.gameState.players.find(p => p.id === 'p1').aiModel).toBe('Claude');
      expect(created.gameState.players.find(p => p.id === 'p2').aiModel).toBe('ChatGPT-4O');
    });

    test('startGame成功后应广播gameStarted，观战视角保留所有手牌但不含牌堆', () => {
      createAndStartGame();

      const started = ws.sent.find(m => m.type === 'gameStarted');
      expect(started).toBeDefined();
      expect(started.gameState.state).toBe('preflop');
      expect(started.gameState.deck).toBeUndefined();
      // 前端是观战UI：所有玩家手牌都应可见
      started.gameState.players.forEach(p => {
        expect(p.cards).toHaveLength(2);
      });
    });

    test('startGame引擎报错时应发送错误消息而不是伪造游戏状态', () => {
      ws.emit('message', JSON.stringify({ type: 'startGame', gameId: 'no-such-game' }));

      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('开始游戏失败'))).toBe(true);
      expect(ws.sent.some(m => m.type === 'gameStarted')).toBe(false);
      expect(wsService.isGameRunning).toBe(false);
    });
  });

  describe('AI决策', () => {
    test('发送给AI服务的游戏视图只包含行动玩家自己的手牌且不含牌堆', async () => {
      aiService.getDecision.mockResolvedValue({ action: 'fold', amount: 0, thinking: '测试思考' });
      createAndStartGame();

      const actingPlayer = wsService.currentGameState.players[wsService.currentGameState.currentPlayerIndex];
      await wsService.handleNextStep();

      expect(aiService.getDecision).toHaveBeenCalledTimes(1);
      const view = aiService.getDecision.mock.calls[0][1];

      expect(view.deck).toBeUndefined();
      expect(view.pot).toBeDefined();
      expect(view.currentBet).toBeDefined();
      expect(view.communityCards).toBeDefined();
      expect(view.actionHistory).toBeDefined();

      // 行动玩家能看到自己的手牌，其他玩家的手牌为空
      view.players.forEach(p => {
        if (p.id === actingPlayer.id) {
          expect(p.cards).toHaveLength(2);
        } else {
          expect(p.cards).toHaveLength(0);
        }
      });
    });

    test('AI返回无效动作时应被替换为合法动作', async () => {
      aiService.getDecision.mockResolvedValue({ action: 'cheat', amount: 0, thinking: 'x' });
      createAndStartGame();

      const actingPlayer = wsService.currentGameState.players[wsService.currentGameState.currentPlayerIndex];
      await wsService.handleNextStep();

      const processed = ws.sent.find(m => m.type === 'playerActionProcessed');
      expect(processed).toBeDefined();
      expect(processed.playerId).toBe(actingPlayer.id);
      expect(['check', 'call', 'fold']).toContain(processed.action);
      expect(actingPlayer.hasActed).toBe(true);
    });

    test('AI服务出错时应执行默认动作而不是卡住', async () => {
      aiService.getDecision.mockRejectedValue(new Error('AI服务不可用'));
      createAndStartGame();

      await wsService.handleNextStep();

      expect(ws.sent.some(m => m.type === 'aiAgentError')).toBe(true);
      expect(ws.sent.some(m => m.type === 'playerActionProcessed')).toBe(true);
    });

    test('gameStageChanged应在阶段真正变化时携带正确的新旧阶段', async () => {
      // 三家依次call/check后进入flop
      aiService.getDecision.mockImplementation((playerId, view, validActions) => {
        const action = validActions.includes('check') ? 'check' : 'call';
        return Promise.resolve({ action, amount: 0, thinking: 'x' });
      });
      createAndStartGame();

      await wsService.handleNextStep();
      await wsService.handleNextStep();
      await wsService.handleNextStep();

      const stageChanged = ws.sent.find(m => m.type === 'gameStageChanged');
      expect(stageChanged).toBeDefined();
      expect(stageChanged.oldStage).toBe('preflop');
      expect(stageChanged.newStage).toBe('flop');
    });
  });

  describe('状态广播', () => {
    test('gameStateUpdate不应包含牌堆', async () => {
      aiService.getDecision.mockResolvedValue({ action: 'fold', amount: 0, thinking: 'x' });
      createAndStartGame();
      await wsService.handleNextStep();

      const updates = ws.sent.filter(m => m.type === 'gameStateUpdate');
      expect(updates.length).toBeGreaterThan(0);
      updates.forEach(update => {
        expect(update.gameState.deck).toBeUndefined();
      });
    });

    test('大盲在翻牌前应获得check选项', () => {
      createAndStartGame();
      const game = wsService.currentGameState;
      // 3人桌dealerIndex对应的大盲位
      const bbIndex = (game.dealerIndex + 2) % game.players.length;
      const bbPlayer = game.players[bbIndex];

      const validActions = wsService.calculateValidActions(bbPlayer);
      expect(validActions).toContain('check');
      expect(validActions).not.toContain('call'); // 无需跟注
    });

    test('面对下注的玩家不能check', () => {
      createAndStartGame();
      const game = wsService.currentGameState;
      const sbIndex = (game.dealerIndex + 1) % game.players.length;
      const sbPlayer = game.players[sbIndex];

      const validActions = wsService.calculateValidActions(sbPlayer);
      expect(validActions).not.toContain('check');
      expect(validActions).toContain('call');
      expect(validActions).toContain('raise');
      expect(validActions).toContain('allin');
    });

    test('resetGame应清空状态并广播gameReset', () => {
      createAndStartGame();
      ws.emit('message', JSON.stringify({ type: 'resetGame' }));

      expect(wsService.isGameRunning).toBe(false);
      expect(wsService.currentGameState).toBeNull();
      expect(ws.sent.some(m => m.type === 'gameReset')).toBe(true);
    });
  });

  describe('添加玩家', () => {
    test('addPlayer应补全玩家属性、标记isAI并创建AI代理', async () => {
      await wsService.handleAddPlayer({ id: 'px', name: 'Claude-X' });

      const added = wsService.currentGameState.players.find(p => p.id === 'px');
      expect(added).toBeDefined();
      expect(added.isAI).toBe(true);
      expect(added.aiModel).toBe('Claude');
      expect(aiService.createAgent).toHaveBeenCalledWith('px', 'Claude-X', 'anthropic', expect.any(String));
      expect(ws.sent.some(m => m.type === 'aiAgentCreated' && m.playerId === 'px')).toBe(true);
    });

    test('addPlayer缺少必要字段应返回错误', () => {
      ws.emit('message', JSON.stringify({ type: 'addPlayer', player: { foo: 1 } }));
      expect(ws.sent.some(m => m.type === 'error' && m.message.includes('addPlayer'))).toBe(true);
    });
  });
  describe('数据传输修复', () => {
    test('状态中每个玩家应带isDealer标记', () => {
      createAndStartGame();
      const started = ws.sent.find(m => m.type === 'gameStarted');
      const dealers = started.gameState.players.filter(p => p.isDealer);
      expect(dealers).toHaveLength(1);
      expect(started.gameState.players.indexOf(dealers[0])).toBe(started.gameState.dealerIndex);
    });

    test('AI思考期间重复的下一步不应发起第二次决策请求', async () => {
      let resolveDecision;
      aiService.getDecision.mockImplementation(() => new Promise(r => { resolveDecision = r; }));
      createAndStartGame();

      const first = wsService.handleNextStep();
      wsService.handleNextStep();
      expect(aiService.getDecision).toHaveBeenCalledTimes(1);

      resolveDecision({ action: 'fold', amount: 0, thinking: 'x' });
      await first;
      expect(wsService.decisionInFlight).toBe(false);
    });

    test('游戏在AI思考期间被重置时应丢弃过期决策', async () => {
      let resolveDecision;
      aiService.getDecision.mockImplementation(() => new Promise(r => { resolveDecision = r; }));
      createAndStartGame();

      const pending = wsService.handleNextStep();
      ws.emit('message', JSON.stringify({ type: 'resetGame' }));
      resolveDecision({ action: 'fold', amount: 0, thinking: 'x' });
      await pending;

      expect(ws.sent.some(m => m.type === 'playerActionProcessed')).toBe(false);
      expect(ws.sent.some(m => m.type === 'error')).toBe(false);
    });

    test('一手牌结束时应推送handResult', async () => {
      aiService.getDecision.mockResolvedValue({ action: 'fold', amount: 0, thinking: 'x' });
      createAndStartGame();

      await wsService.handleNextStep();
      await wsService.handleNextStep();

      const result = ws.sent.find(m => m.type === 'handResult');
      expect(result).toBeDefined();
      expect(result.result.winners).toHaveLength(1);
      expect(result.result.isShowdown).toBe(false);
    });

    test('思考记录只保留最近的100条', () => {
      createAndStartGame();
      const player = wsService.currentGameState.players[0];
      for (let i = 0; i < 120; i++) {
        wsService.addThinkingRecord(player, `t${i}`, 'check');
      }
      const history = wsService.currentGameState.thinkingHistory;
      expect(history).toHaveLength(100);
      expect(history[99].content).toBe('t119');
    });
  });
});
