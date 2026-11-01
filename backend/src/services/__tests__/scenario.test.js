process.env.LOG_LEVEL = 'silent';

const { buildDeck, loadShow } = require('../scenario');
const { GameService } = require('../game.service');
const { CHARACTERS } = require('../../config/characters');

const ids = CHARACTERS.map(c => c.id);

// 按剧本发牌，再一路过牌/跟注打到河牌，取出实际发到的底牌和公共牌
function dealScenario(scenario) {
  const gs = new GameService();
  const game = gs.createGame(ids.map(id => ({ id, name: id, chips: 10000 })), { dealerIndex: ids.indexOf(scenario.button) });
  gs.startGame(game.id, { deck: buildDeck(ids, scenario.holes, scenario.board) });
  while (game.state !== 'finished') {
    const p = game.players[game.currentPlayerIndex];
    gs.handlePlayerAction(game.id, p.id, game.currentBet > p.bet ? 'call' : 'check');
  }
  return game;
}

describe('剧本发牌', () => {
  test('底牌和公共牌按剧本发出，没指定的随机补齐且不重复', () => {
    const scenario = { button: 'grok', holes: { claude: ['Kh', 'Kd'], grok: ['Ac', 'As'] }, board: ['8c', '3d', '2s'] };
    const game = dealScenario(scenario);
    expect(game.players.find(p => p.id === 'claude').cards).toEqual(['Kh', 'Kd']);
    expect(game.players.find(p => p.id === 'grok').cards).toEqual(['Ac', 'As']);
    expect(game.communityCards.slice(0, 3)).toEqual(['8c', '3d', '2s']);
    const all = [...game.players.flatMap(p => p.cards), ...game.communityCards];
    expect(new Set(all).size).toBe(all.length);
  });

  test('剧本有重复或写错的牌时报错', () => {
    expect(() => buildDeck(ids, { claude: ['Ah', 'Ah'] })).toThrow('重复');
    expect(() => buildDeck(ids, { claude: ['Ax', 'Kd'] })).toThrow('无法识别');
    expect(() => buildDeck(ids, { nobody: ['Ah', 'Kd'] })).toThrow('没入座');
  });

  test('第一集的8手剧本都能按设计发出来', () => {
    const show = loadShow('s2e1');
    expect(show.hands).toHaveLength(8);
    for (const scenario of show.hands) {
      const game = dealScenario(scenario);
      expect(game.players[game.dealerIndex].id).toBe(scenario.button);
      for (const [id, cards] of Object.entries(scenario.holes)) {
        expect(game.players.find(p => p.id === id).cards).toEqual(cards);
      }
      expect(game.communityCards).toEqual(scenario.board);
    }
  });
});
