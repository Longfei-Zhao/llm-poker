// 剧本发牌：按剧本指定每个人的底牌和公共牌，排出一副牌堆。
// 引擎从牌堆末尾往前发：先按座位顺序每人一张、再每人一张，然后翻牌三张、转牌、河牌（不烧牌）。
// 剧本没指定的底牌和公共牌，从剩下的牌里随机补。
const fs = require('fs');
const path = require('path');

const RANKS = '23456789TJQKA';
const SUITS = 'hdcs';

function fullDeck() {
  const deck = [];
  for (const s of SUITS) for (const r of RANKS) deck.push(r + s);
  return deck;
}

function shuffle(cards) {
  for (let i = cards.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
  return cards;
}

// playerIds按座位顺序；holes形如 { grok: ['As', 'Ac'] }；board最多5张
function buildDeck(playerIds, holes = {}, board = []) {
  const fixed = [...Object.values(holes).flat(), ...board];
  const bad = fixed.filter(c => typeof c !== 'string' || c.length !== 2 || !RANKS.includes(c[0]) || !SUITS.includes(c[1]));
  if (bad.length) throw new Error(`剧本里有无法识别的牌: ${bad.join(', ')}`);
  const dup = fixed.filter((c, i) => fixed.indexOf(c) !== i);
  if (dup.length) throw new Error(`剧本里有重复的牌: ${[...new Set(dup)].join(', ')}`);
  if (board.length > 5) throw new Error('公共牌最多5张');
  for (const id of Object.keys(holes)) {
    if (!playerIds.includes(id)) throw new Error(`剧本给没入座的${id}发了牌`);
    if (holes[id].length !== 2) throw new Error(`${id}的底牌必须是两张`);
  }

  const rest = shuffle(fullDeck().filter(c => !fixed.includes(c)));
  const draw = () => rest.pop();
  const dealt = [];
  for (const round of [0, 1]) {
    for (const id of playerIds) dealt.push(holes[id] ? holes[id][round] : draw());
  }
  for (let k = 0; k < 5; k++) dealt.push(board[k] || draw());
  // 牌堆末尾先发，所以把发牌顺序倒过来放在剩余牌的后面
  return [...rest, ...dealt.reverse()];
}

function loadShow(name, dir = path.join(__dirname, '..', '..', 'shows')) {
  const file = path.join(dir, `${name}.json`);
  if (!fs.existsSync(file)) throw new Error(`找不到剧本 ${file}`);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

module.exports = { buildDeck, loadShow };
