const { Hand } = require('pokersolver');
const { v4: uuidv4 } = require('uuid');
const config = require('../config');
const logger = require('../utils/logger');

class GameService {
  constructor() {
    this.games = new Map(); // 存储游戏状态
  }

  // 创建新游戏
  createGame(players, options = {}) {
    const gameId = uuidv4();

    // 创建新游戏状态
    const gameState = {
      id: gameId,
      players: players.map((player, index) => ({
        ...player,
        position: Number.isInteger(player.position) && player.position > 0 ? player.position : index + 1,
        isActive: true,
        isCurrent: false,
        isAllIn: false,
        isAI: true, // 本项目中所有玩家都是AI
        cards: [],
        bet: 0,
        chips: Number.isInteger(player.chips) && player.chips > 0 ? player.chips : 1000, // 初始筹码
        totalContribution: 0, // 本手牌累计投入（用于边池计算）
        hasActed: false,
        action: null
      })),
      state: 'waiting', // 游戏状态: waiting, preflop, flop, turn, river, showdown, finished
      pot: 0,
      smallBlind: config.SMALL_BLIND,
      bigBlind: config.BIG_BLIND,
      currentBet: 0,
      currentPlayerIndex: 0,
      // 支持注入dealerIndex以便测试确定性
      dealerIndex: players.length === 0
        ? 0
        : (Number.isInteger(options.dealerIndex)
          ? ((options.dealerIndex % players.length) + players.length) % players.length
          : Math.floor(Math.random() * players.length)),
      lastRaiseIndex: -1,
      lastRaiseAmount: 0, // 记录最后一次加注的增量
      round: 0,
      communityCards: [],
      deck: [],
      actionHistory: []
    };

    // 保存游戏状态
    this.games.set(gameId, gameState);
    return gameState;
  }

  // 开始游戏
  startGame(gameId) {
    const game = this.games.get(gameId);
    if (!game) throw new Error('Game not found');
    // 允许从waiting或finished状态开始游戏
    if (game.state !== 'waiting' && game.state !== 'finished')
      throw new Error('Game already in progress');
    if (game.players.length < 2) throw new Error('Not enough players');

    // 重置游戏状态
    game.deck = this.createDeck();
    this.shuffleDeck(game.deck);
    game.communityCards = [];
    game.pot = 0;
    game.currentBet = 0;
    game.lastRaiseIndex = -1;
    game.lastRaiseAmount = 0;
    game.actionHistory = []; // 重置行动历史
    game.lastHandResult = null;

    // 重置玩家状态
    game.players.forEach(player => {
      player.cards = [];
      player.isActive = true;
      player.isCurrent = false;
      player.isAllIn = false;
      player.bet = 0;
      player.totalContribution = 0;
      player.hasActed = false;
      player.action = null;
    });

    // 发手牌
    for (let i = 0; i < 2; i++) {
      for (let player of game.players) {
        player.cards.push(game.deck.pop());
      }
    }
    logger.debug('发牌完成:', game.players.map(p => ({ id: p.id, cards: p.cards })));

    // 设置初始状态
    game.state = 'preflop';

    // 收取盲注：单挑时庄家是小盲，多人时庄家左侧为小盲
    const headsUp = game.players.length === 2;
    const sbIndex = headsUp ? game.dealerIndex : (game.dealerIndex + 1) % game.players.length;
    const bbIndex = headsUp ? (game.dealerIndex + 1) % game.players.length : (game.dealerIndex + 2) % game.players.length;

    const sbPaid = this.postBlind(game, sbIndex, game.smallBlind);
    const bbPaid = this.postBlind(game, bbIndex, game.bigBlind);
    game.currentBet = game.bigBlind;

    // 记录盲注操作到历史
    game.actionHistory.push({
      stage: 'preflop',
      actions: [
        {
          playerId: game.players[sbIndex].id,
          playerPosition: this.calculateRelativePosition(game.dealerIndex, sbIndex, game.players.length),
          action: 'smallBlind',
          amount: sbPaid,
          isAllIn: game.players[sbIndex].isAllIn,
          timestamp: new Date().toISOString()
        },
        {
          playerId: game.players[bbIndex].id,
          playerPosition: this.calculateRelativePosition(game.dealerIndex, bbIndex, game.players.length),
          action: 'bigBlind',
          amount: bbPaid,
          isAllIn: game.players[bbIndex].isAllIn,
          timestamp: new Date().toISOString()
        }
      ]
    });

    // 设置第一个行动的玩家：单挑为庄家（小盲），多人为大盲后一位
    const firstToAct = headsUp ? game.dealerIndex : (game.dealerIndex + 3) % game.players.length;
    const startIdx = this.findActionableFrom(game, firstToAct);
    if (startIdx === -1) {
      // 盲注已让所有玩家all-in，无人可行动，直接快进到摊牌
      this.fastForwardToShowdown(game);
      return game;
    }
    game.currentPlayerIndex = startIdx;
    game.players[startIdx].isCurrent = true;

    return game;
  }

  // 收取盲注：不足时按剩余筹码全押
  postBlind(game, index, blindAmount) {
    const player = game.players[index];
    const paid = Math.min(blindAmount, player.chips);
    player.chips -= paid;
    player.bet = paid;
    player.totalContribution += paid;
    game.pot += paid;
    if (player.chips === 0) {
      player.isAllIn = true;
    }
    return paid;
  }

  // 处理玩家行动
  handlePlayerAction(gameId, playerId, action, amount = 0) {
    const game = this.games.get(gameId);
    if (!game) throw new Error('Game not found');

    // 输入校验：金额必须是非负整数，防止NaN污染筹码和底池
    if (amount === undefined || amount === null) amount = 0;
    if (typeof amount !== 'number' || !Number.isInteger(amount) || amount < 0) {
      throw new Error('Invalid amount');
    }

    const playerIndex = game.players.findIndex(p => p.id === playerId);
    if (playerIndex === -1) throw new Error('Player not found');

    const player = game.players[playerIndex];
    if (!player.isCurrent) throw new Error('Not your turn');

    // 先完成全部校验再修改状态，非法动作直接抛错（由WS层决定替代动作）
    switch (action) {
      case 'fold':
        break;
      case 'check':
        // 只有下注已对齐时才能check
        if (player.bet < game.currentBet) throw new Error('Cannot check when facing a bet');
        break;
      case 'call': {
        const toCall = game.currentBet - player.bet;
        if (toCall > player.chips) throw new Error('Not enough chips');
        break;
      }
      case 'raise': {
        // 最小加注：当前注 + max(上次加注增量, 大盲)
        const minRaiseTo = game.currentBet + Math.max(game.lastRaiseAmount, game.bigBlind);
        if (amount < minRaiseTo) throw new Error(`Raise must be at least ${minRaiseTo}`);
        if (amount > player.chips + player.bet) throw new Error('Not enough chips');
        break;
      }
      case 'allin':
        if (player.chips <= 0) throw new Error('No chips to go all-in');
        break;
      default:
        throw new Error('Invalid action');
    }

    // 重置当前玩家状态
    player.isCurrent = false;

    switch (action) {
      case 'fold':
        player.isActive = false;
        break;
      case 'check':
        break;
      case 'call': {
        const callAmount = Math.max(game.currentBet - player.bet, 0);
        player.chips -= callAmount;
        player.bet += callAmount;
        player.totalContribution += callAmount;
        game.pot += callAmount;
        break;
      }
      case 'raise': {
        const addAmount = amount - player.bet;
        player.chips -= addAmount;
        player.bet = amount;
        player.totalContribution += addAmount;
        game.pot += addAmount;
        // 记录本次加注增量并重新打开下注
        game.lastRaiseAmount = amount - game.currentBet;
        game.currentBet = amount;
        game.lastRaiseIndex = playerIndex;
        game.players.forEach(p => {
          if (p.id !== player.id && p.isActive && !p.isAllIn) {
            p.hasActed = false;
          }
        });
        break;
      }
      case 'allin': {
        const allinAmount = player.chips;
        player.chips = 0;
        player.bet += allinAmount;
        player.totalContribution += allinAmount;
        game.pot += allinAmount;
        if (player.bet > game.currentBet) {
          const increment = player.bet - game.currentBet;
          // 不足最小加注增量的all-in视为“跟注加码”，不更新加注增量、不重新打开下注
          const isFullRaise = increment >= Math.max(game.lastRaiseAmount, game.bigBlind);
          game.currentBet = player.bet;
          game.lastRaiseIndex = playerIndex;
          if (isFullRaise) {
            game.lastRaiseAmount = increment;
            game.players.forEach(p => {
              if (p.id !== player.id && p.isActive && !p.isAllIn) {
                p.hasActed = false;
              }
            });
          }
        }
        break;
      }
    }

    player.hasActed = true;
    // 筹码打空即标记all-in
    if (player.isActive && player.chips === 0 && (action === 'call' || action === 'raise' || action === 'allin')) {
      player.isAllIn = true;
    }

    // 记录行动到历史
    if (!game.actionHistory.length || game.actionHistory[game.actionHistory.length - 1].stage !== game.state) {
      game.actionHistory.push({
        stage: game.state,
        actions: []
      });
    }

    const currentStageHistory = game.actionHistory[game.actionHistory.length - 1];
    currentStageHistory.actions.push({
      playerId,
      playerPosition: this.calculateRelativePosition(game.dealerIndex, playerIndex, game.players.length),
      action,
      amount: (action === 'raise' || action === 'call' || action === 'allin') ? player.bet : 0,
      isAllIn: player.isAllIn,
      timestamp: new Date().toISOString()
    });

    // 记录玩家的最后行动
    player.action = action;

    // 检查是否只剩一个玩家
    const activePlayers = game.players.filter(p => p.isActive);
    if (activePlayers.length === 1) {
      game.state = 'showdown';
      this.handleShowdown(game);
      return game;
    }

    // 检查当前回合是否结束
    if (this.isRoundComplete(game)) {
      this.moveToNextRound(game);
    } else {
      // 移动到下一个玩家
      this.moveToNextPlayer(game);
    }

    return game;
  }

  // 计算玩家当前可选的动作和加注范围（加注金额都是本轮总下注额，不是增量）
  getLegalActions(game, player) {
    const validActions = ['fold'];
    const toCall = game.currentBet - player.bet;

    // 下注已对齐（含大盲preflop无人加注的情况）时可以check
    if (toCall <= 0) validActions.push('check');
    if (player.chips > 0) validActions.push('allin');
    if (toCall > 0 && toCall <= player.chips) validActions.push('call');

    // 最小加注：当前注 + max(上次加注增量, 大盲)
    const minRaiseTo = game.currentBet === 0
      ? game.bigBlind
      : game.currentBet + Math.max(game.lastRaiseAmount || 0, game.bigBlind);
    const playerTotal = player.chips + player.bet;
    if (player.chips > 0 && playerTotal >= minRaiseTo && minRaiseTo > game.currentBet) {
      validActions.push('raise');
    }

    return {
      validActions,
      minBet: Math.min(minRaiseTo, playerTotal),
      maxBet: playerTotal
    };
  }

  // 获取游戏状态
  getGameState(gameId) {
    const game = this.games.get(gameId);
    if (!game) throw new Error('Game not found');
    return game;
  }

  // 创建一副扑克牌
  createDeck() {
    const suits = ['h', 'd', 'c', 's'];
    const values = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];
    const deck = [];
    for (let suit of suits) {
      for (let value of values) {
        deck.push(value + suit);
      }
    }
    return deck;
  }

  // 洗牌
  shuffleDeck(deck) {
    for (let i = deck.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }
  }

  // 从startIndex起（含自身）查找第一个还能行动的玩家（未弃牌且未all-in）
  findActionableFrom(game, startIndex) {
    const n = game.players.length;
    for (let offset = 0; offset < n; offset++) {
      const idx = (startIndex + offset) % n;
      const p = game.players[idx];
      if (p.isActive && !p.isAllIn) return idx;
    }
    return -1;
  }

  // 统计还能行动的玩家数
  countActionable(game) {
    return game.players.filter(p => p.isActive && !p.isAllIn).length;
  }

  // 移动到下一个玩家（跳过已弃牌和all-in的玩家）
  moveToNextPlayer(game) {
    const next = this.findActionableFrom(game, (game.currentPlayerIndex + 1) % game.players.length);
    if (next === -1) {
      // 无人可行动（理论上isRoundComplete已覆盖），兜底推进回合
      this.moveToNextRound(game);
      return;
    }
    game.currentPlayerIndex = next;
    game.players[next].isCurrent = true;
  }

  // 检查当前回合是否结束
  isRoundComplete(game) {
    // all-in玩家无需再行动；其余活跃玩家必须已行动且下注对齐
    for (const player of game.players) {
      if (!player.isActive || player.isAllIn) continue;
      if (!player.hasActed) return false;
      if (player.bet !== game.currentBet) return false;
    }
    return true;
  }

  // 移动到下一个回合
  moveToNextRound(game) {
    // 支持传入gameId或game对象
    if (typeof game === 'string') {
      const gameId = game;
      game = this.games.get(gameId);
      if (!game) {
        logger.error(`游戏不存在: ${gameId}`);
        return null;
      }
    }

    // 安全检查：确保game和players存在
    if (!game || !game.players) {
      logger.error('无效的游戏状态或玩家列表');
      return game;
    }

    // 重置玩家行动状态；上一街的动作标签也清掉，否则新一街会显示"跟注 0"
    game.players.forEach(player => {
      if (player.isActive) {
        player.hasActed = false;
        player.bet = 0;
        if (!player.isAllIn) player.action = null;
      }
    });

    // 重置下注相关状态
    game.currentBet = 0;
    game.lastRaiseIndex = -1;
    game.lastRaiseAmount = 0;

    // 可行动玩家不足两人时无法继续下注：快进剩余公共牌直接摊牌
    if (['preflop', 'flop', 'turn', 'river'].includes(game.state) && this.countActionable(game) < 2) {
      this.fastForwardToShowdown(game);
      return game;
    }

    // 决定下一阶段
    let nextStage;
    switch (game.state) {
      case 'preflop':
        nextStage = 'flop';
        // 发三张公共牌
        for (let i = 0; i < 3; i++) {
          game.communityCards.push(game.deck.pop());
        }
        break;
      case 'flop':
        nextStage = 'turn';
        // 发一张转牌
        game.communityCards.push(game.deck.pop());
        break;
      case 'turn':
        nextStage = 'river';
        // 发一张河牌
        game.communityCards.push(game.deck.pop());
        break;
      case 'river':
        game.state = 'showdown';
        this.handleShowdown(game);
        return game;
      case 'showdown':
        this.startNewRound(game);
        return game;
      case 'finished':
        return game;
    }

    // 更新游戏状态
    game.state = nextStage;

    // 为新阶段创建历史记录条目
    game.actionHistory.push({
      stage: nextStage,
      actions: []
    });

    // 设置第一个行动玩家（庄家左侧第一个可行动的玩家）
    const startIdx = this.findActionableFrom(game, (game.dealerIndex + 1) % game.players.length);
    game.currentPlayerIndex = startIdx;
    game.players[startIdx].isCurrent = true;

    return game;
  }

  // 无人可再下注时补完公共牌并直接摊牌
  fastForwardToShowdown(game) {
    while (game.communityCards.length < 5) {
      game.communityCards.push(game.deck.pop());
    }
    game.state = 'showdown';
    this.handleShowdown(game);
  }

  // 处理摊牌阶段（按每人实际投入构建主池/边池逐池分配）
  handleShowdown(game) {
    const activePlayers = game.players.filter(p => p.isActive);

    // 按未弃牌玩家的投入从小到大分层构建奖池
    const levels = [...new Set(activePlayers.map(p => p.totalContribution))]
      .filter(c => c > 0)
      .sort((a, b) => a - b);

    const pots = [];
    let prevLevel = 0;
    for (const level of levels) {
      let amount = 0;
      for (const p of game.players) {
        amount += Math.min(p.totalContribution, level) - Math.min(p.totalContribution, prevLevel);
      }
      if (amount > 0) {
        pots.push({
          amount,
          eligible: activePlayers.filter(p => p.totalContribution >= level)
        });
      }
      prevLevel = level;
    }

    // 超出最高有效层的投入无人可赢，退还本人（未被跟注的部分）
    for (const p of game.players) {
      const excess = p.totalContribution - Math.min(p.totalContribution, prevLevel);
      if (excess > 0) {
        p.chips += excess;
      }
    }

    // 多人到河牌才需要亮牌评牌；其余人都弃牌时赢家不亮牌
    const isShowdown = activePlayers.length > 1;
    const handNames = {};
    const handRanks = {};
    if (isShowdown) {
      for (const p of activePlayers) {
        const solved = Hand.solve([...p.cards, ...game.communityCards]);
        handNames[p.id] = solved.descr;
        handRanks[p.id] = solved.name;
      }
    }

    // 逐池评牌并分配（只有一名有效玩家时无需评牌）
    const winnings = {};
    for (const pot of pots) {
      let winners;
      if (pot.eligible.length === 1) {
        winners = pot.eligible;
      } else {
        const playerHands = pot.eligible.map(player => ({
          player,
          hand: Hand.solve([...player.cards, ...game.communityCards])
        }));
        const winningHands = Hand.winners(playerHands.map(ph => ph.hand));
        winners = playerHands
          .filter(ph => winningHands.includes(ph.hand))
          .map(ph => ph.player);
      }
      this.distributePot(game, pot.amount, winners, winnings);
    }

    // 记录本手结果，供前端展示赢家
    game.lastHandResult = {
      round: game.round,
      isShowdown,
      winners: Object.entries(winnings).map(([playerId, amount]) => ({
        playerId,
        amount,
        handName: handNames[playerId] || null,
        handRank: handRanks[playerId] || null
      })),
      hands: handNames,
      ranks: handRanks
    };

    game.pot = 0;
    game.state = 'finished';
  }

  // 分配单个奖池，余数筹码从庄家左侧起按座位顺序分给赢家
  distributePot(game, amount, winners, winnings = {}) {
    const share = Math.floor(amount / winners.length);
    let remainder = amount - share * winners.length;
    const ordered = [...winners].sort(
      (a, b) => this.seatOffsetFromDealer(game, a) - this.seatOffsetFromDealer(game, b)
    );
    for (const player of ordered) {
      let won = share;
      if (remainder > 0) {
        won += 1;
        remainder--;
      }
      player.chips += won;
      winnings[player.id] = (winnings[player.id] || 0) + won;
    }
  }

  // 玩家相对庄家左侧的座位偏移（小盲位=0）
  seatOffsetFromDealer(game, player) {
    const idx = game.players.indexOf(player);
    const n = game.players.length;
    return (idx - game.dealerIndex - 1 + 2 * n) % n;
  }

  // 开始新一轮
  startNewRound(game) {
    // 支持传入gameId或game对象
    if (typeof game === 'string') {
      const gameId = game;
      game = this.games.get(gameId);
      if (!game) {
        logger.error(`游戏不存在: ${gameId}`);
        return null;
      }
    }

    // 安全检查：确保game和players存在
    if (!game || !game.players) {
      logger.error('无效的游戏状态或玩家列表');
      return game;
    }

    // 记录旧座次，按玩家id而不是索引轮转按钮，避免淘汰玩家后按钮错位
    const oldOrder = game.players.map(p => p.id);
    const oldDealerPos = game.dealerIndex;

    // 重置游戏状态
    game.state = 'waiting'; // 显式设置为waiting状态，以便可以重新开始游戏
    game.deck = this.createDeck();
    this.shuffleDeck(game.deck);
    game.communityCards = [];
    game.pot = 0;
    game.currentBet = 0;
    game.lastRaiseIndex = -1;
    game.lastRaiseAmount = 0;
    game.round++;

    // 重置玩家状态
    game.players.forEach(player => {
      player.cards = [];
      player.isActive = true;
      player.isCurrent = false;
      player.isAllIn = false;
      player.bet = 0;
      player.totalContribution = 0;
      player.hasActed = false;
      player.action = null;
    });

    // 淘汰没有筹码的玩家
    game.players = game.players.filter(player => player.chips > 0);

    // 如果玩家数量不足，游戏结束
    if (game.players.length < 2) {
      game.state = 'finished';
      return game;
    }

    // 按钮移动到旧座次中下一位仍在场的玩家
    for (let offset = 1; offset <= oldOrder.length; offset++) {
      const candidateId = oldOrder[(oldDealerPos + offset) % oldOrder.length];
      const newIdx = game.players.findIndex(p => p.id === candidateId);
      if (newIdx !== -1) {
        game.dealerIndex = newIdx;
        break;
      }
    }

    return game;
  }

  // 计算玩家相对位置（按钮位、小盲、大盲等）
  calculateRelativePosition(dealerIndex, playerIndex, totalPlayers) {
    // 计算相对位置
    let relativePos = (playerIndex - dealerIndex + totalPlayers) % totalPlayers;

    // 单挑：庄家兼小盲，另一位是大盲
    if (totalPlayers === 2) {
      return relativePos === 0 ? 'BTN' : 'BB';
    }

    // 位置映射
    const positionNames = {
      0: "BTN", // 庄家/按钮位
      1: "SB",  // 小盲
      2: "BB",  // 大盲
    };

    // 根据玩家数量动态计算其他位置
    if (relativePos <= 2) {
      return positionNames[relativePos];
    }
    // 盲注后第一位总是UTG，其余位置从按钮往前倒数（CO、HJ、MP、UTG+1），
    // 这样6人桌是UTG/HJ/CO而不是UTG/UTG+1/MP
    if (relativePos === 3) return 'UTG';
    const fromButton = totalPlayers - relativePos;
    return ['CO', 'HJ', 'MP', 'UTG+1'][fromButton - 1] || `P${relativePos}`;
  }
}

module.exports = { GameService };
