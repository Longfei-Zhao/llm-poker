// 按剧本跑一集：剧本里每一手的底牌、公共牌、庄家都是事先设计好的，牌怎么打由模型自己决定。
// 每一手都是独立的局面，所以同时跑。需要先启动AI服务。
// 用法: node src/scripts/run-show.js --show s2e1 [--only 2,5] [--parallel 4]
const aiService = require('../services/ai.service');
const { TableRunner } = require('../services/table-runner');
const { getCharacters } = require('../config/characters');
const { loadShow } = require('../services/scenario');
const config = require('../config');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

async function main() {
  const name = arg('show', 's2e1');
  const show = loadShow(name);
  const only = arg('only', '').split(',').map(n => parseInt(n, 10)).filter(Boolean);
  const parallel = Math.max(1, parseInt(arg('parallel', '4'), 10));
  const [sb, bb] = show.blinds || [50, 100];
  const jobs = show.hands.map((scenario, k) => ({ scenario, handNo: k + 1 })).filter(j => !only.length || only.includes(j.handNo));

  if (!(await aiService.checkHealth())) {
    console.error(`连不上AI服务(${config.AI_SERVICE_URL})，请先启动它`);
    process.exit(1);
  }

  // 同时最多跑parallel手；每一手用自己的一组代理，互不干扰
  const queue = [...jobs];
  const worker = async () => {
    while (queue.length) {
      const { scenario, handNo } = queue.shift();
      const runner = new TableRunner({
        ai: aiService,
        characters: getCharacters(),
        handsDir: config.HANDS_DIR,
        stack: show.stack || 10000,
        smallBlind: sb,
        bigBlind: bb,
        session: name,
        agentPrefix: `${name}-${handNo}-`
      });
      try {
        await runner.setup();
        const { file, log } = await runner.playScenario(scenario, handNo);
        const winners = (log.result && log.result.winners || [])
          .map(w => `${log.players.find(p => p.id === w.playerId).name} +${w.amount}`).join(', ');
        console.log(`第 ${handNo} 手「${scenario.title}」完成: ${winners} -> ${file}`);
      } catch (error) {
        console.error(`第 ${handNo} 手「${scenario.title}」失败: ${error.message}`);
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(parallel, jobs.length) }, worker));
  await aiService.deleteAllAgents().catch(() => {});
  console.log(`回放已保存到 ${config.HANDS_DIR}，打开 http://localhost:${config.PORT}/replay/`);
}

main().catch(error => {
  console.error(error.message);
  process.exit(1);
});
