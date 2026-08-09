/**
 * 集成测试：通过WebSocket协议驱动一整手牌到结束
 * AI服务被mock掉，决策策略为：能check就check，否则call
 */

process.env.LOG_LEVEL = 'silent'; // 测试中静默日志

jest.mock('../../services/ai.service', () => ({
  createAgent: jest.fn().mockResolvedValue({ status: 'ok' }),
  getDecision: jest.fn((playerId, gameState, validActions) => {
    let action = 'fold';
    if (validActions.includes('check')) {
      action = 'check';
    } else if (validActions.includes('call')) {
      action = 'call';
    }
    return Promise.resolve({ action, amount: 0, thinking: '集成测试决策' });
  }),
  deleteAgent: jest.fn().mockResolvedValue(undefined)
}));

const WebSocket = require('ws');
const { createServer } = require('http');
const { WebSocketService } = require('../../services/ws.service');
const aiService = require('../../services/ai.service');

jest.setTimeout(30000);

const INITIAL_CHIPS = 1000;
const TOTAL_CHIPS = INITIAL_CHIPS * 3;

describe('游戏流程集成测试', () => {
  let server;
  let wss;
  let wsService;
  let port;
  let client;

  beforeAll((done) => {
    server = createServer();
    wss = new WebSocket.Server({ server });
    wsService = new WebSocketService();
    wsService.initialize(wss);

    server.listen(0, () => {
      port = server.address().port;
      done();
    });
  });

  afterAll((done) => {
    wss.close();
    server.close(() => done());
  });

  beforeEach((done) => {
    client = new WebSocket(`ws://localhost:${port}`);
    client.on('open', () => done());
    client.on('error', (error) => done(error));
  });

  afterEach((done) => {
    if (client.readyState === WebSocket.OPEN) {
      client.on('close', () => done());
      client.close();
    } else {
      done();
    }
  });

  function send(message) {
    client.send(JSON.stringify(message));
  }

  test('未知消息类型应返回错误', (done) => {
    client.on('message', (data) => {
      const message = JSON.parse(data.toString());
      if (message.type === 'error') {
        try {
          expect(message.message).toContain('未知的消息类型');
          done();
        } catch (error) {
          done(error);
        }
      }
    });

    send({ type: 'bogus' });
  });

  test('完整游戏流程：创建、开始、驱动到结束并保持筹码守恒', (done) => {
    const players = [
      { id: 'player1', name: 'Player 1', chips: INITIAL_CHIPS },
      { id: 'player2', name: 'Player 2', chips: INITIAL_CHIPS },
      { id: 'player3', name: 'Player 3', chips: INITIAL_CHIPS }
    ];

    let gameId;
    let latestState = null;
    let nextStepCount = 0;
    const maxSteps = 60; // 防止死循环
    let finished = false;

    const finish = (error) => {
      if (finished) return;
      finished = true;
      done(error);
    };

    client.on('message', (data) => {
      let message;
      try {
        message = JSON.parse(data.toString());
      } catch (error) {
        return finish(error);
      }

      try {
        switch (message.type) {
          case 'error':
            return finish(new Error(`收到错误消息: ${message.message}`));

          case 'gameCreated':
            gameId = message.gameState.id;
            expect(message.gameState.players).toHaveLength(3);
            expect(message.gameState.deck).toBeUndefined();
            send({ type: 'startGame', gameId });
            break;

          case 'gameStarted':
            latestState = message.gameState;
            expect(latestState.state).toBe('preflop');
            expect(latestState.deck).toBeUndefined();
            // 观战视角：所有玩家手牌可见
            latestState.players.forEach(p => expect(p.cards).toHaveLength(2));
            send({ type: 'nextStep' });
            nextStepCount++;
            break;

          case 'gameStateUpdate':
            latestState = message.gameState;
            expect(latestState.deck).toBeUndefined();
            // 每次状态更新都验证筹码守恒：所有筹码 + 底池 = 总量
            {
              const total = latestState.players.reduce((sum, p) => sum + p.chips, 0) + latestState.pot;
              expect(total).toBe(TOTAL_CHIPS);
            }
            break;

          case 'playerActionProcessed':
            // 等待紧随其后的gameStateUpdate已经处理（同步顺序保证latestState最新）
            if (latestState && latestState.state === 'finished') {
              // 一手牌打完：验证结算
              expect(latestState.pot).toBe(0);
              expect(latestState.players.reduce((sum, p) => sum + p.chips, 0)).toBe(TOTAL_CHIPS);
              // 全员check/call到摊牌，底池应有归属（有人赢得盲注以上的筹码）
              expect(latestState.players.some(p => p.chips > INITIAL_CHIPS)).toBe(true);
              expect(aiService.getDecision).toHaveBeenCalled();
              return finish();
            }
            nextStepCount++;
            if (nextStepCount > maxSteps) {
              return finish(new Error('行动次数超限，游戏未能正常结束'));
            }
            setTimeout(() => send({ type: 'nextStep' }), 10);
            break;

          default:
            // 忽略aiThinking/thinkingUpdated/gameStageChanged等消息
            break;
        }
      } catch (error) {
        finish(error);
      }
    });

    send({ type: 'createGame', players });
  });
});
