import 'package:flutter/material.dart';
import 'dart:math';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/poker_card.dart';
import '../models/thinking_record.dart';
import '../theme/app_theme.dart';
import 'player_view.dart';

// 日志和思考内容显示组件
class LogAndThinkingBox extends StatefulWidget {
  final List<String> logs;
  final List<ThinkingRecord> thinkingLogs;
  
  const LogAndThinkingBox({
    Key? key,
    this.logs = const [],
    this.thinkingLogs = const [],
  }) : super(key: key);
  
  @override
  _LogAndThinkingBoxState createState() => _LogAndThinkingBoxState();
}

class _LogAndThinkingBoxState extends State<LogAndThinkingBox> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380, // 增加宽度，从300增加到380
      height: 800, // 增加高度，从700增加到800
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: Colors.blue.shade300.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // 标签栏
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.blue.shade300,
            indicatorWeight: 3,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.article, size: 18, color: Colors.white), // 增大图标
                    SizedBox(width: 6),
                    Text('日志', style: TextStyle(color: Colors.white, fontSize: 16)), // 增大字体
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.psychology, size: 18, color: Colors.white), // 增大图标
                    SizedBox(width: 6),
                    Text('思考', style: TextStyle(color: Colors.white, fontSize: 16)), // 增大字体
                  ],
                ),
              ),
            ],
          ),
          
          // 标签内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 日志标签内容
                _buildLogContent(),
                
                // 思考标签内容
                _buildThinkingContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLogContent() {
    if (widget.logs.isEmpty) {
      return Center(
        child: Text(
          '暂无日志信息',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16, // 增大字体大小
          ),
        ),
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.all(12), // 增大内边距
      itemCount: widget.logs.length,
      reverse: true, // 最新的日志显示在顶部
      itemBuilder: (context, index) {
        final log = widget.logs[widget.logs.length - 1 - index];
        return Padding(
          padding: EdgeInsets.only(bottom: 8), // 增大下边距
          child: Text(
            log,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15, // 增大字体大小
              height: 1.4, // 添加行高，使文本更易读
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildThinkingContent() {
    if (widget.thinkingLogs.isEmpty) {
      return Center(
        child: Text(
          '暂无思考记录',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16, // 增大字体大小
          ),
        ),
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.all(12), // 增大内边距
      itemCount: widget.thinkingLogs.length,
      itemBuilder: (context, index) {
        final thinking = widget.thinkingLogs[widget.thinkingLogs.length - 1 - index];
        return Container(
          margin: EdgeInsets.only(bottom: 12), // 增大下边距
          padding: EdgeInsets.all(12), // 增大内边距
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10), // 稍微增大圆角
            border: Border.all(
              color: _getModelColor(thinking.aiModel).withOpacity(0.3),
              width: 1.5, // 增大边框宽度
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    thinking.playerName,
                    style: TextStyle(
                      color: _getModelColor(thinking.aiModel),
                      fontWeight: FontWeight.bold,
                      fontSize: 15, // 增大字体大小
                    ),
                  ),
                  SizedBox(width: 8), // 增大间距
                  if (thinking.aiModel != null)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), // 增大内边距
                      decoration: BoxDecoration(
                        color: _getModelColor(thinking.aiModel).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4), // 增大圆角
                      ),
                      child: Text(
                        thinking.aiModel!,
                        style: TextStyle(
                          color: _getModelColor(thinking.aiModel),
                          fontSize: 12, // 增大字体大小
                        ),
                      ),
                    ),
                  Spacer(),
                  Text(
                    '${thinking.timestamp.hour.toString().padLeft(2, '0')}:${thinking.timestamp.minute.toString().padLeft(2, '0')}:${thinking.timestamp.second.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12, // 增大字体大小
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8), // 增大间距
              Text(
                thinking.content,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15, // 显著增大思考内容字体大小
                  height: 1.4, // 添加行高，使文本更易读
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  // 根据AI模型获取颜色
  Color _getModelColor(String? modelName) {
    if (modelName == null) return Colors.grey;
    
    if (modelName.contains('ChatGPT') || modelName.contains('GPT-4') || modelName.contains('GPT4')) {
      return Colors.green.shade500;
    } else if (modelName.contains('Claude')) {
      return Colors.orange.shade500;
    } else if (modelName.contains('Gemini')) {
      return Colors.blue.shade500;
    } else if (modelName.contains('DeepSeek')) {
      return Colors.purple.shade500;
    } else if (modelName.contains('Grok')) {
      return Colors.red.shade500;
    } else if (modelName.contains('Ernie')) {
      return Colors.teal.shade500;
    } else {
      return Colors.grey.shade500;
    }
  }
}

class GameTable extends StatefulWidget {
  final GameState gameState;
  final String currentPlayerId;
  final Function(int)? onAddPlayer; // 添加点击空位回调函数
  
  const GameTable({
    Key? key,
    required this.gameState,
    required this.currentPlayerId,
    this.onAddPlayer,
  }) : super(key: key);
  
  @override
  _GameTableState createState() => _GameTableState();
}

class _GameTableState extends State<GameTable> with SingleTickerProviderStateMixin {
  Map<int, bool> _animatedBets = {};
  bool _showChipAnimation = false;
  Offset _tableCenter = Offset.zero;
  Size _tableSize = Size.zero;
  
  // 游戏日志
  List<String> _gameLogs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTableSize();
      
      // 初始化一条日志
      _addGameLog('游戏准备中 - 等待开始');
    });
  }

  @override
  void didUpdateWidget(GameTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 检测游戏状态是否有变化
    if (oldWidget.gameState != widget.gameState) {
      // 检查游戏状态是否重置（从非waiting到waiting，或游戏ID变化）
      if ((oldWidget.gameState.stage != GameStage.waiting && 
          widget.gameState.stage == GameStage.waiting) ||
          oldWidget.gameState.id != widget.gameState.id) {
        _resetAnimationState();
        
        // 添加游戏重置日志
        if (widget.gameState.id != oldWidget.gameState.id) {
          _addGameLog('游戏重置 - 新游戏ID: ${widget.gameState.id}');
        }
      } else {
        // 安全处理oldWidget.gameState.players，避免可能的错误
        final oldPlayers = oldWidget.gameState.players.isNotEmpty 
            ? oldWidget.gameState.players 
            : <Player>[];
        
        _checkForNewBets(oldPlayers);
        
        // 检查游戏阶段变化
        if (oldWidget.gameState.stage != widget.gameState.stage) {
          _addGameLog('阶段变更: ${widget.gameState.stageDescription}');
        }
        
        // 检查当前玩家变化
        final oldCurrentPlayer = oldWidget.gameState.currentPlayer;
        final newCurrentPlayer = widget.gameState.currentPlayer;
        if (oldCurrentPlayer?.id != newCurrentPlayer?.id && newCurrentPlayer != null) {
          _addGameLog('行动玩家: ${newCurrentPlayer.name}');
        }
        
        // 检查玩家行动变化
        for (final player in widget.gameState.players) {
          final oldPlayer = oldPlayers.where((p) => p.id == player.id).toList();
          if (oldPlayer.isNotEmpty && oldPlayer.first.action != player.action && player.action != null && player.action!.isNotEmpty) {
            _addGameLog('${player.name} ${_formatPlayerAction(player)}');
          }
        }
      }
      
      _updateTableSize();
    }
  }
  
  // 添加游戏日志
  void _addGameLog(String log) {
    setState(() {
      _gameLogs.add('${DateTime.now().toString().substring(11, 19)} - $log');
      // 限制日志数量，防止过多
      if (_gameLogs.length > 100) {
        _gameLogs.removeAt(0);
      }
    });
  }
  
  // 格式化玩家行动为易读文本
  String _formatPlayerAction(Player player) {
    if (player.action == null || player.action!.isEmpty) {
      return '';
    }
    
    switch (player.action!.toLowerCase()) {
      case 'fold':
        return '弃牌';
      case 'check':
        return '让牌';
      case 'call':
        return '跟注 ${player.bet}';
      case 'raise':
        return '加注到 ${player.bet}';
      case 'allin':
        return 'ALL IN ${player.bet}';
      default:
        return player.action!;
    }
  }
  
  // 重置动画状态
  void _resetAnimationState() {
    setState(() {
      _animatedBets.clear();
      _showChipAnimation = false;
    });
    print('已重置筹码动画状态');
  }
  
  void _updateTableSize() {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final size = renderBox.size;
      setState(() {
        _tableSize = size;
        _tableCenter = Offset(size.width / 2, size.height / 2);
      });
    }
  }
  
  void _checkForNewBets(List<Player> oldPlayers) {
    // 如果新状态的玩家列表为空，则不处理
    if (widget.gameState.players.isEmpty) return;
    
    // 创建一个映射，用于快速查找旧玩家的下注金额
    Map<String, int> oldBets = {};
    for (var player in oldPlayers) {
      oldBets[player.id] = player.bet;
    }
    
    bool hasNewBets = false;
    
    // 检查每个当前玩家的下注是否增加
    for (var player in widget.gameState.players) {
      final oldBet = oldBets[player.id] ?? 0;
      
      // 如果下注增加且没有显示过动画
      if (player.bet > oldBet && !(_animatedBets[player.position] ?? false)) {
        _animatedBets[player.position] = true;
        hasNewBets = true;
      }
    }
    
    // 如果有新的下注，不再显示动画
    if (hasNewBets) {
      // 已禁用筹码动画
      setState(() {
        _showChipAnimation = false; // 始终保持为false，禁用动画
      });
      
      // 仍然更新状态，但不再延迟
      // Future.delayed(Duration(seconds: 2), () {
      //   if (mounted) {
      //     setState(() {
      //       _showChipAnimation = false;
      //     });
      //   }
      // });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pokerTheme = theme.extension<PokerThemeExtension>();
    final size = MediaQuery.of(context).size;
    
    // 计算桌子尺寸，保持固定长宽比
    final minDimension = min(size.width, size.height);
    final tableWidth = minDimension * 0.85;
    final tableHeight = tableWidth * 0.48; // 长宽比约为2.08:1，更加修长
    
    // 计算表格半径 - 用于定位筹码动画
    final tableRadius = min(tableWidth, tableHeight) * 0.35;
    
    return Padding(
      padding: EdgeInsets.all(32.0), // 增加留白
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 简化的外层背景
          Center(
            child: Container(
              width: tableWidth, // 使用计算的宽度
              height: tableHeight, // 使用计算的高度
              child: ClipPath(
                clipper: PokerTableClipper(),
                child: Container(
                  color: Color(0xFF0A1E38), // 外边框深蓝色
                ),
              ),
            ),
          ),
          
          // 牌桌背景 - 简化设计
          Center(
            child: Container(
              width: tableWidth * 0.95, // 内部尺寸稍小
              height: tableHeight * 0.95, // 内部尺寸稍小
              child: ClipPath(
                clipper: PokerTableClipper(padding: 12),
                child: Container(
                  color: Color(0xFF1A365D), // 单一蓝色背景
                ),
              ),
            ),
          ),
          
          // 玩家下注筹码显示区域
          Positioned.fill(
            child: _buildPlayerBets(context),
          ),
          
          // 主底池显示 - 移到更高的位置，公共牌上方
          if (widget.gameState.pot > 0)
            Positioned(
              top: size.height * 0.5 - 110, // 从-50改为-110，将底池移到更高的位置
              left: 0,
              right: 0,
              child: Center(
                child: _buildMainPot(context),
            ),
          ),
          
          // 玩家手牌显示区域
          Positioned.fill(
            child: _buildPlayerCards(context),
          ),
          
          // 社区牌区域 - 只在游戏开始后显示
          if (widget.gameState.stage != GameStage.waiting)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: _buildCommunityCards(context),
              ),
            ),
          
          // 玩家布局
          Positioned.fill(
            child: _buildEmptyPlayerPositions(context),
          ),
          
          // 筹码动画
          // 注释掉筹码动画相关代码，保留变量以避免引用错误
          // if (_showChipAnimation && _tableCenter != Offset.zero)
          //   ChipAnimationManager(
          //     players: widget.gameState.players,
          //     centerPosition: _tableCenter,
          //     tableRadius: tableRadius,
          //     onAllAnimationsComplete: () {
          //       if (mounted) {
          //         setState(() {
          //           _showChipAnimation = false;
          //         });
          //         print('所有筹码动画已完成');
          //       }
          //     },
          //   ),
            
          // 右上角日志和思考盒子
          Positioned(
            top: 0,
            right: 16,
            child: LogAndThinkingBox(
              logs: _gameLogs,
              thinkingLogs: widget.gameState.thinkingHistory,
            ),
          ),
        ],
      ),
    );
  }
  
  // 显示玩家手牌的方法
  Widget _buildPlayerCards(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;
    
    // 计算桌子尺寸
    final minDimension = min(width, height);
    final tableWidth = minDimension * 0.85 * 0.95; // 内部尺寸
    final tableHeight = tableWidth * 0.48; // 长宽比约为2.08:1，更加修长
    
    // 桌子中心位置
    final centerX = width * 0.5;
    final centerY = height * 0.5;
    
    // 计算桌子边缘
    final tableLeft = centerX - tableWidth / 2;
    final tableRight = centerX + tableWidth / 2;
    final tableTop = centerY - tableHeight / 2;
    final tableBottom = centerY + tableHeight / 2;
    
    // 玩家位置边缘偏移量（与桌子边缘之间的距离）
    final edgeOffset = 50.0;
    
    // 定义8个位置的手牌位置
    final positions = [
      // 上排三个位置（从左到右）
      Offset(tableLeft + tableWidth * 0.20 - 10, centerY - tableHeight * 0.55), // 左上手牌，向左移动10像素
      Offset(centerX - 10, centerY - tableHeight * 0.55), // 上中手牌，向左移动10像素
      Offset(tableRight - tableWidth * 0.20 - 10, centerY - tableHeight * 0.55), // 右上手牌，向左移动10像素
      
      // 右侧手牌
      Offset(tableRight - tableWidth * 0.05, centerY), // 右侧手牌，更靠近右边缘
      
      // 下排三个位置（从右到左）
      Offset(tableRight - tableWidth * 0.20 - 10, centerY + tableHeight * 0.40), // 右下手牌，向左移动10像素
      Offset(centerX - 10, centerY + tableHeight * 0.40), // 下中手牌，向左移动10像素
      Offset(tableLeft + tableWidth * 0.20 - 10, centerY + tableHeight * 0.40), // 左下手牌，向左移动10像素
      
      // 左侧手牌
      Offset(centerX - tableWidth * 0.42 - 60, centerY), // 左侧手牌，向左移动60像素
    ];
    
    // 计算手牌位置偏移量，保持与玩家的一致距离
    final cardOffsets = <Offset>[
      Offset(0, 25),  // 上方玩家，手牌在下方
      Offset(0, 25),
      Offset(0, 25),
      Offset(-25, 0), // 右侧玩家，手牌在左侧
      Offset(0, -25), // 下方玩家，手牌在上方
      Offset(0, -25),
      Offset(0, -25),
      Offset(25, 0),  // 左侧玩家，手牌在右侧
    ];
    
    return Stack(
      children: List.generate(positions.length, (index) {
        // 检查该位置是否已有玩家
        final playerAtPosition = widget.gameState.players
            .where((p) => p.position == index + 1)
            .toList();
        
        if (playerAtPosition.isEmpty) {
          return SizedBox(); // 如果没有玩家，返回空组件
        }
        
        final player = playerAtPosition.first;
        final isCurrentPlayer = player.id == widget.currentPlayerId;
        
        // 放置玩家手牌，与玩家保持固定距离
        return Positioned(
          left: positions[index].dx + cardOffsets[index].dx - 30, // 30是手牌宽度的一半
          top: positions[index].dy + cardOffsets[index].dy - 35,  // 35是手牌高度的一半
          child: _buildPlayerCardView(player, isCurrentPlayer, widget.gameState.isShowdown),
        );
      }),
    );
  }
  
  // 构建玩家手牌视图
  Widget _buildPlayerCardView(Player player, bool isCurrentPlayer, bool isShowdown) {
    // 如果玩家没有手牌，返回空组件
    if (player.cards.isEmpty) {
      return SizedBox();
    }
    
    // 检查玩家是否不活跃
    bool isInactive = player.isActive == false;
    
    // 添加调试日志
    print('_buildPlayerCardView: 玩家 ${player.name}, isActive=${player.isActive}, isInactive=${isInactive}');
    
    // 如果玩家不活跃，则不显示卡牌
    if (isInactive) {
      // 返回与PlayerCardsWidget中相同尺寸的SizedBox
      final double cardWidth = 50.0;
      final double cardHeight = 70.0;
      final double overlapRatio = 0.3;
      final double effectiveWidth = cardWidth * (1 + (1 - overlapRatio));
      
      return SizedBox(
        width: effectiveWidth + 10,
        height: cardHeight,
      );
    }
    
    // 确定是否应该显示手牌
    bool shouldShowCards = isCurrentPlayer || isShowdown;
    
    return PlayerCardsWidget(
      player: player,
      shouldShowCards: shouldShowCards,
      isCurrentPlayer: isCurrentPlayer,
    );
  }
  
  // 空位卡牌占位符
  Widget _buildCommunityCardPlaceholder() {
    return Container(
      width: 50.0,
      height: 70.0,
      decoration: BoxDecoration(
        color: Color(0xFF273142).withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 3,
            offset: Offset(1, 1),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.question_mark,
          color: Colors.white24,
          size: 16,
        ),
      ),
    );
  }
  
  Widget _buildEmptyPlayerPositions(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;
    
    // 计算桌子尺寸，保持固定长宽比
    final minDimension = min(width, height);
    final tableWidth = minDimension * 0.85 * 0.95; // 内部尺寸
    final tableHeight = tableWidth * 0.48; // 长宽比约为2.08:1，更加修长
    
    // 桌子中心位置
    final centerX = width * 0.5;
    final centerY = height * 0.5;
    
    // 计算桌子边缘
    final tableLeft = centerX - tableWidth / 2;
    final tableRight = centerX + tableWidth / 2;
    final tableTop = centerY - tableHeight / 2;
    final tableBottom = centerY + tableHeight / 2;
    
    // 玩家位置边缘偏移量（与桌子边缘之间的距离）
    final edgeOffset = 50.0;
    
    // 计算八个玩家位置
    final positions = <Offset>[
      // 上方三个位置（从左到右）- 上移到桌子外更远处
      Offset(tableLeft + tableWidth * 0.20, tableTop - edgeOffset - 80),  // 左上
      Offset(centerX, tableTop - edgeOffset - 80),                        // 上中
      Offset(tableRight - tableWidth * 0.20, tableTop - edgeOffset - 80), // 右上
      
      // 右侧
      Offset(tableRight + edgeOffset, centerY), // 右侧
      
      // 下方三个位置（从右到左）
      Offset(tableRight - tableWidth * 0.20, tableBottom + edgeOffset), // 右下
      Offset(centerX, tableBottom + edgeOffset),                        // 下中
      Offset(tableLeft + tableWidth * 0.20, tableBottom + edgeOffset),  // 左下
      
      // 左侧 - 左移到桌子外更远处
      Offset(tableLeft - edgeOffset - 75, centerY), // 左侧，从60增加到75
    ];
    
    return Stack(
      children: List.generate(positions.length, (index) {
        // 检查该位置是否已有玩家
        final playerAtPosition = widget.gameState.players
            .where((p) => p.position == index + 1)
            .toList();
        
        final hasPlayer = playerAtPosition.isNotEmpty;
        
        return Positioned(
          left: positions[index].dx - 45, // 调整为组件宽度的一半
          top: positions[index].dy - 45,  // 调整为组件高度的一半
          child: hasPlayer 
              ? PlayerView(
                  player: playerAtPosition.first,
                  isCurrentPlayer: playerAtPosition.first.id == widget.currentPlayerId,
                  isShowdown: widget.gameState.isShowdown,
                  highlight: playerAtPosition.first.isCurrent,
                  isDealer: playerAtPosition.first.isDealer,
                  onTap: (player) {
                    // 可以添加点击玩家的事件处理
                    print('点击了玩家: ${player.name}');
                  },
                )
              : _buildModernEmptySeat(context, index),
        );
      }),
    );
  }
  
  // 简化的空座位设计 - 保持简洁
  Widget _buildModernEmptySeat(BuildContext context, int position) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;
    final seatSize = isSmallScreen ? 60.0 : 70.0;
    
    return GestureDetector(
      onTap: () {
        if (widget.onAddPlayer != null) {
          widget.onAddPlayer!(position);
        }
      },
      child: Container(
        width: seatSize,
        height: seatSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF273142).withOpacity(0.7),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.add,
            color: Colors.white.withOpacity(0.7),
            size: isSmallScreen ? 30 : 36,
          ),
        ),
      ),
    );
  }
  
  Widget _buildGameInfo(BuildContext context) {
    return Column(
      children: [
        // 游戏阶段信息
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Color(0xFF273142),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Text(
            widget.gameState.stageDescription,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildInfoChip({required String label, required String value, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFF273142),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPotInfo(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFF273142),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white24,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pot',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '${widget.gameState.pot > 0 ? widget.gameState.pot : 0}',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  // 新增：构建社区牌
  Widget _buildCommunityCards(BuildContext context) {
    // 如果有实际的公共牌，则显示
    if (widget.gameState.communityCards.isNotEmpty) {
      return CommunityCardsWidget(
        cards: widget.gameState.communityCards,
        totalCards: 5,
      );
    } else {
      // 如果没有公共牌但游戏已开始，显示5个占位符
      return CommunityCardsWidget(
        cards: const [],
        totalCards: 5,
      );
    }
  }

  // 新增：显示玩家下注筹码的方法
  Widget _buildPlayerBets(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;
    
    // 计算桌子尺寸
    final minDimension = min(width, height);
    final tableWidth = minDimension * 0.85 * 0.95; // 内部尺寸
    final tableHeight = tableWidth * 0.48; // 长宽比约为2.08:1，更加修长
    
    // 桌子中心位置
    final centerX = width * 0.5;
    final centerY = height * 0.5;
    
    // 计算桌子边缘
    final tableLeft = centerX - tableWidth / 2;
    final tableRight = centerX + tableWidth / 2;
    final tableTop = centerY - tableHeight / 2;
    final tableBottom = centerY + tableHeight / 2;
    
    // 卡牌尺寸
    final double cardWidth = 50.0;
    final double cardHeight = 70.0;
    
    // 定义8个位置的手牌位置 - 与_buildPlayerCards方法中相同
    final cardPositions = [
      // 上排三个位置（从左到右）
      Offset(tableLeft + tableWidth * 0.20 - 10, centerY - tableHeight * 0.55), // 左上手牌
      Offset(centerX - 10, centerY - tableHeight * 0.55), // 上中手牌
      Offset(tableRight - tableWidth * 0.20 - 10, centerY - tableHeight * 0.55), // 右上手牌
      
      // 右侧手牌
      Offset(tableRight - tableWidth * 0.05, centerY), // 右侧手牌
      
      // 下排三个位置（从右到左）
      Offset(tableRight - tableWidth * 0.20 - 10, centerY + tableHeight * 0.40), // 右下手牌
      Offset(centerX - 10, centerY + tableHeight * 0.40), // 下中手牌
      Offset(tableLeft + tableWidth * 0.20 - 10, centerY + tableHeight * 0.40), // 左下手牌
      
      // 左侧手牌
      Offset(centerX - tableWidth * 0.42 - 60, centerY), // 左侧手牌
    ];
    
    // 筹码相对于手牌的偏移量 - 调整右侧玩家和下方玩家的偏移量
    final chipOffsets = [
      Offset(0, 50),    // 位置1: 上方左侧玩家 - 筹码在手牌下方，向上移动20px (从80改为60)
      Offset(0, 50),    // 位置2: 上方中间玩家 - 筹码在手牌下方，向上移动20px (从80改为60)
      Offset(0, 50),    // 位置3: 上方右侧玩家 - 筹码在手牌下方，向上移动20px (从80改为60)
      Offset(-100, -30),  // 位置4: 右侧玩家 - 筹码在手牌左侧，向上移动10px (添加Y轴偏移-10)
      Offset(0, -110),  // 位置5: 下方右侧玩家 - 筹码在手牌上方，向上移动10px (从-100改为-90)
      Offset(0, -110),  // 位置6: 下方中间玩家 - 筹码在手牌上方，向上移动10px (从-100改为-90)
      Offset(0, -110),  // 位置7: 下方左侧玩家 - 筹码在手牌上方，向上移动10px (从-100改为-90)
      Offset(80, -30),    // 位置8: 左侧玩家 - 筹码在手牌右侧
    ];
    
    List<Widget> bets = [];
    
    // 添加调试日志，输出所有玩家信息
    print('当前玩家数量: ${widget.gameState.players.length}');
    for (final player in widget.gameState.players) {
      print('玩家 ${player.name} (${player.id}): 位置=${player.position}, 下注=${player.bet}, 是否活跃=${player.isActive}');
    }
    
    // 遍历所有玩家，显示有下注的玩家筹码
    for (int i = 0; i < widget.gameState.players.length; i++) {
      final player = widget.gameState.players[i];
      
      // 添加详细的调试日志
      print('玩家${player.position}(${player.name})下注信息: bet=${player.bet}, isActive=${player.isActive}');
      
      // 只有当玩家有下注且玩家处于活跃状态时才显示筹码
      if (player.bet > 0 && player.isActive) {
        // 获取玩家位置索引（0-7）- 需要减1因为position从1开始
        final positionIndex = player.position - 1;
        
        if (positionIndex >= 0 && positionIndex < cardPositions.length) {
          // 获取该玩家手牌的坐标
          final cardPosition = cardPositions[positionIndex];
          
          // 计算手牌中心点
          final cardCenterX = cardPosition.dx + cardWidth / 2;
          final cardCenterY = cardPosition.dy + cardHeight / 2;
          
          // 计算筹码显示位置，相对于手牌中心点
          final chipPosition = Offset(
            cardCenterX + chipOffsets[positionIndex].dx,
            cardCenterY + chipOffsets[positionIndex].dy
          );
          
          // 添加Z-Index调试信息
          print('  Z-Index: 筹码将被添加为Stack中的第${bets.length}个元素');
          
          // 使用绝对定位显示筹码
          bets.add(
            Positioned(
              left: chipPosition.dx - 25, // 筹码宽度的一半，保持居中
              top: chipPosition.dy - 12,  // 筹码高度的一半，保持居中
              child: Container(
                constraints: BoxConstraints(maxWidth: 100), // 限制宽度以避免溢出
                child: _buildBetChips(context, player.bet),
              ),
            ),
          );
          
          // 输出详细日志，显示筹码位置和计算过程
          print('为玩家${player.position}(${player.name}, 位置索引$positionIndex)显示筹码:');
          print('  手牌位置: (${cardPosition.dx}, ${cardPosition.dy})');
          print('  手牌中心: (${cardCenterX}, ${cardCenterY})');
          print('  偏移量: (${chipOffsets[positionIndex].dx}, ${chipOffsets[positionIndex].dy})');
          print('  最终筹码位置: (${chipPosition.dx}, ${chipPosition.dy})');
        } else {
          print('警告：玩家${player.position}(${player.name})的位置索引$positionIndex超出了定义的下注位置范围');
        }
      } else {
        // 添加未显示筹码的原因
        if (player.bet <= 0) {
          print('  未显示筹码原因: 玩家${player.position}(${player.name})的下注金额为${player.bet}，小于等于0');
        }
        if (!player.isActive) {
          print('  未显示筹码原因: 玩家${player.position}(${player.name})不处于活跃状态(isActive=${player.isActive})');
        }
      }
    }
    
    return Stack(
      children: bets,
    );
  }

  // 显示主底池的筹码
  Widget _buildMainPot(BuildContext context) {
    // 只有当底池有筹码时才显示
    if (widget.gameState.pot <= 0) {
      print('底池为空，不显示底池: ${widget.gameState.pot}');
      return SizedBox();
    }
    
    print('显示底池: ${widget.gameState.pot}');
    
    return Center(
      child: Container(
        padding: EdgeInsets.only(top: 15), // 向下移动15像素
        child: Text(
          '底池: ${widget.gameState.pot}',
          style: TextStyle(
            color: Colors.amber,
            fontWeight: FontWeight.bold,
            fontSize: 16,
            shadows: [
              Shadow(
                color: Colors.black54,
                blurRadius: 2.0,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 显示玩家下注筹码的组件 - 恢复到原始样式
  Widget _buildBetChips(BuildContext context, int betAmount) {
    // 构建动画的关键帧
    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 500),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, double value, child) {
        // 确保值在有效范围内
        final safeValue = value.clamp(0.0, 1.0);
        return Transform.scale(
          scale: safeValue,
          child: Opacity(
            opacity: safeValue,
            child: Row(
              mainAxisSize: MainAxisSize.min,
        children: [
                // 堆叠的筹码图标
                _buildChipStack(context, betAmount),
                SizedBox(width: 4),
                // 下注金额
                Text(
                  '${betAmount}',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 2.0,
                        offset: Offset(1, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // 筹码堆叠样式 - 调小尺寸
  Widget _buildChipStack(BuildContext context, int betAmount) {
    // 计算要显示的筹码数量（最大5个）
    int chipCount = min(5, max(1, betAmount ~/ 100));
    if (chipCount == 0) chipCount = 1;
    
    return SizedBox(
      width: 18, // 从22调小到18
      height: 24, // 从28调小到24
      child: Stack(
        children: List.generate(chipCount, (index) {
          // 根据筹码大小选择不同的颜色
          Color chipColor;
          if (betAmount >= 1000) {
            chipColor = Colors.purple.shade300; // 紫色筹码表示高额下注
          } else if (betAmount >= 500) {
            chipColor = Colors.red.shade500; // 红色筹码表示中高额下注
          } else if (betAmount >= 200) {
            chipColor = Colors.green.shade600; // 绿色筹码表示中额下注
    } else {
            chipColor = Colors.amber.shade600; // 黄色筹码表示低额下注
          }
          
          return Positioned(
            top: index * 3.0,
            child: Container(
              width: 18, // 从22调小到18
              height: 18, // 从22调小到18
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chipColor,
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 1,
                    spreadRadius: 0,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 10, // 从12调小到10
                  height: 10, // 从12调小到10
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: chipColor.withOpacity(0.7),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// 赛道式扑克桌剪裁器
class PokerTableClipper extends CustomClipper<Path> {
  final double padding;
  final double radiusRatio;
  
  PokerTableClipper({this.padding = 0, this.radiusRatio = 1.0});
  
  @override
  Path getClip(Size size) {
    final path = Path();
    final width = size.width;
    final height = size.height;
    
    // 对于真正的赛道形状，半径应该是高度的一半
    final radius = height / 2 - padding;
    
    // 左半圆的中心点
    final leftCenter = Offset(padding + radius, height / 2);
    // 右半圆的中心点
    final rightCenter = Offset(width - padding - radius, height / 2);
    
    // 起点：左半圆顶部
    path.moveTo(leftCenter.dx, padding);
    
    // 上边：直线
    path.lineTo(rightCenter.dx, padding);
    
    // 右半圆：顺时针180度
    path.arcTo(
      Rect.fromCircle(center: rightCenter, radius: radius),
      -pi / 2,  // 从顶部开始
      pi,       // 半圆
      false
    );
    
    // 下边：直线
    path.lineTo(leftCenter.dx, height - padding);
    
    // 左半圆：顺时针180度
    path.arcTo(
      Rect.fromCircle(center: leftCenter, radius: radius),
      pi / 2,   // 从底部开始
      pi,       // 半圆
      false
    );
    
    // 闭合路径
    path.close();
    
    return path;
  }
  
  @override
  bool shouldReclip(PokerTableClipper oldClipper) {
    return oldClipper.padding != padding || oldClipper.radiusRatio != radiusRatio;
  }
}

class DealerButton extends StatelessWidget {
  const DealerButton({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Center(
        child: Text(
          'D',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// 玩家手牌显示组件（带动画效果）
class PlayerCardsWidget extends StatefulWidget {
  final Player player;
  final bool shouldShowCards;
  final bool isCurrentPlayer;
  
  const PlayerCardsWidget({
    Key? key,
    required this.player,
    required this.shouldShowCards,
    required this.isCurrentPlayer,
  }) : super(key: key);
  
  @override
  _PlayerCardsWidgetState createState() => _PlayerCardsWidgetState();
}

class _PlayerCardsWidgetState extends State<PlayerCardsWidget> {
  // 是否显示手牌
  bool _cardsVisible = false;
  
  @override
  void initState() {
    super.initState();
  }
  
  // 切换整个手牌的显示状态
  void _toggleCardsVisibility() {
    // 如果玩家不活跃，禁用点击显示功能
    if (widget.player.isActive == false) {
      return;
    }
    
    setState(() {
      _cardsVisible = !_cardsVisible;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    // 卡牌叠放配置
    final double cardWidth = 50.0;
    final double cardHeight = 70.0;
    final double overlapRatio = 0.3; // 固定的叠放比例
    final double effectiveWidth = cardWidth * (1 + (1 - overlapRatio)); // 两张牌叠放后的总宽度
    
    // 检查玩家是否不活跃
    bool isInactive = widget.player.isActive == false;
    
    // 添加调试日志，检查玩家状态
    print('玩家 ${widget.player.name} 状态: isActive=${widget.player.isActive}, isInactive=${isInactive}');
    
    // 如果玩家不活跃，不显示卡牌
    if (isInactive) {
      return SizedBox(
        width: effectiveWidth + 10, // 保持相同的宽度，避免布局变化
        height: cardHeight,
      );
    }
    
    return GestureDetector(
      onTap: _toggleCardsVisibility,
      child: SizedBox(
        width: effectiveWidth + 10, // 额外加一些空间
        height: cardHeight,
        child: Stack(
          clipBehavior: Clip.none, // 允许子组件绘制超出父组件范围
          children: [
            // 第一张牌
            Positioned(
              left: 0,
              top: 0,
              child: CardView(
                card: widget.player.cards.isNotEmpty ? widget.player.cards[0] : null,
                faceUp: widget.shouldShowCards || _cardsVisible, // 只检查是否应该显示牌面
                width: cardWidth,
                height: cardHeight,
                highlighted: widget.isCurrentPlayer,
                showCardInfo: false,
              ),
            ),
            // 第二张牌，叠放在第一张之上
            if (widget.player.cards.length > 1)
              Positioned(
                left: cardWidth * (1 - overlapRatio),
                top: 0,
                child: CardView(
                  card: widget.player.cards[1],
                  faceUp: widget.shouldShowCards || _cardsVisible, // 只检查是否应该显示牌面
                  width: cardWidth,
                  height: cardHeight,
                  highlighted: widget.isCurrentPlayer,
                  showCardInfo: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 社区牌叠放显示组件
class CommunityCardsWidget extends StatefulWidget {
  final List<PokerCard> cards;
  final int totalCards;
  final double spacing;
  
  const CommunityCardsWidget({
    Key? key,
    required this.cards,
    required this.totalCards,
    this.spacing = 8.0,
  }) : super(key: key);
  
  @override
  _CommunityCardsWidgetState createState() => _CommunityCardsWidgetState();
}

class _CommunityCardsWidgetState extends State<CommunityCardsWidget> {
  @override
  void initState() {
    super.initState();
  }
  
  @override
  Widget build(BuildContext context) {
    // 卡牌配置
    final double cardWidth = 50.0;
    final double cardHeight = 70.0;
    final double spacing = 10.0; // 固定间距
    
    // 计算总宽度
    final double effectiveWidth = (cardWidth + spacing) * widget.totalCards - spacing;
    
    return Container(
      width: effectiveWidth,
      height: cardHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 生成所有卡牌（实际卡牌或占位符）
          for (int i = 0; i < widget.totalCards; i++)
            Padding(
              padding: EdgeInsets.only(
                right: i < widget.totalCards - 1 ? spacing : 0
              ),
              child: i < widget.cards.length
                ? CardView(
                    card: widget.cards[i],
                    faceUp: true,
                    width: cardWidth,
                    height: cardHeight,
                    showCardInfo: false,
                  )
                : _buildCommunityCardPlaceholder(),
            ),
        ],
      ),
    );
  }
  
  // 社区牌占位符
  Widget _buildCommunityCardPlaceholder() {
    return Container(
      width: 50.0,
      height: 70.0,
      decoration: BoxDecoration(
        color: Color(0xFF273142).withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 3,
            offset: Offset(1, 1),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.question_mark,
          color: Colors.white24,
          size: 16,
        ),
      ),
    );
  }
}

// 修改CardView组件以支持高亮和显示详细信息
class CardView extends StatelessWidget {
  final PokerCard? card;
  final bool faceUp;
  final double width;
  final double height;
  final bool highlighted;
  final bool showCardInfo;

  const CardView({
    Key? key,
    this.card,
    this.faceUp = true,
    required this.width,
    required this.height,
    this.highlighted = false,
    this.showCardInfo = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 如果没有卡牌，显示一个空白卡牌背面
    if (card == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Color(0xFF273142),
          borderRadius: BorderRadius.circular(width * 0.15),
          border: Border.all(
            color: highlighted ? Colors.amber.withOpacity(0.5) : Colors.white24,
            width: highlighted ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(1, 1),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.help_outline,
            color: Colors.white24,
            size: width * 0.3,
          ),
        ),
      );
    }

    // 如果卡牌不应该显示正面，显示卡牌背面
    if (!faceUp) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Color(0xFF0C3868), // 使用更深的蓝色作为基础颜色
          borderRadius: BorderRadius.circular(width * 0.15),
          border: Border.all(
            color: highlighted ? Colors.amber : Colors.white38,
            width: highlighted ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: highlighted ? Colors.amber.withOpacity(0.3) : Colors.black26,
              blurRadius: 3,
              offset: Offset(1, 1),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 内部边框
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(width * 0.06),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white30,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(width * 0.08),
                  ),
                ),
              ),
            ),
            
            // 重复的网格图案
            Positioned.fill(
              child: CustomPaint(
                painter: CardBackPatternPainter(),
              ),
            ),
          ],
        ),
      );
    }

    // 确定花色颜色
    final Color suitColor = card!.isRed ? Colors.red : Colors.black87;
    
    return Stack(
      children: [
        // 基本卡牌显示
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(width * 0.15),
            border: Border.all(
              color: highlighted ? Colors.amber : Colors.grey.shade300,
              width: highlighted ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: highlighted ? Colors.amber.withOpacity(0.3) : Colors.black26,
                blurRadius: highlighted ? 5 : 3,
                spreadRadius: highlighted ? 1 : 0,
                offset: Offset(1, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 左上角显示卡牌数值和小花色
              Positioned(
                left: width * 0.1,
                top: height * 0.05,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      card!.rankSymbol,
                      style: TextStyle(
                        color: suitColor,
                        fontSize: width * 0.3,
                        fontWeight: FontWeight.bold,
                        height: 0.8, // 减小行高
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, 0), // 调整为0，不再向上平移花色
                      child: Text(
                        card!.suitSymbol,
                        style: TextStyle(
                          color: suitColor,
                          fontSize: width * 0.25, // 稍微缩小花色
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // 右下角显示大花色
              Positioned(
                right: width * 0.1,
                bottom: height * 0.05,
                child: Text(
                  card!.suitSymbol,
                  style: TextStyle(
                    color: suitColor,
                    fontSize: width * 0.6, // 增大比例，从0.5到0.6
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 自定义绘制类，用于绘制卡牌背面的重复图案
class CardBackPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 设置画笔
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    // 计算网格间距
    final gridSize = size.width / 8;
    
    // 绘制水平线
    for (double y = gridSize; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y), 
        Offset(size.width, y),
        paint,
      );
    }
    
    // 绘制垂直线
    for (double x = gridSize; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    
    // 在每个交叉点绘制小圆点
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    
    for (double x = gridSize; x < size.width; x += gridSize) {
      for (double y = gridSize; y < size.height; y += gridSize) {
        canvas.drawCircle(
          Offset(x, y),
          1,
          dotPaint,
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(CardBackPatternPainter oldDelegate) => false;
} 