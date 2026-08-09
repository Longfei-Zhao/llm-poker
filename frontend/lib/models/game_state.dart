import 'package:flutter/foundation.dart';

import '../constants.dart';
import 'player.dart';
import 'poker_card.dart';
import 'thinking_record.dart';

enum GameStage {
  waiting,  // 等待开始
  preflop,  // 翻牌前
  flop,     // 翻牌
  turn,     // 转牌
  river,    // 河牌
  showdown, // 摊牌
  finished  // 游戏结束
}

class GameState {
  final String? id; // 游戏ID，null表示尚未在后端创建游戏
  final GameStage stage;
  final List<Player> players;
  final List<PokerCard> communityCards;
  final int pot;
  final int currentBet;
  final int smallBlind;
  final int bigBlind;
  final int dealerIndex; // 庄家位置索引
  final int currentPlayerIndex; // 当前行动玩家的索引
  final Map<String, int>? winners; // 获胜玩家ID及获得筹码数量
  final List<ThinkingRecord> thinkingHistory; // 思考历史记录

  GameState({
    this.id,
    required this.stage,
    required this.players,
    required this.communityCards,
    required this.pot,
    required this.currentBet,
    this.smallBlind = GameConstants.smallBlind,
    this.bigBlind = GameConstants.bigBlind,
    required this.dealerIndex,
    required this.currentPlayerIndex,
    this.winners,
    this.thinkingHistory = const [],
  });

  // 从JSON创建游戏状态对象
  factory GameState.fromJson(Map<String, dynamic> json) {
    try {
      // 解析阶段/状态（兼容 stage/state 两种字段名）
      final String stageStr =
          json['stage']?.toString() ?? json['state']?.toString() ?? 'preflop';

      // 解析ID（兼容 id/gameId 两种字段名），缺失时保持null
      final String? id = json['id']?.toString() ?? json['gameId']?.toString();

      // 解析庄家位置
      final int dealerIndex = json['dealerIndex'] is int
          ? json['dealerIndex']
          : (int.tryParse(json['dealerIndex'].toString()) ?? 0);

      // 解析玩家
      final playersList = json['players'] as List? ?? [];
      final List<Player> players = [];
      final Set<int> usedPositions = {}; // 跟踪已使用的位置

      // 增强players处理逻辑，确保即使有无效数据也不会崩溃
      for (var playerJson in playersList) {
        if (playerJson == null) continue;
        try {
          // 确保每个玩家都有唯一ID
          playerJson['id'] ??=
              'player_${DateTime.now().millisecondsSinceEpoch}_${players.length}';

          Player player = Player.fromJson(playerJson);

          // 检查位置是否已被使用，冲突时重新分配
          if (player.position <= 0 || usedPositions.contains(player.position)) {
            int newPosition = 1;
            while (usedPositions.contains(newPosition) &&
                newPosition <= GameConstants.maxPlayers) {
              newPosition++;
            }
            player = Player(
              id: player.id,
              name: player.name,
              position: newPosition,
              chips: player.chips,
              bet: player.bet,
              isActive: player.isActive,
              isCurrent: player.isCurrent,
              isDealer: player.isDealer,
              action: player.action,
              aiModel: player.aiModel,
              modelColor: player.modelColor,
              cards: player.cards,
            );
          }
          usedPositions.add(player.position);
          players.add(player);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('解析玩家数据错误: $e，跳过此玩家');
          }
        }
      }

      // 解析公共牌
      final List<PokerCard> communityCards = [];
      if (json['communityCards'] != null) {
        for (var card in (json['communityCards'] as List)) {
          if (card == null) continue;
          try {
            communityCards.add(PokerCard.fromString(card));
          } catch (e) {
            if (kDebugMode) {
              debugPrint('解析卡牌错误: $e，跳过此卡牌: $card');
            }
          }
        }
      }

      // 解析游戏阶段
      GameStage stage;
      switch (stageStr.toLowerCase()) {
        case 'waiting':
          stage = GameStage.waiting;
          break;
        case 'preflop':
          stage = GameStage.preflop;
          break;
        case 'flop':
          stage = GameStage.flop;
          break;
        case 'turn':
          stage = GameStage.turn;
          break;
        case 'river':
          stage = GameStage.river;
          break;
        case 'showdown':
          stage = GameStage.showdown;
          break;
        case 'finished':
          stage = GameStage.finished;
          break;
        default:
          stage = GameStage.waiting;
      }

      // 解析获胜者
      Map<String, int>? winners;
      if (json['winners'] != null) {
        try {
          winners = {};
          for (final winner in (json['winners'] as List)) {
            if (winner != null && winner['playerId'] != null) {
              final String playerId = winner['playerId'].toString();
              final int amount = winner['amount'] is int
                  ? winner['amount']
                  : (int.tryParse(winner['amount'].toString()) ?? 0);
              winners[playerId] = amount;
            }
          }
        } catch (e) {
          winners = null;
        }
      }

      // 解析思考历史记录
      final List<ThinkingRecord> thinkingHistory = [];
      if (json['thinkingHistory'] != null) {
        for (var thinking in (json['thinkingHistory'] as List)) {
          if (thinking == null) continue;
          try {
            thinkingHistory.add(ThinkingRecord.fromJson(thinking));
          } catch (e) {
            if (kDebugMode) {
              debugPrint('解析思考记录错误: $e，跳过此记录');
            }
          }
        }
      }

      // 安全解析整数值
      final int pot = json['pot'] is int
          ? json['pot']
          : (int.tryParse(json['pot'].toString()) ?? 0);
      final int currentBet = json['currentBet'] is int
          ? json['currentBet']
          : (int.tryParse(json['currentBet'].toString()) ?? 0);
      final int smallBlind = json['smallBlind'] is int
          ? json['smallBlind']
          : (int.tryParse(json['smallBlind'].toString()) ??
              GameConstants.smallBlind);
      final int bigBlind = json['bigBlind'] is int
          ? json['bigBlind']
          : (int.tryParse(json['bigBlind'].toString()) ??
              GameConstants.bigBlind);
      final int currentPlayerIndex = json['currentPlayerIndex'] is int
          ? json['currentPlayerIndex']
          : (int.tryParse(json['currentPlayerIndex'].toString()) ?? 0);

      // 确保所有玩家都有正确的庄家标记
      for (int i = 0; i < players.length; i++) {
        players[i] = players[i].copyWith(isDealer: i == dealerIndex);
      }

      return GameState(
        id: id,
        stage: stage,
        players: players,
        communityCards: communityCards,
        pot: pot,
        currentBet: currentBet,
        smallBlind: smallBlind,
        bigBlind: bigBlind,
        dealerIndex: dealerIndex,
        currentPlayerIndex: currentPlayerIndex,
        winners: winners,
        thinkingHistory: thinkingHistory,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('解析GameState错误: $e');
      }
      return GameState(
        stage: GameStage.waiting,
        players: [],
        communityCards: [],
        pot: 0,
        currentBet: 0,
        dealerIndex: 0,
        currentPlayerIndex: 0,
      );
    }
  }

  // 获取当前玩家
  Player? get currentPlayer {
    if (currentPlayerIndex >= 0 && currentPlayerIndex < players.length) {
      return players[currentPlayerIndex];
    }
    return null;
  }

  // 获取庄家
  Player? get dealer {
    if (dealerIndex >= 0 && dealerIndex < players.length) {
      return players[dealerIndex];
    }
    return null;
  }

  // 获取小盲注玩家
  Player? get smallBlindPlayer {
    if (players.isEmpty) return null;
    final sbIndex = (dealerIndex + 1) % players.length;
    return players[sbIndex];
  }

  // 获取大盲注玩家
  Player? get bigBlindPlayer {
    if (players.isEmpty) return null;
    final bbIndex = (dealerIndex + 2) % players.length;
    return players[bbIndex];
  }

  // 获取指定玩家
  Player? getPlayerById(String playerId) {
    for (final player in players) {
      if (player.id == playerId) {
        return player;
      }
    }
    return null;
  }

  // 获取游戏阶段描述
  String get stageDescription {
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

  // 判断游戏是否正在进行中
  bool get isPlaying {
    return stage != GameStage.waiting && stage != GameStage.finished;
  }

  // 判断是否已在后端创建游戏
  bool get isCreated => id != null;

  // 判断是否为摊牌阶段
  bool get isShowdown {
    return stage == GameStage.showdown;
  }

  // 创建一个新的游戏状态对象，但只更改特定的属性
  GameState copyWith({
    String? id,
    GameStage? stage,
    List<Player>? players,
    List<PokerCard>? communityCards,
    int? pot,
    int? currentBet,
    int? smallBlind,
    int? bigBlind,
    int? dealerIndex,
    int? currentPlayerIndex,
    Map<String, int>? winners,
    List<ThinkingRecord>? thinkingHistory,
  }) {
    return GameState(
      id: id ?? this.id,
      stage: stage ?? this.stage,
      players: players ?? List<Player>.from(this.players), // 确保创建一个新的列表
      communityCards: communityCards ??
          List<PokerCard>.from(this.communityCards), // 确保创建一个新的列表
      pot: pot ?? this.pot,
      currentBet: currentBet ?? this.currentBet,
      smallBlind: smallBlind ?? this.smallBlind,
      bigBlind: bigBlind ?? this.bigBlind,
      dealerIndex: dealerIndex ?? this.dealerIndex,
      currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
      winners: winners ?? this.winners,
      thinkingHistory:
          thinkingHistory ?? List<ThinkingRecord>.from(this.thinkingHistory),
    );
  }

  // 将游戏状态转换为JSON格式
  Map<String, dynamic> toJson() {
    // 将GameStage转换为字符串
    String stateStr;
    switch (stage) {
      case GameStage.waiting:
        stateStr = 'waiting';
        break;
      case GameStage.preflop:
        stateStr = 'preflop';
        break;
      case GameStage.flop:
        stateStr = 'flop';
        break;
      case GameStage.turn:
        stateStr = 'turn';
        break;
      case GameStage.river:
        stateStr = 'river';
        break;
      case GameStage.showdown:
        stateStr = 'showdown';
        break;
      case GameStage.finished:
        stateStr = 'finished';
        break;
    }

    // 构建JSON对象
    return {
      'gameId': id,
      'state': stateStr,
      'players': players.map((player) => player.toJson()).toList(),
      'communityCards': communityCards.map((card) => card.toString()).toList(),
      'pot': pot,
      'currentBet': currentBet,
      'smallBlind': smallBlind,
      'bigBlind': bigBlind,
      'dealerIndex': dealerIndex,
      'currentPlayerIndex': currentPlayerIndex,
      'winners': winners?.entries
          .map((entry) => {
                'playerId': entry.key,
                'amount': entry.value,
              })
          .toList(),
      'thinkingHistory': thinkingHistory.map((record) => record.toJson()).toList(),
    };
  }
}
