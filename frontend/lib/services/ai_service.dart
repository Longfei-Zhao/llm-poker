import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// AI服务状态枚举
enum AIServiceStatus {
  idle,     // 空闲状态
  creating, // 正在创建代理
  created,  // 代理创建成功
  thinking, // 正在思考/决策
  error     // 发生错误
}

/// AI模型连接服务
/// 负责与后端通信，创建AI代理并获取决策
class AIService {
  final String baseUrl;
  final http.Client _httpClient = http.Client();
  bool _isInitialized = false;
  int _requestCounter = 0;
  
  // 状态通知器
  final ValueNotifier<AIServiceStatus> statusNotifier = ValueNotifier(AIServiceStatus.idle);
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);
  
  // 缓存模型和代理信息
  final Map<String, Map<String, dynamic>> _agentCache = {};
  
  /// AI服务构造函数
  AIService({this.baseUrl = 'http://localhost:8000'}) {
    print('🔧 初始化AI服务，基础URL: $baseUrl');
    _isInitialized = true;
    print('✅ AI服务初始化完成');
  }
  
  /// 创建AI代理
  Future<Map<String, dynamic>> createAgent({
    required String playerId,
    required String name,
    required String provider,
    String? model,
    double temperature = 0.7,
  }) async {
    print('📥 发送创建AI代理请求 - 玩家ID: $playerId, 名称: $name, 提供商: $provider, 模型: ${model ?? "默认"}');
    _requestCounter++;
    final requestId = _requestCounter;
    
    try {
      final response = await _httpClient.post(
        Uri.parse('$baseUrl/api/agents'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'player_id': playerId,
          'name': name,
          'provider': provider,
          'model': model,
          'temperature': temperature,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ 代理创建成功 [请求#$requestId] - 玩家ID: $playerId, 提供商: $provider, 模型: ${responseData['model']}');
        return responseData;
      } else {
        final errorMessage = '创建代理失败 [请求#$requestId] - 状态码: ${response.statusCode}, 响应: ${response.body}';
        print('❌ $errorMessage');
        throw Exception(errorMessage);
      }
    } catch (e) {
      final errorMessage = '创建代理请求异常 [请求#$requestId] - 错误: $e';
      print('❌ $errorMessage');
      rethrow;
    }
  }
  
  /// 批量创建AI代理
  Future<List<Map<String, dynamic>>> createAgentsBatch(
      List<Map<String, dynamic>> agentConfigs) async {
    print('📥 发送批量创建AI代理请求 - 数量: ${agentConfigs.length}');
    final results = <Map<String, dynamic>>[];
    final futures = <Future<void>>[];

    for (final config in agentConfigs) {
      final future = createAgent(
        playerId: config['player_id'],
        name: config['name'],
        provider: config['provider'],
        model: config['model'],
        temperature: config['temperature'] ?? 0.7,
      ).then((result) {
        results.add(result);
      }).catchError((error) {
        print('⚠️ 批量创建中单个代理创建失败 - 玩家ID: ${config['player_id']}, 错误: $error');
        // 添加错误信息到结果中
        results.add({
          'player_id': config['player_id'],
          'name': config['name'],
          'error': error.toString(),
          'status': 'failed',
        });
      });

      futures.add(future);
    }

    // 等待所有请求完成
    await Future.wait(futures);
    print('📤 批量创建AI代理完成 - 成功: ${results.where((r) => !r.containsKey('error')).length}/${agentConfigs.length}');
    return results;
  }
  
  /// 获取AI决策
  Future<Map<String, dynamic>> getDecision({
    required String playerId,
    required Map<String, dynamic> gameState,
    required List<String> validActions,
    required int minBet,
    required int maxBet,
  }) async {
    print('📥 发送获取AI决策请求 - 玩家ID: $playerId, 有效动作: $validActions');
    _requestCounter++;
    final requestId = _requestCounter;
    
    try {
      final response = await _httpClient.post(
        Uri.parse('$baseUrl/api/decision'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'player_id': playerId,
          'game_state': gameState,
          'valid_actions': validActions,
          'min_bet': minBet,
          'max_bet': maxBet,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ 获取决策成功 [请求#$requestId] - 玩家ID: $playerId, 动作: ${responseData['action']}, 金额: ${responseData['amount']}');
        return responseData;
      } else {
        final errorMessage = '获取决策失败 [请求#$requestId] - 状态码: ${response.statusCode}, 响应: ${response.body}';
        print('❌ $errorMessage');
        throw Exception(errorMessage);
      }
    } catch (e) {
      final errorMessage = '获取决策请求异常 [请求#$requestId] - 错误: $e';
      print('❌ $errorMessage');
      rethrow;
    }
  }
  
  /// 健康检查
  Future<bool> checkHealth() async {
    print('📥 发送AI服务健康检查请求');
    _requestCounter++;
    final requestId = _requestCounter;
    
    try {
      final response = await _httpClient.get(Uri.parse('$baseUrl/api/health'));

      if (response.statusCode == 200) {
        print('✅ 健康检查通过 [请求#$requestId] - 响应: ${response.body}');
        return true;
      } else {
        print('❌ 健康检查失败 [请求#$requestId] - 状态码: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ 健康检查异常 [请求#$requestId] - 错误: $e');
      return false;
    }
  }
  
  /// 删除AI代理
  Future<bool> deleteAgent(String playerId) async {
    print('📥 发送删除AI代理请求 - 玩家ID: $playerId');
    _requestCounter++;
    final requestId = _requestCounter;
    
    try {
      final response = await _httpClient.delete(
        Uri.parse('$baseUrl/api/agents/$playerId'),
      );

      if (response.statusCode == 200) {
        print('✅ 代理删除成功 [请求#$requestId] - 玩家ID: $playerId');
        return true;
      } else {
        print('❌ 代理删除失败 [请求#$requestId] - 状态码: ${response.statusCode}, 响应: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ 代理删除异常 [请求#$requestId] - 错误: $e');
      return false;
    }
  }
  
  /// 删除所有AI代理
  Future<bool> deleteAllAgents() async {
    print('📥 发送删除所有AI代理请求');
    _requestCounter++;
    final requestId = _requestCounter;
    
    try {
      final response = await _httpClient.delete(
        Uri.parse('$baseUrl/api/agents'),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ 所有代理删除成功 [请求#$requestId] - 删除数量: ${responseData['deleted_count'] ?? "未知"}');
        return true;
      } else {
        print('❌ 删除所有代理失败 [请求#$requestId] - 状态码: ${response.statusCode}, 响应: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ 删除所有代理异常 [请求#$requestId] - 错误: $e');
      return false;
    }
  }
  
  /// 获取所有AI代理列表
  Future<List<Map<String, dynamic>>> listAgents() async {
    print('📥 发送获取AI代理列表请求');
    _requestCounter++;
    final requestId = _requestCounter;
    
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/api/agents'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> responseData = jsonDecode(response.body);
        print('✅ 获取代理列表成功 [请求#$requestId] - 代理数量: ${responseData.length}');
        return responseData.cast<Map<String, dynamic>>();
      } else {
        print('❌ 获取代理列表失败 [请求#$requestId] - 状态码: ${response.statusCode}, 响应: ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ 获取代理列表异常 [请求#$requestId] - 错误: $e');
      return [];
    }
  }
  
  /// 将模型名称映射到对应的提供商和模型
  Map<String, String> _mapModelToProvider(String model) {
    // 根据AI模型名称获取对应的提供商和模型
    switch (model) {
      case 'ChatGPT-Mini':
        return {
          'provider': 'openai',
          'model': 'gpt-4o-mini'
        };
      case 'ChatGPT-4O':
        return {
          'provider': 'openai',
          'model': 'gpt-4o'
        };
      case 'Claude':
        return {
          'provider': 'anthropic',
          'model': 'claude-3-7-sonnet-20250219'
        };
      case 'Grok':
        return {
          'provider': 'xai',
          'model': 'grok-2'
        };
      case 'Gemini':
        return {
          'provider': 'google',
          'model': 'gemini-2.0-pro-exp-02-05'
        };
      case 'DeepSeek':
        return {
          'provider': 'deepseek',
          'model': 'deepseek-chat'
        };
      case 'Sonar':
        return {
          'provider': 'perplexity',
          'model': 'sonar-medium-chat'
        };
      case 'Qwen':
        return {
          'provider': 'aliyun',
          'model': 'qwen-plus'
        };
      default:
        return {
          'provider': 'openai',
          'model': 'gpt-4o'
        };
    }
  }
  
  /// 销毁AI服务
  void dispose() {
    print('🧹 清理AI服务资源');
    _httpClient.close();
    print('👋 AI服务销毁完成');
    statusNotifier.dispose();
    errorNotifier.dispose();
  }
} 