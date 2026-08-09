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
  final String id;
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
    required this.id,
    required this.stage,
    required this.players,
    required this.communityCards,
    required this.pot,
    required this.currentBet,
    required this.smallBlind,
    required this.bigBlind,
    required this.dealerIndex,
    required this.currentPlayerIndex,
    this.winners,
    this.thinkingHistory = const [],
  });

  // 从JSON创建游戏状态对象
  factory GameState.fromJson(Map<String, dynamic> json) {
    print('GameState.fromJson: 解析游戏状态');
    
    try {
      // 解析阶段/状态
      String stageStr;
      if (json['stage'] != null) {
        stageStr = json['stage'].toString();
      } else if (json['state'] != null) {
        stageStr = json['state'].toString();
      } else {
        stageStr = 'preflop';
      }
      
      // 解析ID
      String id;
      if (json['id'] != null) {
        id = json['id'].toString();
      } else if (json['gameId'] != null) {
        id = json['gameId'].toString();
      } else {
        // 生成一个随机ID作为后备
        id = 'game_${DateTime.now().millisecondsSinceEpoch}';
      }
      
      // 解析庄家位置
      int dealerIndex = 0;
      try {
        dealerIndex = json['dealerIndex'] is int
          ? json['dealerIndex']
          : (int.tryParse(json['dealerIndex'].toString()) ?? 0);
      } catch (e) {
        print('解析dealerIndex错误: $e，使用默认值0');
      }
            
      // 解析玩家
      final playersList = json['players'] as List? ?? [];
      final List<Player> players = [];
      final Set<int> usedPositions = {}; // 跟踪已使用的位置

      try {
        print('开始解析${playersList.length}个玩家');
        
        // 增强players处理逻辑，确保即使有无效数据也不会崩溃
        for (var playerJson in playersList) {
          if (playerJson != null) {
            try {
              // 确保每个玩家都有唯一ID
              if (playerJson['id'] == null) {
                playerJson['id'] = 'player_${DateTime.now().millisecondsSinceEpoch}_${players.length}';
                print('为玩家创建临时ID: ${playerJson['id']}');
              }
              
              Player player = Player.fromJson(playerJson);

              // 检查位置是否已被使用
              if (player.position > 0 && !usedPositions.contains(player.position)) {
                usedPositions.add(player.position);
                players.add(player);
                print('添加玩家: ID=${player.id}, 位置=${player.position}, 模型=${player.aiModel}');
              } else {
                // 如果位置冲突，分配一个新位置
                int newPosition = 1;
                while (usedPositions.contains(newPosition) && newPosition <= 8) {
                  newPosition++;
                }

                print('玩家位置冲突，重新分配: 原位置=${player.position}, 新位置=$newPosition, 玩家ID=${player.id}');

                // 创建一个新的Player对象，使用新位置
                Player adjustedPlayer = Player(
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

                usedPositions.add(newPosition);
                players.add(adjustedPlayer);
                print('添加调整后的玩家: ID=${adjustedPlayer.id}, 位置=${adjustedPlayer.position}');
              }

              // 明确设置庄家属性
              players[players.length - 1] = players[players.length - 1].copyWith(
                isDealer: players.length - 1 == dealerIndex
              );
              
              if (players[players.length - 1].isDealer) {
                print('设置庄家: 玩家 ${players[players.length - 1].name} (索引: ${players.length - 1}, 位置: ${players[players.length - 1].position})');
              }
            } catch (e) {
              print('解析玩家数据错误: $e，跳过此玩家');
              print('问题玩家数据: $playerJson');
            }
          }
        }

        // 如果没有玩家，打印警告
        if (players.isEmpty) {
          print('警告: 解析后没有玩家数据');
        } else {
          print('成功解析 ${players.length} 个玩家，使用的位置: $usedPositions');
        }
      } catch (e) {
        print('解析玩家列表错误: $e');
      }
      
      // 解析公共牌
      List<PokerCard> communityCards = [];
      if (json.containsKey('communityCards') && json['communityCards'] != null) {
        try {
          final cardsList = json['communityCards'] as List;
          print('开始解析${cardsList.length}张公共牌');
          
          for (var card in cardsList) {
            if (card != null) {
              try {
                PokerCard pokerCard = PokerCard.fromString(card);
                communityCards.add(pokerCard);
                print('添加公共牌: ${pokerCard.toString()}');
              } catch (e) {
                print('解析卡牌错误: $e，跳过此卡牌: $card');
              }
            }
          }
          
          print('成功解析${communityCards.length}张公共牌');
        } catch (e) {
          print('解析公共牌错误: $e');
        }
      } else {
        print('没有公共牌数据');
      }
      
      // 解析游戏阶段
      GameStage stage;
      print('解析游戏阶段: $stageStr');
      
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
          print('未知游戏阶段: $stageStr，使用默认值waiting');
          stage = GameStage.waiting;
      }
      
      // 解析获胜者
      Map<String, int>? winners;
      if (json.containsKey('winners') && json['winners'] != null) {
        try {
          winners = {};
          final winnersList = json['winners'] as List;
          print('开始解析${winnersList.length}个获胜者');
          
          for (final winner in winnersList) {
            if (winner != null && winner['playerId'] != null) {
              final String playerId = winner['playerId'].toString();
              final int amount = winner['amount'] is int 
                  ? winner['amount'] 
                  : (int.tryParse(winner['amount'].toString()) ?? 0);
                  
              winners[playerId] = amount;
              print('添加获胜者: ID=$playerId, 获得筹码=$amount');
            }
          }
          
          print('成功解析${winners.length}个获胜者');
        } catch (e) {
          print('解析获胜者数据错误: $e');
          winners = null;
        }
      } else {
        print('没有获胜者数据');
      }

      // 解析思考历史记录
      List<ThinkingRecord> thinkingHistory = [];
      if (json.containsKey('thinkingHistory') && json['thinkingHistory'] != null) {
        try {
          final thinkingList = json['thinkingHistory'] as List;
          print('开始解析${thinkingList.length}条思考记录');
          
          for (var thinking in thinkingList) {
            if (thinking != null) {
              try {
                ThinkingRecord record = ThinkingRecord.fromJson(thinking);
                thinkingHistory.add(record);
                print('添加思考记录: 玩家=${record.playerId}, 时间=${record.timestamp}');
              } catch (e) {
                print('解析思考记录错误: $e，跳过此记录');
              }
            }
          }
          
          print('成功解析${thinkingHistory.length}条思考记录');
        } catch (e) {
          print('解析思考历史错误: $e');
        }
      } else {
        print('没有思考历史数据');
      }

      // 安全解析整数值
      int pot = 0;
      try {
        pot = json['pot'] is int 
            ? json['pot'] 
            : (int.tryParse(json['pot'].toString()) ?? 0);
      } catch (e) {
        print('解析pot错误: $e，使用默认值0');
      }
      
      int currentBet = 0;
      try {
        currentBet = json['currentBet'] is int 
            ? json['currentBet'] 
            : (int.tryParse(json['currentBet'].toString()) ?? 0);
      } catch (e) {
        print('解析currentBet错误: $e，使用默认值0');
      }
      
      int smallBlind = 5;
      try {
        smallBlind = json['smallBlind'] is int 
            ? json['smallBlind'] 
            : (int.tryParse(json['smallBlind'].toString()) ?? 5);
      } catch (e) {
        print('解析smallBlind错误: $e，使用默认值5');
      }
      
      int bigBlind = 10;
      try {
        bigBlind = json['bigBlind'] is int 
            ? json['bigBlind'] 
            : (int.tryParse(json['bigBlind'].toString()) ?? 10);
      } catch (e) {
        print('解析bigBlind错误: $e，使用默认值10');
      }
      
      int currentPlayerIndex = 0;
      try {
        currentPlayerIndex = json['currentPlayerIndex'] is int 
            ? json['currentPlayerIndex'] 
            : (int.tryParse(json['currentPlayerIndex'].toString()) ?? 0);
      } catch (e) {
        print('解析currentPlayerIndex错误: $e，使用默认值0');
      }

      print('GameState解析完成: ID=$id, 玩家数=${players.length}, 阶段=$stage');

      // 确保所有玩家都有正确的庄家标记
      for (int i = 0; i < players.length; i++) {
        // 检查dealer的逻辑
        bool oldIsDealer = players[i].isDealer;
        bool shouldBeDealer = i == dealerIndex;
        players[i] = players[i].copyWith(
          isDealer: shouldBeDealer
        );
        
        print('检查庄家标记: 玩家 ${players[i].name}, 索引 $i, 位置 ${players[i].position}');
        print('dealerIndex = $dealerIndex, 原来是否庄家: $oldIsDealer, 现在是否庄家: ${players[i].isDealer}');
        
        if (players[i].isDealer) {
          print('🎲 设置庄家: 玩家 ${players[i].name} (索引: $i, 位置: ${players[i].position})');
        }
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
      print('解析GameState错误: $e');
      return GameState(
        id: 'game_${DateTime.now().millisecondsSinceEpoch}',
        stage: GameStage.waiting,
        players: [],
        communityCards: [],
        pot: 0,
        currentBet: 0,
        smallBlind: 5,
        bigBlind: 10,
        dealerIndex: 0,
        currentPlayerIndex: 0,
        winners: null,
        thinkingHistory: [],
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
    final sbIndex = (dealerIndex + 1) % players.length;
    return players[sbIndex];
  }
  
  // 获取大盲注玩家
  Player? get bigBlindPlayer {
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
      communityCards: communityCards ?? List<PokerCard>.from(this.communityCards), // 确保创建一个新的列表
      pot: pot ?? this.pot,
      currentBet: currentBet ?? this.currentBet,
      smallBlind: smallBlind ?? this.smallBlind,
      bigBlind: bigBlind ?? this.bigBlind,
      dealerIndex: dealerIndex ?? this.dealerIndex,
      currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
      winners: winners ?? this.winners,
      thinkingHistory: thinkingHistory ?? List<ThinkingRecord>.from(this.thinkingHistory),
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
      'winners': winners != null
          ? winners!.entries.map((entry) => {
              'playerId': entry.key,
              'amount': entry.value,
            }).toList()
          : null,
      'thinkingHistory': thinkingHistory.map((record) => record.toJson()).toList(),
    };
  }
} 