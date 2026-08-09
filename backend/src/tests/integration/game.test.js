const WebSocket = require('ws');
const { WebSocketService } = require('../../services/ws.service');
const { GameController } = require('../../controllers/game.controller');
const { createServer } = require('http');

jest.setTimeout(120000); // 增加超时时间到120秒

describe('游戏流程集成测试', () => {
  let server;
  let wsService;
  let clients;
  let port;

  beforeAll((done) => {
    // 创建HTTP服务器
    server = createServer();
    wsService = new WebSocketService();
    wsService.initialize(server);

    // 启动服务器并监听随机端口
    server.listen(0, () => {
      port = server.address().port;
      console.log('Test server started on port:', port);
      // 等待WebSocket服务器完全启动
      setTimeout(() => {
        done();
      }, 1000);
    });
  });

  afterAll((done) => {
    // 关闭服务器
    server.close(() => {
      console.log('Test server closed');
      // 等待所有连接关闭
      setTimeout(() => {
        done();
      }, 1000);
    });
  });

  beforeEach((done) => {
    // 初始化客户端连接
    clients = {
      player1: new WebSocket(`ws://localhost:${port}`),
      player2: new WebSocket(`ws://localhost:${port}`),
      player3: new WebSocket(`ws://localhost:${port}`)
    };

    // 等待所有客户端连接建立
    let connectedClients = 0;
    Object.entries(clients).forEach(([playerId, client]) => {
      client.on('open', () => {
        connectedClients++;
        console.log(`${playerId} connected (${connectedClients}/3)`);
        if (connectedClients === 3) {
          // 等待连接稳定
          setTimeout(() => {
            done();
          }, 1000);
        }
      });

      // 添加错误处理
      client.on('error', (error) => {
        console.error(`${playerId} WebSocket error:`, error);
      });

      // 添加关闭处理
      client.on('close', () => {
        console.log(`${playerId} connection closed`);
      });
    });
  });

  afterEach((done) => {
    // 关闭所有客户端连接
    let closedClients = 0;
    Object.entries(clients).forEach(([playerId, client]) => {
      if (client.readyState === WebSocket.OPEN) {
        client.on('close', () => {
          closedClients++;
          console.log(`${playerId} closed (${closedClients}/3)`);
          if (closedClients === 3) {
            setTimeout(() => {
              done();
            }, 1000);
          }
        });
        client.close();
      } else {
        closedClients++;
        console.log(`${playerId} already closed (${closedClients}/3)`);
        if (closedClients === 3) {
          setTimeout(() => {
            done();
          }, 1000);
        }
      }
    });
  });

  test('错误处理', (done) => {
    // 测试无效的游戏ID
    clients.player1.send(JSON.stringify({
      type: 'join',
      payload: { playerId: 'player1', gameId: 'invalid-game-id' }
    }));

    clients.player1.on('message', (data) => {
      try {
        const message = JSON.parse(data);
        expect(message.type).toBe('error');
        expect(message.payload.message).toBe('Game not found');
        done();
      } catch (error) {
        done(error);
      }
    });
  });

  test('游戏创建和加入', (done) => {
    let gameId;
    const players = [
      { id: 'player1', name: 'Player 1', chips: 1000 },
      { id: 'player2', name: 'Player 2', chips: 1000 },
      { id: 'player3', name: 'Player 3', chips: 1000 }
    ];

    // 设置消息处理器
    const messageHandlers = new Map();
    Object.keys(clients).forEach(playerId => {
      messageHandlers.set(playerId, new Map());
    });

    // 为每个客户端设置消息监听
    Object.entries(clients).forEach(([playerId, client]) => {
      client.on('message', (data) => {
        try {
          const message = JSON.parse(data);
          console.log(`${playerId} received message:`, message.type);
          
          // 检查错误消息
          if (message.type === 'error') {
            console.error(`${playerId} received error:`, message.payload);
            done(message.payload);
            return;
          }

          const handler = messageHandlers.get(playerId).get(message.type);
          if (handler) {
            handler(message);
          }
        } catch (error) {
          done(error);
        }
      });
    });

    // 创建游戏
    messageHandlers.get('player1').set('gameCreated', (message) => {
      try {
        expect(message.type).toBe('gameCreated');
        gameId = message.payload.id;
        console.log('Game created:', gameId);

        // 所有玩家加入游戏
        Object.entries(clients).forEach(([playerId, client], index) => {
          setTimeout(() => {
            console.log(`${playerId} joining game...`);
            client.send(JSON.stringify({
              type: 'join',
              payload: { playerId, gameId }
            }));
          }, index * 500); // 错开加入时间
        });
      } catch (error) {
        done(error);
      }
    });

    // 处理游戏状态更新
    let joinedPlayers = 0;
    Object.keys(clients).forEach(playerId => {
      messageHandlers.get(playerId).set('gameState', (message) => {
        try {
          const gameState = message.payload;
          
          // 处理加入游戏的响应
          if (!gameState.state || gameState.state === 'waiting') {
            joinedPlayers++;
            console.log(`${playerId} joined game (${joinedPlayers}/3)`);

            if (joinedPlayers === 3) {
              // 验证游戏状态
              expect(gameState.id).toBe(gameId);
              expect(gameState.players).toHaveLength(3);
              expect(gameState.state).toBe('waiting');
              done();
            }
          }
        } catch (error) {
          done(error);
        }
      });
    });

    // 开始游戏流程
    console.log('Starting game creation');
    clients.player1.send(JSON.stringify({
      type: 'create',
      payload: { players }
    }));
  });

  test('完整游戏流程', (done) => {
    let gameId;
    const players = [
      { id: 'player1', name: 'Player 1', chips: 1000 },
      { id: 'player2', name: 'Player 2', chips: 1000 },
      { id: 'player3', name: 'Player 3', chips: 1000 }
    ];

    // 设置消息处理器
    const messageHandlers = new Map();
    Object.keys(clients).forEach(playerId => {
      messageHandlers.set(playerId, new Map());
    });

    // 为每个客户端设置消息监听
    Object.entries(clients).forEach(([playerId, client]) => {
      client.on('message', (data) => {
        try {
          const message = JSON.parse(data);
          console.log(`${playerId} received message:`, message.type);
          
          // 检查错误消息
          if (message.type === 'error') {
            console.error(`${playerId} received error:`, message.payload);
            done(message.payload);
            return;
          }

          const handler = messageHandlers.get(playerId).get(message.type);
          if (handler) {
            handler(message);
          }
        } catch (error) {
          done(error);
        }
      });
    });

    // 创建游戏
    messageHandlers.get('player1').set('gameCreated', (message) => {
      try {
        expect(message.type).toBe('gameCreated');
        gameId = message.payload.id;
        console.log('Game created:', gameId);

        // 所有玩家加入游戏
        Object.entries(clients).forEach(([playerId, client], index) => {
          setTimeout(() => {
            console.log(`${playerId} joining game...`);
            client.send(JSON.stringify({
              type: 'join',
              payload: { playerId, gameId }
            }));
          }, index * 500); // 错开加入时间
        });
      } catch (error) {
        done(error);
      }
    });

    // 处理游戏状态更新
    let joinedPlayers = 0;
    let gameStarted = false;
    let lastState = '';
    let actionCount = 0;
    const maxActions = 50; // 设置最大行动次数以防止无限循环

    Object.keys(clients).forEach(playerId => {
      messageHandlers.get(playerId).set('gameState', (message) => {
        try {
          const gameState = message.payload;
          
          // 处理加入游戏的响应
          if (!gameState.state || gameState.state === 'waiting') {
            if (!gameStarted) {
              joinedPlayers++;
              console.log(`${playerId} joined game (${joinedPlayers}/3)`);

              if (joinedPlayers === 3) {
                setTimeout(() => {
                  console.log('All players joined, starting game...');
                  gameStarted = true;
                  clients.player1.send(JSON.stringify({
                    type: 'start',
                    payload: { gameId }
                  }));
                }, 1000);
              }
            }
            return;
          }

          // 记录状态变化
          if (gameState.state !== lastState) {
            lastState = gameState.state;
            console.log(`Game state changed to: ${gameState.state}`);
            actionCount = 0; // 重置行动计数
          }

          // 验证游戏状态
          expect(gameState.id).toBe(gameId);
          expect(gameState.players).toHaveLength(3);
          expect(gameState.state).toBeDefined();

          // 如果是当前玩家的回合，执行行动
          const currentPlayer = gameState.players.find(p => p.isCurrent);
          if (currentPlayer && currentPlayer.id === playerId && gameState.state !== 'finished') {
            actionCount++;
            if (actionCount > maxActions) {
              done(new Error('Too many actions without game completion'));
              return;
            }

            console.log(`${playerId} acting in ${gameState.state} (action ${actionCount})`);
            
            setTimeout(() => {
              let action;
              const currentBet = gameState.currentBet || 0;
              
              // 根据游戏状态选择行动
              if (gameState.state === 'river' || actionCount > 30) {
                // 在河牌圈或行动次数过多时增加弃牌概率
                action = Math.random() < 0.6 ? 'fold' : 'call';
              } else {
                // 其他情况下的行动选择
                const rand = Math.random();
                if (rand < 0.2) {
                  action = 'fold';
                } else if (rand < 0.7) {
                  action = 'call';
                } else {
                  action = 'raise';
                }
              }

              const amount = action === 'raise' ? Math.min(currentBet * 2 + 1, currentPlayer.chips) : currentBet;
              
              console.log(`${playerId} performing action: ${action} with amount: ${amount}`);
              client.send(JSON.stringify({
                type: 'action',
                payload: {
                  gameId,
                  playerId,
                  action,
                  amount
                }
              }));
            }, 500);
          }

          // 如果游戏结束，调用done
          if (gameState.state === 'finished') {
            console.log('Game finished!');
            // 验证游戏结果
            expect(gameState.pot).toBe(0); // 奖池应该已经分配完
            expect(gameState.players.some(p => p.chips > 1000)).toBe(true); // 至少有一个玩家赢钱
            done();
          }
        } catch (error) {
          done(error);
        }
      });
    });

    // 开始游戏流程
    console.log('Starting game flow');
    clients.player1.send(JSON.stringify({
      type: 'create',
      payload: { players }
    }));
  });
}); 