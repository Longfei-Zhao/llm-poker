import 'package:flutter_test/flutter_test.dart';
import 'package:poker_app/models/player.dart';
import 'package:poker_app/models/poker_card.dart';

void main() {
  group('Player.fromJson', () {
    test('基本字段解析', () {
      final player = Player.fromJson({
        'id': 'p1',
        'name': 'Claude',
        'position': 3,
        'chips': 800,
        'bet': 50,
        'isActive': true,
        'isCurrent': false,
        'isDealer': true,
        'cards': ['AS', 'KH'],
      });

      expect(player.id, 'p1');
      expect(player.name, 'Claude');
      expect(player.position, 3);
      expect(player.chips, 800);
      expect(player.bet, 50);
      expect(player.isActive, isTrue);
      expect(player.isDealer, isTrue);
      expect(player.cards.length, 2);
      expect(player.cards[0].toString(), 'AS');
    });

    test('数字字段可以从字符串强制转换', () {
      final player = Player.fromJson({
        'id': 'p1',
        'name': 'x',
        'position': '4',
        'chips': '650',
        'bet': '25',
      });

      expect(player.position, 4);
      expect(player.chips, 650);
      expect(player.bet, 25);
    });

    test('chips缺失时默认1000，bet缺失时默认0', () {
      final player = Player.fromJson({'id': 'p1', 'name': 'x', 'position': 1});
      expect(player.chips, 1000);
      expect(player.bet, 0);
    });

    test('folded字段可作为isActive的反义别名', () {
      final folded = Player.fromJson(
          {'id': 'p1', 'name': 'x', 'position': 1, 'folded': true});
      expect(folded.isActive, isFalse);

      final active = Player.fromJson(
          {'id': 'p2', 'name': 'x', 'position': 2, 'folded': false});
      expect(active.isActive, isTrue);

      // 字符串形式
      final foldedStr = Player.fromJson(
          {'id': 'p3', 'name': 'x', 'position': 3, 'folded': 'true'});
      expect(foldedStr.isActive, isFalse);
    });

    test('isTurn字段可作为isCurrent的别名', () {
      final player = Player.fromJson(
          {'id': 'p1', 'name': 'x', 'position': 1, 'isTurn': true});
      expect(player.isCurrent, isTrue);
    });

    test('aiModel兼容ai_model和model字段名', () {
      final a = Player.fromJson(
          {'id': 'p1', 'name': 'x', 'position': 1, 'aiModel': 'Claude'});
      expect(a.aiModel, 'Claude');

      final b = Player.fromJson(
          {'id': 'p2', 'name': 'x', 'position': 2, 'ai_model': 'Grok'});
      expect(b.aiModel, 'Grok');

      final c = Player.fromJson(
          {'id': 'p3', 'name': 'x', 'position': 3, 'model': 'Gemini'});
      expect(c.aiModel, 'Gemini');
    });

    test('模型名称标准化', () {
      final claude = Player.fromJson({
        'id': 'p1',
        'name': 'x',
        'position': 1,
        'model': 'claude-3-7-sonnet-20250219'
      });
      expect(claude.aiModel, 'Claude');
      expect(claude.modelColor, isNotNull);

      final mini = Player.fromJson(
          {'id': 'p2', 'name': 'x', 'position': 2, 'model': 'gpt-4o-mini'});
      expect(mini.aiModel, 'ChatGPT-Mini');

      final full = Player.fromJson(
          {'id': 'p3', 'name': 'x', 'position': 3, 'model': 'gpt-4o'});
      expect(full.aiModel, 'ChatGPT-4O');
    });

    test('无效位置分配1-8之间的确定性随机位置', () {
      final player = Player.fromJson({'id': 'p1', 'name': 'x', 'position': 0});
      expect(player.position, inInclusiveRange(1, 8));

      // 相同ID的分配结果应一致
      final again = Player.fromJson({'id': 'p1', 'name': 'x', 'position': 0});
      expect(again.position, player.position);
    });

    test('无效手牌被忽略且不崩溃', () {
      final player = Player.fromJson({
        'id': 'p1',
        'name': 'x',
        'position': 1,
        'cards': ['AS', 'ZZ'],
      });
      // 整体解析失败时手牌为空，但玩家本身仍然构建成功
      expect(player.id, 'p1');
    });

    test('id缺失时生成后备id', () {
      final player = Player.fromJson({'name': 'x', 'position': 1});
      expect(player.id, isNotEmpty);
    });
  });

  group('Player其他行为', () {
    test('isAI取决于aiModel是否存在', () {
      final ai = Player(id: 'a', name: 'x', position: 1, chips: 100, aiModel: 'Claude');
      expect(ai.isAI, isTrue);

      final human = Player(id: 'b', name: 'y', position: 2, chips: 100);
      expect(human.isAI, isFalse);
    });

    test('toJson使用短字符串序列化手牌', () {
      final player = Player(
        id: 'a',
        name: 'x',
        position: 1,
        chips: 100,
        cards: [PokerCard.fromString('TS'), PokerCard.fromString('AH')],
      );
      final json = player.toJson();
      expect(json['cards'], ['10S', 'AH']);
    });
  });
}
