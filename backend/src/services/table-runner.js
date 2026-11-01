// 无界面批量跑牌：一桌AI自己连打N手，每手记录成一份回放JSON。
const { GameService } = require('./game.service');
const { HandRecorder } = require('./hand-recorder');
const { buildPlayerView, sanitizeDecision, defaultAction } = require('./player-view');
const { buildDeck } = require('./scenario');
const logger = require('../utils/logger');

class TableRunner {
  constructor({ ai, characters, handsDir, stack = 10000, smallBlind = 50, bigBlind = 100, gameService = new GameService(), session = null, agentPrefix = '' }) {
    this.ai = ai;
    this.characters = characters;
    this.stack = stack;
    this.smallBlind = smallBlind;
    this.bigBlind = bigBlind;
    this.gameService = gameService;
    this.recorder = new HandRecorder(handsDir);
    this.session = session || new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
    this.seats = {};
    this.game = null;
    // 同时开多桌时，AI服务里的代理按桌区分（同一个角色每桌一个代理）
    this.agentPrefix = agentPrefix;
  }

  // 为每个角色创建AI代理；没配好密钥的角色跳过，至少要两人才能开桌
  async setup() {
    const seated = [];
    for (const c of this.characters) {
      try {
        await this.ai.createAgent(this.agentPrefix + c.id, c.name, c.provider, c.model, 0.7, c.effort);
        this.seats[c.id] = c;
        seated.push(c);
      } catch (error) {
        logger.warn(`角色${c.name}(${c.provider})无法入座: ${error.message}`);
      }
    }
    if (seated.length < 2) throw new Error('可入座的角色不足两人，请检查AI服务和API密钥');
    this.seated = seated;
    this.newGame();
    return seated;
  }

  // 开一张新桌：stacks按角色id指定筹码（缺省用统一筹码），dealerIndex指定庄家
  newGame({ stacks = {}, dealerIndex } = {}) {
    this.game = this.gameService.createGame(
      this.seated.map(c => ({ id: c.id, name: c.name, aiModel: c.label, chips: stacks[c.id] || this.stack })),
      Number.isInteger(dealerIndex) ? { dealerIndex } : {}
    );
    this.game.smallBlind = this.smallBlind;
    this.game.bigBlind = this.bigBlind;
    return this.game;
  }

  // 打一手剧本牌：按剧本指定庄家、底牌和公共牌，牌怎么打仍完全由模型决定
  async playScenario(scenario, handNo) {
    const ids = this.seated.map(c => c.id);
    const dealerIndex = scenario.button ? ids.indexOf(scenario.button) : undefined;
    if (scenario.button && dealerIndex === -1) throw new Error(`剧本里的庄家${scenario.button}没有入座`);
    const game = this.newGame({ stacks: scenario.stacks, dealerIndex });
    const deck = buildDeck(game.players.map(p => p.id), scenario.holes || {}, scenario.board || []);
    return this.playHand(handNo, { deck, title: scenario.title });
  }

  // 打完整一手牌并落盘，返回 { file, log }
  async playHand(handNo, { deck, title } = {}) {
    const game = this.game;
    this.gameService.startGame(game.id, deck ? { deck } : {});
    this.recorder.begin(game, this.seats, { id: `${this.session}-${String(handNo).padStart(3, '0')}`, session: this.session, hand: handNo, title });
    const tableTalk = [];
    while (game.state !== 'finished') {
      await this.turn(tableTalk);
    }
    return this.recorder.finish(game);
  }

  async turn(tableTalk) {
    const game = this.game;
    const player = game.players[game.currentPlayerIndex];
    const seat = this.seats[player.id] || {};
    const legal = this.gameService.getLegalActions(game, player);
    const roster = game.players.map(p => ({ id: p.id, name: p.name, image: (this.seats[p.id] || {}).image }));
    const view = buildPlayerView(game, player, { persona: seat.persona, tableTalk, roster });

    let decision;
    let failed = false;
    try {
      decision = await this.ai.getDecision(this.agentPrefix + player.id, view, legal.validActions, legal.minBet, legal.maxBet);
    } catch (error) {
      logger.warn(`${player.name}决策失败，使用默认动作: ${error.message}`);
      decision = { action: defaultAction(legal.validActions), amount: 0 };
      failed = true;
    }

    let { action, amount, corrected } = sanitizeDecision(decision, legal);
    // AI调用失败时是系统替它出的手，回放里要能看出来
    corrected = corrected || failed;
    const street = game.state;
    const boardBefore = game.communityCards.length;
    try {
      this.gameService.handlePlayerAction(game.id, player.id, action, amount);
    } catch (error) {
      action = legal.validActions.includes('check') ? 'check' : 'fold';
      corrected = true;
      logger.warn(`${player.name}的动作被引擎拒绝(${error.message})，改为${action}`);
      this.gameService.handlePlayerAction(game.id, player.id, action, 0);
    }

    // 引擎在处理动作时已记录本街累计下注额和是否全下，回合推进后bet会清零，所以从历史里取
    const stageLog = game.actionHistory.filter(h => h.stage === street).pop();
    const last = stageLog && stageLog.actions[stageLog.actions.length - 1];
    this.recorder.action({
      playerId: player.id,
      street,
      action,
      to: last ? last.amount : 0,
      allIn: last ? last.isAllIn : false,
      speech: decision.speech,
      inner: decision.inner,
      corrected
    });
    if (decision.speech) tableTalk.push({ name: player.name, stage: street, speech: decision.speech });
    if (game.communityCards.length > boardBefore) this.recorder.board(game, boardBefore);
  }

  // 连打n手，每手结束回调onHand；有人输光到只剩一人时提前结束
  async run(hands, onHand = () => {}) {
    await this.setup();
    for (let k = 1; k <= hands; k++) {
      const result = await this.playHand(k);
      onHand(result, k);
      this.gameService.startNewRound(this.game);
      if (this.game.state === 'finished') {
        logger.info('只剩一名玩家，牌局结束');
        break;
      }
    }
  }
}

module.exports = { TableRunner };
