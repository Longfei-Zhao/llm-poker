// 后端主入口文件
const express = require('express');
const http = require('http');
const cors = require('cors');
const WebSocket = require('ws');
const { WebSocketService } = require('./services/ws.service');
const aiService = require('./services/ai.service');
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

// 创建HTTP服务器
const server = http.createServer(app);

// 创建WebSocket服务器
const wss = new WebSocket.Server({ server });

// 初始化WebSocket服务
const wsService = new WebSocketService();
wsService.initialize(wss);

// 启动服务器
server.listen(PORT, () => {
  console.log(`服务器已启动，监听端口 ${PORT}`);
  console.log(`健康检查: http://localhost:${PORT}/api/health`);
});

// 处理未捕获的异常
process.on('uncaughtException', (error) => {
  console.error('未捕获的异常:', error);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('未处理的拒绝:', reason);
}); 