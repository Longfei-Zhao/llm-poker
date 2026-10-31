// 无界面批量跑牌：一桌AI自己连打N手，每手记录成一份回放JSON。
const { GameService } = require('./game.service');
const { HandRecorder } = require('./hand-recorder');
const { buildPlayerView, sanitizeDecision, defaultAction } = require('./player-view');
const logger = require('../utils/logger');

class TableRunner {
  constructor({ ai, characters, handsDir, stack = 10000, smallBlind = 50, bigBlind = 100, gameService = new GameService(), session = null }) {
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
  }

  // 为每个角色创建AI代理；没配好密钥的角色跳过，至少要两人才能开桌
  async setup() {
    const seated = [];
    for (const c of this.characters) {
      try {
        await this.ai.createAgent(c.id, c.name, c.provider, c.model);
        this.seats[c.id] = c;
        seated.push(c);
      } catch (error) {
        logger.warn(`角色${c.name}(${c.provider})无法入座: ${error.message}`);
      }
    }
    if (seated.length < 2) throw new Error('可入座的角色不足两人，请检查AI服务和API密钥');

    this.game = this.gameService.createGame(
      seated.map(c => ({ id: c.id, name: c.name, aiModel: c.label, chips: this.stack }))
    );
    this.game.smallBlind = this.smallBlind;
    this.game.bigBlind = this.bigBlind;
    return seated;
  }

  // 打完整一手牌并落盘，返回 { file, log }
  async playHand(handNo) {
    const game = this.game;
    this.gameService.startGame(game.id);
    this.recorder.begin(game, this.seats, { id: `${this.session}-${String(handNo).padStart(3, '0')}`, session: this.session, hand: handNo });
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
    const view = buildPlayerView(game, player, { persona: seat.persona, tableTalk });

    let decision;
    try {
      decision = await this.ai.getDecision(player.id, view, legal.validActions, legal.minBet, legal.maxBet);
    } catch (error) {
      logger.warn(`${player.name}决策失败，使用默认动作: ${error.message}`);
      decision = { action: defaultAction(legal.validActions), amount: 0 };
    }

    let { action, amount, corrected } = sanitizeDecision(decision, legal);
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
