import '../constants.dart';
import '../models/player.dart';

/// 合并后端返回的玩家列表与本地已有玩家列表：
/// - 已存在的玩家保留本地的 position/aiModel/modelColor，其余字段取后端最新值
/// - 新玩家如缺少 aiModel，尝试从名称推断并补充模型颜色
/// - 后端返回空列表时保留本地玩家，避免状态丢失
List<Player> mergePlayers(List<Player> existing, List<Player> incoming) {
  if (incoming.isEmpty) {
    return existing;
  }

  final Map<String, Player> existingById = {
    for (final player in existing) player.id: player,
  };

  return incoming.map((player) {
    final Player? old = existingById[player.id];
    if (old != null) {
      return Player(
        id: player.id,
        name: player.name,
        position: old.position, // 保留原始位置
        chips: player.chips,
        bet: player.bet,
        isActive: player.isActive,
        isCurrent: player.isCurrent,
        isDealer: player.isDealer,
        action: player.action,
        aiModel: old.aiModel ?? player.aiModel, // 保留原始AI模型
        modelColor: old.modelColor ?? player.modelColor, // 保留原始模型颜色
        cards: player.cards,
      );
    }

    // 新玩家：如缺少 aiModel，尝试从名称推断
    String? aiModel = player.aiModel;
    if (aiModel == null || aiModel.isEmpty) {
      for (final model in GameConstants.aiModels) {
        if (player.name.contains(model)) {
          aiModel = model;
          break;
        }
      }
    }

    if (aiModel != null && aiModel.isNotEmpty && aiModel != player.aiModel) {
      return player.copyWith(
        aiModel: aiModel,
        modelColor: GameConstants.aiModelColors[aiModel],
      );
    }
    return player;
  }).toList();
}
