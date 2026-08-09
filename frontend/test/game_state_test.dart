import 'package:flutter_test/flutter_test.dart';
import 'package:poker_app/constants.dart';
import 'package:poker_app/models/game_state.dart';

void main() {
  group('GameState.fromJson 字段别名容错', () {
    test('id字段', () {
      final byId = GameState.fromJson({'id': 'abc123', 'players': []});
      expect(byId.id, 'abc123');
      expect(byId.isCreated, isTrue);
    });

    test('gameId字段作为id别名', () {
      final byGameId = GameState.fromJson({'gameId': 'xyz789', 'players': []});
      expect(byGameId.id, 'xyz789');
    });

    test('id缺失时保持null（表示未创建）', () {
      final noId = GameState.fromJson({'players': []});
      expect(noId.id, isNull);
      expect(noId.isCreated, isFalse);
    });

    test('state字段作为stage别名', () {
      final byState = GameState.fromJson({'id': 'g', 'state': 'flop'});
      expect(byState.stage, GameStage.flop);

      final byStage = GameState.fromJson({'id': 'g', 'stage': 'river'});
      expect(byStage.stage, GameStage.river);

      final unknown = GameState.fromJson({'id': 'g', 'state': 'bogus'});
      expect(unknown.stage, GameStage.waiting);
    });

    test('玩家的isActive/folded与aiModel/ai_model别名', () {
      final state = GameState.fromJson({
        'id': 'g',
        'players': [
          {'id': 'p1', 'name': 'A', 'position': 1, 'folded': true, 'ai_model': 'Claude'},
          {'id': 'p2', 'name': 'B', 'position': 2, 'isActive': true, 'aiModel': 'Grok'},
        ],
      });

      expect(state.players.length, 2);
      expect(state.players[0].isActive, isFalse);
      expect(state.players[0].aiModel, 'Claude');
      expect(state.players[1].isActive, isTrue);
      expect(state.players[1].aiModel, 'Grok');
    });
  });

  group('GameState.fromJson 数值解析', () {
    test('盲注缺失时使用统一常量默认值', () {
      final state = GameState.fromJson({'id': 'g', 'players': []});
      expect(state.smallBlind, GameConstants.smallBlind);
      expect(state.bigBlind, GameConstants.bigBlind);
    });

    test('数值可从字符串强制转换', () {
      final state = GameState.fromJson({
        'id': 'g',
        'pot': '150',
        'currentBet': '20',
        'smallBlind': '5',
        'bigBlind': '10',
        'dealerIndex': '1',
        'currentPlayerIndex': '2',
      });
      expect(state.pot, 150);
      expect(state.currentBet, 20);
      expect(state.smallBlind, 5);
      expect(state.bigBlind, 10);
      expect(state.dealerIndex, 1);
      expect(state.currentPlayerIndex, 2);
    });

    test('公共牌解析，无效牌被跳过', () {
      final state = GameState.fromJson({
        'id': 'g',
        'communityCards': ['AS', 'Th', 'ZZ', '10D'],
      });
      expect(state.communityCards.length, 3);
      expect(state.communityCards.map((c) => c.toString()).toList(),
          ['AS', '10H', '10D']);
    });

    test('获胜者列表解析为映射', () {
      final state = GameState.fromJson({
        'id': 'g',
        'winners': [
          {'playerId': 'p1', 'amount': 300},
          {'playerId': 'p2', 'amount': '50'},
        ],
      });
      expect(state.winners, {'p1': 300, 'p2': 50});
    });

    test('dealerIndex标记对应玩家的isDealer', () {
      final state = GameState.fromJson({
        'id': 'g',
        'dealerIndex': 1,
        'players': [
          {'id': 'p1', 'name': 'A', 'position': 1},
          {'id': 'p2', 'name': 'B', 'position': 2},
        ],
      });
      expect(state.players[0].isDealer, isFalse);
      expect(state.players[1].isDealer, isTrue);
    });

    test('玩家位置冲突时重新分配', () {
      final state = GameState.fromJson({
        'id': 'g',
        'players': [
          {'id': 'p1', 'name': 'A', 'position': 1},
          {'id': 'p2', 'name': 'B', 'position': 1},
        ],
      });
      expect(state.players.length, 2);
      final positions = state.players.map((p) => p.position).toSet();
      expect(positions.length, 2);
    });

    test('完全非法的输入返回安全的空状态', () {
      final state = GameState.fromJson({'players': 'not-a-list'});
      expect(state.players, isEmpty);
      expect(state.stage, GameStage.waiting);
    });
  });

  group('GameState行为', () {
    test('isPlaying仅在进行中阶段为true', () {
      final waiting = GameState.fromJson({'id': 'g', 'state': 'waiting'});
      expect(waiting.isPlaying, isFalse);

      final flop = GameState.fromJson({'id': 'g', 'state': 'flop'});
      expect(flop.isPlaying, isTrue);

      final finished = GameState.fromJson({'id': 'g', 'state': 'finished'});
      expect(finished.isPlaying, isFalse);
    });

    test('toJson往返保留关键字段', () {
      final state = GameState.fromJson({
        'gameId': 'g1',
        'state': 'turn',
        'pot': 100,
        'currentBet': 20,
        'communityCards': ['AS', 'KH', 'TD', '2C'],
        'players': [
          {'id': 'p1', 'name': 'A', 'position': 1, 'chips': 900},
        ],
      });

      final json = state.toJson();
      expect(json['gameId'], 'g1');
      expect(json['state'], 'turn');
      expect(json['pot'], 100);
      expect(json['communityCards'], ['AS', 'KH', '10D', '2C']);

      // 再解析一遍保持一致
      final reparsed = GameState.fromJson(json);
      expect(reparsed.id, 'g1');
      expect(reparsed.stage, GameStage.turn);
      expect(reparsed.communityCards.length, 4);
    });
  });
}
