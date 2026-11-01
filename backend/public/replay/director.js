// 导演：把一手牌的记录排成镜头。回放页面和配音脚本共用，配音配的就是画面上放的那几句。
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign(root, api);
})(typeof self !== 'undefined' ? self : this, function () {
  const STREET_CN = { preflop: '翻牌前', flop: '翻牌', turn: '转牌', river: '河牌' };

  // 每个动作都有台词和心声，回放挑着放，保持节奏：
  // - 全下放大招特写；全下之后、河牌上的下注/跟注、大额加注，用完整对话框（台词+心声）并推镜头
  // - 点名对手的台词、下注加注时的台词，放台词
  // - 其余动作放一句心声
  // - 翻牌前的弃牌只放点名了别人的（互相接话），每手最多两句；拿垃圾牌自言自语的直接弃，不占时间
  function direct(log) {
    const idx = Object.fromEntries(log.players.map((p, i) => [p.id, i]));
    const bb = log.blinds[1];
    const out = [], chaps = [];
    const chap = name => { chaps.push(name); out.push({ t: 'chap', i: chaps.length - 1 }); };
    const seat = s => (s ? { p: idx[s.p], amount: s.amount } : null);
    chap('发牌');
    out.push({ t: 'deal' });
    const blinds = log.events.find(e => e.t === 'blinds');
    out.push({ t: 'blinds', sb: seat(blinds && blinds.sb), bb: seat(blinds && blinds.bb) });
    chap('翻牌前');
    const nameOf = Object.fromEntries(log.players.map(p => [p.id, p.name]));
    const mentions = e => !!e.sp && log.players.some(p => p.id !== e.p && e.sp.includes(p.name));
    const preflopFolds = log.events.filter(e => e.t === 'act' && e.street === 'preflop' && e.a === 'fold' && !e.corrected && e.sp);
    const shownFolds = new Set(preflopFolds.filter(mentions).slice(0, 2));
    let pressure = false;
    for (const [k, e] of log.events.entries()) {
      if (e.t === 'act') {
        if (e.allIn && !pressure) chap('全下');
        const key = e.allIn || pressure || (e.a === 'raise' && e.to >= 8 * bb) || (e.street === 'river' && ['bet', 'raise', 'call'].includes(e.a));
        let show;
        if (e.corrected) show = 'none';
        else if (key && (e.sp || e.in)) show = 'full';
        else if (e.street === 'preflop' && e.a === 'fold') show = shownFolds.has(e) ? 'say' : 'none';
        else if (e.sp && (mentions(e) || ['raise', 'bet'].includes(e.a))) show = 'say';
        else if (e.in) show = 'think';
        else show = e.sp ? 'say' : 'none';
        out.push({ t: 'act', ev: k, p: idx[e.p], a: e.a, to: e.to || 0, allIn: !!e.allIn, sp: e.sp || '', in: e.in || '', show, full: show === 'full', cut: !!e.allIn && e.a !== 'call', street: e.street, auto: !!e.corrected, who: nameOf[e.p] });
        if (e.allIn) pressure = true;
      } else if (e.t === 'board') {
        out.push({ t: 'collect' });
        chap(STREET_CN[e.street]);
        out.push({ t: 'board', cards: e.cards, river: e.street === 'river', street: e.street });
      } else if (e.t === 'result') {
        out.push({ t: 'collect' });
        chap('结算');
        out.push({ t: 'show' });
        // 赛后感言（postgame.js 补录的），结算后播放
        (log.post || []).forEach((x, n) => out.push({ t: 'post', p: idx[x.p], sp: x.sp, ev: `post${n}` }));
        out.push({ t: 'end' });
      }
    }
    return { shots: out, chaps };
  }

  return { STREET_CN, direct };
});
