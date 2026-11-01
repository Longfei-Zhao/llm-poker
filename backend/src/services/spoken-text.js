// 把台词/心声的文字转成给中文配音念的版本：字幕保留原文，配音念这个。
// 牌面按中国牌手的叫法念（Q念圈、J念勾、QQ念圈圈），花色念成中文，英文缩写换成好念的说法。

const RANK = { A: 'A', K: 'K', Q: '圈', J: '勾', T: '十', 9: '九', 8: '八', 7: '七', 6: '六', 5: '五', 4: '四', 3: '三', 2: '二' };
const SUIT = { s: '黑桃', h: '红桃', d: '方块', c: '梅花', '♠': '黑桃', '♥': '红桃', '♦': '方块', '♣': '梅花' };
const NUM = { 2: '二', 3: '三', 4: '四', 5: '五', 6: '六', 7: '七', 8: '八', 9: '九', 10: '十' };
const R = '[AKQJT2-9]';

function rank(r) {
  return RANK[r];
}

// 两张牌的组合：对子念“圈圈”“一对七”，其余逐张念，s/o念同花/杂色
function combo(a, b, suited) {
  let text;
  if (a === b) text = /[AKQJ]/.test(a) ? rank(a) + rank(b) : `一对${rank(a)}`;
  else text = rank(a) + rank(b);
  if (suited === 's') text += '同花';
  if (suited === 'o') text += '杂色';
  return text;
}

function toSpoken(text) {
  if (!text) return '';
  let s = text;

  // 下注术语：3-bet念“三bet”，c-bet、check-raise、all-in去掉连字符
  s = s.replace(/(\d)-?bet/gi, (_, n) => `${NUM[n] || n}bet`);
  s = s.replace(/\bc-?bet/gi, 'C bet');
  s = s.replace(/check-raise/gi, 'check raise');
  s = s.replace(/all-in/gi, 'all in');

  // 位置和盲注
  s = s.replace(/UTG位?/g, '枪口位');
  s = s.replace(/BTN位?/g, '按钮位');
  s = s.replace(/(\d+(?:\.\d+)?)\s*BB\b/gi, (_, n) => `${n}个大盲`);
  s = s.replace(/\bBB\b/g, '大盲');
  s = s.replace(/\bSB\b/g, '小盲');

  // 带花色的牌，可以连写：Kh -> 红桃K，KsJs -> 黑桃K黑桃勾，9♠5♥ -> 黑桃九红桃五
  const card = `(?:10|${R})[shdc♠♥♦♣]`;
  s = s.replace(new RegExp(`(?<![A-Za-z0-9])(?:${card})+(?![A-Za-z])`, 'g'),
    m => m.match(new RegExp(card, 'g')).map(c => SUIT[c.slice(-1)] + (c.startsWith('10') ? '十' : rank(c[0]))).join(''));

  // 牌面连写：K-9-4、K94 -> K九四（不带字母的三位数是普通数字，不动）
  s = s.replace(new RegExp(`(?<![A-Za-z0-9])${R}(?:-${R})+(?![A-Za-z0-9])`, 'g'),
    m => m.split('-').map(rank).join(''));
  s = s.replace(new RegExp(`(?<![A-Za-z0-9])(?=[2-9]*[AKQJT])${R}{3}(?![A-Za-z0-9%])`, 'g'),
    m => [...m].map(rank).join(''));

  // 两张牌的组合：AKo、A5s、QQ+、72o。两个数字的（比如35）只有带s/o或后面跟着“同花/杂色”时才当牌念
  s = s.replace(new RegExp(`(?<![A-Za-z0-9])(${R})(${R})([so])?(\\+)?(?![A-Za-z0-9%])`, 'g'),
    (m, a, b, suited, plus, offset, str) => {
      const named = /^\s*(不?同花|杂色|offsuit|suited)/.test(str.slice(offset + m.length));
      if (/\d\d/.test(a + b) && a !== b && !suited && !named) return m;
      return combo(a, b, suited) + (plus ? '以上' : '');
    });
  s = s.replace(/(?:同花|杂色)(?=不?同花|杂色)/g, '');

  // 单独出现的Q/J/T：顶对J -> 顶对勾
  s = s.replace(/(?<![A-Za-z])([QJT])(?![A-Za-z])/g, (_, r) => rank(r));

  // 牌桌黑话里“湿板”“开枪”会被配音的内容审核误判，念的时候换成平实的说法
  s = s.replace(/湿(板|牌面|面)/g, '听牌很多的牌面');
  s = s.replace(/(开|打)(了)?一枪/g, '下了一注').replace(/一枪/g, '一注').replace(/([二两三])枪/g, '$1条街');

  // 表情和波浪号不念
  s = s.replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}️～~]/gu, '');
  return s.trim();
}

module.exports = { toSpoken };
