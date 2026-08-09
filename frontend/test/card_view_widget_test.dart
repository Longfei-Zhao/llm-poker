import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_app/components/game_table.dart';
import 'package:poker_app/models/poker_card.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: Center(child: child)));
  }

  group('CardView', () {
    testWidgets('正面朝上时显示点数和花色', (tester) async {
      await tester.pumpWidget(wrap(CardView(
        card: PokerCard.fromString('AS'),
        faceUp: true,
        width: 50,
        height: 70,
      )));

      expect(find.text('A'), findsOneWidget);
      expect(find.text('♠'), findsNWidgets(2)); // 左上小花色 + 右下大花色
    });

    testWidgets('10显示为"10"', (tester) async {
      await tester.pumpWidget(wrap(CardView(
        card: PokerCard.fromString('TH'),
        faceUp: true,
        width: 50,
        height: 70,
      )));

      expect(find.text('10'), findsOneWidget);
      expect(find.text('♥'), findsNWidgets(2));
    });

    testWidgets('背面朝上时不显示点数', (tester) async {
      await tester.pumpWidget(wrap(CardView(
        card: PokerCard.fromString('AS'),
        faceUp: false,
        width: 50,
        height: 70,
      )));

      expect(find.text('A'), findsNothing);
      expect(find.text('♠'), findsNothing);
    });

    testWidgets('无卡牌时显示占位图标', (tester) async {
      await tester.pumpWidget(wrap(const CardView(
        card: null,
        width: 50,
        height: 70,
      )));

      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });
  });
}
