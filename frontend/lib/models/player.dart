import 'poker_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class Player {
  final String id;
  final String name;
  final int position; // 位置，从1开始
  final List<PokerCard> cards; // 手牌
  int chips; // 筹码数量
  int bet; // 当前下注金额
  bool isActive; // 是否还在当前局中
  bool isCurrent; // 是否是当前行动玩家
  bool isDealer; // 是否是庄家
  String? action; // 最后一次执行的动作
  String? aiModel; // AI模型名称
  Color? modelColor; // AI模型颜色

  Player({
    required this.id,
    required this.name,
    required this.position,
    required this.chips,
    this.bet = 0,
    this.isActive = true,
    this.isCurrent = false,
    this.isDealer = false,
    this.action,
    this.aiModel,
    this.modelColor,
    List<PokerCard>? cards,
  }) : cards = cards ?? [];

  // 从JSON创建玩家对象
  factory Player.fromJson(Map<String, dynamic> json) {
    List<PokerCard> cards = [];
    if (json['cards'] != null) {
      try {
        cards = (json['cards'] as List)
            .where((card) => card != null)
            .map((card) => PokerCard.fromString(card))
            .toList();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('解析玩家手牌错误: $e');
        }
      }
    }

    // 安全解析整数值，确保它们有默认值
    int? positionRaw;
    if (json['position'] != null) {
      positionRaw = json['position'] is int
          ? json['position'] as int
          : int.tryParse(json['position'].toString());
    }

    // 确保位置是有效的（1-8）
    int position = positionRaw ?? 0;

    // 如果位置无效（0或null），分配一个随机位置
    if (position <= 0) {
      // 使用玩家ID作为随机种子以确保一致性
      final String playerId = json['id']?.toString() ?? 'unknown';
      final random = Random(playerId.hashCode);
      position = random.nextInt(8) + 1; // 1到8之间的随机数
    }

    // 确保如果JSON中有aiModel，它被正确保留
    // 检查多个可能的字段名
    String? aiModel;
    if (json['aiModel'] != null) {
      aiModel = json['aiModel'].toString();
    } else if (json['ai_model'] != null) {
      aiModel = json['ai_model'].toString();
    } else if (json['model'] != null) {
      aiModel = json['model'].toString();
    }

    // 标准化模型名称
    if (aiModel != null) {
      if (aiModel.contains('gpt-4o-mini')) {
        aiModel = 'ChatGPT-Mini';
      } else if (aiModel.contains('gpt-4o')) {
        aiModel = 'ChatGPT-4O';
      } else if (aiModel.contains('claude')) {
        aiModel = 'Claude';
      } else if (aiModel.contains('grok')) {
        aiModel = 'Grok';
      } else if (aiModel.contains('gemini')) {
        aiModel = 'Gemini';
      } else if (aiModel.contains('deepseek')) {
        aiModel = 'DeepSeek';
      } else if (aiModel.contains('sonar')) {
        aiModel = 'Sonar';
      } else if (aiModel.contains('qwen')) {
        aiModel = 'Qwen';
      }
    }

    // 为特定AI模型设置颜色
    Color? modelColor;
    if (aiModel != null) {
      // 根据不同的模型名称变体匹配颜色
      if (aiModel.contains('ChatGPT') ||
          aiModel.contains('GPT-4') ||
          aiModel.contains('GPT4')) {
        modelColor = Colors.green.shade700;
      } else if (aiModel.contains('Claude')) {
        modelColor = Colors.orange.shade700;
      } else if (aiModel.contains('Gemini')) {
        modelColor = Colors.blue.shade700;
      } else if (aiModel.contains('DeepSeek')) {
        modelColor = Colors.purple.shade700;
      } else if (aiModel.contains('Grok')) {
        modelColor = Colors.red.shade700;
      } else if (aiModel.contains('Ernie')) {
        modelColor = Colors.teal.shade700;
      } else {
        modelColor = Colors.grey.shade700;
      }
    }

    final int chips = json['chips'] == null
        ? 1000
        : (json['chips'] is int
            ? json['chips'] as int
            : int.tryParse(json['chips'].toString()) ?? 1000);

    int bet = 0;
    if (json['bet'] != null) {
      bet = int.tryParse(json['bet'].toString()) ?? 0;
    }

    // 处理布尔字段（兼容 isActive/folded 两种写法）
    bool isActive = true;
    if (json['isActive'] != null) {
      isActive = json['isActive'] is bool
          ? json['isActive']
          : json['isActive'].toString().toLowerCase() == 'true';
    } else if (json['folded'] != null) {
      isActive = json['folded'] is bool
          ? !(json['folded'] as bool)
          : json['folded'].toString().toLowerCase() != 'true';
    }

    // 兼容 isCurrent/isTurn 两种写法
    bool isCurrent = false;
    if (json['isCurrent'] != null) {
      isCurrent = json['isCurrent'] is bool
          ? json['isCurrent']
          : json['isCurrent'].toString().toLowerCase() == 'true';
    } else if (json['isTurn'] != null) {
      isCurrent = json['isTurn'] is bool
          ? json['isTurn']
          : json['isTurn'].toString().toLowerCase() == 'true';
    }

    // 处理是否为庄家
    bool isDealer = false;
    if (json['isDealer'] != null) {
      isDealer = json['isDealer'] is bool
          ? json['isDealer']
          : json['isDealer'].toString().toLowerCase() == 'true';
    } else if (json['dealerIndex'] != null && json['position'] != null) {
      // 如果dealerIndex等于position-1，则为庄家
      int dealerIndex = int.tryParse(json['dealerIndex'].toString()) ?? -1;
      int playerPosition = int.tryParse(json['position'].toString()) ?? 0;
      isDealer = dealerIndex == playerPosition - 1;
    }

    // 构建Player对象
    return Player(
      id: json['id']?.toString() ??
          'player_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name']?.toString() ?? 'Player',
      position: position,
      chips: chips,
      bet: bet,
      isActive: isActive,
      isCurrent: isCurrent,
      isDealer: isDealer,
      action: json['action']?.toString(),
      aiModel: aiModel,
      modelColor: modelColor,
      cards: cards,
    );
  }

  // 判断是否为AI玩家
  bool get isAI => aiModel != null;

  // 获取玩家位置描述
  String get positionName {
    switch (position) {
      case 1:
        return '小盲';
      case 2:
        return '大盲';
      case 9:
        return 'BTN';
      default:
        return position.toString();
    }
  }

  // 创建一个更新后的玩家对象
  Player copyWith({
    int? chips,
    int? bet,
    bool? isActive,
    bool? isCurrent,
    bool? isDealer,
    String? action,
    List<PokerCard>? cards,
    String? aiModel,
    Color? modelColor,
  }) {
    return Player(
      id: id,
      name: name,
      position: position,
      chips: chips ?? this.chips,
      bet: bet ?? this.bet,
      isActive: isActive ?? this.isActive,
      isCurrent: isCurrent ?? this.isCurrent,
      isDealer: isDealer ?? this.isDealer,
      action: action ?? this.action,
      cards: cards ?? this.cards,
      aiModel: aiModel ?? this.aiModel,
      modelColor: modelColor ?? this.modelColor,
    );
  }

  // 将玩家对象转换为JSON格式
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'chips': chips,
      'bet': bet,
      'cards': cards.map((card) => card.toString()).toList(),
      'isActive': isActive,
      'isCurrent': isCurrent,
      'isDealer': isDealer,
      'action': action,
      'aiModel': aiModel,
      // 不包含modelColor，因为Color不能直接转换为JSON
    };
  }
}
