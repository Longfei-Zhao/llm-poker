// 把每一手牌记录成一份JSON：谁坐哪、手牌、每个动作带台词和心声、公共牌、结算结果。
// 回放页面只读这份记录就能完整重演这一手。
const fs = require('fs');
const path = require('path');

const STREET_BY_BOARD = { 3: 'flop', 4: 'turn', 5: 'river' };

class HandRecorder {
  constructor(dir) {
    this.dir = dir;
    this.log = null;
  }

  // 在startGame之后调用：此时盲注已下、手牌已发
  begin(game, seats, meta = {}) {
    const blinds = (game.actionHistory[0] && game.actionHistory[0].actions) || [];
    const sb = blinds.find(a => a.action === 'smallBlind');
    const bb = blinds.find(a => a.action === 'bigBlind');
    this.log = {
      id: meta.id || `hand-${Date.now()}`,
      session: meta.session || null,
      hand: meta.hand || game.round + 1,
      title: meta.title || null,
      startedAt: new Date().toISOString(),
      blinds: [game.smallBlind, game.bigBlind],
      button: game.players[game.dealerIndex].id,
      players: game.players.map(p => {
        const seat = seats[p.id] || {};
        return {
          id: p.id,
          name: p.name,
          label: seat.label || p.aiModel || null,
          model: seat.model || null,
          color: seat.color || null,
          look: seat.look || null,
          stack: p.chips + p.totalContribution,
          cards: [...p.cards]
        };
      }),
      events: [],
      board: [],
      result: null
    };
    this.log.events.push({
      t: 'blinds',
      sb: sb ? { p: sb.playerId, amount: sb.amount } : null,
      bb: bb ? { p: bb.playerId, amount: bb.amount } : null
    });
    // 盲注直接让所有人all-in时，startGame已经快进发完公共牌
    this.board(game, 0);
  }

  // 记录一个动作。to是该玩家本街累计下注额，speech是台词，inner是心声
  action({ playerId, street, action, to, allIn, speech, inner, corrected }) {
    const ev = { t: 'act', p: playerId, street, a: action };
    if (to) ev.to = to;
    if (allIn) ev.allIn = true;
    if (speech) ev.sp = speech;
    if (inner) ev.in = inner;
    if (corrected) ev.corrected = true;
    this.log.events.push(ev);
  }

  // 记录从prevCount张之后新发的公共牌；快进时一次可能补多条街，按街拆开
  board(game, prevCount) {
    const cards = game.communityCards;
    for (const n of [3, 4, 5]) {
      if (n <= prevCount || n > cards.length) continue;
      const from = n === 3 ? 0 : n - 1;
      this.log.events.push({ t: 'board', street: STREET_BY_BOARD[n], cards: cards.slice(from, n) });
    }
    this.log.board = [...cards];
  }

  // 一手结束：写入结算结果并落盘，返回文件路径
  finish(game) {
    const result = game.lastHandResult || null;
    this.log.result = result && {
      ...result,
      stacks: Object.fromEntries(game.players.map(p => [p.id, p.chips]))
    };
    this.log.events.push({ t: 'result' });
    this.log.endedAt = new Date().toISOString();
    fs.mkdirSync(this.dir, { recursive: true });
    const file = path.join(this.dir, `${this.log.id}.json`);
    fs.writeFileSync(file, JSON.stringify(this.log, null, 2), 'utf8');
    const log = this.log;
    this.log = null;
    return { file, log };
  }
}

module.exports = { HandRecorder };
