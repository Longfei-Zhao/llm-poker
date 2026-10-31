process.env.LOG_LEVEL = 'silent';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { TableRunner } = require('../table-runner');

const characters = [
  { id: 'claude', name: '克劳德爵士', label: 'Claude', provider: 'anthropic', model: null, color: '#F08A5D', look: 'claude', persona: '老绅士' },
  { id: 'grok', name: '狂客', label: 'Grok', provider: 'xai', model: null, color: '#FF2E7E', look: 'grok', persona: '朋克少年' },
  { id: 'kimi', name: 'Kimi', label: 'Kimi', provider: 'moonshot', model: null, color: '#E5E7EB', look: 'kimi', persona: '学霸' }
];

function mockAI(decide) {
  return {
    createAgent: jest.fn().mockResolvedValue({}),
    getDecision: jest.fn((playerId, view, validActions, minBet, maxBet) => Promise.resolve(decide(playerId, view, validActions, minBet, maxBet)))
  };
}

describe('TableRunner', () => {
  let dir;
  beforeEach(() => { dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hands-')); });
  afterEach(() => { fs.rmSync(dir, { recursive: true, force: true }); });

  test('跑完一手后写出包含台词、心声和结算的回放记录', async () => {
    const ai = mockAI((playerId, view, validActions) => ({
      action: validActions.includes('check') ? 'check' : 'call',
      amount: 0,
      speech: `${playerId}说话`,
      inner: `${playerId}心声`
    }));
    const runner = new TableRunner({ ai, characters, handsDir: dir, stack: 1000, smallBlind: 5, bigBlind: 10 });
    const results = [];
    await runner.run(1, r => results.push(r));

    expect(results).toHaveLength(1);
    const log = JSON.parse(fs.readFileSync(results[0].file, 'utf8'));
    expect(log.players).toHaveLength(3);
    expect(log.players[0]).toMatchObject({ stack: 1000, look: expect.any(String) });
    expect(log.players.every(p => p.cards.length === 2)).toBe(true);
    expect(log.board).toHaveLength(5);
    expect(log.events.filter(e => e.t === 'board').map(e => e.street)).toEqual(['flop', 'turn', 'river']);
    const acts = log.events.filter(e => e.t === 'act');
    expect(acts.length).toBeGreaterThan(0);
    expect(acts[0]).toMatchObject({ sp: expect.stringContaining('说话'), in: expect.stringContaining('心声') });
    expect(log.result.winners.length).toBeGreaterThan(0);
    // 筹码守恒
    expect(Object.values(log.result.stacks).reduce((a, b) => a + b, 0)).toBe(3000);
  });

  test('人设和此前的台词会出现在发给AI的视图里，心声不会', async () => {
    const views = [];
    const ai = mockAI((playerId, view, validActions) => {
      views.push(view);
      return { action: validActions.includes('check') ? 'check' : 'call', amount: 0, speech: '来点刺激的', inner: '秘密' };
    });
    const runner = new TableRunner({ ai, characters, handsDir: dir, stack: 1000, smallBlind: 5, bigBlind: 10 });
    await runner.run(1);

    expect(views[0].persona).toBeTruthy();
    expect(views[0].tableTalk).toEqual([]);
    expect(views[1].tableTalk[0]).toMatchObject({ speech: '来点刺激的' });
    expect(JSON.stringify(views)).not.toContain('秘密');
    // 视图里只有行动玩家自己的手牌
    expect(views[0].players.filter(p => p.cards.length > 0)).toHaveLength(1);
  });

  test('AI给出非法动作或调用失败时用默认动作并标记corrected', async () => {
    let n = 0;
    const ai = mockAI(() => {
      n++;
      if (n === 1) return Promise.reject(new Error('timeout'));
      return { action: 'steal', amount: 0 };
    });
    const runner = new TableRunner({ ai, characters, handsDir: dir, stack: 1000, smallBlind: 5, bigBlind: 10 });
    const results = [];
    await runner.run(1, r => results.push(r));
    const acts = results[0].log.events.filter(e => e.t === 'act');
    expect(acts.some(a => a.corrected)).toBe(true);
    expect(results[0].log.result).toBeTruthy();
  });

  test('角色无法创建代理时跳过，不足两人报错', async () => {
    const ai = mockAI(() => ({ action: 'fold' }));
    ai.createAgent.mockRejectedValueOnce(new Error('no key')).mockRejectedValueOnce(new Error('no key'));
    const runner = new TableRunner({ ai, characters, handsDir: dir });
    await expect(runner.run(1)).rejects.toThrow('不足两人');
  });

  test('连打多手时按钮轮转且记录编号递增', async () => {
    const ai = mockAI((playerId, view, validActions) => ({ action: validActions.includes('check') ? 'check' : 'fold', amount: 0 }));
    const runner = new TableRunner({ ai, characters, handsDir: dir, stack: 1000, smallBlind: 5, bigBlind: 10 });
    const logs = [];
    await runner.run(3, r => logs.push(r.log));
    expect(logs.map(l => l.hand)).toEqual([1, 2, 3]);
    expect(new Set(logs.map(l => l.button)).size).toBeGreaterThan(1);
    expect(fs.readdirSync(dir)).toHaveLength(3);
  });
});
