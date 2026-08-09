import 'package:flutter/material.dart';

/// 全局游戏常量
/// 盲注等数值与后端配置保持一致
class GameConstants {
  GameConstants._();

  // 盲注配置（与后端 config/index.js 保持一致）
  static const int smallBlind = 5;
  static const int bigBlind = 10;

  // 初始筹码
  static const int initialChips = 1000;

  // 最大玩家数
  static const int maxPlayers = 8;

  // 服务地址，可通过 --dart-define=WS_URL=... / --dart-define=AI_SERVICE_URL=... 覆盖
  static const String wsUrl =
      String.fromEnvironment('WS_URL', defaultValue: 'ws://localhost:3000');
  static const String aiServiceUrl = String.fromEnvironment('AI_SERVICE_URL',
      defaultValue: 'http://localhost:8000');

  // 可用的AI模型列表
  static const List<String> aiModels = [
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
  static const Map<String, Color> aiModelColors = {
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
  static const Map<String, String> aiModelLogos = {
    'ChatGPT-Mini': 'assets/images/llm_logos/openai.svg',
    'ChatGPT-4O': 'assets/images/llm_logos/openai.svg',
    'Claude': 'assets/images/llm_logos/anthropic.svg',
    'Grok': 'assets/images/llm_logos/xai.svg',
    'Gemini': 'assets/images/llm_logos/google.svg',
    'DeepSeek': 'assets/images/llm_logos/deepseek.svg',
    'Sonar': 'assets/images/llm_logos/perplexity.svg',
    'Qwen': 'assets/images/llm_logos/aliyun.svg',
  };
}
