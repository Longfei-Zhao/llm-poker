
/// 存储AI玩家思考过程的记录
class ThinkingRecord {
  final String playerId;      // 玩家ID
  final String playerName;    // 玩家名称
  final String? aiModel;      // AI模型名称
  final String content;       // 思考内容
  final String gameStage;     // 游戏阶段
  final String? action;       // 关联的动作
  final DateTime timestamp;   // 记录时间
  
  ThinkingRecord({
    required this.playerId,
    required this.playerName,
    this.aiModel,
    required this.content,
    required this.gameStage,
    this.action,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  // 从JSON创建思考记录对象
  factory ThinkingRecord.fromJson(Map<String, dynamic> json) {
    return ThinkingRecord(
      playerId: json['playerId'],
      playerName: json['playerName'],
      aiModel: json['aiModel'],
      content: json['content'],
      gameStage: json['gameStage'],
      action: json['action'],
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : DateTime.now(),
    );
  }
  
  // 将思考记录转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'playerId': playerId,
      'playerName': playerName,
      'aiModel': aiModel,
      'content': content,
      'gameStage': gameStage,
      'action': action,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  // 格式化显示的思考内容
  String get formattedContent {
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final modelStr = aiModel != null ? ' ($aiModel)' : '';
    
    return '$timeStr\n$playerName$modelStr:\n$content';
  }
  
  // 让思考记录可以直接转换为字符串显示
  @override
  String toString() {
    return formattedContent;
  }
} 