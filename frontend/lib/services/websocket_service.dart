import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants.dart';

/// WebSocket连接状态枚举
enum WSConnectionStatus {
  connecting,  // 正在连接
  connected,   // 连接成功
  disconnected,// 已断开连接
  reconnecting,// 正在重连
  failed       // 连接失败(无法重新连接)
}

/// 错误类型枚举
enum WSErrorType {
  connectionFailed,  // 连接失败
  connectionClosed,  // 连接意外关闭
  timeout,           // 连接超时
  serverError,       // 服务器错误
  clientError,       // 客户端错误
  unknown            // 未知错误
}

/// WebSocket服务
/// 纯传输层：负责连接管理和消息收发，不做任何游戏逻辑决策
class WebSocketService {
  WebSocketChannel? _channel;
  String _serverUrl = GameConstants.wsUrl;

  // 广播流，允许多个监听器
  Stream<dynamic>? _broadcastStream;

  // 连接超时时间
  final Duration _connectionTimeout = const Duration(seconds: 10);

  // 心跳检测间隔和超时
  Timer? _heartbeatTimer;
  final Duration _heartbeatInterval = const Duration(seconds: 30);
  final Duration _heartbeatTimeout = const Duration(seconds: 5);
  int _missedHeartbeats = 0;
  final int _maxMissedHeartbeats = 2;

  // 流控制器，用于广播游戏状态更新
  final StreamController<Map<String, dynamic>> _gameStateController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 流控制器，用于广播玩家操作结果
  final StreamController<Map<String, dynamic>> _playerActionController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 流控制器，用于广播AI代理错误
  final StreamController<Map<String, dynamic>> _aiAgentErrorController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 流控制器，用于广播AI代理创建成功
  final StreamController<Map<String, dynamic>> _aiAgentCreatedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 错误信息流
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // 思考记录更新控制器
  final StreamController<Map<String, dynamic>> _thinkingUpdatedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 等待人类玩家操作控制器
  final StreamController<Map<String, dynamic>> _waitingForHumanActionController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 状态通知器
  final ValueNotifier<WSConnectionStatus> connectionStatusNotifier =
      ValueNotifier(WSConnectionStatus.disconnected);

  // 错误信息通知器
  final ValueNotifier<String?> errorMessageNotifier = ValueNotifier(null);

  // 错误类型通知器
  final ValueNotifier<WSErrorType?> errorTypeNotifier = ValueNotifier(null);

  // 连接失败计数器（用于用户界面显示）
  final ValueNotifier<int> reconnectAttemptsNotifier = ValueNotifier(0);

  // 最近一次活动时间戳
  DateTime _lastActivity = DateTime.now();

  // 公开的流，供外部监听
  Stream<Map<String, dynamic>> get gameStateStream =>
      _gameStateController.stream;
  Stream<Map<String, dynamic>> get playerActionStream =>
      _playerActionController.stream;
  Stream<Map<String, dynamic>> get aiAgentErrorStream =>
      _aiAgentErrorController.stream;
  Stream<Map<String, dynamic>> get aiAgentCreatedStream =>
      _aiAgentCreatedController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Map<String, dynamic>> get thinkingUpdatedStream =>
      _thinkingUpdatedController.stream;
  Stream<Map<String, dynamic>> get waitingForHumanActionStream =>
      _waitingForHumanActionController.stream;

  // 初始化
  WebSocketService({String? serverUrl}) {
    if (serverUrl != null) {
      _serverUrl = serverUrl;
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  /// 连接到WebSocket服务器
  Future<bool> connect() async {
    // 清理之前的连接
    _cleanup();

    try {
      // 更新状态为连接中
      connectionStatusNotifier.value = WSConnectionStatus.connecting;
      errorMessageNotifier.value = null;
      errorTypeNotifier.value = null;
      _log('尝试连接到WebSocket服务器: $_serverUrl');

      // 创建超时计时器
      final completer = Completer<bool>();
      final timeoutTimer = Timer(_connectionTimeout, () {
        if (!completer.isCompleted) {
          _log('WebSocket连接超时');
          errorMessageNotifier.value = "连接超时，请检查网络或服务器状态";
          errorTypeNotifier.value = WSErrorType.timeout;
          completer.complete(false);
        }
      });

      try {
        // 尝试建立连接
        _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));

        // 创建广播流
        _broadcastStream = _channel!.stream.asBroadcastStream();

        // 设置消息监听器
        _setupMessageListener();

        // 发送ping消息验证连接
        bool connected = await _verifyConnection();

        // 取消超时计时器
        timeoutTimer.cancel();

        if (connected) {
          _log('WebSocket连接成功');
          connectionStatusNotifier.value = WSConnectionStatus.connected;
          _resetReconnectAttempts();
          _startHeartbeat(); // 启动心跳检测
          _updateLastActivity();

          if (!completer.isCompleted) {
            completer.complete(true);
          }
        } else {
          _log('WebSocket连接验证失败');
          connectionStatusNotifier.value = WSConnectionStatus.disconnected;
          errorMessageNotifier.value = "无法验证连接，服务器可能未响应";
          errorTypeNotifier.value = WSErrorType.connectionFailed;

          // 关闭通道
          _channel?.sink.close();
          _channel = null;

          // 尝试重连
          _scheduleReconnect();

          if (!completer.isCompleted) {
            completer.complete(false);
          }
        }

        return await completer.future;
      } catch (e) {
        // 连接初始化异常
        _log('WebSocket连接初始化异常: $e');
        timeoutTimer.cancel();

        connectionStatusNotifier.value = WSConnectionStatus.disconnected;
        errorMessageNotifier.value =
            "连接失败: ${e.toString().substring(0, min(50, e.toString().length))}...";
        errorTypeNotifier.value = WSErrorType.connectionFailed;

        // 尝试重连
        _scheduleReconnect();

        if (!completer.isCompleted) {
          completer.complete(false);
        }

        return false;
      }
    } catch (e) {
      // 捕获所有其他异常
      _log('连接处理过程中发生异常: $e');
      connectionStatusNotifier.value = WSConnectionStatus.disconnected;
      errorMessageNotifier.value = "发生意外错误: ${e.toString()}";
      errorTypeNotifier.value = WSErrorType.unknown;
      return false;
    }
  }

  /// 验证连接是否有效
  Future<bool> _verifyConnection() async {
    if (_broadcastStream == null) return false;

    Completer<bool> verifyCompleter = Completer<bool>();
    Timer? verifyTimer;

    // 设置超时
    verifyTimer = Timer(const Duration(seconds: 3), () {
      if (!verifyCompleter.isCompleted) {
        _log('连接验证超时');
        verifyCompleter.complete(false);
      }
    });

    try {
      // 发送ping消息
      _channel!.sink.add(jsonEncode({
        'type': 'ping',
        'timestamp': DateTime.now().millisecondsSinceEpoch
      }));

      // 使用广播流等待响应
      bool receivedPong = false;
      late StreamSubscription subscription;

      subscription = _broadcastStream!.listen((message) {
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'pong') {
            receivedPong = true;
            if (!verifyCompleter.isCompleted) {
              verifyCompleter.complete(true);
            }
            subscription.cancel();
          }
        } catch (e) {
          _log('解析消息失败: $e');
        }
      });

      // 设置错误处理
      subscription.onError((e) {
        _log('验证连接监听时发生错误: $e');
        if (!verifyCompleter.isCompleted) {
          verifyCompleter.complete(false);
        }
        subscription.cancel();
      });

      // 设置完成处理
      subscription.onDone(() {
        if (!verifyCompleter.isCompleted) {
          verifyCompleter.complete(receivedPong);
        }
      });

      // 等待结果或超时
      final result = await verifyCompleter.future;
      verifyTimer.cancel();
      return result;
    } catch (e) {
      _log('验证连接时发生错误: $e');
      verifyTimer.cancel();

      if (!verifyCompleter.isCompleted) {
        verifyCompleter.complete(false);
      }

      return false;
    }
  }

  /// 设置消息监听器
  void _setupMessageListener() {
    if (_broadcastStream == null) return;

    _broadcastStream!.listen(
      (message) {
        // 更新最后活动时间
        _updateLastActivity();
        // 处理消息
        _handleMessage(message);
      },
      onDone: () {
        _log('WebSocket连接已关闭');
        connectionStatusNotifier.value = WSConnectionStatus.disconnected;
        errorMessageNotifier.value = "连接已关闭";
        errorTypeNotifier.value = WSErrorType.connectionClosed;

        // 停止心跳检测
        _stopHeartbeat();

        // 尝试重连
        _scheduleReconnect();
      },
      onError: (error) {
        _log('WebSocket错误: $error');
        connectionStatusNotifier.value = WSConnectionStatus.disconnected;
        errorMessageNotifier.value = "连接错误: ${error.toString()}";
        errorTypeNotifier.value = WSErrorType.connectionFailed;

        // 停止心跳检测
        _stopHeartbeat();

        // 通知错误
        _notifyError("连接错误", error.toString(), WSErrorType.connectionFailed);

        // 尝试重连
        _scheduleReconnect();
      },
      cancelOnError: false, // 发生错误时不要取消监听
    );
  }

  /// 启动心跳检测
  void _startHeartbeat() {
    // 取消现有心跳
    _stopHeartbeat();

    // 重置计数器
    _missedHeartbeats = 0;

    // 启动新的心跳定时器
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      _sendHeartbeat();
    });
  }

  /// 停止心跳检测
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 发送心跳消息
  void _sendHeartbeat() {
    // 检查自上次活动以来的时间
    final now = DateTime.now();
    final timeSinceLastActivity = now.difference(_lastActivity);

    // 如果最近有活动，跳过本次心跳
    if (timeSinceLastActivity < _heartbeatInterval) {
      return;
    }

    if (_channel != null &&
        connectionStatusNotifier.value == WSConnectionStatus.connected) {
      try {
        // 发送心跳消息
        _channel!.sink.add(jsonEncode(
            {'type': 'ping', 'timestamp': now.millisecondsSinceEpoch}));

        // 启动超时计时器
        Timer(_heartbeatTimeout, () {
          // 如果没有收到响应，增加计数器
          if (connectionStatusNotifier.value == WSConnectionStatus.connected) {
            _missedHeartbeats++;
            _log('未收到心跳响应，已错过: $_missedHeartbeats/$_maxMissedHeartbeats');

            // 如果错过太多心跳，认为连接已断开
            if (_missedHeartbeats >= _maxMissedHeartbeats) {
              _log('心跳检测失败，尝试重连');

              // 更新状态
              connectionStatusNotifier.value = WSConnectionStatus.disconnected;
              errorMessageNotifier.value = "心跳检测失败，服务器无响应";
              errorTypeNotifier.value = WSErrorType.connectionClosed;

              // 关闭并重连
              _cleanup();
              _scheduleReconnect();
            }
          }
        });
      } catch (e) {
        _log('发送心跳消息失败: $e');

        // 更新错过的心跳计数
        _missedHeartbeats++;

        if (_missedHeartbeats >= _maxMissedHeartbeats) {
          _log('心跳检测失败，尝试重连');

          // 更新状态
          connectionStatusNotifier.value = WSConnectionStatus.disconnected;

          // 关闭并重连
          _cleanup();
          _scheduleReconnect();
        }
      }
    }
  }

  /// 更新最后活动时间
  void _updateLastActivity() {
    _lastActivity = DateTime.now();
    // 重置错过的心跳计数
    _missedHeartbeats = 0;
  }

  // 安排重新连接
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 10;

  void _scheduleReconnect() {
    // 取消任何现有的重连计时器
    _reconnectTimer?.cancel();

    // 如果已达到最大重试次数，转为失败状态但不停止尝试重连
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _log('达到最大重连尝试次数($_maxReconnectAttempts)，状态转为失败但仍会尝试重连');
      connectionStatusNotifier.value = WSConnectionStatus.failed;
      errorMessageNotifier.value = "无法连接到服务器，已尝试$_reconnectAttempts次";
      _notifyError("连接失败", "达到最大重试次数", WSErrorType.connectionFailed);

      // 仍然安排重连，但间隔更长
      _reconnectTimer = Timer(const Duration(seconds: 30), () async {
        _log('继续尝试重连...');
        connectionStatusNotifier.value = WSConnectionStatus.reconnecting;
        await connect();
      });

      return;
    }

    // 增加重连尝试次数
    _reconnectAttempts++;

    // 更新状态
    connectionStatusNotifier.value = WSConnectionStatus.reconnecting;
    reconnectAttemptsNotifier.value = _reconnectAttempts;

    // 使用指数退避策略计算等待时间
    // 初始1秒，然后2秒、4秒、8秒...最多30秒
    const baseDelay = 1000; // 1秒
    const maxDelay = 30000; // 30秒
    int backoffMs = baseDelay * (1 << min(_reconnectAttempts - 1, 5)); // 2的指数，但最多2^5
    backoffMs = min(backoffMs, maxDelay); // 不超过最大延迟

    _log('安排重连尝试 #$_reconnectAttempts，$backoffMs毫秒后执行');

    // 安排重连
    _reconnectTimer = Timer(Duration(milliseconds: backoffMs), () async {
      _log('执行重连尝试 #$_reconnectAttempts');
      await connect();
    });
  }

  /// 手动重新连接（供UI调用）
  Future<bool> manualReconnect() async {
    // 取消任何未完成的重连计时器
    _reconnectTimer?.cancel();

    // 重置连接状态
    connectionStatusNotifier.value = WSConnectionStatus.connecting;
    errorMessageNotifier.value = "正在尝试重新连接...";

    // 重置重连尝试计数
    _resetReconnectAttempts();

    // 尝试连接
    return await connect();
  }

  // 重置重连计数器
  void _resetReconnectAttempts() {
    _reconnectAttempts = 0;
    reconnectAttemptsNotifier.value = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// 清理所有资源并关闭连接
  void _cleanup() {
    // 停止心跳
    _stopHeartbeat();

    // 清除广播流
    _broadcastStream = null;

    // 关闭现有连接
    if (_channel != null) {
      try {
        _channel!.sink.close();
        _channel = null;
      } catch (e) {
        _log('关闭WebSocket通道时出错: $e');
      }
    }
  }

  /// 通知错误
  void _notifyError(String title, String message, WSErrorType type) {
    _errorController.add(message);
  }

  /// 断开连接
  void disconnect() {
    _channel?.sink.close();
    connectionStatusNotifier.value = WSConnectionStatus.disconnected;
  }

  /// 发送消息
  void sendMessage(Map<String, dynamic> data) {
    if (isConnected) {
      _channel!.sink.add(jsonEncode(data));
    } else {
      _log('无法发送消息，WebSocket未连接');
    }
  }

  /// 创建游戏
  void createGame(List<dynamic> players) {
    sendMessage({
      'type': 'createGame',
      'players': players
    });
  }

  /// 加入游戏
  void joinGame(String gameId, String playerId) {
    sendMessage({
      'type': 'joinGame',
      'gameId': gameId,
      'playerId': playerId
    });
  }

  /// 添加玩家
  void addPlayer(Map<String, dynamic> player) {
    sendMessage({
      'type': 'addPlayer',
      'player': player
    });
  }

  /// 发送玩家操作
  void sendAction(String action, {int? amount}) {
    final Map<String, dynamic> data = {
      'type': 'playerAction',
      'action': action,
    };

    if (amount != null) {
      data['amount'] = amount;
    }

    sendMessage(data);
  }

  /// 请求游戏状态
  void getGameState() {
    sendMessage({
      'type': 'getGameState',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// 开始游戏
  void startGame(String gameId) {
    sendMessage({
      'type': 'startGame',
      'gameId': gameId,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });
  }

  /// 重置游戏
  void resetGame() {
    sendMessage({
      'type': 'resetGame'
    });
  }

  /// 发送暂停游戏请求
  void pauseGame() {
    sendMessage({
      'type': 'pauseGame',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// 发送继续游戏请求
  void resumeGame() {
    sendMessage({
      'type': 'resumeGame',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// 发送下一步请求
  void nextStep() {
    sendMessage({
      'type': 'nextStep',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// 处理接收到的消息（只做分发，不做游戏逻辑决策）
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      switch (data['type']) {
        // 游戏状态相关消息统一交给游戏状态流，由界面层决定如何处理
        case 'gameState':
        case 'gameStateUpdate':
        case 'gameStarted':
        case 'gameCreated':
        case 'gameReset':
        case 'gameStageChanged':
          _gameStateController.add(data);
          break;

        case 'playerActionProcessed':
          _playerActionController.add(data);
          break;

        case 'aiAgentError':
          _aiAgentErrorController.add(data);
          break;

        case 'aiAgentCreated':
          _aiAgentCreatedController.add(data);
          break;

        case 'thinkingUpdated':
          _thinkingUpdatedController.add(data['record']);
          break;

        case 'waitingForHumanAction':
          // 由界面层决定如何响应（本项目中所有玩家都是AI）
          _waitingForHumanActionController.add(data);
          break;

        case 'aiThinking':
          // 处理AI正在思考的消息
          _thinkingUpdatedController.add({
            'playerId': data['playerId'],
            'thinking': '正在思考...',
            'timestamp': data['timestamp'],
            'isProcessing': true
          });
          break;

        case 'pong':
          // 心跳响应已通过_updateLastActivity处理
          break;

        case 'error':
          _log('服务器错误: ${data['message']}');
          _errorController.add(data['message']);
          break;

        default:
          _log('未处理的消息类型: ${data['type']}');
      }
    } catch (e) {
      _log('处理消息错误: $e');
    }
  }

  /// 释放资源
  void dispose() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _errorController.close();
    _gameStateController.close();
    _playerActionController.close();
    _aiAgentErrorController.close();
    _aiAgentCreatedController.close();
    _thinkingUpdatedController.close();
    _waitingForHumanActionController.close();
  }

  // 判断WebSocket是否已连接
  bool get isConnected =>
      _channel != null &&
      connectionStatusNotifier.value == WSConnectionStatus.connected;
}
