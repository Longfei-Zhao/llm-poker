// 给录好的手牌配音：只配回放画面上会放的台词和心声（和回放页共用同一个导演），
// 文字先转成中文念法，音色用characters.js里的MiniMax预设音色，心声再做一层后期。
// 用法：node src/scripts/voice-hands.js --session s2e1 [--only 2,5] [--dry]
// 已经配过、文字没变的句子直接复用，不会重复花钱。
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const config = require('../config');
const { CHARACTERS } = require('../config/characters');
const { toSpoken } = require('../services/spoken-text');
const { direct } = require('../../public/replay/director');

require('dotenv').config({ path: path.join(__dirname, '..', '..', '..', 'ai_service', '.env') });

const TTS_URL = 'https://fal.run/fal-ai/minimax/speech-2.8-hd';
const PRICE_PER_1K = 0.1;
// 台词稍快带情绪；心声放慢放轻、语气平，再削掉刺耳的高频、加一点混响、左右声道错开，听起来像在脑子里
const TALK = { speed: 1.05, vol: 1, pitch: 0 };
const INNER = { speed: 0.92, vol: 0.8, pitch: -1, emotion: 'neutral' };
const INNER_FX = 'highpass=f=120,lowpass=f=6000,equalizer=f=3000:t=q:w=1.5:g=-2,'
  + 'aecho=0.8:0.8:70|120|180:0.14|0.09|0.05,pan=stereo|c0=c0|c1=c0,adelay=0|16,loudnorm=I=-18';

function parseArgs(argv) {
  const args = { session: null, only: null, dry: false, parallel: 4 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--session') args.session = argv[++i];
    else if (argv[i] === '--only') args.only = argv[++i].split(',').map(Number);
    else if (argv[i] === '--dry') args.dry = true;
    else if (argv[i] === '--parallel') args.parallel = Number(argv[++i]);
  }
  return args;
}

// 一手牌里要配的句子：say配台词，think配心声，full两句都配
function linesOf(log) {
  const lines = [];
  for (const shot of direct(log).shots) {
    if (shot.t !== 'act' || shot.show === 'none') continue;
    const who = log.players[shot.p].id;
    if ((shot.show === 'say' || shot.show === 'full') && shot.sp) lines.push({ k: shot.ev, kind: 'sp', who, text: toSpoken(shot.sp) });
    if ((shot.show === 'think' || shot.show === 'full') && shot.in) lines.push({ k: shot.ev, kind: 'in', who, text: toSpoken(shot.in) });
  }
  return lines.filter(l => l.text);
}

async function tts(text, voice, setting) {
  const res = await fetch(TTS_URL, {
    method: 'POST',
    headers: { Authorization: `Key ${process.env.FAL_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      prompt: text,
      voice_setting: { voice_id: voice.id, ...setting },
      language_boost: 'Chinese',
      output_format: 'url'
    })
  });
  if (!res.ok) throw new Error(`TTS ${res.status} ${(await res.text()).slice(0, 200)}`);
  const audio = await fetch((await res.json()).audio.url);
  return Buffer.from(await audio.arrayBuffer());
}

function ffmpeg(args) {
  return new Promise((resolve, reject) => execFile('ffmpeg', ['-y', '-loglevel', 'error', ...args], err => (err ? reject(err) : resolve())));
}

async function voiceLine(line, dir) {
  const voice = CHARACTERS.find(c => c.id === line.who).voice;
  const file = `${line.k}-${line.kind}.mp3`;
  if (line.kind === 'sp') {
    fs.writeFileSync(path.join(dir, file), await tts(line.text, voice, { ...TALK, ...(voice.emotion ? { emotion: voice.emotion } : {}) }));
  } else {
    const raw = path.join(dir, `${line.k}-in-raw.mp3`);
    fs.writeFileSync(raw, await tts(line.text, voice, INNER));
    await ffmpeg(['-i', raw, '-af', INNER_FX, '-ar', '44100', path.join(dir, file)]);
    fs.unlinkSync(raw);
  }
  return file;
}

async function pool(items, size, fn) {
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(size, items.length) }, async () => {
    while (next < items.length) await fn(items[next++]);
  }));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.session) throw new Error('需要 --session，比如 --session s2e1');
  const logs = fs.readdirSync(config.HANDS_DIR)
    .filter(f => f.endsWith('.json'))
    .map(f => JSON.parse(fs.readFileSync(path.join(config.HANDS_DIR, f), 'utf8')))
    .filter(l => l.session === args.session && (!args.only || args.only.includes(l.hand)))
    .sort((a, b) => a.hand - b.hand);
  if (!logs.length) throw new Error(`没有找到 ${args.session} 的手牌记录`);

  let total = 0, todo = 0;
  const jobs = [];
  for (const log of logs) {
    const dir = path.join(config.VOICE_DIR, log.id);
    const manifestFile = path.join(dir, 'manifest.json');
    const old = fs.existsSync(manifestFile) ? JSON.parse(fs.readFileSync(manifestFile, 'utf8')) : {};
    const manifest = {};
    const lines = linesOf(log);
    for (const line of lines) {
      total += line.text.length;
      const prev = old[line.k] && old[line.k][line.kind];
      manifest[line.k] = manifest[line.k] || {};
      if (prev && prev.text === line.text && fs.existsSync(path.join(dir, prev.file))) {
        manifest[line.k][line.kind] = prev;
      } else {
        todo += line.text.length;
        jobs.push({ line, dir, manifest });
      }
    }
    jobs.push({ save: true, dir, manifestFile, manifest, log });
  }
  console.log(`${logs.length} 手，${jobs.filter(j => j.line).length} 句要配，${todo} 字（全部 ${total} 字），约 $${(todo / 1000 * PRICE_PER_1K).toFixed(3)}`);
  if (args.dry) return;
  if (!process.env.FAL_KEY) throw new Error('没有 FAL_KEY');

  await pool(jobs.filter(j => j.line), args.parallel, async ({ line, dir, manifest }) => {
    fs.mkdirSync(dir, { recursive: true });
    try {
      manifest[line.k][line.kind] = { file: await voiceLine(line, dir), text: line.text };
    } catch (error) {
      console.error(`第 ${line.k} 个事件（${line.who} ${line.kind}）配音失败：${error.message}`);
    }
  });
  for (const { dir, manifestFile, manifest, log } of jobs.filter(j => j.save)) {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, 2));
    console.log(`第 ${log.hand} 手配音完成 -> ${dir}`);
  }
}

main().catch(error => {
  console.error(error.message);
  process.exit(1);
});
