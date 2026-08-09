import 'dart:async';
import 'dart:math' show min, Random;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';  // 导入SVG支持
import '../components/game_table.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../services/ai_service.dart'; // 导入AI服务
import '../services/websocket_service.dart'; // 导入WebSocket服务

class GameScreen extends StatefulWidget {
  final String gameId;
  final String playerId;
  final String playerName;
  
  const GameScreen({
    Key? key,
    required this.gameId,
    required this.playerId,
    required this.playerName,
  }) : super(key: key);
  
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  // 游戏状态
  late GameState _gameState;
  Player? _currentPlayer;
  
  // 服务
  late AIService _aiService;
  late WebSocketService _wsService;
  
  // 游戏状态订阅
  StreamSubscription<Map<String, dynamic>>? _gameStateSubscription;
  
  // 连接状态
  bool _isLoadingModels = false;
  String _loadingMessage = '';
  
  // AI连接状态映射
  final Map<String, AIServiceStatus> _aiConnectionStatus = {};
  
  // 存储上一次的游戏状态，用于避免重复通知
  String? _lastGameState;
  
  // 连接状态
  bool _isGameActive = false;
  bool _isCreatingGame = false;
  
  // 连接状态
  bool _wsConnected = false;
  
  // 加载状态
  bool _isLoading = false;
  
  bool _isShowingRules = false;
  
  // 可用的AI模型列表
  final List<String> aiModels = [
    'ChatGPT-Mini',
    'ChatGPT-4O',
    'Claude',
    'Grok',
    'Gemini',
    'DeepSeek',
    'Sonar',
    'Qwen',
  ];

  // AI模型颜色映射
  final Map<String, Color> aiModelColors = {
    'ChatGPT-Mini': Color(0xFF74AA9C),
    'ChatGPT-4O': Color(0xFF10A37F),
    'Claude': Color(0xFF7F5BEB),
    'Grok': Color(0xFFFF0000),
    'Gemini': Color(0xFF1A73E8),
    'DeepSeek': Color(0xFF4B5563),
    'Sonar': Color(0xFF5B21B6),
    'Qwen': Color(0xFF1677FF),
  };

  // AI模型Logo映射
  final Map<String, String> aiModelLogos = {
    'ChatGPT-Mini': 'assets/images/llm_logos/openai.svg',
    'ChatGPT-4O': 'assets/images/llm_logos/openai.svg',
    'Claude': 'assets/images/llm_logos/anthropic.svg',
    'Grok': 'assets/images/llm_logos/xai.svg',
    'Gemini': 'assets/images/llm_logos/google.svg',
    'DeepSeek': 'assets/images/llm_logos/deepseek.svg',
    'Sonar': 'assets/images/llm_logos/perplexity.svg',
    'Qwen': 'assets/images/llm_logos/aliyun.svg',
  };
  
  @override
  void initState() {
    super.initState();
    _initGameState();
    _initServices();
    
    // 初始化上一次游戏状态为空
    _lastGameState = null;
    
    // 添加游戏状态更新的监听，使用_onGameStateUpdate处理所有游戏状态相关消息
    _gameStateSubscription = _wsService.gameStateStream.listen(_onGameStateUpdate);
  }
  
  // 初始化游戏状态
  void _initGameState() {
    // 初始化游戏状态
    setState(() {
      _gameState = GameState(
        id: 'game1',
        players: [],
        communityCards: [],
        pot: 0,
        currentBet: 0,
        currentPlayerIndex: -1,
        dealerIndex: 0,
        stage: GameStage.waiting,
        smallBlind: 10,
        bigBlind: 20,
      );
    });
  }
  
  // 初始化服务
  void _initServices() {
    // 初始化AI服务
    _aiService = AIService();
    
    // 订阅AI状态变化
    _aiService.statusNotifier.addListener(_onAIStatusChanged);
    _aiService.errorNotifier.addListener(_onAIError);
    
    // 检查AI服务健康状态
    _checkAIServiceHealth();
    
    // 初始化WebSocket服务
    _wsService = WebSocketService();
    
    // 使用Future.microtask确保初始化在同一帧内完成，但在构建之后
    Future.microtask(() {
    // 异步连接WebSocket
    _connectWebSocket();
    
    // 监听WebSocket状态变化
    _wsService.connectionStatusNotifier.addListener(_onWSStatusChanged);
      
      // 监听WebSocket错误信息
      _wsService.errorMessageNotifier.addListener(_onWSErrorChanged);
      
      // 监听WebSocket重连尝试次数
      _wsService.reconnectAttemptsNotifier.addListener(_onReconnectAttemptsChanged);
      
      // 监听WebSocket发送的错误
      _wsService.errorStream.listen(_onWSError);
    
    // 监听WebSocket发送的AI代理错误
    _wsService.aiAgentErrorStream.listen(_onAIAgentError);
    
    // 监听WebSocket发送的AI代理创建成功
    _wsService.aiAgentCreatedStream.listen(_onAIAgentCreated);
    
    // 监听玩家操作处理结果
    _wsService.playerActionStream.listen(_onPlayerActionProcessed);
    });
  }
  
  // WebSocket错误信息变化监听
  void _onWSErrorChanged() {
    final errorMsg = _wsService.errorMessageNotifier.value;
    if (errorMsg != null && mounted) {
      setState(() {
        // 可以在状态面板中显示错误信息
      });
      
      // 如果是严重错误，显示提示
      if (_wsService.connectionStatusNotifier.value == WSConnectionStatus.failed) {
        _showWebSocketError(errorMsg);
      }
    }
  }
  
  // WebSocket重连尝试次数监听
  void _onReconnectAttemptsChanged() {
    final attempts = _wsService.reconnectAttemptsNotifier.value;
    if (mounted && attempts > 0) {
      setState(() {
        // 可以在状态面板中显示重连次数
      });
    }
  }
  
  // 处理WebSocket错误
  void _onWSError(String error) {
    if (mounted) {
      print('📛 收到WebSocket错误: $error');
      // 可以在UI中显示更详细的错误信息或添加到错误日志
    }
  }
  
  // 连接WebSocket
  Future<void> _connectWebSocket() async {
    // 使用安全的context访问方法
    void showConnectingSnackBar() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20, 
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
                SizedBox(width: 10),
                Text('正在连接服务器...'),
            ],
          ),
          duration: Duration(seconds: 2),
            backgroundColor: Colors.blue.shade700,
            behavior: SnackBarBehavior.fixed, // 添加固定行为
        ),
      );
      }
    }
    
    // 显示连接中提示
    showConnectingSnackBar();
    
    try {
    // 尝试连接
      final success = await _wsService.connect();
    
    if (mounted) {
        if (success) {
          // 连接成功，显示成功消息
          setState(() {
            _wsConnected = true;
          });
          
          // 请求游戏状态
          _wsService.getGameState();
          
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                  Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('已连接到游戏服务器'),
              ],
            ),
            duration: Duration(seconds: 2),
              backgroundColor: Colors.green.shade900,
          ),
        );
      } else {
          // 连接失败，不显示提示，因为错误监听器会处理
          setState(() {
            _wsConnected = false;
          });
        }
      }
    } catch (e) {
      // 处理连接过程中的异常
      print('❌ WebSocket连接过程中发生异常: $e');
      
      if (mounted) {
        setState(() {
          _wsConnected = false;
        });
        
        _showWebSocketError('连接失败: $e');
      }
    }
  }
  
  // 显示WebSocket错误弹窗
  void _showWebSocketError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('WebSocket错误: $message'),
          backgroundColor: Colors.red.shade700,
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }
  
  // 处理手动重连
  Future<void> _handleManualReconnect() async {
    if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
              SizedBox(
                width: 20, 
                height: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2.0,
                ),
              ),
                SizedBox(width: 8),
              Text('正在尝试重新连接...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
      
      try {
        final success = await _wsService.manualReconnect();
        
        if (mounted) {
          setState(() {
            _wsConnected = success;
          });
          
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('重新连接成功'),
                  ],
                ),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green.shade900,
              ),
            );
            
            // 请求游戏状态
            _wsService.getGameState();
          }
        }
      } catch (e) {
        print('❌ 手动重连过程中发生异常: $e');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Text('重新连接失败: ${e.toString()}'),
                ],
              ),
            duration: Duration(seconds: 3),
              backgroundColor: Colors.red.shade900,
            ),
          );
        }
      }
    }
  }
  
  // WebSocket状态变化监听
  void _onWSStatusChanged() {
    if (!mounted) return;
    
    final status = _wsService.connectionStatusNotifier.value;
    
    setState(() {
      _wsConnected = status == WSConnectionStatus.connected;
    });
    
    // 根据不同状态进行处理
    switch (status) {
      case WSConnectionStatus.connected:
        // 连接成功，已在连接方法中处理
        break;
        
      case WSConnectionStatus.disconnected:
        // 断开连接，可以显示提示
        break;
        
      case WSConnectionStatus.reconnecting:
        // 重连中，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16, 
                  height: 16,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2.0,
                  ),
                ),
                SizedBox(width: 8),
                Text('正在尝试重新连接(${_wsService.reconnectAttemptsNotifier.value})...'),
              ],
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange.shade900,
          ),
        );
        break;
        
      case WSConnectionStatus.failed:
        // 连接失败，已通过错误通知处理
        break;
        
      case WSConnectionStatus.connecting:
        // 正在连接中
        break;
    }
  }
  
  // AI状态变化处理
  void _onAIStatusChanged() {
    // 这里可以根据AI状态更新UI
    if (_aiService.statusNotifier.value == AIServiceStatus.error) {
      // 显示错误
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_aiService.errorNotifier.value ?? '发生未知错误'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  // AI错误处理
  void _onAIError() {
    if (_aiService.errorNotifier.value != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_aiService.errorNotifier.value!),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  
  // 处理游戏状态更新
  void _onGameStateUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    final String messageType = data['type']?.toString() ?? 'unknown';
    print('收到游戏状态更新消息类型: $messageType');

    try {
      // 处理游戏重置消息
      if (messageType == 'gameReset') {
        print('收到游戏重置消息，重置游戏ID和玩家列表');
    setState(() {
          _gameState = _gameState.copyWith(
            id: 'game1',
            players: [],
            stage: GameStage.waiting,
            communityCards: [],
            pot: 0,
            currentBet: 0,
            currentPlayerIndex: -1
          );
          _currentPlayer = null;
        });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('游戏已重置'),
            backgroundColor: Colors.blue.shade700,
            behavior: SnackBarBehavior.fixed,
          ),
        );
        return;
      }

      // 处理gameCreated消息
      if (messageType == 'gameCreated') {
        print('处理gameCreated消息');

        Map<String, dynamic>? backendGameState = data['gameState'];
        if (backendGameState == null) {
          print('错误: gameCreated消息中没有gameState字段');
          _showErrorSnackBar('接收到的游戏创建消息格式错误');
          return;
        }

        // 记录原始数据，用于调试
        final String jsonString = backendGameState.toString().length > 200 
            ? '${backendGameState.toString().substring(0, 200)}...' 
            : backendGameState.toString();
        print('gameCreated消息中的gameState: $jsonString');

        try {
          // 从返回的数据中提取游戏ID
          final String newGameId = backendGameState['id']?.toString() ??
              backendGameState['gameId']?.toString() ??
              'game${DateTime.now().millisecondsSinceEpoch}';

          print('从gameCreated消息获取到游戏ID: $newGameId');

          // 保存现有玩家的aiModel和position信息
          Map<String, Player> existingPlayersMap = {};
          for (var player in _gameState.players) {
            existingPlayersMap[player.id] = player;
            print('保存现有玩家信息: ID=${player.id}, 位置=${player.position}, 模型=${player.aiModel}');  
          }

          // 从gameState中提取玩家列表
          List<dynamic> backendPlayers = backendGameState['players'] as List? ?? [];
          print('从gameCreated消息获取到玩家数: ${backendPlayers.length}');

          // 对后端返回的玩家列表进行检查
          if (backendPlayers.isEmpty && existingPlayersMap.isNotEmpty) {
            print('后端返回空玩家列表，但我们有现有玩家，使用现有玩家');
            
            // 仅更新游戏ID和状态，保留现有玩家
    setState(() {
              _gameState = _gameState.copyWith(
                id: newGameId,
                stage: GameStage.waiting,
                pot: backendGameState['pot'] ?? 0,
                currentBet: backendGameState['currentBet'] ?? 0,
              );
              _currentPlayer = _gameState.currentPlayer;
            });
          } else {
            // 创建新的GameState对象
            final GameState updatedGameState = GameState.fromJson(backendGameState);
            
            // 如果解析后的玩家列表为空，但我们有现有玩家，保留现有玩家
            if (updatedGameState.players.isEmpty && existingPlayersMap.isNotEmpty) {
              print('GameState.fromJson解析后玩家列表为空，使用现有玩家');
              
              setState(() {
                _gameState = updatedGameState.copyWith(
                  players: _gameState.players
                );
                _currentPlayer = _gameState.currentPlayer;
              });
            } else {
              // 合并玩家数据，保留原有玩家的aiModel和position属性
              List<Player> updatedPlayers = updatedGameState.players.map((player) {
                if (existingPlayersMap.containsKey(player.id)) {
                  // 对于已存在的玩家，保留原有属性
                  Player existingPlayer = existingPlayersMap[player.id]!;
                  print('合并现有玩家数据: ID=${player.id}, 名称=${player.name}, 保留模型=${existingPlayer.aiModel}');
                  return Player(
                    id: player.id,
                    name: player.name,
                    position: existingPlayer.position, // 保留原始位置
                    chips: player.chips,
                    bet: player.bet,
                    isActive: player.isActive,
                    isCurrent: player.isCurrent,
                    isDealer: player.isDealer,
                    action: player.action,
                    aiModel: existingPlayer.aiModel ?? player.aiModel, // 保留原始AI模型，如果为空则使用新值
                    modelColor: existingPlayer.modelColor ?? player.modelColor, // 保留原始模型颜色，如果为空则使用新值
                    cards: player.cards,
                  );
                } else {
                  // 对于新玩家，检查是否需要从名称推断AI模型
                  String? inferredModel = player.aiModel;
                  
                  // 如果aiModel为空，尝试从名称中推断
                  if (inferredModel == null || inferredModel.isEmpty) {
                    for (String model in aiModels) {
                      if (player.name.contains(model)) {
                        inferredModel = model;
                        print('从名称推断AI模型: 玩家=${player.name}, 模型=$inferredModel');
        break;
                      }
                    }
                  }
                  
                  // 为新玩家设置推断的模型和颜色
                  if (inferredModel != null && inferredModel.isNotEmpty) {
                    Color? modelColor = aiModelColors[inferredModel];
                    print('为新玩家设置AI模型: ID=${player.id}, 名称=${player.name}, 模型=$inferredModel');
                    return Player(
                      id: player.id,
                      name: player.name,
                      position: player.position,
                      chips: player.chips,
                      bet: player.bet,
                      isActive: player.isActive,
                      isCurrent: player.isCurrent,
                      isDealer: player.isDealer,
                      action: player.action,
                      aiModel: inferredModel,
                      modelColor: modelColor,
                      cards: player.cards,
                    );
                  }
                  
                  return player;
                }
              }).toList();
              
              setState(() {
                _gameState = updatedGameState.copyWith(
                  players: updatedPlayers
                );
                _currentPlayer = _gameState.currentPlayer;
              });
            }
          }
          
          // 显示创建成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
              content: Text('游戏创建成功: ID ${newGameId.substring(0, min(8, newGameId.length))}...'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.fixed,
            ),
          );
        } catch (e, stack) {
          print('处理gameCreated消息错误: $e');
          print('错误堆栈: $stack');
          
          // 尝试只更新游戏ID
          try {
            final String newGameId = backendGameState['id']?.toString() ?? 
                backendGameState['gameId']?.toString() ?? 
                'game${DateTime.now().millisecondsSinceEpoch}';
                
            if (newGameId != _gameState.id) {
            setState(() {
                _gameState = _gameState.copyWith(id: newGameId);
            });
            
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                  content: Text('已更新游戏ID: ${newGameId.substring(0, min(8, newGameId.length))}...'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.fixed,
                  ),
                );
              }
          } catch (e2) {
            print('提取游戏ID错误: $e2');
          }
        }
        return;
      }

      // 处理gameState消息
      if (data.containsKey('gameState')) {
        final backendGameState = data['gameState'];
        
        print('收到游戏状态更新: ${data['type']}, 玩家数: ${backendGameState['players']?.length ?? 0}');
        
        try {
          // 保存现有玩家的aiModel、modelColor和position信息
          Map<String, Player> existingPlayersMap = {};
          for (var player in _gameState.players) {
            existingPlayersMap[player.id] = player;
          }
          
        // 构建新的游戏状态对象
        final updatedGameState = GameState.fromJson(backendGameState);
        
          // 检查玩家数量是否为0但原来不为0，这可能是个问题
          if (updatedGameState.players.isEmpty && _gameState.players.isNotEmpty) {
            print('警告：从后端接收到的游戏状态中玩家数量为0，但原来有${_gameState.players.length}个玩家');
            print('保留原有玩家数据');
            
            // 保留原有玩家，只更新其他字段
        setState(() {
              _gameState = GameState(
                id: updatedGameState.id,
                stage: updatedGameState.stage,
                players: _gameState.players, // 使用原有玩家列表
                communityCards: updatedGameState.communityCards,
                pot: updatedGameState.pot,
                currentBet: updatedGameState.currentBet,
                smallBlind: updatedGameState.smallBlind,
                bigBlind: updatedGameState.bigBlind,
                dealerIndex: updatedGameState.dealerIndex,
                currentPlayerIndex: updatedGameState.currentPlayerIndex,
                winners: updatedGameState.winners,
              );
              _currentPlayer = _gameState.currentPlayer;
            });
          } else {
            // 合并玩家数据，保留原有玩家的aiModel、modelColor和position属性
            List<Player> updatedPlayers = updatedGameState.players.map((player) {
              if (existingPlayersMap.containsKey(player.id)) {
                // 对于已存在的玩家，保留原有属性
                Player existingPlayer = existingPlayersMap[player.id]!;
                return Player(
                  id: player.id,
                  name: player.name,
                  position: existingPlayer.position, // 保留原始位置
                  chips: player.chips,
                  bet: player.bet,
                  isActive: player.isActive,
                  isCurrent: player.isCurrent,
                  isDealer: player.isDealer,
                  action: player.action,
                  aiModel: existingPlayer.aiModel, // 保留原始AI模型
                  modelColor: existingPlayer.modelColor, // 保留原始模型颜色
                  cards: player.cards,
                );
              }
              return player;
            }).toList();
            
            // 正常更新
            setState(() {
              _gameState = updatedGameState.copyWith(
                players: updatedPlayers
              );
              _currentPlayer = _gameState.currentPlayer;
            });
          }
        
        // 处理游戏阶段变化
        if (backendGameState['state'] != null) {
          final newState = backendGameState['state'];
          print('游戏阶段更新: $newState (上一状态: $_lastGameState)');
          
          // 只有在游戏阶段发生变化时才显示通知
          if (_lastGameState != newState) {
          // 如果是游戏开始消息，显示特殊的开始动画
            if (data['type'] == 'gameStarted') {
            // 显示游戏开始的特效
            _showGameStartedAnimation();
          } else {
              // 游戏阶段变化通知已禁用，避免频繁弹出
              /*
            // 当游戏进入新阶段时显示提示
            Map<String, String> stageMessages = {
              'preflop': '开始发牌，进入前翻牌阶段',
              'flop': '发放三张公共牌，进入翻牌圈',
              'turn': '发放转牌，进入转牌圈',
              'river': '发放河牌，进入河牌圈',
              'showdown': '所有玩家摊牌，开始结算',
              'finished': '本局游戏结束',
            };
            
            if (stageMessages.containsKey(newState)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(stageMessages[newState]!),
                  backgroundColor: Colors.blue.shade700,
                  duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.fixed,
                ),
              );
            }
              */
            }
            
            // 更新上一次状态
            _lastGameState = newState;
          }
        }
        
        // 处理获胜者信息
        if (backendGameState['winners'] != null) {
          // 显示获胜者信息
          _showWinnersInfo(backendGameState['winners']);
        }
        } catch (e, stack) {
        print('解析游戏状态更新错误: $e');
          print('错误堆栈: $stack');
          
          // 尝试只更新游戏ID，而不触及其他数据
          if (backendGameState['id'] != null || backendGameState['gameId'] != null) {
            final newGameId = backendGameState['id']?.toString() ?? 
              backendGameState['gameId']?.toString() ?? 
              _gameState.id;
            
            if (newGameId != _gameState.id) {
              setState(() {
                _gameState = _gameState.copyWith(id: newGameId);
              });
            }
          }
        }
      }

      // 处理gameStarted消息
      if (messageType == 'gameStarted') {
        print('处理gameStarted消息');

        Map<String, dynamic>? backendGameState = data['gameState'];
        if (backendGameState == null) {
          print('错误: gameStarted消息中没有gameState字段');
          _showErrorSnackBar('接收到的游戏开始消息格式错误');
          return;
        }

        try {
          // 记录原始数据，用于调试
          final String jsonString = backendGameState.toString().length > 200 
              ? '${backendGameState.toString().substring(0, 200)}...' 
              : backendGameState.toString();
          print('gameStarted消息中的gameState: $jsonString');
          
          // 保存现有玩家的aiModel和position信息
          Map<String, Player> existingPlayersMap = {};
          for (var player in _gameState.players) {
            existingPlayersMap[player.id] = player;
            print('保存现有玩家信息: ID=${player.id}, 位置=${player.position}, 模型=${player.aiModel}');  
          }
          
          // 创建新的游戏状态
          GameState newGameState = GameState.fromJson(backendGameState);
          
          // 确保保留现有玩家的aiModel和position信息
          if (existingPlayersMap.isNotEmpty && newGameState.players.isNotEmpty) {
            List<Player> updatedPlayers = newGameState.players.map((player) {
              Player? existingPlayer = existingPlayersMap[player.id];
              if (existingPlayer != null && existingPlayer.aiModel != null) {
                return player.copyWith(
                  aiModel: existingPlayer.aiModel,
                  modelColor: existingPlayer.modelColor
                );
              }
              return player;
            }).toList();
            
            newGameState = newGameState.copyWith(players: updatedPlayers);
          }

          // 更新游戏状态
          setState(() {
            _gameState = newGameState;
            _currentPlayer = _gameState.currentPlayer;
          });

          // 显示游戏开始提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
              content: Text('游戏已开始，阶段: ${_gameStageToString(_gameState.stage)}'),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.fixed,
            ),
          );
          
          print('游戏开始成功，当前阶段: ${_gameStageToString(_gameState.stage)}, 玩家数: ${_gameState.players.length}');
        } catch (e) {
          print('解析gameStarted消息错误: $e');
          _showErrorSnackBar('游戏开始失败: 数据解析错误');
        }
        return;
      }
      
      // 处理gameStateUpdate消息
      if (messageType == 'gameStateUpdate') {
        print('处理gameStateUpdate消息');

        Map<String, dynamic>? backendGameState = data['gameState'];
        if (backendGameState == null) {
          print('错误: gameStateUpdate消息中没有gameState字段');
          _showErrorSnackBar('接收到的游戏状态更新消息格式错误');
          return;
        }

        try {
          // 记录原始数据，用于调试
          final String jsonString = backendGameState.toString().length > 200 
              ? '${backendGameState.toString().substring(0, 200)}...' 
              : backendGameState.toString();
          print('gameStateUpdate消息中的gameState: $jsonString');
          
          // 保存现有玩家的aiModel和position信息
          Map<String, Player> existingPlayersMap = {};
          for (var player in _gameState.players) {
            existingPlayersMap[player.id] = player;
          }
          
          // 创建新的游戏状态
          GameState newGameState = GameState.fromJson(backendGameState);
          
          // 确保保留现有玩家的aiModel和position信息
          if (existingPlayersMap.isNotEmpty && newGameState.players.isNotEmpty) {
            List<Player> updatedPlayers = newGameState.players.map((player) {
              Player? existingPlayer = existingPlayersMap[player.id];
              if (existingPlayer != null && existingPlayer.aiModel != null) {
                return player.copyWith(
                  aiModel: existingPlayer.aiModel,
                  modelColor: existingPlayer.modelColor
                );
              }
              return player;
            }).toList();
            
            newGameState = newGameState.copyWith(players: updatedPlayers);
          }

          // 检测游戏阶段变化
          bool stageChanged = _gameState.stage != newGameState.stage;
          
          // 更新游戏状态
          setState(() {
            _gameState = newGameState;
            _currentPlayer = _gameState.currentPlayer;
          });
          
          // 如果游戏阶段发生变化，显示提示
          if (stageChanged) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('游戏进入${_gameStageToString(newGameState.stage)}阶段'),
                backgroundColor: Colors.blue.shade700,
                behavior: SnackBarBehavior.fixed,
              ),
            );
            
            print('游戏阶段变化: ${_gameStageToString(_gameState.stage)}');
          }
        } catch (e) {
          print('解析gameStateUpdate消息错误: $e');
          _showErrorSnackBar('游戏状态更新失败: 数据解析错误');
        }
        return;
      }
    } catch (e) {
      print('处理游戏状态更新错误: $e');
    }
  }
  
  // 显示游戏开始动画
  void _showGameStartedAnimation() {
    // 已删除游戏开始通知
    // 不显示任何提示
  }
  
  // 显示获胜者信息
  void _showWinnersInfo(dynamic winnersData) {
    if (!mounted || winnersData == null) return;
    
    // 将winnersData转换为List
    List<dynamic> winners = winnersData is List ? winnersData : [];
    if (winners.isEmpty) return;
    
    // 构建获胜者的文本
    final List<Widget> winnerTexts = [];
    
    for (final winner in winners) {
      final playerId = winner['playerId'];
      final amount = winner['amount'];
      
      // 查找玩家
      final player = _gameState.getPlayerById(playerId);
      if (player != null) {
        winnerTexts.add(
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${player.name}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.yellow,
                  ),
                ),
                TextSpan(
                  text: ' 赢得 ',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: '$amount',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                TextSpan(
                  text: ' 筹码',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      }
    }
    
    // 显示获胜者信息
    if (winnerTexts.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '游戏结束，获胜者：',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              ...winnerTexts,
            ],
          ),
          backgroundColor: Colors.purple.shade800,
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 100, left: 50, right: 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
  
  // 处理玩家操作处理结果
  void _onPlayerActionProcessed(Map<String, dynamic> data) {
    final playerId = data['playerId'];
    final action = data['action'];
    final amount = data['amount'];
    
    print('玩家操作已处理: playerId=$playerId, action=$action, amount=$amount');
    
    // 处理操作结果
    // ... 实现操作结果处理代码 ...
  }
  
  @override
  void dispose() {
    // 取消订阅
    _gameStateSubscription?.cancel();
    
    // 释放资源
    _wsService.dispose();
    _aiService.dispose();
    
    super.dispose();
  }
  
  void _createEmptyGameState() {
    // 创建一个没有玩家的空游戏状态
    _gameState = GameState(
      id: 'game1', // 使用默认游戏ID，而不是widget.gameId
      stage: GameStage.waiting,
      players: [],
      communityCards: [],
      pot: 0,
      currentBet: 0,
      smallBlind: 25,
      bigBlind: 50,
      dealerIndex: 0,
      currentPlayerIndex: 0,
    );
  }
  
  void _addPlayer(int position) {
      setState(() {
      if (_gameState.players.any((p) => p.position == position + 1)) {
        // 如果位置已有玩家，不进行操作
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('该位置已有玩家'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // 显示添加玩家对话框
      _showAddPlayerDialog(position + 1);
    });
  }
  
  void _showAddPlayerDialog(int position) {
    final nameController = TextEditingController();
    
    // 选择第一个未被使用的模型
    var selectedModel = aiModels.firstWhere(
      (model) => !_gameState.players
          .where((p) => p.isAI && p.aiModel != null)
          .map((p) => p.aiModel!)
          .contains(model), 
      orElse: () => aiModels[0]
    );
    
    // 初始设置玩家名称为选择的模型名称
    nameController.text = selectedModel;
    
    // 显示模型logo的函数
    Widget modelLogoWidget(String modelName, {double size = 24}) {
      String? logoPath = aiModelLogos[modelName];
      
      if (logoPath != null) {
        return Container(
          height: size,
          width: size,
          padding: EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: aiModelColors[modelName]?.withOpacity(0.3) ?? Colors.black12,
                blurRadius: 2,
                spreadRadius: 0,
              ),
            ],
          ),
          child: SvgPicture.asset(
            logoPath,
            height: size - 4,
            width: size - 4,
          ),
        );
      }
      
      // 备用显示：如果没有找到对应的logo
      String displayText = '';
      
      if (modelName.contains('ChatGPT')) {
        displayText = modelName.contains('O1') ? 'O1' : '4O';
      } else if (modelName.contains('DeepSeek')) {
        displayText = modelName.contains('R1') ? 'R1' : 'DS';
      } else if (modelName == '通义千问') {
        displayText = 'TY';
      } else {
        // 截取模型名称的前两个字符
        displayText = modelName.substring(0, modelName.length > 2 ? 2 : modelName.length);
      }
      
      return Container(
        padding: EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: aiModelColors[modelName]?.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayText,
          style: TextStyle(
            color: aiModelColors[modelName],
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              title: Text(
                '添加AI到位置 $position',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              content: Container(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 玩家名称输入
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: '玩家名称',
                        hintText: '默认使用模型名称',
                        labelStyle: TextStyle(color: Colors.black54),
                        hintStyle: TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Color(0xFF1B5E20)), // 使用固定的绿色作为边框颜色
                        ),
                        prefixIcon: Icon(Icons.edit, color: Colors.grey.shade700),
                      ),
                    ),
                    
                    SizedBox(height: 16),
                    
                    // 模型选择
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            '选择大模型',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                        ),
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                                dropdownColor: Colors.white,
                            value: selectedModel,
                                icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade700),
                                style: TextStyle(color: Colors.black87),
                            hint: Text(
                              '选择AI模型',
                              style: TextStyle(color: Colors.grey),
                            ),
                            onChanged: (value) {
                              setState(() {
                                selectedModel = value!;
                                    // 当选择新模型时，自动更新名称输入框
                                    nameController.text = value;
                              });
                            },
                                items: aiModels.map((model) {
                                  // 检查模型是否已被使用
                                  final bool isUsed = _gameState.players
                                      .where((p) => p.isAI && p.aiModel != null)
                                      .map((p) => p.aiModel!)
                                      .contains(model);
                              return DropdownMenuItem<String>(
                                value: model,
                                    enabled: !isUsed, // 如果已被使用，则禁用此选项
                                child: Row(
                                  children: [
                                        modelLogoWidget(model, size: 20),
                                    SizedBox(width: 8),
                                        Text(
                                          model,
                                          style: TextStyle(
                                            color: isUsed ? Colors.grey.shade400 : Colors.black87,
                                            decoration: isUsed ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                        if (isUsed)
                                          Padding(
                                            padding: EdgeInsets.only(left: 4),
                                            child: Icon(
                                              Icons.person_off,
                                              color: Colors.grey.shade400,
                                              size: 14,
                                            ),
                                          ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '取消',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1B5E20), // 使用固定的绿色作为按钮背景色
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    
                    // 获取玩家名称 (现在已经默认设置为模型名称)
                    String playerName = nameController.text.trim();
                    
                    // 添加AI玩家到游戏
                    _addPlayerToGame(
                      name: playerName,
                      position: position,
                      aiModel: selectedModel,
                      modelColor: aiModelColors[selectedModel] ?? Colors.blue.shade700,
                    );
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            modelLogoWidget(selectedModel),
                            SizedBox(width: 8),
                            Text('添加 $playerName 到位置 $position'),
                          ],
                        ),
                        backgroundColor: Color(0xFF1B5E20).withOpacity(0.8), // 使用固定的绿色作为Snackbar背景色
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.fixed,
                      ),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      '添加',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        );
      },
    );
  }
  
  // 添加玩家到游戏
  void _addPlayerToGame({
    required String name,
    required int position,
    String? aiModel,
    Color? modelColor,
  }) {
    // 生成唯一ID - 统一使用ai_player_前缀
    final id = 'ai_player_${DateTime.now().millisecondsSinceEpoch}_${position}';
    
    // 更新AI连接状态
    setState(() {
      _aiConnectionStatus[id] = AIServiceStatus.creating;
    });
    
    // 更新游戏状态
    final updatedPlayers = List<Player>.from(_gameState.players);
    
    // 检查是否有相同位置的玩家，如果有则移除
    updatedPlayers.removeWhere((p) => p.position == position);
    
    // 添加新玩家
    updatedPlayers.add(Player(
      id: id,
      name: name,
      position: position,
      chips: 1000,
      cards: [],
      isActive: true,
      isCurrent: false,
      isDealer: false,
      aiModel: aiModel,
      modelColor: modelColor ?? Theme.of(context).primaryColor,
    ));
      
      // 更新游戏状态
    setState(() {
      _gameState = GameState(
        id: _gameState.id,
        stage: _gameState.stage,
        players: updatedPlayers,
        communityCards: _gameState.communityCards,
        pot: _gameState.pot,
        currentBet: _gameState.currentBet,
        smallBlind: _gameState.smallBlind,
        bigBlind: _gameState.bigBlind,
        dealerIndex: _gameState.dealerIndex,
        currentPlayerIndex: _gameState.currentPlayerIndex,
      );
    });
    
    // 构建玩家数据以发送到后端
    final playerData = {
      'id': id,
      'name': name,
      'position': position,
      'chips': 1000,
      'cards': [],
      'folded': false,
      'isDealer': false,
      'isTurn': false,
      'aiModel': aiModel,
    };
    
    // 通过WebSocket发送到后端
    _wsService.addPlayer(playerData);
    
    // 不再直接调用AI服务，改为通过后端代理
    /*
    try {
      // 更新AI连接状态为创建中
      setState(() {
        _aiConnectionStatus[id] = AIServiceStatus.creating;
      });
      
      // 发送创建代理请求
      final result = await _aiService.createAgent(id, name, aiModel);
      
      if (result != null) {
        // 更新AI连接状态为已创建
        setState(() {
          _aiConnectionStatus[id] = AIServiceStatus.created;
        });
        
        // 显示成功消息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('AI模型 "$name" 连接成功'),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // 更新AI连接状态为错误
        setState(() {
          _aiConnectionStatus[id] = AIServiceStatus.error;
        });
      }
    } catch (e) {
      // 更新AI连接状态为错误
      setState(() {
        _aiConnectionStatus[id] = AIServiceStatus.error;
      });
      
      // 显示错误消息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI模型连接失败: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
    */
  }
  
  // 随机分配AI模型到不同位置
  void _randomlyAssignAIModels() async {
    // 首先重置游戏状态
    setState(() {
      _createEmptyGameState();
      
      // 清除AI连接状态
      _aiConnectionStatus.clear();
    });
    
    // 显示动画过程提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2.0,
              ),
            ),
            SizedBox(width: 16),
            Text('正在随机分配模型...'),
          ],
        ),
        backgroundColor: Color(0xFF5E35B1).withOpacity(0.8),
        duration: Duration(seconds: 1),
      ),
    );
    
    // 打乱AI模型顺序
    aiModels.shuffle();
    
    // 准备批量创建请求
    final agentRequests = <Map<String, dynamic>>[];
    
    // 延迟添加，创造动画效果
    for (int i = 0; i < 8; i++) {
      final position = i + 1; // 位置从1开始
      final modelName = aiModels[i];
      final playerId = 'ai_player_${DateTime.now().millisecondsSinceEpoch}_$i';
      
      // 添加到批量创建请求
      agentRequests.add({
        'playerId': playerId,
        'name': modelName,
        'aiModel': modelName,
      });
      
      Future.delayed(Duration(milliseconds: 300 * (i + 1)), () {
        if (mounted) {
          setState(() {
            // 添加AI玩家到游戏
            _addPlayerToGame(
              name: modelName,
              position: position,
              aiModel: modelName,
              modelColor: aiModelColors[modelName] ?? Colors.blue.shade700,
            );
            
            // 最后一个添加完成后，显示完成消息
            if (i == 7) {
              Future.delayed(Duration(milliseconds: 500), () {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 8),
                          Text('随机分配完成！8个AI模型已就座'),
                        ],
                      ),
                      backgroundColor: Colors.green.shade700,
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.fixed,
                    ),
                  );
                }
              });
            }
          });
        }
      });
    }
    
    // 尝试批量创建AI代理
    try {
      await _aiService.createAgentsBatch(agentRequests);
    } catch (e) {
      // 批量创建失败，显示错误消息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('部分AI模型连接失败，请检查后端服务'),
            backgroundColor: Colors.orange.shade700,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 使用主题中定义的背景颜色
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor, // 使用主题背景色
              Color(0xFFE1E8F0), // 底部稍深一点的浅色
            ],
          ),
        ),
        child: Stack(
          children: [
            // 游戏桌面
            GameTable(
          gameState: _gameState,
          currentPlayerId: widget.playerId,
          onAddPlayer: _addPlayer,
        ),
            
            // 玩家状态面板放在左上角
            Positioned(
              left: 16,
              top: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                  // 玩家状态面板
                  _buildPlayerStatusPanel(),
                  
                  // 添加16px的间距
          SizedBox(height: 16),
                  
                  // 游戏状态面板
                  _buildGameStatusPanel(),
                  
                  // 添加16px的间距
          SizedBox(height: 16),
                  
          // 重置游戏按钮
          FloatingActionButton(
            backgroundColor: Color(0xFF1B5E20), // 深绿色按钮
            foregroundColor: Colors.white,
            heroTag: 'resetGame',
        elevation: 4,
                    mini: true, // 使用小一点的按钮
        child: Icon(Icons.refresh),
        tooltip: '重置游戏',
        onPressed: () {
          // 重置游戏状态
          setState(() {
            _createEmptyGameState();
          });
              
              // 通知后端重置游戏
              _wsService.resetGame();
              
              // 删除所有AI代理（使用deleteAll参数）
              _deleteAllAIAgents([], deleteAll: true);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
          children: [
                  Icon(Icons.restart_alt, color: Colors.white),
                  SizedBox(width: 8),
                  Text('游戏已重置'),
                ],
              ),
              backgroundColor: Color(0xFF7DCE82),
              duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.fixed,
            ),
          );
        },
          ),
        ],
      ),
            ),
            
            // 按钮区域放在中间顶部
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 控制按钮
                    _buildControlButtons(),
                    
                    SizedBox(height: 10),
                    
                    // 辅助按钮放在一行
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 随机入座按钮 - 仅在玩家数量少于8时显示
                        if (_gameState.players.length < 8)
                          FloatingActionButton(
                            backgroundColor: Color(0xFF5E35B1), // 紫色按钮
                            foregroundColor: Colors.white,
                            heroTag: 'randomSeat',
                            elevation: 4,
                            mini: true, // 使用小一点的按钮
                            child: Icon(Icons.shuffle),
                            tooltip: '随机分配AI',
                            onPressed: _randomlyAssignAIModels,
                          ),
                        
                        // 删除重置游戏按钮及相关代码
                        // if (_gameState.players.length < 8)
                        //   SizedBox(width: 15),
                        // 
                        // // 重置游戏按钮
                        // FloatingActionButton(
                        //     backgroundColor: Color(0xFF1B5E20), // 深绿色按钮
                        //     foregroundColor: Colors.white,
                        //     heroTag: 'resetGame',
                        //     elevation: 4,
                        //     mini: true, // 使用小一点的按钮
                        //     child: Icon(Icons.refresh),
                        //     tooltip: '重置游戏',
                        //     onPressed: () {
                        //       // 重置游戏状态
                        //       setState(() {
                        //         _createEmptyGameState();
                        //       });
                        //       
                        //       // 通知后端重置游戏
                        //       _wsService.resetGame();
                        //       
                        //       // 删除所有AI代理（使用deleteAll参数）
                        //       _deleteAllAIAgents([], deleteAll: true);
                        //       
                        //       ScaffoldMessenger.of(context).showSnackBar(
                        //         SnackBar(
                        //           content: Row(
                        //             children: [
                        //               Icon(Icons.restart_alt, color: Colors.white),
                        //               SizedBox(width: 8),
                        //               Text('游戏已重置'),
                        //             ],
                        //           ),
                        //           backgroundColor: Color(0xFF7DCE82),
                        //           duration: Duration(seconds: 2),
                        //           behavior: SnackBarBehavior.fixed,
                        //         ),
                        //       );
                        //     },
                        // ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 构建游戏状态面板
  Widget _buildGameStatusPanel() {
    // 获取当前玩家名称
    String currentPlayerName = '无';
    final currentPlayer = _gameState.currentPlayer;
    if (currentPlayer != null) {
      currentPlayerName = currentPlayer.name;
    }
    
    // 获取庄家名称
    String dealerName = '无';
    final dealer = _gameState.dealer;
    if (dealer != null) {
      dealerName = dealer.name;
    }
    
    return Container(
      width: 250,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: Colors.blue.shade300.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.blue.shade300,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                '游戏信息',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Divider(color: Colors.white30, height: 16),
          
          // 游戏ID
          _buildStatusRow(
            '游戏ID', 
            _gameState.id == 'game1' ? '未创建' : _gameState.id.substring(0, min(8, _gameState.id.length)) + '...', 
            Icons.tag, 
            _gameState.id == 'game1' ? Colors.grey : Colors.purple.shade300
          ),
          
          // 游戏阶段
          _buildStatusRow(
            '游戏阶段', 
            _gameState.stageDescription, 
            Icons.casino, 
            _getStageColor(_gameState.stage)
          ),
          
          // 普通状态行
          _buildStatusRow(
            '底池', 
            '${_gameState.pot}', 
            Icons.monetization_on, 
            Colors.amber
          ),
          _buildStatusRow(
            '当前下注', 
            '${_gameState.currentBet}', 
            Icons.attach_money, 
            Colors.green.shade300
          ),
          _buildStatusRow(
            '小盲/大盲', 
            '${_gameState.smallBlind}/${_gameState.bigBlind}',
            Icons.money, 
            Colors.blue.shade300
          ),
          _buildStatusRow(
            '当前玩家', 
            currentPlayerName, 
            Icons.person_pin,
            Colors.orange
          ),
          _buildStatusRow(
            '庄家', 
            dealerName, 
            Icons.album, 
            Colors.white
          ),
          _buildStatusRow(
            '玩家数', 
            '${_gameState.players.length}/8', 
            Icons.group, 
            Colors.lightBlue
          ),
        ],
      ),
    );
  }
  
  // 构建玩家状态面板
  Widget _buildPlayerStatusPanel() {
    return Container(
      width: 250,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: Colors.blue.shade300.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 玩家状态标题
          Row(
            children: [
              Icon(
                Icons.people_alt,
                color: Colors.blue.shade300,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                '玩家状态',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Divider(color: Colors.white30, height: 16),
          
          // 玩家状态部分
          if (_gameState.players.isNotEmpty) 
            _buildPlayerStatusSection()
          else
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  Icon(Icons.person_add_alt, color: Colors.grey),
                  SizedBox(width: 8),
                Text(
                    '暂无玩家入座',
                  style: TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          // 显示服务状态
          SizedBox(height: 8),
          // AI服务状态行
          _buildStatusRow(
            'AI服务', 
            _getAIServiceStatusText(), 
            Icons.psychology, 
            _getAIServiceStatusColor()
          ),
          
          // WebSocket连接状态行
          _buildStatusRow(
            'WebSocket', 
            _getWebSocketStatusText(), 
            Icons.wifi, 
            _getWebSocketStatusColor()
          ),
        ],
      ),
    );
  }
  
  // 构建玩家状态部分
  Widget _buildPlayerStatusSection() {
    // 为不同类型的AI模型定义图标
    Widget getModelStatusIcon(Player player) {
      // 使用实际连接状态
      AIServiceStatus? status = _aiConnectionStatus[player.id];
      
      // 如果没有状态，默认为已连接
      if (status == null) {
        // 默认所有玩家都是已连接状态
            status = AIServiceStatus.created;
      }
      
      // 定义状态图标和颜色
      IconData statusIcon;
      Color statusColor;
      String statusTooltip;
      
      switch (status) {
        case AIServiceStatus.created:
          statusIcon = Icons.check_circle;
          statusColor = Colors.green;
          statusTooltip = '已连接';
          break;
        case AIServiceStatus.thinking:
          statusIcon = Icons.motion_photos_pause;
          statusColor = Colors.orange;
          statusTooltip = '思考中';
          break;
        case AIServiceStatus.error:
          statusIcon = Icons.error_outline;
          statusColor = Colors.red.shade300;
          statusTooltip = '连接异常';
          break;
        case AIServiceStatus.creating:
          statusIcon = Icons.sync;
          statusColor = Colors.blue;
          statusTooltip = '连接中';
          break;
        case AIServiceStatus.idle:
        default:
          statusIcon = Icons.help_outline;
          statusColor = Colors.grey;
          statusTooltip = '未知状态';
      }
      
      return Tooltip(
        message: statusTooltip,
        child: Icon(
          statusIcon,
          color: statusColor,
          size: 14,
        ),
      );
    }
    
    // 获取玩家模型Logo
    Widget getPlayerLogo(Player player) {
      if (player.isAI && player.aiModel != null) {
        String? logoPath = aiModelLogos[player.aiModel!];
        
        if (logoPath != null) {
          return Container(
            height: 20,
            width: 20,
            padding: EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: player.modelColor?.withOpacity(0.3) ?? Colors.black12,
                  blurRadius: 2,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: SvgPicture.asset(
              logoPath,
              height: 18,
              width: 18,
            ),
          );
        }
      }
      
      // 默认头像
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person,
          size: 12,
          color: Colors.white70,
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _gameState.players.map((player) {
        return Container(
          margin: EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: player.modelColor?.withOpacity(0.3) ?? Colors.grey.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // 玩家Logo
              getPlayerLogo(player),
              SizedBox(width: 6),
              
              // 玩家名称
              Expanded(
                child: Text(
                  player.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  ),
                ),
              
              // 筹码量
              Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                      '${player.chips}',
                      style: TextStyle(
                    color: Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              
              SizedBox(width: 4),
              
              // 状态图标
              getModelStatusIcon(player),
            ],
          ),
        );
      }).toList(),
    );
  }
  
  // 构建状态行
  Widget _buildStatusRow(String label, String value, IconData icon, Color iconColor) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 16,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade300,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 删除所有AI代理
  Future<void> _deleteAllAIAgents(List<String> playerIds, {bool deleteAll = false}) async {
    // 显示正在清理的提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.white),
            SizedBox(width: 8),
            Text('正在清理AI代理...'),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
      ),
    );
    
    try {
      if (deleteAll) {
        // 请求后端删除所有AI代理，不依赖前端提供的ID列表
        await _aiService.deleteAllAgents();
        // 清理AI连接状态映射
        setState(() {
          _aiConnectionStatus.clear();
        });
        print('已请求删除所有AI代理');
      } else {
        // 按原方式依次删除每个AI代理
        for (final playerId in playerIds) {
          try {
            await _aiService.deleteAgent(playerId);
            // 清理AI连接状态映射
            setState(() {
              _aiConnectionStatus.remove(playerId);
            });
          } catch (e) {
            print('删除AI代理失败: $playerId - $e');
          }
        }
        print('已尝试删除${playerIds.length}个AI代理');
      }
    } catch (e) {
      print('删除AI代理过程中发生错误: $e');
    }
    
    // 操作完成提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('AI代理已清理'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }
  
  // 获取AI服务状态文本
  String _getAIServiceStatusText() {
    if (_aiConnectionStatus.isEmpty) {
      // 如果没有玩家，返回"未连接"
      if (_gameState.players.isEmpty) {
      return '未连接';
      }
      // 如果有玩家但没有连接状态记录，也视为全部已连接
      return '全部已连接';
    }
    
    // 检查是否有明确的错误或思考状态
    final errorCount = _aiConnectionStatus.values.where((status) => status == AIServiceStatus.error).length;
    final creatingCount = _aiConnectionStatus.values.where((status) => status == AIServiceStatus.creating).length;
    final thinkingCount = _aiConnectionStatus.values.where((status) => status == AIServiceStatus.thinking).length;
    
    if (errorCount > 0) {
      return '部分连接异常($errorCount)';
    } else if (thinkingCount > 0) {
      return '思考中($thinkingCount)';
    } else if (creatingCount > 0) {
      return '正在连接($creatingCount)';
    } else {
      // 其他情况都视为已连接
      return '全部已连接';
    }
  }
  
  // 获取AI服务状态颜色
  Color _getAIServiceStatusColor() {
    if (_aiConnectionStatus.isEmpty) {
      // 如果没有玩家，显示灰色
      if (_gameState.players.isEmpty) {
      return Colors.grey;
      }
      // 如果有玩家但没有连接状态记录，也视为已连接（绿色）
      return Colors.green.shade300;
    }
    
    // 检查是否有明确的错误或思考状态
    final errorCount = _aiConnectionStatus.values.where((status) => status == AIServiceStatus.error).length;
    final creatingCount = _aiConnectionStatus.values.where((status) => status == AIServiceStatus.creating).length;
    final thinkingCount = _aiConnectionStatus.values.where((status) => status == AIServiceStatus.thinking).length;
    
    if (errorCount > 0) {
      return Colors.red.shade300;
    } else if (thinkingCount > 0) {
      return Colors.orange.shade300;
    } else if (creatingCount > 0) {
      return Colors.blue.shade300;
    } else {
      // 其他情况都视为已连接（绿色）
      return Colors.green.shade300;
    }
  }
  
  // 获取WebSocket状态文本
  String _getWebSocketStatusText() {
    switch (_wsService.connectionStatusNotifier.value) {
      case WSConnectionStatus.connected:
        return '已连接';
      case WSConnectionStatus.connecting:
        return '连接中';
      case WSConnectionStatus.reconnecting:
        return '重连中';
      case WSConnectionStatus.failed:
        return '连接失败';
      case WSConnectionStatus.disconnected:
      default:
        return '未连接';
    }
  }
  
  // 获取WebSocket状态颜色
  Color _getWebSocketStatusColor() {
    switch (_wsService.connectionStatusNotifier.value) {
      case WSConnectionStatus.connected:
        return Colors.green.shade300;
      case WSConnectionStatus.connecting:
        return Colors.blue.shade300;
      case WSConnectionStatus.reconnecting:
        return Colors.orange.shade300;
      case WSConnectionStatus.failed:
        return Colors.red.shade300;
      case WSConnectionStatus.disconnected:
      default:
        return Colors.grey.shade300;
    }
  }
  
  // 检查AI服务健康状态
  Future<void> _checkAIServiceHealth() async {
    final isHealthy = await _aiService.checkHealth();
    
    if (!isHealthy && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI服务不可用，请检查后端服务是否启动'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }
  
  // 处理来自WebSocket的AI代理错误事件
  void _onAIAgentError(Map<String, dynamic> data) {
    final playerId = data['playerId'];
    final errorMessage = data['error'];
    
    print('AI代理错误: playerId=$playerId, error=$errorMessage');
    
    // 更新玩家的AI连接状态
    setState(() {
      _aiConnectionStatus[playerId] = AIServiceStatus.error;
    });
    
    // 显示错误消息
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI模型连接失败: $errorMessage'),
          backgroundColor: Colors.red.shade700,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }
  
  // 处理AI代理创建成功事件
  void _onAIAgentCreated(Map<String, dynamic> data) {
    final playerId = data['playerId'];
    
    print('收到AI代理创建成功消息: playerId=$playerId');
    
    // 更新玩家的AI连接状态
    setState(() {
      _aiConnectionStatus[playerId] = AIServiceStatus.created;
    });
    
    // 查找对应的玩家名称
    String playerName = 'AI玩家';
    for (var player in _gameState.players) {
      if (player.id == playerId) {
        playerName = player.name;
        break;
      }
    }
    
    // 显示成功消息
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('AI模型 "$playerName" 连接成功'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  // 创建游戏
  void _createGame() {
    if (!_wsService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('WebSocket未连接，无法创建游戏'), behavior: SnackBarBehavior.fixed),
      );
      return;
    }

    // 显示加载状态
    setState(() {
      _isLoading = true;
      _loadingMessage = '正在创建游戏...';
    });

    try {
      // 使用当前游戏状态中的玩家列表
      final players = _gameState.players.map((player) => player.toJson()).toList();
      
      // 调用WebSocketService的createGame方法，传递玩家列表
      _wsService.createGame(players);
      
      // 显示成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('游戏创建请求已发送'), behavior: SnackBarBehavior.fixed),
      );
    } catch (e) {
      // 显示错误消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建游戏失败: $e'), behavior: SnackBarBehavior.fixed),
      );
    } finally {
      // 隐藏加载状态
      setState(() {
        _isLoading = false;
        _loadingMessage = '';
      });
    }
  }

  // 修改开始游戏方法
  void _startGame() async {
    // 检查游戏ID是否有效
    if (_gameState.id == 'game1') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请先创建游戏'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 检查玩家数量
    if (_gameState.players.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('至少需要2名玩家才能开始游戏'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // 检查WebSocket连接状态
    if (!_wsConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('WebSocket未连接，无法开始游戏'),
          backgroundColor: Colors.red.shade700,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = '正在开始游戏...';
    });

    try {
      // 发送开始游戏的WebSocket消息，使用正确的格式
      _wsService.startGame({
        'gameId': _gameState.id,
      });
      
      print('📤 已发送开始游戏请求: gameId=${_gameState.id}');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('游戏开始请求已发送'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } catch (e) {
      print('❌ 开始游戏请求发送失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('开始游戏失败: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // 暂停/继续游戏逻辑
  void _togglePauseGame() {
    // 如果游戏已经开始，发送下一步请求
    if (_gameState.stage != GameStage.waiting) {
      String stageText = _gameStageToString(_gameState.stage);
      String currentPlayerInfo = '';
      
      // 获取当前玩家信息
      if (_gameState.currentPlayerIndex >= 0 && 
          _gameState.currentPlayerIndex < _gameState.players.length) {
        final currentPlayer = _gameState.players[_gameState.currentPlayerIndex];
        currentPlayerInfo = '${currentPlayer.name}';
      }
      
      print('发送下一步请求，当前阶段: $stageText, 当前玩家: $currentPlayerInfo');
      _wsService.nextStep();
      
      // 显示提示信息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.navigate_next, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '处理下一步: $stageText阶段' + 
                  (currentPlayerInfo.isNotEmpty ? ', 玩家$currentPlayerInfo' : '')
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } else {
      // 游戏尚未开始，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('游戏尚未开始，无法执行下一步操作'),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  // 构建控制按钮
  Widget _buildControlButtons() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 创建游戏按钮 - 仅在没有游戏进行时显示
          if (!_gameState.isPlaying && _gameState.id == 'game1')
            ElevatedButton.icon(
              onPressed: _wsConnected ? _createGame : null,
              icon: Icon(Icons.create_new_folder),
              label: Text('创建游戏'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _wsConnected ? Colors.blue.shade700 : Colors.grey.shade600,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              ),
            ),
          if (!_gameState.isPlaying && _gameState.id == 'game1')
            SizedBox(width: 10),
          
          // 开始游戏按钮 - 仅在游戏未开始且有有效游戏ID时显示
          if (!_gameState.isPlaying && _gameState.id != 'game1')
            ElevatedButton.icon(
              onPressed: _startGame,
              icon: Icon(Icons.play_arrow),
              label: Text('开始游戏'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              ),
            ),
          if (!_gameState.isPlaying)
            SizedBox(width: 10),
          
          // 暂停/下一步按钮
          ElevatedButton.icon(
            onPressed: _gameState.stage != GameStage.waiting ? _togglePauseGame : null,
            icon: Icon(_gameState.stage == GameStage.waiting ? Icons.pause : Icons.navigate_next),
            label: Text(_gameState.stage == GameStage.waiting ? '暂停' : '下一步'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gameState.stage != GameStage.waiting ? Colors.orange.shade700 : Colors.grey.shade600,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  // 生成游戏阶段颜色
  Color _getStageColor(GameStage stage) {
    switch (stage) {
      case GameStage.waiting:
        return Colors.grey;
      case GameStage.preflop:
        return Colors.blue;
      case GameStage.flop:
        return Colors.green;
      case GameStage.turn:
        return Colors.amber;
      case GameStage.river:
        return Colors.deepOrange;
      case GameStage.showdown:
        return Colors.purple;
      case GameStage.finished:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // 显示通用错误提示
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  // 将游戏阶段枚举转换为中文字符串
  String _gameStageToString(GameStage stage) {
    switch (stage) {
      case GameStage.waiting:
        return '等待开始';
      case GameStage.preflop:
        return '翻牌前';
      case GameStage.flop:
        return '翻牌';
      case GameStage.turn:
        return '转牌';
      case GameStage.river:
        return '河牌';
      case GameStage.showdown:
        return '摊牌';
      case GameStage.finished:
        return '游戏结束';
      default:
        return '未知阶段';
    }
  }
} 