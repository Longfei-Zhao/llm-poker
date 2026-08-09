import 'package:flutter/material.dart';
import 'screens/game_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(PokerApp());
}

class PokerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '大模型德州对决',
      theme: AppTheme.darkTheme,
      home: GameScreen(
        gameId: 'default_game_${DateTime.now().millisecondsSinceEpoch}',
        playerId: 'player_${DateTime.now().millisecondsSinceEpoch}',
        playerName: '玩家',
      ),
      debugShowCheckedModeBanner: false,
    );
  }
} 