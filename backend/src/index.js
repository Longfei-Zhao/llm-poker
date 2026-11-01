// 后端主入口文件
const express = require('express');
const http = require('http');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const WebSocket = require('ws');
const { WebSocketService } = require('./services/ws.service');
const aiService = require('./services/ai.service');
const logger = require('./utils/logger');
const config = require('./config');
require('dotenv').config();

// 创建Express应用
const app = express();
const PORT = process.env.PORT || 3000;

// 中间件
app.use(cors());
app.use(express.json());

// 状态检查路由
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', message: '后端服务运行正常' });
});

// 简单的API路由
app.get('/api/info', (req, res) => {
  res.json({
    name: 'LLM Poker Backend',
    version: '1.0.0',
    description: '为大模型德州扑克游戏提供后端支持',
  });
});

// AI服务代理路由
// 创建AI代理
app.post('/api/agents', async (req, res) => {
  try {
    const { player_id, name, provider, model, temperature } = req.body;
    const result = await aiService.createAgent(player_id, name, provider, model, temperature);
    res.status(201).json(result);
  } catch (error) {
    console.error('创建AI代理失败:', error);
    res.status(500).json({ error: error.message || '创建AI代理失败' });
  }
});

// 获取AI决策
app.post('/api/decision', async (req, res) => {
  try {
    const { player_id, game_state, valid_actions, min_bet, max_bet } = req.body;
    const result = await aiService.getDecision(player_id, game_state, valid_actions, min_bet, max_bet);
    res.json(result);
  } catch (error) {
    console.error('获取AI决策失败:', error);
    res.status(500).json({ error: error.message || '获取AI决策失败' });
  }
});

// 删除AI代理
app.delete('/api/agents/:playerId', async (req, res) => {
  try {
    const { playerId } = req.params;
    await aiService.deleteAgent(playerId);
    res.json({ status: 'ok' });
  } catch (error) {
    console.error('删除AI代理失败:', error);
    res.status(500).json({ error: error.message || '删除AI代理失败' });
  }
});

// 删除所有AI代理
app.delete('/api/agents', async (req, res) => {
  try {
    await aiService.deleteAllAgents();
    res.json({ status: 'ok', message: '所有AI代理已删除' });
  } catch (error) {
    console.error('删除所有AI代理失败:', error);
    res.status(500).json({ error: error.message || '删除所有AI代理失败' });
  }
});

// 获取AI代理列表
app.get('/api/agents', async (req, res) => {
  try {
    const agents = await aiService.listAgents();
    res.json(agents);
  } catch (error) {
    console.error('获取AI代理列表失败:', error);
    res.status(500).json({ error: error.message || '获取AI代理列表失败' });
  }
});

// 回放：列出已记录的手牌，按开始时间倒序
app.get('/api/hands', (req, res) => {
  let files = [];
  try {
    files = fs.readdirSync(config.HANDS_DIR).filter(f => f.endsWith('.json'));
  } catch (error) {
    return res.json([]);
  }
  const hands = [];
  for (const f of files) {
    try {
      const log = JSON.parse(fs.readFileSync(path.join(config.HANDS_DIR, f), 'utf8'));
      const name = id => (log.players.find(p => p.id === id) || {}).name || id;
      hands.push({
        id: log.id,
        session: log.session,
        hand: log.hand,
        title: log.title || null,
        startedAt: log.startedAt,
        players: log.players.length,
        winners: ((log.result && log.result.winners) || []).map(w => ({ name: name(w.playerId), amount: w.amount }))
      });
    } catch (error) {
      logger.warn(`无法读取回放文件${f}: ${error.message}`);
    }
  }
  hands.sort((a, b) => String(b.startedAt).localeCompare(String(a.startedAt)));
  res.json(hands);
});

// 回放：读取单手记录
app.get('/api/hands/:id', (req, res) => {
  const { id } = req.params;
  if (!/^[\w-]+$/.test(id)) return res.status(400).json({ error: '无效的手牌ID' });
  const file = path.join(config.HANDS_DIR, `${id}.json`);
  if (!fs.existsSync(file)) return res.status(404).json({ error: '找不到这一手' });
  res.type('application/json').send(fs.readFileSync(file, 'utf8'));
});

// 回放页面
app.use('/replay', express.static(path.join(__dirname, '..', 'public', 'replay')));
app.use('/voice', express.static(config.VOICE_DIR));

// 创建HTTP服务器
const server = http.createServer(app);

// 创建WebSocket服务器
const wss = new WebSocket.Server({ server });

// 初始化WebSocket服务
const wsService = new WebSocketService();
wsService.initialize(wss);

// 启动服务器
server.listen(PORT, () => {
  logger.info(`服务器已启动，监听端口 ${PORT}`);
  logger.info(`健康检查: http://localhost:${PORT}/api/health`);
});

// 未捕获异常时状态已不可信，记录后退出，交给进程管理器重启
process.on('uncaughtException', (error) => {
  logger.error('未捕获的异常，进程退出:', error);
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  logger.error('未处理的拒绝:', reason);
});

// 优雅关闭
function shutdown(signal) {
  logger.info(`收到${signal}，正在关闭服务器...`);
  wss.clients.forEach(client => client.terminate());
  wss.close();
  server.close(() => {
    logger.info('服务器已关闭');
    process.exit(0);
  });
  // 兜底：5秒内未关闭则强制退出
  setTimeout(() => process.exit(0), 5000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM')); 