import 'package:flutter_test/flutter_test.dart';
import 'package:poker_app/models/poker_card.dart';

void main() {
  group('PokerCard.fromString', () {
    test('解析普通牌', () {
      final card = PokerCard.fromString('AS');
      expect(card.rank, CardRank.ace);
      expect(card.suit, CardSuit.spades);

      final king = PokerCard.fromString('KH');
      expect(king.rank, CardRank.king);
      expect(king.suit, CardSuit.hearts);
    });

    test('10可以用T或10表示', () {
      final tenShort = PokerCard.fromString('TD');
      expect(tenShort.rank, CardRank.ten);
      expect(tenShort.suit, CardSuit.diamonds);

      final tenLong = PokerCard.fromString('10C');
      expect(tenLong.rank, CardRank.ten);
      expect(tenLong.suit, CardSuit.clubs);
    });

    test('大小写不敏感（后端使用小写花色）', () {
      final card = PokerCard.fromString('th');
      expect(card.rank, CardRank.ten);
      expect(card.suit, CardSuit.hearts);

      final ace = PokerCard.fromString('as');
      expect(ace.rank, CardRank.ace);
      expect(ace.suit, CardSuit.spades);
    });

    test('所有花色都可解析', () {
      expect(PokerCard.fromString('2S').suit, CardSuit.spades);
      expect(PokerCard.fromString('2H').suit, CardSuit.hearts);
      expect(PokerCard.fromString('2D').suit, CardSuit.diamonds);
      expect(PokerCard.fromString('2C').suit, CardSuit.clubs);
    });

    test('无效输入抛出ArgumentError', () {
      expect(() => PokerCard.fromString(''), throwsArgumentError);
      expect(() => PokerCard.fromString('A'), throwsArgumentError);
      expect(() => PokerCard.fromString('XS'), throwsArgumentError);
      expect(() => PokerCard.fromString('AX'), throwsArgumentError);
      expect(() => PokerCard.fromString('1S'), throwsArgumentError);
      expect(() => PokerCard.fromString('10XS'), throwsArgumentError);
    });
  });

  group('PokerCard round-trip', () {
    test('全部52张牌 fromString(toString) 保持一致', () {
      for (final suit in CardSuit.values) {
        for (final rank in CardRank.values) {
          final card = PokerCard(suit: suit, rank: rank);
          final parsed = PokerCard.fromString(card.toString());
          expect(parsed.suit, suit, reason: 'suit mismatch for ${card.toString()}');
          expect(parsed.rank, rank, reason: 'rank mismatch for ${card.toString()}');
        }
      }
    });

    test('toString与toShortString一致', () {
      final card = PokerCard(suit: CardSuit.hearts, rank: CardRank.ten);
      expect(card.toString(), '10H');
      expect(card.toString(), card.toShortString());
    });
  });

  group('PokerCard显示属性', () {
    test('花色符号与颜色', () {
      expect(PokerCard.fromString('AS').suitSymbol, '♠');
      expect(PokerCard.fromString('AH').suitSymbol, '♥');
      expect(PokerCard.fromString('AD').suitSymbol, '♦');
      expect(PokerCard.fromString('AC').suitSymbol, '♣');

      expect(PokerCard.fromString('AH').isRed, isTrue);
      expect(PokerCard.fromString('AD').isRed, isTrue);
      expect(PokerCard.fromString('AS').isRed, isFalse);
      expect(PokerCard.fromString('AC').isRed, isFalse);
    });

    test('rankSymbol', () {
      expect(PokerCard.fromString('AS').rankSymbol, 'A');
      expect(PokerCard.fromString('TS').rankSymbol, '10');
      expect(PokerCard.fromString('JS').rankSymbol, 'J');
      expect(PokerCard.fromString('QS').rankSymbol, 'Q');
      expect(PokerCard.fromString('KS').rankSymbol, 'K');
      expect(PokerCard.fromString('7S').rankSymbol, '7');
    });
  });
}
