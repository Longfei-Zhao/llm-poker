// 发给AI服务的玩家视角，以及对AI决策的合法化处理。实时WebSocket模式和批量跑牌共用。

// 构建某个玩家可见的游戏视图：只含他自己的手牌，不含他人手牌与牌堆。
// extras.persona 是该角色的人设，extras.tableTalk 是本手牌里大家说出口的台词（不含心声），
// extras.roster 是同桌其他人的公众形象（可以拿来互相调侃）
function buildPlayerView(game, actingPlayer, extras = {}) {
  return {
    id: game.id,
    gameId: game.gameId || game.id,
    state: game.state,
    stage: game.stage || game.state,
    round: game.round,
    pot: game.pot,
    currentBet: game.currentBet,
    lastRaiseAmount: game.lastRaiseAmount,
    smallBlind: game.smallBlind,
    bigBlind: game.bigBlind,
    dealerIndex: game.dealerIndex,
    currentPlayerIndex: game.currentPlayerIndex,
    communityCards: [...(game.communityCards || [])],
    actionHistory: game.actionHistory || [],
    actingPlayerId: actingPlayer.id,
    persona: extras.persona || null,
    tableTalk: [...(extras.tableTalk || [])],
    roster: (extras.roster || []).filter(r => r.id !== actingPlayer.id).map(r => ({ name: r.name, image: r.image })),
    players: game.players.map(p => ({
      id: p.id,
      name: p.name,
      aiModel: p.aiModel,
      position: p.position,
      chips: p.chips,
      bet: p.bet,
      isActive: p.isActive,
      isCurrent: p.isCurrent,
      isAllIn: p.isAllIn,
      hasActed: p.hasActed,
      action: p.action,
      cards: p.id === actingPlayer.id ? [...(p.cards || [])] : []
    }))
  };
}

// 默认动作：优先check，其次call，最后才fold
function defaultAction(validActions) {
  if (validActions.includes('check')) return 'check';
  if (validActions.includes('call')) return 'call';
  return 'fold';
}

// 把AI返回的决策修正为合法动作：非法动作换成默认动作，加注金额取整并钳制到范围内
function sanitizeDecision(decision, legal) {
  const { validActions, minBet, maxBet } = legal;
  let action = decision && decision.action;
  let amount = 0;
  const corrected = !validActions.includes(action);
  if (corrected) action = defaultAction(validActions);

  if (action === 'raise') {
    amount = Math.floor(Number(decision.amount));
    if (!Number.isFinite(amount)) amount = minBet;
    amount = Math.max(minBet, Math.min(maxBet, amount));
  }
  return { action, amount, corrected };
}

module.exports = { buildPlayerView, defaultAction, sanitizeDecision };
