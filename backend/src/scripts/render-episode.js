// 把整集录成视频：用本机 Chrome 打开回放页的渲染模式（?render，只留舞台，1920×1080），
// 画面用无头 Chrome 的标签页录屏，声音录页面里 Web Audio 汇总的那一路，实时录下来再用 ffmpeg 转成 MP4。整集多长就要录多久。
// 用法：node src/scripts/render-episode.js --show s2e1 [--seconds 30] [--out 路径.mp4]
// 需要：后端在跑（默认 http://localhost:3000，可用 --base 改），本机装了 Chrome（CHROME_PATH 可改路径）和 ffmpeg。
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const puppeteer = require('puppeteer-core');
const config = require('../config');

const CHROME = process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe';

function parseArgs(argv) {
  const args = { show: null, seconds: 0, out: null, base: 'http://localhost:3000' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--show') args.show = argv[++i];
    else if (argv[i] === '--seconds') args.seconds = Number(argv[++i]);
    else if (argv[i] === '--out') args.out = argv[++i];
    else if (argv[i] === '--base') args.base = argv[++i];
  }
  return args;
}

function ffmpeg(args) {
  return new Promise((resolve, reject) => execFile('ffmpeg', ['-y', '-loglevel', 'error', ...args], { maxBuffer: 1 << 24 }, err => (err ? reject(err) : resolve())));
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.show) throw new Error('需要 --show，比如 --show s2e1');
  const outDir = path.join(path.dirname(config.HANDS_DIR), 'renders');
  fs.mkdirSync(outDir, { recursive: true });
  const out = args.out || path.join(outDir, `${args.show}${args.seconds ? `-test${args.seconds}s` : ''}.mp4`);
  const webm = out.replace(/\.mp4$/, '.webm');
  const file = fs.createWriteStream(webm);

  // 单独的临时用户目录，不碰本机正在用的 Chrome；页面在后台也不降速
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: process.env.RENDER_HEADFUL ? false : true,
    userDataDir: fs.mkdtempSync(path.join(os.tmpdir(), 'llm-poker-render-')),
    defaultViewport: { width: 1920, height: 1080, deviceScaleFactor: 1 },
    args: [
      '--window-size=1940,1200', '--hide-scrollbars', '--no-first-run', '--no-default-browser-check',
      // 只自动同意“录当前标签页”，不能用 --use-fake-ui-for-media-stream（那会直接选整个屏幕）
      '--autoplay-policy=no-user-gesture-required', '--auto-accept-this-tab-capture', '--auto-select-tab-capture-source-by-title=大模型德州回放',
      '--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding'
    ]
  });
  try {
    const page = (await browser.pages())[0] || await browser.newPage();
    page.on('pageerror', e => console.error('页面报错：', e.message));
    await page.exposeFunction('__chunk', b64 => new Promise(r => file.write(Buffer.from(b64, 'base64'), r)));
    await page.goto(`${args.base}/replay/?render=1#${args.show}-001`, { waitUntil: 'networkidle0' });
    console.log('等页面算好时长、加载完声音…');
    await page.waitForFunction('window.__ready === true', { timeout: 180000, polling: 500 });

    // 开始录：标签页画面 + 页面声音，VP9/Opus 高码率，每秒交一块数据回来写盘
    await page.evaluate(async () => {
      const stream = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: 30, width: 1920, height: 1080 },
        audio: false,
        preferCurrentTab: true, selfBrowserSurface: 'include', systemAudio: 'exclude', surfaceSwitching: 'exclude', monitorTypeSurfaces: 'exclude'
      });
      // 只许录这个标签页：拿到的不是标签页（比如整个屏幕）就立刻停掉，绝不录别的东西
      const settings = stream.getVideoTracks()[0].getSettings();
      if (settings.displaySurface !== 'browser') {
        stream.getTracks().forEach(t => t.stop());
        throw new Error(`拿到的录制源是 ${settings.displaySurface}，不是这个标签页，已停止`);
      }
      // 声音不从标签页录（无头模式没有声音输出），用页面里 Web Audio 汇总出来的那一路
      if (AC.state !== 'running') await AC.resume();
      if (AC.state !== 'running') { stream.getTracks().forEach(t => t.stop()); throw new Error(`页面声音没起来（${AC.state}），已停止`); }
      const mixed = new MediaStream([...stream.getVideoTracks(), ...window.__audioStream().getAudioTracks()]);
      const rec = new MediaRecorder(mixed, { mimeType: 'video/webm;codecs=vp9,opus', videoBitsPerSecond: 16000000, audioBitsPerSecond: 192000 });
      let queue = Promise.resolve();
      rec.ondataavailable = e => {
        if (!e.data.size) return;
        queue = queue.then(async () => {
          const bytes = new Uint8Array(await e.data.arrayBuffer());
          let bin = '';
          for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
          await window.__chunk(btoa(bin));
        });
      };
      rec.onstop = () => { queue.then(() => { window.__stopped = true; }); mixed.getTracks().forEach(t => t.stop()); };
      window.__rec = rec;
      rec.start(1000);
    });
    await sleep(800);
    await page.evaluate(() => window.__play());
    const t0 = Date.now();
    console.log('开始录制');
    if (args.seconds) {
      await sleep(args.seconds * 1000);
    } else {
      // 整集放完（片尾视频播完）再多录一秒
      while (!(await page.evaluate(() => window.__epDone === true))) {
        await sleep(2000);
        const sec = Math.round((Date.now() - t0) / 1000);
        if (sec % 60 < 2) console.log(`已录 ${Math.floor(sec / 60)} 分钟`);
      }
      await sleep(1000);
    }
    await page.evaluate(() => window.__rec.stop());
    await page.waitForFunction('window.__stopped === true', { timeout: 60000, polling: 300 });
  } finally {
    await browser.close();
    await new Promise(r => file.end(r));
  }

  // 录下来的 webm 是变帧率的，转成 30fps 定帧率的 H.264 + AAC
  console.log('转码成 MP4…');
  // 开头 0.8 秒是开录到开播之间的黑场，剪掉 0.7 秒
  await ffmpeg(['-ss', '0.7', '-i', webm, '-r', '30', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
    '-af', 'alimiter=limit=0.89:level=false', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', out]);
  fs.unlinkSync(webm);
  console.log(`完成 -> ${out}`);
}

main().catch(error => {
  console.error(error.message);
  process.exit(1);
});
