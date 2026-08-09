const WebSocket = require('ws');
const { WebSocketService } = require('../ws.service');
const { GameController } = require('../../controllers/game.controller');

// Mock WebSocket and GameController
jest.mock('ws');
jest.mock('../../controllers/game.controller');

describe('WebSocketService', () => {
  let wsService;
  let mockServer;
  let mockWs;
  let messageCallback;
  let closeCallback;
  let mockGameController;

  beforeEach(() => {
    // 重置所有mock
    jest.clearAllMocks();

    // 创建mock WebSocket服务器
    mockServer = {
      on: jest.fn()
    };

    // 创建mock WebSocket客户端
    mockWs = {
      on: jest.fn(),
      send: jest.fn(),
      readyState: WebSocket.OPEN
    };

    // 设置WebSocket.Server构造函数mock
    WebSocket.Server = jest.fn(() => mockServer);

    // 设置GameController mock
    mockGameController = {
      getGameState: jest.fn(),
      createGame: jest.fn(),
      startGame: jest.fn(),
      handlePlayerAction: jest.fn()
    };
    GameController.mockImplementation(() => mockGameController);

    // 创建WebSocketService实例
    wsService = new WebSocketService();
    wsService.initialize({});

    // 模拟客户端连接
    const connectionCallback = mockServer.on.mock.calls.find(call => call[0] === 'connection')[1];
    connectionCallback(mockWs);

    // 获取message和close回调函数
    messageCallback = mockWs.on.mock.calls.find(call => call[0] === 'message')[1];
    closeCallback = mockWs.on.mock.calls.find(call => call[0] === 'close')[1];
  });

  test('应正确初始化WebSocket服务器', () => {
    expect(WebSocket.Server).toHaveBeenCalledWith(expect.any(Object));
    expect(mockServer.on).toHaveBeenCalledWith('connection', expect.any(Function));
  });

  test('应正确处理新的客户端连接', () => {
    expect(mockWs.on).toHaveBeenCalledWith('message', expect.any(Function));
    expect(mockWs.on).toHaveBeenCalledWith('close', expect.any(Function));
  });

  test('应正确处理加入游戏消息', async () => {
    const gameState = { 
      id: 'game1', 
      players: [
        { id: 'player1', name: 'Player 1' },
        { id: 'player2', name: 'Player 2' }
      ] 
    };
    mockGameController.getGameState.mockResolvedValue(gameState);

    await messageCallback(JSON.stringify({
      type: 'join',
      payload: { playerId: 'player1', gameId: 'game1' }
    }));

    expect(wsService.clients.get('player1')).toBe(mockWs);
    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"gameState"')
    );
  });

  test('应正确处理加入游戏失败', async () => {
    mockGameController.getGameState.mockRejectedValue(new Error('Game not found'));

    await messageCallback(JSON.stringify({
      type: 'join',
      payload: { playerId: 'player1', gameId: 'invalid-game' }
    }));

    expect(wsService.clients.get('player1')).toBeUndefined();
    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"error"')
    );
  });

  test('应正确处理玩家不在游戏中的情况', async () => {
    const gameState = { 
      id: 'game1', 
      players: [
        { id: 'player2', name: 'Player 2' },
        { id: 'player3', name: 'Player 3' }
      ] 
    };
    mockGameController.getGameState.mockResolvedValue(gameState);

    await messageCallback(JSON.stringify({
      type: 'join',
      payload: { playerId: 'player1', gameId: 'game1' }
    }));

    expect(wsService.clients.get('player1')).toBeUndefined();
    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"error"')
    );
    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('Player not in game')
    );
  });

  test('应正确处理创建游戏消息', async () => {
    const newGame = { id: 'game1', players: [{ id: 'player1' }] };
    mockGameController.createGame.mockResolvedValue(newGame);

    await messageCallback(JSON.stringify({
      type: 'create',
      payload: { players: [{ id: 'player1' }] }
    }));

    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"gameCreated"')
    );
  });

  test('应正确处理开始游戏消息', async () => {
    const gameState = { id: 'game1', players: [{ id: 'player1' }] };
    mockGameController.startGame.mockResolvedValue(gameState);

    wsService.clients.set('player1', mockWs);
    await messageCallback(JSON.stringify({
      type: 'start',
      payload: { gameId: 'game1' }
    }));

    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"gameState"')
    );
  });

  test('应正确处理玩家行动消息', async () => {
    const gameState = { id: 'game1', players: [{ id: 'player1' }] };
    mockGameController.handlePlayerAction.mockResolvedValue(gameState);

    wsService.clients.set('player1', mockWs);
    await messageCallback(JSON.stringify({
      type: 'action',
      payload: {
        gameId: 'game1',
        playerId: 'player1',
        action: 'call',
        amount: 10
      }
    }));

    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"gameState"')
    );
  });

  test('应正确处理无效的消息类型', async () => {
    await messageCallback(JSON.stringify({
      type: 'invalid',
      payload: {}
    }));

    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"error"')
    );
  });

  test('应正确处理无效的JSON消息', async () => {
    await messageCallback('invalid json');

    expect(mockWs.send).toHaveBeenCalledWith(
      expect.stringContaining('"type":"error"')
    );
  });

  test('应正确处理客户端断开连接', () => {
    wsService.clients.set('player1', mockWs);
    closeCallback();
    expect(wsService.clients.has('player1')).toBe(false);
  });

  test('应正确创建玩家视图', () => {
    const game = {
      id: 'game1',
      players: [
        { id: 'player1', cards: ['AS', 'KS'] },
        { id: 'player2', cards: ['AH', 'KH'] }
      ]
    };

    const playerView = wsService.createPlayerView(game, 'player1');

    expect(playerView.players[0].cards).toEqual(['AS', 'KS']);
    expect(playerView.players[1].cards).toBeNull();
  });
}); 