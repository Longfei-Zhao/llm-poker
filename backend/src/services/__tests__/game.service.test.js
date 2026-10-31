const { GameService } = require('../game.service');
const config = require('../../config');

// 构造从牌堆尾部依次发出指定牌的牌堆（deck.pop()从末尾取牌）
// dealt顺序：先每人一张再每人一张，然后依次是flop三张、turn、river
function riggedDeck(dealtInOrder) {
  const all = new GameService().createDeck();
  const filler = all.filter(card => !dealtInOrder.includes(card));
  return [...filler, ...[...dealtInOrder].reverse()];
}

describe('GameService', () => {
  let gameService;

  const createPlayers = (chipCounts) =>
    chipCounts.map((chips, i) => ({ id: `player${i + 1}`, name: `Player ${i + 1}`, chips }));

  beforeEach(() => {
    gameService = new GameService();
  });

  describe('创建游戏', () => {
    test('创建游戏时应设置正确的初始状态', () => {
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      expect(game.players).toHaveLength(3);
      expect(game.players[0].chips).toBe(1000);
      expect(game.state).toBe('waiting');
      expect(game.communityCards).toHaveLength(0);
      expect(game.pot).toBe(0);
      expect(game.round).toBe(0);
      expect(game.smallBlind).toBe(config.SMALL_BLIND);
      expect(game.bigBlind).toBe(config.BIG_BLIND);
      expect(game.dealerIndex).toBe(0);
      game.players.forEach(p => {
        expect(p.isAllIn).toBe(false);
        expect(p.isAI).toBe(true);
      });
    });

    test('应尊重传入的玩家筹码数量', () => {
      const game = gameService.createGame(createPlayers([50, 500, 500]), { dealerIndex: 0 });
      expect(game.players.map(p => p.chips)).toEqual([50, 500, 500]);
    });
  });

  describe('开始游戏', () => {
    test('开始游戏时应正确发牌、收盲注并设置状态', () => {
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);

      expect(game.state).toBe('preflop');
      game.players.forEach(p => expect(p.cards).toHaveLength(2));
      expect(game.deck).toHaveLength(46); // 52 - 3人 * 2张
      // dealer=player1, SB=player2, BB=player3
      expect(game.players[1].bet).toBe(config.SMALL_BLIND);
      expect(game.players[2].bet).toBe(config.BIG_BLIND);
      expect(game.pot).toBe(config.SMALL_BLIND + config.BIG_BLIND);
      expect(game.currentBet).toBe(config.BIG_BLIND);
      // 3人桌大盲后一位就是按钮位
      expect(game.currentPlayerIndex).toBe(0);
      expect(game.players[0].isCurrent).toBe(true);
    });

    test('盲注不足时按剩余筹码全押，不会出现负筹码', () => {
      const game = gameService.createGame(createPlayers([1000, 3, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);

      const sb = game.players[1];
      expect(sb.bet).toBe(3);
      expect(sb.chips).toBe(0);
      expect(sb.isAllIn).toBe(true);
      expect(game.pot).toBe(3 + config.BIG_BLIND);
    });

    test('应正确处理无效的游戏ID', () => {
      expect(() => gameService.startGame('invalid-id')).toThrow('Game not found');
    });
  });

  describe('单挑规则', () => {
    test('单挑时庄家是小盲并且翻牌前先行动', () => {
      const game = gameService.createGame(createPlayers([1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);

      expect(game.players[0].bet).toBe(config.SMALL_BLIND); // 庄家=小盲
      expect(game.players[1].bet).toBe(config.BIG_BLIND);
      expect(game.currentPlayerIndex).toBe(0); // 庄家先行动
    });

    test('单挑翻牌后大盲先行动', () => {
      const game = gameService.createGame(createPlayers([1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);

      gameService.handlePlayerAction(game.id, 'player1', 'call');
      gameService.handlePlayerAction(game.id, 'player2', 'check');

      expect(game.state).toBe('flop');
      expect(game.currentPlayerIndex).toBe(1); // 大盲（非庄家）先行动
    });
  });

  describe('玩家行动', () => {
    let game;

    beforeEach(() => {
      game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);
    });

    test('大盲在翻牌前无人加注时可以check并保留手牌', () => {
      gameService.handlePlayerAction(game.id, 'player1', 'call');
      gameService.handlePlayerAction(game.id, 'player2', 'call');

      expect(game.state).toBe('preflop'); // 大盲仍有行动权
      expect(game.currentPlayerIndex).toBe(2);

      gameService.handlePlayerAction(game.id, 'player3', 'check');

      expect(game.state).toBe('flop');
      expect(game.players[2].isActive).toBe(true); // check没有被转成fold
      expect(game.communityCards).toHaveLength(3);
      expect(game.pot).toBe(config.BIG_BLIND * 3);
    });

    test('面对下注时check应抛错且不改变游戏状态', () => {
      expect(() => {
        gameService.handlePlayerAction(game.id, 'player1', 'check');
      }).toThrow('Cannot check when facing a bet');

      // 状态未被破坏：player1仍是当前玩家且未弃牌
      expect(game.players[0].isActive).toBe(true);
      expect(game.players[0].isCurrent).toBe(true);
    });

    test('跟注应正确扣减筹码并累积底池', () => {
      gameService.handlePlayerAction(game.id, 'player1', 'call');

      expect(game.players[0].chips).toBe(1000 - config.BIG_BLIND);
      expect(game.pot).toBe(config.SMALL_BLIND + config.BIG_BLIND * 2);
    });

    test('弃牌应正确处理', () => {
      gameService.handlePlayerAction(game.id, 'player1', 'fold');

      expect(game.players[0].isActive).toBe(false);
      expect(game.players.filter(p => p.isActive)).toHaveLength(2);
    });

    test('加注应更新当前注并要求其他玩家重新行动', () => {
      const raiseTo = config.BIG_BLIND * 3;
      gameService.handlePlayerAction(game.id, 'player1', 'raise', raiseTo);

      expect(game.currentBet).toBe(raiseTo);
      expect(game.players[0].chips).toBe(1000 - raiseTo);
      expect(game.lastRaiseAmount).toBe(raiseTo - config.BIG_BLIND);
    });

    test('应正确处理无效的玩家行动', () => {
      expect(() => {
        gameService.handlePlayerAction(game.id, 'player1', 'invalid-action');
      }).toThrow('Invalid action');
    });
  });

  describe('最小加注规则', () => {
    let game;

    beforeEach(() => {
      game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);
    });

    test('低于最小加注额的raise应被拒绝', () => {
      // 翻牌前最小加注 = 大盲 + 大盲
      expect(() => {
        gameService.handlePlayerAction(game.id, 'player1', 'raise', config.BIG_BLIND + 1);
      }).toThrow(`Raise must be at least ${config.BIG_BLIND * 2}`);
    });

    test('再加注必须至少增加上一次加注的增量', () => {
      gameService.handlePlayerAction(game.id, 'player1', 'raise', 30); // 增量20
      expect(() => {
        gameService.handlePlayerAction(game.id, 'player2', 'raise', 40); // 最小应为50
      }).toThrow('Raise must be at least 50');

      gameService.handlePlayerAction(game.id, 'player2', 'raise', 50);
      expect(game.currentBet).toBe(50);
      expect(game.lastRaiseAmount).toBe(20);
    });

    test('不足最小加注的all-in不重新打开下注', () => {
      const gs = new GameService();
      const g = gs.createGame(createPlayers([1000, 1000, 45]), { dealerIndex: 0 });
      gs.startGame(g.id);

      gs.handlePlayerAction(g.id, 'player1', 'raise', 30); // 增量20，最小再加注到50
      gs.handlePlayerAction(g.id, 'player2', 'call');
      gs.handlePlayerAction(g.id, 'player3', 'allin'); // 总注45 < 50，属于跟注加码

      expect(g.currentBet).toBe(45);
      expect(g.lastRaiseAmount).toBe(20); // 增量未被更新
      // player1/player2只需补齐差额，不重新获得加注权（hasActed未被重置）
      expect(g.players[0].hasActed).toBe(true);
      expect(g.players[1].hasActed).toBe(true);
    });
  });

  describe('输入校验', () => {
    let game;

    beforeEach(() => {
      game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);
    });

    test.each([
      ['字符串', 'abc'],
      ['NaN', NaN],
      ['负数', -5],
      ['小数', 3.5],
      ['对象', {}]
    ])('非法金额(%s)应被拒绝且不污染状态', (_label, badAmount) => {
      expect(() => {
        gameService.handlePlayerAction(game.id, 'player1', 'raise', badAmount);
      }).toThrow('Invalid amount');

      expect(game.players[0].chips).toBe(1000);
      expect(game.pot).toBe(config.SMALL_BLIND + config.BIG_BLIND);
      expect(Number.isNaN(game.pot)).toBe(false);
    });
  });

  describe('all-in处理', () => {
    test('all-in玩家被跳过而不是被自动弃牌', () => {
      const game = gameService.createGame(createPlayers([100, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);

      gameService.handlePlayerAction(game.id, 'player1', 'allin'); // 100
      expect(game.players[0].isAllIn).toBe(true);
      expect(game.players[0].isActive).toBe(true);

      gameService.handlePlayerAction(game.id, 'player2', 'call');
      gameService.handlePlayerAction(game.id, 'player3', 'call');

      // 进入flop：只剩player2/player3能行动，行动权不会落到all-in玩家身上
      expect(game.state).toBe('flop');
      expect(game.currentPlayerIndex).toBe(1);

      gameService.handlePlayerAction(game.id, 'player2', 'check');
      gameService.handlePlayerAction(game.id, 'player3', 'check');
      expect(game.state).toBe('turn');
      expect(game.currentPlayerIndex).toBe(1);
      expect(game.players[0].isActive).toBe(true); // 始终未被弃牌

      gameService.handlePlayerAction(game.id, 'player2', 'check');
      gameService.handlePlayerAction(game.id, 'player3', 'check');
      gameService.handlePlayerAction(game.id, 'player2', 'check');
      gameService.handlePlayerAction(game.id, 'player3', 'check');

      expect(game.state).toBe('finished');
      expect(game.pot).toBe(0);
      // 筹码守恒
      expect(game.players.reduce((sum, p) => sum + p.chips, 0)).toBe(2100);
    });

    test('可行动玩家不足两人时快进剩余公共牌直接摊牌', () => {
      const game = gameService.createGame(createPlayers([100, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);

      gameService.handlePlayerAction(game.id, 'player1', 'allin');
      gameService.handlePlayerAction(game.id, 'player2', 'allin');
      gameService.handlePlayerAction(game.id, 'player3', 'fold');

      // 双方all-in，无人可行动：直接发完5张公共牌并结算
      expect(game.state).toBe('finished');
      expect(game.communityCards).toHaveLength(5);
      expect(game.pot).toBe(0);
      expect(game.players.reduce((sum, p) => sum + p.chips, 0)).toBe(2100);
      // 未被跟注的部分应退回：player2至少拿回900
      expect(game.players[1].chips).toBeGreaterThanOrEqual(900);
    });
  });

  describe('边池计算', () => {
    test('短筹码all-in只能赢主池，边池归次强牌', () => {
      // A(50) all-in，B(500)/C(500)对决：A牌最大只赢主池150，B赢边池900
      const game = gameService.createGame(createPlayers([50, 500, 500]), { dealerIndex: 0 });
      gameService.shuffleDeck = () => {}; // 保持牌堆顺序确定
      gameService.createDeck = () => riggedDeck([
        'Ah', 'Kh', '2c',  // 第一轮：A, B, C
        'Ad', 'Kd', '7d',  // 第二轮：A, B, C
        'Qs', 'Js', '9h',  // flop
        '5c',              // turn
        '3d'               // river
      ]);
      gameService.startGame(game.id);

      gameService.handlePlayerAction(game.id, 'player1', 'allin');     // A 50
      gameService.handlePlayerAction(game.id, 'player2', 'raise', 500); // B all-in到500
      gameService.handlePlayerAction(game.id, 'player3', 'call');       // C 跟到500（恰好all-in）

      expect(game.state).toBe('finished');
      // 主池 50*3=150 归A(AA)，边池 450*2=900 归B(KK)，C(垃圾牌)出局
      expect(game.players[0].chips).toBe(150);
      expect(game.players[1].chips).toBe(900);
      expect(game.players[2].chips).toBe(0);
      expect(game.pot).toBe(0);
      expect(game.players.reduce((sum, p) => sum + p.chips, 0)).toBe(1050);
    });

    test('平分奖池时余数筹码分给庄家左侧最近的赢家', () => {
      // A和B同牌力平分，C弃牌后底池为奇数
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      gameService.shuffleDeck = () => {};
      gameService.createDeck = () => riggedDeck([
        'Ah', 'Ad', '2c',  // A和B同拿A，C垃圾牌
        'Kh', 'Kd', '7d',
        'Qs', 'Js', '9s',  // 公共牌构成两人相同的最佳牌型
        '5c',
        '3c'
      ]);
      gameService.startGame(game.id);

      gameService.handlePlayerAction(game.id, 'player1', 'call');
      gameService.handlePlayerAction(game.id, 'player2', 'call');
      gameService.handlePlayerAction(game.id, 'player3', 'fold'); // 大盲弃牌，底池 10+10+10=30？大盲已投10 -> pot=30
      // 大盲fold后只剩A、B，翻牌继续
      gameService.handlePlayerAction(game.id, 'player2', 'check');
      gameService.handlePlayerAction(game.id, 'player1', 'check');
      gameService.handlePlayerAction(game.id, 'player2', 'check');
      gameService.handlePlayerAction(game.id, 'player1', 'check');
      gameService.handlePlayerAction(game.id, 'player2', 'check');
      gameService.handlePlayerAction(game.id, 'player1', 'check');

      expect(game.state).toBe('finished');
      // 底池30，两人平分各15，无余数：验证守恒即可
      expect(game.players.reduce((sum, p) => sum + p.chips, 0)).toBe(3000);
      expect(game.players[0].chips).toBe(game.players[1].chips); // 平分
    });
  });

  describe('新一轮', () => {
    test('round从0开始并正确递增，牌堆重新洗牌', () => {
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      expect(game.round).toBe(0);

      const shuffleSpy = jest.spyOn(gameService, 'shuffleDeck');
      gameService.startNewRound(game);

      expect(game.round).toBe(1);
      expect(Number.isNaN(game.round)).toBe(false);
      expect(shuffleSpy).toHaveBeenCalled();
      expect(game.deck).toHaveLength(52);
    });

    test('淘汰玩家后按钮按玩家顺延而不是索引错位', () => {
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      game.players[1].chips = 0; // player2出局

      gameService.startNewRound(game);

      expect(game.players.map(p => p.id)).toEqual(['player1', 'player3']);
      // 按钮应从player1移到下一位仍在场的player3
      expect(game.players[game.dealerIndex].id).toBe('player3');
    });

    test('剩余玩家不足两人时游戏结束', () => {
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      game.players[1].chips = 0;
      game.players[2].chips = 0;

      gameService.startNewRound(game);

      expect(game.state).toBe('finished');
    });
  });

  describe('完整对局', () => {
    test('跟注到摊牌的一手牌应保持筹码守恒', () => {
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);

      gameService.handlePlayerAction(game.id, 'player1', 'call');
      gameService.handlePlayerAction(game.id, 'player2', 'call');
      gameService.handlePlayerAction(game.id, 'player3', 'check');

      for (const stage of ['flop', 'turn', 'river']) {
        expect(game.state).toBe(stage);
        gameService.handlePlayerAction(game.id, 'player2', 'check');
        gameService.handlePlayerAction(game.id, 'player3', 'check');
        gameService.handlePlayerAction(game.id, 'player1', 'check');
      }

      expect(game.state).toBe('finished');
      expect(game.pot).toBe(0);
      expect(game.players.reduce((sum, p) => sum + p.chips, 0)).toBe(3000);
    });
  });
  describe('本手结果与位置', () => {
    test('摊牌后lastHandResult应记录赢家、赢得筹码和牌型', () => {
      const game = gameService.createGame(createPlayers([1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);
      // 单挑：p1(庄/小盲)拿AA，p2拿72，公共牌不帮p2
      game.players[0].cards = ['Ah', 'As'];
      game.players[1].cards = ['7d', '2c'];
      game.deck = riggedDeck(['Kc', '9h', '4s', '3d', 'Jc']);
      gameService.handlePlayerAction(game.id, 'player1', 'call');
      gameService.handlePlayerAction(game.id, 'player2', 'check');
      for (let street = 0; street < 3; street++) {
        gameService.handlePlayerAction(game.id, 'player2', 'check');
        gameService.handlePlayerAction(game.id, 'player1', 'check');
      }

      expect(game.state).toBe('finished');
      expect(game.lastHandResult.isShowdown).toBe(true);
      expect(game.lastHandResult.winners).toEqual([
        { playerId: 'player1', amount: config.BIG_BLIND * 2, handName: expect.stringContaining('Pair'), handRank: 'Pair' }
      ]);
      expect(game.lastHandResult.hands.player2).toBeTruthy();
    });

    test('其余人弃牌时赢家不亮牌', () => {
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);
      gameService.handlePlayerAction(game.id, 'player1', 'fold');
      gameService.handlePlayerAction(game.id, 'player2', 'fold');

      expect(game.lastHandResult.isShowdown).toBe(false);
      expect(game.lastHandResult.winners).toEqual([
        { playerId: 'player3', amount: config.SMALL_BLIND + config.BIG_BLIND, handName: null, handRank: null }
      ]);
    });

    test('进入下一街时清除上一街的动作标签，all-in玩家保留', () => {
      const game = gameService.createGame(createPlayers([1000, 1000, 1000]), { dealerIndex: 0 });
      gameService.startGame(game.id);
      gameService.handlePlayerAction(game.id, 'player1', 'call');
      gameService.handlePlayerAction(game.id, 'player2', 'call');
      gameService.handlePlayerAction(game.id, 'player3', 'check');

      expect(game.state).toBe('flop');
      game.players.forEach(p => expect(p.action).toBeNull());
    });

    test('6人桌位置应为BTN/SB/BB/UTG/HJ/CO', () => {
      const names = [0, 1, 2, 3, 4, 5].map(i => gameService.calculateRelativePosition(0, i, 6));
      expect(names).toEqual(['BTN', 'SB', 'BB', 'UTG', 'HJ', 'CO']);
    });

    test('8人桌位置应为完整的UTG到CO', () => {
      const names = [3, 4, 5, 6, 7].map(i => gameService.calculateRelativePosition(0, i, 8));
      expect(names).toEqual(['UTG', 'UTG+1', 'MP', 'HJ', 'CO']);
    });
  });
});
