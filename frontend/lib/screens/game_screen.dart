import 'dart:async';
import 'dart:math' show min;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; // 导入SVG支持
import '../components/game_table.dart';
import '../constants.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../services/ai_service.dart'; // 导入AI服务
import '../services/websocket_service.dart'; // 导入WebSocket服务
import '../utils/player_merge.dart';

class GameScreen extends StatefulWidget {
  final String gameId;
  final String playerId;
  final String playerName;

  const GameScreen({
    super.key,
    required this.gameId,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  // 游戏状态
  late GameState _gameState;

  // 服务
  late AIService _aiService;
  late WebSocketService _wsService;

  // 游戏状态订阅
  StreamSubscription<Map<String, dynamic>>? _gameStateSubscription;
  StreamSubscription<Map<String, dynamic>>? _waitingForHumanActionSubscription;

  // AI连接状态映射
  final Map<String, AIServiceStatus> _aiConnectionStatus = {};

  // WebSocket连接状态
  bool _wsConnected = false;

  @override
  void initState() {
    super.initState();
    _gameState = _createEmptyGameState();
    _initServices();

    // 添加游戏状态更新的监听，使用_onGameStateUpdate处理所有游戏状态相关消息
    _gameStateSubscription = _wsService.gameStateStream.listen(_onGameStateUpdate);

    // 本项目中所有玩家都是AI，收到等待人类操作消息时由界面层自动推进下一步
    _waitingForHumanActionSubscription =
        _wsService.waitingForHumanActionStream.listen(_onWaitingForHumanAction);
  }

  // 创建一个没有玩家的空游戏状态（id为null表示后端尚未创建游戏）
  GameState _createEmptyGameState() {
    return GameState(
      stage: GameStage.waiting,
      players: [],
      communityCards: [],
      pot: 0,
      currentBet: 0,
      currentPlayerIndex: -1,
      dealerIndex: 0,
    );
  }

  // 初始化服务
  void _initServices() {
    // 初始化AI服务
    _aiService = AIService();

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

      // 监听WebSocket发送的错误
      _wsService.errorStream.listen(_onWSError);

      // 监听WebSocket发送的AI代理错误
      _wsService.aiAgentErrorStream.listen(_onAIAgentError);

      // 监听WebSocket发送的AI代理创建成功
      _wsService.aiAgentCreatedStream.listen(_onAIAgentCreated);
    });
  }

  // WebSocket错误信息变化监听
  void _onWSErrorChanged() {
    final errorMsg = _wsService.errorMessageNotifier.value;
    if (errorMsg != null && mounted) {
      // 如果是严重错误，显示提示
      if (_wsService.connectionStatusNotifier.value == WSConnectionStatus.failed) {
        _showWebSocketError(errorMsg);
      }
    }
  }

  // 处理WebSocket错误
  void _onWSError(String error) {
    if (kDebugMode) {
      debugPrint('收到WebSocket错误: $error');
    }
  }

  // 等待人类玩家操作 - 本项目所有玩家都是AI，自动推进下一步
  void _onWaitingForHumanAction(Map<String, dynamic> data) {
    // 添加短暂延迟，避免过快发送请求
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _wsService.nextStep();
      }
    });
  }

  // 连接WebSocket
  Future<void> _connectWebSocket() async {
    // 显示连接中提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
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
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue.shade700,
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }

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
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('已连接到游戏服务器'),
                ],
              ),
              duration: const Duration(seconds: 2),
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
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  // WebSocket状态变化监听
  void _onWSStatusChanged() {
    if (!mounted) return;

    final status = _wsService.connectionStatusNotifier.value;

    setState(() {
      _wsConnected = status == WSConnectionStatus.connected;
    });

    if (status == WSConnectionStatus.reconnecting) {
      // 重连中，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2.0,
                ),
              ),
              const SizedBox(width: 8),
              Text('正在尝试重新连接(${_wsService.reconnectAttemptsNotifier.value})...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.orange.shade900,
        ),
      );
    }
  }

  // 处理游戏状态更新 - 每种消息类型只经过一个处理分支
  void _onGameStateUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    final String messageType = data['type']?.toString() ?? 'unknown';

    switch (messageType) {
      case 'gameReset':
        _handleGameReset();
        break;

      case 'gameStageChanged':
        // 游戏阶段变化后，向后端请求最新游戏状态
        _wsService.getGameState();
        break;

      case 'gameCreated':
      case 'gameStarted':
      case 'gameState':
      case 'gameStateUpdate':
        final dynamic backendGameState = data['gameState'];
        if (backendGameState is! Map) {
          _showErrorSnackBar('接收到的游戏状态消息格式错误: $messageType');
          return;
        }
        _applyGameState(
            messageType, Map<String, dynamic>.from(backendGameState));
        break;

      default:
        break;
    }
  }

  // 处理游戏重置消息
  void _handleGameReset() {
    setState(() {
      _gameState = _createEmptyGameState();
      _aiConnectionStatus.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('游戏已重置'),
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  // 解析并应用后端游戏状态，合并保留本地玩家的aiModel/position等属性
  void _applyGameState(String messageType, Map<String, dynamic> json) {
    try {
      final GameState parsed = GameState.fromJson(json);
      final GameStage oldStage = _gameState.stage;

      final GameState merged = parsed.copyWith(
        // 后端消息缺少id时保留本地已知的游戏id
        id: parsed.id ?? _gameState.id,
        players: mergePlayers(_gameState.players, parsed.players),
      );

      setState(() {
        _gameState = merged;
      });

      // 按消息类型显示一次性提示
      switch (messageType) {
        case 'gameCreated':
          final String? newGameId = merged.id;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newGameId == null
                  ? '游戏创建成功'
                  : '游戏创建成功: ID ${newGameId.substring(0, min(8, newGameId.length))}...'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.fixed,
            ),
          );
          break;

        case 'gameStarted':
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('游戏已开始，阶段: ${_gameStageToString(merged.stage)}'),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.fixed,
            ),
          );
          break;

        default:
          // 普通状态更新时只在阶段变化时提示
          if (merged.stage != oldStage) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('游戏进入${_gameStageToString(merged.stage)}阶段'),
                backgroundColor: Colors.blue.shade700,
                behavior: SnackBarBehavior.fixed,
              ),
            );
          }
      }

      // 处理获胜者信息
      if (json['winners'] != null) {
        _showWinnersInfo(json['winners']);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('解析游戏状态更新错误($messageType): $e');
      }
      _showErrorSnackBar('游戏状态更新失败: 数据解析错误');
    }
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
      final player =
          playerId != null ? _gameState.getPlayerById(playerId.toString()) : null;
      if (player != null) {
        winnerTexts.add(
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: player.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.yellow,
                  ),
                ),
                const TextSpan(
                  text: ' 赢得 ',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: '$amount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                const TextSpan(
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
              const Text(
                '游戏结束，获胜者：',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...winnerTexts,
            ],
          ),
          backgroundColor: Colors.purple.shade800,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 100, left: 50, right: 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    // 取消订阅
    _gameStateSubscription?.cancel();
    _waitingForHumanActionSubscription?.cancel();

    // 释放资源
    _wsService.dispose();
    _aiService.dispose();

    super.dispose();
  }

  void _addPlayer(int position) {
    if (_gameState.players.any((p) => p.position == position + 1)) {
      // 如果位置已有玩家，不进行操作
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该位置已有玩家'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 显示添加玩家对话框
    _showAddPlayerDialog(position + 1);
  }

  void _showAddPlayerDialog(int position) {
    final nameController = TextEditingController();

    // 选择第一个未被使用的模型
    var selectedModel = GameConstants.aiModels.firstWhere(
        (model) => !_gameState.players
            .where((p) => p.isAI && p.aiModel != null)
            .map((p) => p.aiModel!)
            .contains(model),
        orElse: () => GameConstants.aiModels[0]);

    // 初始设置玩家名称为选择的模型名称
    nameController.text = selectedModel;

    // 显示模型logo的函数
    Widget modelLogoWidget(String modelName, {double size = 24}) {
      String? logoPath = GameConstants.aiModelLogos[modelName];

      if (logoPath != null) {
        return Container(
          height: size,
          width: size,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: GameConstants.aiModelColors[modelName]
                        ?.withValues(alpha: 0.3) ??
                    Colors.black12,
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
        displayText =
            modelName.substring(0, modelName.length > 2 ? 2 : modelName.length);
      }

      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: GameConstants.aiModelColors[modelName]?.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayText,
          style: TextStyle(
            color: GameConstants.aiModelColors[modelName],
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: Text(
              '添加AI到位置 $position',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 玩家名称输入
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: '玩家名称',
                      hintText: '默认使用模型名称',
                      labelStyle: const TextStyle(color: Colors.black54),
                      hintStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFF1B5E20)), // 使用固定的绿色作为边框颜色
                      ),
                      prefixIcon: Icon(Icons.edit, color: Colors.grey.shade700),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 模型选择
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: Colors.white,
                            value: selectedModel,
                            icon: Icon(Icons.arrow_drop_down,
                                color: Colors.grey.shade700),
                            style: const TextStyle(color: Colors.black87),
                            hint: const Text(
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
                            items: GameConstants.aiModels.map((model) {
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
                                    const SizedBox(width: 8),
                                    Text(
                                      model,
                                      style: TextStyle(
                                        color: isUsed
                                            ? Colors.grey.shade400
                                            : Colors.black87,
                                        decoration: isUsed
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    if (isUsed)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
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
                  backgroundColor: const Color(0xFF1B5E20), // 使用固定的绿色作为按钮背景色
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
                    modelColor: GameConstants.aiModelColors[selectedModel] ??
                        Colors.blue.shade700,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          modelLogoWidget(selectedModel),
                          const SizedBox(width: 8),
                          Text('添加 $playerName 到位置 $position'),
                        ],
                      ),
                      backgroundColor: const Color(0xFF1B5E20)
                          .withValues(alpha: 0.8), // 使用固定的绿色作为Snackbar背景色
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.fixed,
                    ),
                  );
                },
                child: const Padding(
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
        });
      },
    );
  }

  // 添加玩家到游戏
  // AI代理的创建由后端在处理addPlayer消息时代理完成
  void _addPlayerToGame({
    required String name,
    required int position,
    String? aiModel,
    Color? modelColor,
  }) {
    // 生成唯一ID - 统一使用ai_player_前缀
    final id = 'ai_player_${DateTime.now().millisecondsSinceEpoch}_$position';

    // 更新游戏状态
    final updatedPlayers = List<Player>.from(_gameState.players);

    // 检查是否有相同位置的玩家，如果有则移除
    updatedPlayers.removeWhere((p) => p.position == position);

    // 添加新玩家
    updatedPlayers.add(Player(
      id: id,
      name: name,
      position: position,
      chips: GameConstants.initialChips,
      cards: [],
      isActive: true,
      isCurrent: false,
      isDealer: false,
      aiModel: aiModel,
      modelColor: modelColor ?? Theme.of(context).primaryColor,
    ));

    // 更新游戏状态和AI连接状态
    setState(() {
      _aiConnectionStatus[id] = AIServiceStatus.creating;
      _gameState = _gameState.copyWith(players: updatedPlayers);
    });

    // 构建玩家数据以发送到后端
    final playerData = {
      'id': id,
      'name': name,
      'position': position,
      'chips': GameConstants.initialChips,
      'cards': [],
      'folded': false,
      'isDealer': false,
      'isTurn': false,
      'aiModel': aiModel,
    };

    // 通过WebSocket发送到后端，由后端创建对应的AI代理
    _wsService.addPlayer(playerData);
  }

  // 随机分配AI模型到不同位置
  void _randomlyAssignAIModels() {
    // 首先重置游戏状态
    setState(() {
      _gameState = _createEmptyGameState();
      _aiConnectionStatus.clear();
    });

    // 显示动画过程提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
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
        backgroundColor: const Color(0xFF5E35B1).withValues(alpha: 0.8),
        duration: const Duration(seconds: 1),
      ),
    );

    // 打乱AI模型顺序
    final models = List<String>.from(GameConstants.aiModels)..shuffle();

    // 延迟添加，创造动画效果
    // AI代理由后端在处理addPlayer消息时创建，前端无需再直接请求AI服务
    for (int i = 0; i < GameConstants.maxPlayers; i++) {
      final position = i + 1; // 位置从1开始
      final modelName = models[i];

      Future.delayed(Duration(milliseconds: 300 * (i + 1)), () {
        if (!mounted) return;

        // 添加AI玩家到游戏
        _addPlayerToGame(
          name: modelName,
          position: position,
          aiModel: modelName,
          modelColor:
              GameConstants.aiModelColors[modelName] ?? Colors.blue.shade700,
        );

        // 最后一个添加完成后，显示完成消息
        if (i == GameConstants.maxPlayers - 1) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('随机分配完成！8个AI模型已就座'),
                    ],
                  ),
                  backgroundColor: Colors.green.shade700,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.fixed,
                ),
              );
            }
          });
        }
      });
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
              const Color(0xFFE1E8F0), // 底部稍深一点的浅色
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
                  const SizedBox(height: 16),

                  // 游戏状态面板
                  _buildGameStatusPanel(),

                  // 添加16px的间距
                  const SizedBox(height: 16),

                  // 重置游戏按钮
                  FloatingActionButton(
                    backgroundColor: const Color(0xFF1B5E20), // 深绿色按钮
                    foregroundColor: Colors.white,
                    heroTag: 'resetGame',
                    elevation: 4,
                    mini: true, // 使用小一点的按钮
                    tooltip: '重置游戏',
                    onPressed: () {
                      // 重置游戏状态
                      setState(() {
                        _gameState = _createEmptyGameState();
                      });

                      // 通知后端重置游戏
                      _wsService.resetGame();

                      // 删除所有AI代理
                      _deleteAllAIAgents();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.restart_alt, color: Colors.white),
                              SizedBox(width: 8),
                              Text('游戏已重置'),
                            ],
                          ),
                          backgroundColor: const Color(0xFF7DCE82),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.fixed,
                        ),
                      );
                    },
                    child: const Icon(Icons.refresh),
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

                    const SizedBox(height: 10),

                    // 辅助按钮放在一行
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 随机入座按钮 - 仅在玩家数量少于8时显示
                        if (_gameState.players.length < GameConstants.maxPlayers)
                          FloatingActionButton(
                            backgroundColor: const Color(0xFF5E35B1), // 紫色按钮
                            foregroundColor: Colors.white,
                            heroTag: 'randomSeat',
                            elevation: 4,
                            mini: true, // 使用小一点的按钮
                            tooltip: '随机分配AI',
                            onPressed: _randomlyAssignAIModels,
                            child: const Icon(Icons.shuffle),
                          ),
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

    final String? gameId = _gameState.id;

    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: Colors.blue.shade300.withValues(alpha: 0.5),
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
              const SizedBox(width: 8),
              const Text(
                '游戏信息',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white30, height: 16),

          // 游戏ID
          _buildStatusRow(
              '游戏ID',
              gameId == null
                  ? '未创建'
                  : '${gameId.substring(0, min(8, gameId.length))}...',
              Icons.tag,
              gameId == null ? Colors.grey : Colors.purple.shade300),

          // 游戏阶段
          _buildStatusRow('游戏阶段', _gameState.stageDescription, Icons.casino,
              _getStageColor(_gameState.stage)),

          // 普通状态行
          _buildStatusRow(
              '底池', '${_gameState.pot}', Icons.monetization_on, Colors.amber),
          _buildStatusRow('当前下注', '${_gameState.currentBet}',
              Icons.attach_money, Colors.green.shade300),
          _buildStatusRow(
              '小盲/大盲',
              '${_gameState.smallBlind}/${_gameState.bigBlind}',
              Icons.money,
              Colors.blue.shade300),
          _buildStatusRow('当前玩家', currentPlayerName, Icons.person_pin,
              Colors.orange),
          _buildStatusRow('庄家', dealerName, Icons.album, Colors.white),
          _buildStatusRow(
              '玩家数',
              '${_gameState.players.length}/${GameConstants.maxPlayers}',
              Icons.group,
              Colors.lightBlue),
        ],
      ),
    );
  }

  // 构建玩家状态面板
  Widget _buildPlayerStatusPanel() {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: Colors.blue.shade300.withValues(alpha: 0.5),
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
              const SizedBox(width: 8),
              const Text(
                '玩家状态',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white30, height: 16),

          // 玩家状态部分
          if (_gameState.players.isNotEmpty)
            _buildPlayerStatusSection()
          else
            const Padding(
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
          const SizedBox(height: 8),
          // AI服务状态行
          _buildStatusRow('AI服务', _getAIServiceStatusText(), Icons.psychology,
              _getAIServiceStatusColor()),

          // WebSocket连接状态行
          _buildStatusRow('WebSocket', _getWebSocketStatusText(), Icons.wifi,
              _getWebSocketStatusColor()),
        ],
      ),
    );
  }

  // 构建玩家状态部分
  Widget _buildPlayerStatusSection() {
    // 为不同类型的AI模型定义图标
    Widget getModelStatusIcon(Player player) {
      // 使用实际连接状态，如果没有状态，默认为已连接
      AIServiceStatus status =
          _aiConnectionStatus[player.id] ?? AIServiceStatus.created;

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
        String? logoPath = GameConstants.aiModelLogos[player.aiModel!];

        if (logoPath != null) {
          return Container(
            height: 20,
            width: 20,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: player.modelColor?.withValues(alpha: 0.3) ??
                      Colors.black12,
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
          color: Colors.grey.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
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
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: player.modelColor?.withValues(alpha: 0.3) ??
                  Colors.grey.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // 玩家Logo
              getPlayerLogo(player),
              const SizedBox(width: 6),

              // 玩家名称
              Expanded(
                child: Text(
                  player.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 筹码量
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  '${player.chips}',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // 状态图标
              getModelStatusIcon(player),
            ],
          ),
        );
      }).toList(),
    );
  }

  // 构建状态行
  Widget _buildStatusRow(
      String label, String value, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 16,
          ),
          const SizedBox(width: 8),
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
            style: const TextStyle(
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
  Future<void> _deleteAllAIAgents() async {
    // 显示正在清理的提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.white),
            SizedBox(width: 8),
            Text('正在清理AI代理...'),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
      ),
    );

    // 请求AI服务删除所有代理
    await _aiService.deleteAllAgents();

    if (!mounted) return;

    // 清理AI连接状态映射
    setState(() {
      _aiConnectionStatus.clear();
    });

    // 操作完成提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('AI代理已清理'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
      ),
    );
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
    final errorCount = _aiConnectionStatus.values
        .where((status) => status == AIServiceStatus.error)
        .length;
    final creatingCount = _aiConnectionStatus.values
        .where((status) => status == AIServiceStatus.creating)
        .length;
    final thinkingCount = _aiConnectionStatus.values
        .where((status) => status == AIServiceStatus.thinking)
        .length;

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
    final errorCount = _aiConnectionStatus.values
        .where((status) => status == AIServiceStatus.error)
        .length;
    final creatingCount = _aiConnectionStatus.values
        .where((status) => status == AIServiceStatus.creating)
        .length;
    final thinkingCount = _aiConnectionStatus.values
        .where((status) => status == AIServiceStatus.thinking)
        .length;

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
        return Colors.grey.shade300;
    }
  }

  // 检查AI服务健康状态
  Future<void> _checkAIServiceHealth() async {
    final isHealthy = await _aiService.checkHealth();

    if (!isHealthy && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
    if (!mounted) return;

    final playerId = data['playerId'];
    final errorMessage = data['error'];

    // 更新玩家的AI连接状态
    setState(() {
      _aiConnectionStatus[playerId] = AIServiceStatus.error;
    });

    // 显示错误消息
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('AI模型连接失败: $errorMessage'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  // 处理AI代理创建成功事件
  void _onAIAgentCreated(Map<String, dynamic> data) {
    if (!mounted) return;

    final playerId = data['playerId'];

    // 更新玩家的AI连接状态
    setState(() {
      _aiConnectionStatus[playerId] = AIServiceStatus.created;
    });

    // 查找对应的玩家名称
    final playerName = _gameState.getPlayerById(playerId?.toString() ?? '')?.name ?? 'AI玩家';

    // 显示成功消息
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('AI模型 "$playerName" 连接成功'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  // 创建游戏
  void _createGame() {
    if (!_wsService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('WebSocket未连接，无法创建游戏'),
            behavior: SnackBarBehavior.fixed),
      );
      return;
    }

    // 使用当前游戏状态中的玩家列表
    final players = _gameState.players.map((player) => player.toJson()).toList();

    // 调用WebSocketService的createGame方法，传递玩家列表
    _wsService.createGame(players);

    // 显示成功消息
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('游戏创建请求已发送'), behavior: SnackBarBehavior.fixed),
    );
  }

  // 开始游戏
  void _startGame() {
    // 检查游戏是否已创建
    final String? gameId = _gameState.id;
    if (gameId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先创建游戏'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 检查玩家数量
    if (_gameState.players.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
          content: const Text('WebSocket未连接，无法开始游戏'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 发送开始游戏的WebSocket消息
    _wsService.startGame(gameId);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('游戏开始请求已发送'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  // 下一步游戏逻辑
  void _togglePauseGame() {
    // 如果游戏已经开始，发送下一步请求
    if (_gameState.stage != GameStage.waiting) {
      String stageText = _gameStageToString(_gameState.stage);
      String currentPlayerInfo = '';

      // 获取当前玩家信息
      if (_gameState.currentPlayerIndex >= 0 &&
          _gameState.currentPlayerIndex < _gameState.players.length) {
        final currentPlayer =
            _gameState.players[_gameState.currentPlayerIndex];
        currentPlayerInfo = currentPlayer.name;
      }

      _wsService.nextStep();

      // 显示提示信息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.navigate_next, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('处理下一步: $stageText阶段'
                    '${currentPlayerInfo.isNotEmpty ? ', 玩家$currentPlayerInfo' : ''}'),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } else {
      // 游戏尚未开始，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('游戏尚未开始，无法执行下一步操作'),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  // 构建控制按钮
  Widget _buildControlButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 创建游戏按钮 - 仅在没有游戏进行时显示
          if (!_gameState.isPlaying && !_gameState.isCreated)
            ElevatedButton.icon(
              onPressed: _wsConnected ? _createGame : null,
              icon: const Icon(Icons.create_new_folder),
              label: const Text('创建游戏'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _wsConnected ? Colors.blue.shade700 : Colors.grey.shade600,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              ),
            ),
          if (!_gameState.isPlaying && !_gameState.isCreated)
            const SizedBox(width: 10),

          // 开始游戏按钮 - 仅在游戏未开始且有有效游戏ID时显示
          if (!_gameState.isPlaying && _gameState.isCreated)
            ElevatedButton.icon(
              onPressed: _startGame,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始游戏'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              ),
            ),
          if (!_gameState.isPlaying) const SizedBox(width: 10),

          // 暂停/下一步按钮
          ElevatedButton.icon(
            onPressed:
                _gameState.stage != GameStage.waiting ? _togglePauseGame : null,
            icon: Icon(_gameState.stage == GameStage.waiting
                ? Icons.pause
                : Icons.navigate_next),
            label: Text(_gameState.stage == GameStage.waiting ? '暂停' : '下一步'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gameState.stage != GameStage.waiting
                  ? Colors.orange.shade700
                  : Colors.grey.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
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
    }
  }

  // 显示通用错误提示
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
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
    }
  }
}
