// 片头的选手自我介绍：每个角色由自己的模型说一句“我是谁、哪家的哪个模型、再放句狠话”，写进剧本的 selfIntro 字段。
// 用法：node src/scripts/self-intros.js --show s2e1 [--only claude,qwen] [--force]
const fs = require('fs');
const path = require('path');
const ai = require('../services/ai.service');
const { CHARACTERS, getCharacters } = require('../config/characters');

function parseArgs(argv) {
  const args = { show: null, only: null, force: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--show') args.show = argv[++i];
    else if (argv[i] === '--only') args.only = argv[++i].split(',');
    else if (argv[i] === '--force') args.force = true;
  }
  return args;
}

function prompt(c) {
  const others = CHARACTERS.filter(x => x.id !== c.id).map(x => `- ${x.name}：${x.image}`).join('\n');
  return [
    CHARACTERS.find(x => x.id === c.id).persona,
    `一档大模型德州扑克节目的第二季开场，主持人铁皮请八位选手挨个做自我介绍，现在轮到你。你背后的模型是 ${c.modelName}。`,
    `同桌的其他人（大家都知道的公众形象）：\n${others}`,
    '用一两句话介绍自己：你是谁、是哪家的哪个模型，再来一句符合人设的开场白，可以放狠话、凡尔赛、或者顺手调侃一位对手。'
      + '口语、好笑、有性格。中文，45 字以内。只输出这句话本身，不要引号和解释。'
  ].join('\n\n');
}

function clean(text) {
  return String(text || '').split('\n').map(s => s.trim()).filter(Boolean).pop()?.replace(/^["“「]|["”」]$/g, '') || '';
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.show) throw new Error('需要 --show，比如 --show s2e1');
  const file = path.join(__dirname, '..', '..', 'shows', `${args.show}.json`);
  const show = JSON.parse(fs.readFileSync(file, 'utf8'));
  show.selfIntro = show.selfIntro || {};
  for (const c of getCharacters()) {
    if (args.only && !args.only.includes(c.id)) continue;
    if (show.selfIntro[c.id] && !args.force) continue;
    const id = `intro-${args.show}-${c.id}`;
    try {
      await ai.createAgent(id, c.name, c.provider, c.model, 0.7, c.effort);
      show.selfIntro[c.id] = clean(await ai.chat(id, prompt(c)));
      console.log(`${c.name}：${show.selfIntro[c.id]}`);
    } catch (error) {
      console.error(`${c.name} 自我介绍失败：${error.message}`);
    } finally {
      await ai.deleteAgent(id).catch(() => {});
    }
  }
  fs.writeFileSync(file, JSON.stringify(show, null, 2));
}

main().catch(error => {
  console.error(error.message);
  process.exit(1);
});
