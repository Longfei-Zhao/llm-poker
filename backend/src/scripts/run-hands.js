// 让一桌AI自己连打N手并记录回放。需要先启动AI服务。
// 用法: node src/scripts/run-hands.js --hands 20 [--seats claude,gpt,grok] [--stack 10000] [--blinds 50/100]
// 做节目用剧本发牌（run-show.js）；这个脚本是随机发牌、一桌连打
const aiService = require('../services/ai.service');
const { TableRunner } = require('../services/table-runner');
const { getCharacters } = require('../config/characters');
const config = require('../config');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

async function main() {
  const hands = parseInt(arg('hands', '10'), 10);
  const seats = arg('seats', '').split(',').map(s => s.trim()).filter(Boolean);
  const [sb, bb] = arg('blinds', '50/100').split('/').map(n => parseInt(n, 10));
  const runner = new TableRunner({
    ai: aiService,
    characters: getCharacters(seats),
    handsDir: config.HANDS_DIR,
    stack: parseInt(arg('stack', '10000'), 10),
    smallBlind: sb,
    bigBlind: bb
  });

  if (!(await aiService.checkHealth())) {
    console.error(`连不上AI服务(${config.AI_SERVICE_URL})，请先启动它`);
    process.exit(1);
  }

  await runner.run(hands, ({ file, log }, k) => {
    const winners = (log.result && log.result.winners || [])
      .map(w => `${log.players.find(p => p.id === w.playerId).name} +${w.amount}`).join(', ');
    console.log(`第 ${k} 手完成: ${winners} -> ${file}`);
  });
  await aiService.deleteAllAgents().catch(() => {});
  console.log(`回放已保存到 ${config.HANDS_DIR}，启动后端后打开 http://localhost:${config.PORT}/replay/`);
}

main().catch(error => {
  console.error(error.message);
  process.exit(1);
});
