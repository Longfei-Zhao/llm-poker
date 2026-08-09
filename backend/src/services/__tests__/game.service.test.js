const { GameService } = require('../game.service');

describe('GameService', () => {
  let gameService;
  let gameId;
  let players;

  beforeEach(() => {
    gameService = new GameService();
    players = [
      { id: 'player1', name: 'Player 1', chips: 1000 },
      { id: 'player2', name: 'Player 2', chips: 1000 },
      { id: 'player3', name: 'Player 3', chips: 1000 }
    ];
    const game = gameService.createGame(players);
    gameId = game.id;
  });

  test('创建游戏时应设置正确的初始状态', () => {
    const game = gameService.games.get(gameId);
    expect(game).toBeDefined();
    expect(game.players.length).toBe(3);
    expect(game.players[0].chips).toBe(1000);
    expect(game.state).toBe('waiting');
    expect(game.deck.length).toBe(52);
    expect(game.communityCards).toHaveLength(0);
    expect(game.pot).toBe(0);
  });

  test('开始游戏时应正确发牌和设置状态', () => {
    const game = gameService.startGame(gameId);
    expect(game.state).toBe('preflop');
    expect(game.players[0].cards).toHaveLength(2);
    expect(game.players[1].cards).toHaveLength(2);
    expect(game.players[2].cards).toHaveLength(2);
    expect(game.deck.length).toBe(46); // 52 - (3 players * 2 cards)
    expect(game.pot).toBe(3); // 小盲1 + 大盲2
  });

  test('玩家行动应正确更新游戏状态', () => {
    const game = gameService.startGame(gameId);
    const initialChips = game.players[0].chips;
    
    // 玩家1下注10筹码
    const updatedGame = gameService.handlePlayerAction(gameId, game.players[0].id, 'raise', 10);
    
    expect(updatedGame.players[0].chips).toBe(initialChips - 10);
    expect(updatedGame.pot).toBe(13); // 小盲1 + 大盲2 + 加注10
    expect(updatedGame.currentBet).toBe(10);
  });

  test('游戏状态应正确转换', () => {
    const game = gameService.startGame(gameId);
    
    // 所有玩家跟注
    for (let i = 0; i < 3; i++) {
      const player = game.players[i];
      if (player.isCurrent) {
        gameService.handlePlayerAction(gameId, player.id, 'call');
      }
    }
    
    const updatedGame = gameService.games.get(gameId);
    expect(updatedGame.state).toBe('flop');
    expect(updatedGame.communityCards).toHaveLength(3);
  });

  test('弃牌应正确处理', () => {
    const game = gameService.startGame(gameId);
    
    gameService.handlePlayerAction(gameId, game.players[0].id, 'fold');
    
    const updatedGame = gameService.games.get(gameId);
    expect(updatedGame.players[0].isActive).toBe(false);
    expect(updatedGame.players.filter(p => p.isActive).length).toBe(2);
  });

  test('应正确处理无效的游戏ID', () => {
    expect(() => {
      gameService.startGame('invalid-id');
    }).toThrow('Game not found');
  });

  test('应正确处理无效的玩家行动', () => {
    const game = gameService.startGame(gameId);
    
    expect(() => {
      gameService.handlePlayerAction(gameId, game.players[0].id, 'invalid-action');
    }).toThrow('Invalid action');
  });

  test('应正确处理玩家跟注', () => {
    const game = gameService.startGame(gameId);
    
    // 第一个玩家加注10
    gameService.handlePlayerAction(gameId, game.players[0].id, 'raise', 10);
    
    // 第二个玩家跟注
    const updatedGame = gameService.handlePlayerAction(gameId, game.players[1].id, 'call');
    
    expect(updatedGame.players[1].chips).toBe(990); // 1000 - 10
    expect(updatedGame.pot).toBe(22); // 小盲1 + 大盲2 + 加注10 + 跟注9
  });

  test('应正确处理玩家加注', () => {
    const game = gameService.startGame(gameId);
    
    // 第一个玩家加注10
    gameService.handlePlayerAction(gameId, game.players[0].id, 'raise', 10);
    
    // 第二个玩家加注到20
    const updatedGame = gameService.handlePlayerAction(gameId, game.players[1].id, 'raise', 20);
    
    expect(updatedGame.players[1].chips).toBe(980); // 1000 - 20
    expect(updatedGame.pot).toBe(32); // 小盲1 + 大盲2 + 加注10 + 加注19
    expect(updatedGame.currentBet).toBe(20);
  });
}); 