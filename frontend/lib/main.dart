import 'package:flutter/material.dart';
import 'screens/game_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PokerApp());
}

class PokerApp extends StatelessWidget {
  const PokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '大模型德州对决',
      theme: AppTheme.lightTheme,
      home: GameScreen(
        gameId: 'default_game_${DateTime.now().millisecondsSinceEpoch}',
        playerId: 'player_${DateTime.now().millisecondsSinceEpoch}',
        playerName: '玩家',
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
