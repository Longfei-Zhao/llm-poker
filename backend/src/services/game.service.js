const { Hand } = require('pokersolver');
const { v4: uuidv4 } = require('uuid');

class GameService {
  constructor() {
    this.games = new Map(); // 存储游戏状态
  }

  // 创建新游戏
  createGame(players) {
    const gameId = Math.random().toString(36).substring(2, 15);
    
    // 创建新游戏状态
    const gameState = {
      id: gameId,
      players: players.map((player, index) => ({
        ...player,
        position: index + 1,
        isActive: true,
        isCurrent: false,
        cards: [],
        bet: 0,
        chips: 1000, // 初始筹码
        hasActed: false,
        action: null
      })),
      state: 'waiting', // 游戏状态: waiting, preflop, flop, turn, river, showdown, finished
      pot: 0,
      smallBlind: 5,
      bigBlind: 10,
      currentBet: 0,
      currentPlayerIndex: 0,
      dealerIndex: Math.floor(Math.random() * players.length),
      lastRaiseIndex: -1,
      lastRaiseAmount: 0, // 添加记录最后一次加注的增量
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
    console.log('games:', this.games);
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
    game.actionHistory = []; // 重置行动历史

    // 重置玩家状态
    game.players.forEach(player => {
      player.cards = [];
      player.isActive = true;
      player.isCurrent = false;
      player.bet = 0;
      player.hasActed = false;
    });

    // 发手牌
    for (let i = 0; i < 2; i++) {
      for (let player of game.players) {
        player.cards.push(game.deck.pop());
      }
    }

    // 设置初始状态
    game.state = 'preflop';
    
    // 收取盲注
    const sbIndex = (game.dealerIndex + 1) % game.players.length;
    const bbIndex = (game.dealerIndex + 2) % game.players.length;
    
    game.players[sbIndex].chips -= game.smallBlind;
    game.players[sbIndex].bet = game.smallBlind;
    game.players[bbIndex].chips -= game.bigBlind;
    game.players[bbIndex].bet = game.bigBlind;
    game.pot = game.smallBlind + game.bigBlind;
    game.currentBet = game.bigBlind;

    // 记录盲注操作到历史
    game.actionHistory.push({
      stage: 'preflop',
      actions: [
        {
          playerId: game.players[sbIndex].id,
          playerPosition: this.calculateRelativePosition(game.dealerIndex, sbIndex, game.players.length),
          action: 'smallBlind',
          amount: game.smallBlind,
          timestamp: new Date().toISOString()
        },
        {
          playerId: game.players[bbIndex].id,
          playerPosition: this.calculateRelativePosition(game.dealerIndex, bbIndex, game.players.length),
          action: 'bigBlind',
          amount: game.bigBlind,
          timestamp: new Date().toISOString()
        }
      ]
    });

    // 设置第一个行动的玩家（大盲注后的玩家）
    game.currentPlayerIndex = (game.dealerIndex + 3) % game.players.length;
    game.players[game.currentPlayerIndex].isCurrent = true;

    return game;
  }

  // 处理玩家行动
  handlePlayerAction(gameId, playerId, action, amount = 0) {
    const game = this.games.get(gameId);
    if (!game) throw new Error('Game not found');

    const playerIndex = game.players.findIndex(p => p.id === playerId);
    if (playerIndex === -1) throw new Error('Player not found');
    
    const player = game.players[playerIndex];
    if (!player.isCurrent) throw new Error('Not your turn');

    // 重置当前玩家状态
    player.isCurrent = false;
    
    // 确定是否是All-in
    let isAllIn = false;

    switch (action) {
      case 'fold':
        player.isActive = false;
        player.hasActed = true;
        break;
      case 'call':
        const callAmount = game.currentBet - player.bet;
        if (callAmount > player.chips) throw new Error('Not enough chips');
        player.chips -= callAmount;
        player.bet = game.currentBet;
        game.pot += callAmount;
        player.hasActed = true;
        isAllIn = (player.chips === 0);
        break;
      case 'allin':
        // 玩家所有筹码都投入
        const allinAmount = player.chips;
        player.bet += allinAmount;
        game.pot += allinAmount;
        // 更新当前下注金额，如果all-in金额大于当前下注
        if (player.bet > game.currentBet) {
          game.currentBet = player.bet;
          game.lastRaiseIndex = game.currentPlayerIndex;
        }
        player.chips = 0;
        player.hasActed = true;
        isAllIn = true;
        break;
      case 'raise':
        if (amount <= game.currentBet) throw new Error('Raise amount must be greater than current bet');
        if (amount > player.chips + player.bet) throw new Error('Not enough chips');
        const raiseAmount = amount - player.bet;
        player.chips -= raiseAmount;
        player.bet = amount;
        game.pot += raiseAmount;
        // 计算加注增量（相对于当前最高下注的增加值）
        const raiseIncrement = amount - game.currentBet;
        game.lastRaiseAmount = raiseIncrement; // 记录本次加注增量
        game.currentBet = amount;
        game.lastRaiseIndex = game.currentPlayerIndex;
        player.hasActed = true;
        isAllIn = (player.chips === 0);
        // 重置其他玩家的hasActed状态
        game.players.forEach(p => {
          if (p.id !== player.id && p.isActive) {
            p.hasActed = false;
          }
        });
        break;
      case 'check':
        if (game.currentBet > 0) {
          // 如果已有下注，将check转为fold处理
          console.warn(`玩家${player.name}(${playerId})在不能check的情况下尝试check，自动转为fold处理`);
          player.isActive = false;
          player.hasActed = true;
          // 记录实际执行的操作是fold
          action = 'fold';
        } else {
          player.hasActed = true;
        }
        break;
      default:
        throw new Error('Invalid action');
    }

    // 记录行动到历史
    // 检查当前阶段是否已有记录
    if (!game.actionHistory.length || game.actionHistory[game.actionHistory.length - 1].stage !== game.state) {
      // 如果是新阶段的第一个行动，创建新阶段记录
      game.actionHistory.push({
        stage: game.state,
        actions: []
      });
    }
    
    // 获取当前阶段历史
    const currentStageHistory = game.actionHistory[game.actionHistory.length - 1];
    
    // 添加行动记录
    currentStageHistory.actions.push({
      playerId,
      playerPosition: this.calculateRelativePosition(game.dealerIndex, playerIndex, game.players.length),
      action,
      amount: (action === 'raise' || action === 'call' || action === 'allin') ? player.bet : 0,
      isAllIn,
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

  // 移动到下一个玩家
  moveToNextPlayer(game) {
    do {
      game.currentPlayerIndex = (game.currentPlayerIndex + 1) % game.players.length;
    } while (!game.players[game.currentPlayerIndex].isActive);
    game.players[game.currentPlayerIndex].isCurrent = true;
  }

  // 检查当前回合是否结束
  isRoundComplete(game) {
    // 检查是否所有玩家都行动过，且下注相等
    let lastActivePlayer = null;
    let allBetsEqual = true;
    let allPlayersActed = true;

    for (let player of game.players) {
      if (!player.isActive) continue;
      
      if (lastActivePlayer === null) {
        lastActivePlayer = player;
      } else if (player.bet !== lastActivePlayer.bet) {
        allBetsEqual = false;
      }

      // 检查是否所有玩家都行动过
      if (!player.hasActed && player.isActive) {
        allPlayersActed = false;
      }
    }

    return allBetsEqual && allPlayersActed;
  }

  // 移动到下一个回合
  moveToNextRound(game) {
    // 支持传入gameId或game对象
    if (typeof game === 'string') {
      const gameId = game;
      game = this.games.get(gameId);
      if (!game) {
        console.error(`游戏不存在: ${gameId}`);
        return null;
      }
    }
    
    // 安全检查：确保game和players存在
    if (!game || !game.players) {
      console.error('无效的游戏状态或玩家列表');
      return game;
    }
    
    // 重置玩家行动状态
    game.players.forEach(player => {
      if (player.isActive) {
        player.hasActed = false;
        player.bet = 0;
      }
    });

    // 重置下注相关状态
    game.currentBet = 0;
    game.lastRaiseIndex = -1;
    game.lastRaiseAmount = 0; // 重置最后一次加注的增量

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
        nextStage = 'showdown';
        this.handleShowdown(game);
        return; // 摊牌阶段不需要继续
      case 'showdown':
        this.startNewRound(game);
        return; // 新一轮已经设置了玩家状态
      case 'finished':
        return; // 游戏结束
    }

    // 更新游戏状态
    game.state = nextStage;
    
    // 为新阶段创建历史记录条目(除非是showdown)
    if (nextStage !== 'showdown' && nextStage !== 'finished') {
      game.actionHistory.push({
        stage: nextStage,
        actions: []
      });
    }

    // 设置第一个行动玩家（最靠近小盲注的玩家）
    game.currentPlayerIndex = (game.dealerIndex + 1) % game.players.length;
    while (!game.players[game.currentPlayerIndex].isActive && game.players.some(p => p.isActive)) {
      game.currentPlayerIndex = (game.currentPlayerIndex + 1) % game.players.length;
    }
    game.players[game.currentPlayerIndex].isCurrent = true;
    
    // 返回更新后的游戏对象
    return game;
  }

  // 处理摊牌阶段
  handleShowdown(game) {
    // 获取所有活跃玩家的手牌
    const activePlayers = game.players.filter(p => p.isActive);
    
    if (activePlayers.length === 1) {
      // 如果只有一个玩家，直接获胜
      const winner = activePlayers[0];
      winner.chips += game.pot;
      game.pot = 0;
      game.state = 'finished';
      return;
    }

    // 计算每个玩家的最佳手牌
    const playerHands = activePlayers.map(player => {
      const cards = [...player.cards, ...game.communityCards];
      const hand = Hand.solve(cards);
      return {
        player,
        hand
      };
    });

    // 找出获胜者
    const winners = Hand.winners(playerHands.map(ph => ph.hand));
    const winningPlayers = playerHands
      .filter(ph => winners.includes(ph.hand))
      .map(ph => ph.player);

    // 分配奖池
    const winAmount = Math.floor(game.pot / winningPlayers.length);
    winningPlayers.forEach(player => {
      player.chips += winAmount;
    });
    game.pot = 0;
    game.state = 'finished';
  }

  // 开始新一轮
  startNewRound(game) {
    // 支持传入gameId或game对象
    if (typeof game === 'string') {
      const gameId = game;
      game = this.games.get(gameId);
      if (!game) {
        console.error(`游戏不存在: ${gameId}`);
        return null;
      }
    }
    
    // 安全检查：确保game和players存在
    if (!game || !game.players) {
      console.error('无效的游戏状态或玩家列表');
      return game;
    }
    
    // 移动庄家位置
    game.dealerIndex = (game.dealerIndex + 1) % game.players.length;
    
    // 重置游戏状态
    game.state = 'waiting';  // 显式设置为waiting状态，以便可以重新开始游戏
    game.deck = this.createDeck();
    game.communityCards = [];
    game.pot = 0;
    game.currentBet = 0;
    game.lastRaiseIndex = -1;
    game.lastRaiseAmount = 0; // 重置最后一次加注的增量
    game.round++;

    // 重置玩家状态
    game.players.forEach(player => {
      player.cards = [];
      player.isActive = true;
      player.isCurrent = false;
      player.bet = 0;
      player.hasActed = false;
    });

    // 检查是否有玩家筹码不足
    game.players = game.players.filter(player => player.chips >= game.bigBlind);
    
    // 如果玩家数量不足，游戏结束
    if (game.players.length < 2) {
      game.state = 'finished';
      return game;
    }
    
    // 返回更新后的游戏对象
    return game;
  }

  // 保存游戏状态
  saveGame(gameState) {
    if (!gameState || !gameState.id) {
      console.error('无法保存游戏：游戏状态或ID无效');
      return false;
    }
    
    // 如果传入的是前端格式的游戏状态，需要转换为后端格式
    const gameId = gameState.id;
    
    // 检查游戏是否已存在
    if (this.games.has(gameId)) {
      console.log(`游戏ID ${gameId} 已存在，更新状态`);
      // 可以选择更新现有游戏或保留现有游戏
      // 这里我们选择保留现有游戏，避免覆盖可能的其他状态
      return true;
    }
    
    // 创建一个新的游戏对象
    const newGame = {
      id: gameId,
      players: gameState.players || [],
      state: gameState.stage || 'waiting',
      deck: this.createDeck(),
      communityCards: gameState.communityCards || [],
      pot: gameState.pot || 0,
      currentBet: gameState.currentBet || 0,
      smallBlind: gameState.smallBlind || 1,
      bigBlind: gameState.bigBlind || 2,
      dealerIndex: gameState.dealerIndex || 0,
      currentPlayerIndex: gameState.currentPlayerIndex || 0,
      lastRaiseIndex: -1,
      round: 0
    };
    
    // 保存到games映射中
    this.games.set(gameId, newGame);
    console.log(`游戏ID ${gameId} 已保存到GameService`);
    return true;
  }

  // 计算玩家相对位置（按钮位、小盲、大盲等）
  calculateRelativePosition(dealerIndex, playerIndex, totalPlayers) {
    // 计算相对位置
    let relativePos = (playerIndex - dealerIndex + totalPlayers) % totalPlayers;
    
    // 位置映射
    const positionNames = {
      0: "BTN", // 庄家/按钮位
      1: "SB",  // 小盲
      2: "BB",  // 大盲
    };
    
    // 根据玩家数量动态计算其他位置
    if (totalPlayers <= 3) {
      return positionNames[relativePos] || `P${relativePos}`;
    } else {
      if (relativePos >= 3) {
        // 3人以上桌子的其他位置
        const positions = ["UTG", "UTG+1", "MP", "HJ", "CO"];
        const index = relativePos - 3;
        if (index < positions.length) {
          return positions[index];
        } else {
          return `P${relativePos}`;
        }
      } else {
        return positionNames[relativePos];
      }
    }
  }
}

module.exports = { GameService }; 