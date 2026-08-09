import 'package:flutter/material.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _gameIdController = TextEditingController();
  
  @override
  void dispose() {
    _nameController.dispose();
    _gameIdController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('德州扑克对决'),
      ),
      body: Center(
        child: Container(
          width: 400,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Text(
                'AI德州扑克对决',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
              SizedBox(height: 20),
              
              // 玩家名称输入
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '玩家名称',
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 16),
              
              // 创建游戏按钮
              ElevatedButton(
                onPressed: _createGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: Size(double.infinity, 50),
                ),
                child: Text('创建新游戏'),
              ),
              SizedBox(height: 16),
              
              // 分隔线
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.white30)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '或',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.white30)),
                ],
              ),
              SizedBox(height: 16),
              
              // 游戏ID输入
              TextField(
                controller: _gameIdController,
                decoration: InputDecoration(
                  labelText: '游戏ID',
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 16),
              
              // 加入游戏按钮
              ElevatedButton(
                onPressed: _joinGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: Size(double.infinity, 50),
                ),
                child: Text('加入游戏'),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _createGame() {
    final playerName = _nameController.text.trim();
    if (playerName.isEmpty) {
      _showError('请输入玩家名称');
      return;
    }
    
    // 模拟创建游戏，实际应该调用API
    final gameId = 'game_${DateTime.now().millisecondsSinceEpoch}';
    final playerId = 'player_${DateTime.now().millisecondsSinceEpoch}';
    
    // 导航到游戏界面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameScreen(
          gameId: gameId,
          playerId: playerId,
          playerName: playerName,
        ),
      ),
    );
  }
  
  void _joinGame() {
    final playerName = _nameController.text.trim();
    final gameId = _gameIdController.text.trim();
    
    if (playerName.isEmpty) {
      _showError('请输入玩家名称');
      return;
    }
    
    if (gameId.isEmpty) {
      _showError('请输入游戏ID');
      return;
    }
    
    // 模拟加入游戏，实际应该调用API
    final playerId = 'player_${DateTime.now().millisecondsSinceEpoch}';
    
    // 导航到游戏界面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameScreen(
          gameId: gameId,
          playerId: playerId,
          playerName: playerName,
        ),
      ),
    );
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
} 