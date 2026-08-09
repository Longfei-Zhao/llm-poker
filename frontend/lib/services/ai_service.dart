import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../constants.dart';

/// AI服务状态枚举
enum AIServiceStatus {
  idle,     // 空闲状态
  creating, // 正在创建代理
  created,  // 代理创建成功
  thinking, // 正在思考/决策
  error     // 发生错误
}

/// AI服务
/// AI代理的创建与决策均由后端通过WebSocket代理完成，
/// 这里只保留健康检查和代理清理等辅助接口
class AIService {
  final String baseUrl;
  final http.Client _httpClient = http.Client();

  AIService({this.baseUrl = GameConstants.aiServiceUrl});

  /// 健康检查
  Future<bool> checkHealth() async {
    try {
      final response = await _httpClient.get(Uri.parse('$baseUrl/api/health'));
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI服务健康检查异常: $e');
      }
      return false;
    }
  }

  /// 删除AI代理
  Future<bool> deleteAgent(String playerId) async {
    try {
      final response = await _httpClient.delete(
        Uri.parse('$baseUrl/api/agents/$playerId'),
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('删除AI代理异常 - 玩家ID: $playerId, 错误: $e');
      }
      return false;
    }
  }

  /// 删除所有AI代理
  Future<bool> deleteAllAgents() async {
    try {
      final response = await _httpClient.delete(
        Uri.parse('$baseUrl/api/agents'),
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('删除所有AI代理异常: $e');
      }
      return false;
    }
  }

  /// 销毁AI服务
  void dispose() {
    _httpClient.close();
  }
}
