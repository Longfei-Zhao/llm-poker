// 赛后感言：一手牌打完后，让输得最多的人先说一句，赢家再接一句。不用重跑牌局，直接读录好的记录，
// 每句话由角色自己的模型来说，结果写回记录的 post 字段，回放在结算后播放，配音脚本也会一起配。
// 用法：node src/scripts/postgame.js --session s2e1 [--only 2,5] [--force]
const fs = require('fs');
const path = require('path');
const config = require('../config');
const ai = require('../services/ai.service');
const { CHARACTERS, getCharacters } = require('../config/characters');

const STREET = { preflop: '翻牌前', flop: '翻牌', turn: '转牌', river: '河牌' };
const ACT = { fold: '弃牌', check: '过牌', call: '跟注', bet: '下注', raise: '加注到', allin: '全下' };

function parseArgs(argv) {
  const args = { session: null, only: null, force: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--session') args.session = argv[++i];
    else if (argv[i] === '--only') args.only = argv[++i].split(',').map(Number);
    else if (argv[i] === '--force') args.force = true;
  }
  return args;
}

// 谁说：净输最多的人先说，赢得最多的人接话
function speakers(log) {
  const delta = log.players.map(p => ({ id: p.id, d: (log.result.stacks?.[p.id] ?? p.stack) - p.stack }));
  const loser = delta.filter(x => x.d < 0).sort((a, b) => a.d - b.d)[0];
  const winner = delta.filter(x => x.d > 0).sort((a, b) => b.d - a.d)[0];
  return { loser, winner };
}

// 这手牌的经过：只写桌上所有人都看得到的东西（亮出来的牌、公共牌、下注和台词），心声不写
function recap(log, me) {
  const name = Object.fromEntries(log.players.map(p => [p.id, p.name]));
  const shown = new Set(log.result.isShowdown ? Object.keys(log.result.ranks || {}) : []);
  const lines = [`公共牌：${log.board.join(' ') || '没发到翻牌'}`];
  for (const p of log.players) {
    if (p.id === me) lines.push(`你的底牌：${p.cards.join(' ')}`);
    else if (shown.has(p.id)) lines.push(`${p.name} 亮出了 ${p.cards.join(' ')}`);
  }
  lines.push('过程：');
  for (const e of log.events) {
    if (e.t !== 'act' || (e.a === 'fold' && e.street === 'preflop')) continue;
    const amt = ['raise', 'bet', 'call', 'allin'].includes(e.a) ? ` ${e.to}` : '';
    lines.push(`- ${STREET[e.street]} ${name[e.p]} ${ACT[e.a] || e.a}${amt}${e.sp ? `，说：“${e.sp}”` : ''}`);
  }
  const res = (log.result.winners || []).map(w => `${name[w.playerId]} 赢下 ${w.amount}${w.handName ? `（${w.handName}）` : ''}`);
  lines.push(`结果：${res.join('，')}`);
  return lines.join('\n');
}

function prompt(c, log, role, other, earlier) {
  const name = Object.fromEntries(log.players.map(p => [p.id, p.name]));
  const delta = (log.result.stacks?.[c.id] ?? 0) - log.players.find(p => p.id === c.id).stack;
  const roster = getCharacters().filter(x => x.id !== c.id).map(x => `- ${x.name}：${x.image}`).join('\n');
  // 用不带“少玩梗”后缀的原始人设：赛后这句正是该玩梗的时候
  return [
    CHARACTERS.find(x => x.id === c.id).persona,
    `你正在一档大模型德州扑克节目里打牌，这一手刚刚结束。你${delta >= 0 ? '赢了' : '输了'} ${Math.abs(delta)} 筹码。`,
    recap(log, c.id),
    `同桌的人（大家都知道的公众形象）：\n${roster}`,
    earlier ? `${name[other]} 刚刚对你说：“${earlier}”` : '',
    `现在说一句赛后的话，${role === 'loser' ? `对着 ${name[other]}` : `回应 ${name[other]}`}。可以是认栽、嘴硬、自嘲、酸一句对方运气、或者调侃对方，`
      + '这是这手牌最适合玩梗的时候，可以拿对方或自己现实里的公众形象开个玩笑，但要和这手牌扯得上。'
      + '要像真人牌桌上的一句话，口语、好笑、有性格。中文，30 字以内，扑克术语用英文。只输出这句话本身，不要引号和解释。'
  ].filter(Boolean).join('\n\n');
}

function clean(text) {
  return String(text || '').split('\n').map(s => s.trim()).filter(Boolean).pop()?.replace(/^["“「]|["”」]$/g, '') || '';
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.session) throw new Error('需要 --session，比如 --session s2e1');
  const chars = Object.fromEntries(getCharacters().map(c => [c.id, c]));
  const files = fs.readdirSync(config.HANDS_DIR).filter(f => f.endsWith('.json'));
  for (const f of files) {
    const file = path.join(config.HANDS_DIR, f);
    const log = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (log.session !== args.session || (args.only && !args.only.includes(log.hand))) continue;
    if (log.post && !args.force) { console.log(`第 ${log.hand} 手已经有赛后感言，跳过（--force 重做）`); continue; }
    const { loser, winner } = speakers(log);
    if (!loser || !winner) continue;
    const prefix = `post-${log.id}-`;
    const post = [];
    try {
      for (const id of [loser.id, winner.id]) {
        const c = chars[id];
        await ai.createAgent(prefix + id, c.name, c.provider, c.model, 0.7, c.effort);
      }
      const first = clean(await ai.chat(prefix + loser.id, prompt(chars[loser.id], log, 'loser', winner.id)));
      post.push({ p: loser.id, sp: first });
      const second = clean(await ai.chat(prefix + winner.id, prompt(chars[winner.id], log, 'winner', loser.id, first)));
      post.push({ p: winner.id, sp: second });
    } catch (error) {
      console.error(`第 ${log.hand} 手赛后感言失败：${error.message}`);
      continue;
    } finally {
      await Promise.all([loser.id, winner.id].map(id => ai.deleteAgent(prefix + id).catch(() => {})));
    }
    log.post = post;
    fs.writeFileSync(file, JSON.stringify(log, null, 2));
    console.log(`第 ${log.hand} 手「${log.title}」：${post.map(x => `${chars[x.p].name}：${x.sp}`).join(' / ')}`);
  }
}

main().catch(error => {
  console.error(error.message);
  process.exit(1);
});
