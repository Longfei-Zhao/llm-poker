import 'package:flutter/material.dart';
import 'dart:math';
import '../models/player.dart';

// 新增：筹码动画组件
class ChipAnimation extends StatefulWidget {
  final Offset startPosition;
  final Offset endPosition;
  final int amount;
  final VoidCallback? onComplete;
  
  const ChipAnimation({
    Key? key,
    required this.startPosition,
    required this.endPosition,
    required this.amount,
    this.onComplete,
  }) : super(key: key);
  
  @override
  _ChipAnimationState createState() => _ChipAnimationState();
}

class _ChipAnimationState extends State<ChipAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    
    // 创建动画控制器
    _controller = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    
    // 创建曲线动画
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    );
    
    // 在动画完成时回调
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (widget.onComplete != null) {
          widget.onComplete!();
        }
      }
    });
    
    // 启动动画
    _controller.forward();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // 计算当前位置
        final double x = widget.startPosition.dx + (widget.endPosition.dx - widget.startPosition.dx) * _animation.value;
        final double y = widget.startPosition.dy + (widget.endPosition.dy - widget.startPosition.dy) * _animation.value;
        
        // 添加抛物线效果
        final double yOffset = -20 * sin(_animation.value * 3.14); // 使用正弦函数创建抛物线
        
        return Positioned(
          left: x - 15, // 调整位置以使筹码居中
          top: y + yOffset - 15,
          child: Opacity(
            opacity: (1.0 - (_animation.value * 0.3)).clamp(0.0, 1.0), // 确保opacity值在有效范围内
            child: Transform.scale(
              scale: (1.0 - (_animation.value * 0.3)).clamp(0.1, 1.0), // 确保scale不会太小或为负值
              child: _buildChip(widget.amount),
            ),
          ),
        );
      },
    );
  }
  
  // 创建筹码组件
  Widget _buildChip(int amount) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getChipColor(amount),
        border: Border.all(
          color: Colors.white.withOpacity(0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 2,
            spreadRadius: 0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _getChipColor(amount).withOpacity(0.7),
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1.0,
            ),
          ),
        ),
      ),
    );
  }
  
  // 根据金额获取筹码颜色
  Color _getChipColor(int amount) {
    if (amount >= 1000) {
      return Colors.purple.shade300; // 紫色筹码表示高额下注
    } else if (amount >= 500) {
      return Colors.red.shade500; // 红色筹码表示中高额下注
    } else if (amount >= 200) {
      return Colors.green.shade600; // 绿色筹码表示中额下注
    } else if (amount >= 100) {
      return Colors.blue.shade400; // 蓝色筹码表示中低额下注
    } else {
      return Colors.amber.shade600; // 黄色筹码表示低额下注
    }
  }
}

// 多筹码动画管理器
class ChipAnimationManager extends StatefulWidget {
  final List<Player> players;
  final Offset centerPosition;
  final double tableRadius;
  final VoidCallback? onAllAnimationsComplete;
  
  const ChipAnimationManager({
    Key? key,
    required this.players,
    required this.centerPosition,
    this.tableRadius = 200.0,
    this.onAllAnimationsComplete,
  }) : super(key: key);
  
  @override
  _ChipAnimationManagerState createState() => _ChipAnimationManagerState();
}

class _ChipAnimationManagerState extends State<ChipAnimationManager> {
  final List<_ChipAnimationData> _animations = [];
  
  @override
  void initState() {
    super.initState();
    _scheduleAnimations();
  }
  
  @override
  void didUpdateWidget(ChipAnimationManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果中心位置或玩家发生变化，重新计算动画
    if (oldWidget.centerPosition != widget.centerPosition ||
        oldWidget.players != widget.players) {
      _scheduleAnimations();
    }
  }
  
  void _scheduleAnimations() {
    // 清除旧的动画
    _animations.clear();
    
    // 为每个有下注的玩家添加动画
    for (int i = 0; i < widget.players.length; i++) {
      final player = widget.players[i];
      if (player.bet > 0) {
        // 根据玩家位置(1-8)计算起始位置
        final position = player.position;
        final double angle = 2 * pi * ((position - 1) / 8);
        final double radius = widget.tableRadius;
        
        // 计算起始位置 - 距离桌面边缘
        final Offset startPosition = Offset(
          widget.centerPosition.dx + radius * cos(angle),
          widget.centerPosition.dy + radius * sin(angle),
        );
        
        // 添加多个筹码以表示不同面额
        int remainingAmount = player.bet;
        List<int> chipValues = [500, 100, 25, 5, 1];
        
        // 限制动画筹码数量，避免创建太多动画对象
        int totalChips = 0;
        
        for (int value in chipValues) {
          int count = remainingAmount ~/ value;
          remainingAmount %= value;
          
          // 限制每个面额最多5个筹码
          count = min(count, 5);
          
          // 限制总筹码数量不超过15个
          if (totalChips + count > 15) {
            count = max(0, 15 - totalChips);
          }
          
          totalChips += count;
          
          for (int j = 0; j < count; j++) {
            // 添加一点随机性以使动画更加自然
            final double randX = (Random().nextDouble() - 0.5) * 20;
            final double randY = (Random().nextDouble() - 0.5) * 20;
            final Offset adjustedStart = Offset(
              startPosition.dx + randX,
              startPosition.dy + randY,
            );
            
            // 添加随机延迟以使动画错开(0-300ms)
            final int delay = Random().nextInt(300);
            
            _animations.add(_ChipAnimationData(
              startPosition: adjustedStart,
              endPosition: widget.centerPosition,
              amount: value,
              delay: delay,
            ));
          }
          
          // 如果达到限制，停止添加
          if (totalChips >= 15) break;
        }
      }
    }
    
    // 如果有动画，触发重建
    if (_animations.isNotEmpty) {
      setState(() {});
      print('创建了 ${_animations.length} 个筹码动画');
    }
  }
  
  void _onAnimationComplete(_ChipAnimationData animation) {
    setState(() {
      _animations.remove(animation);
    });
    
    // 检查是否所有动画都已完成
    if (_animations.isEmpty && widget.onAllAnimationsComplete != null) {
      widget.onAllAnimationsComplete!();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final animation in _animations)
          FutureBuilder(
            future: Future.delayed(Duration(milliseconds: animation.delay)),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return ChipAnimation(
                  startPosition: animation.startPosition,
                  endPosition: animation.endPosition,
                  amount: animation.amount,
                  onComplete: () => _onAnimationComplete(animation),
                );
              } else {
                return SizedBox();
              }
            },
          ),
      ],
    );
  }
}

// 动画数据类
class _ChipAnimationData {
  final Offset startPosition;
  final Offset endPosition;
  final int amount;
  final int delay;
  
  _ChipAnimationData({
    required this.startPosition,
    required this.endPosition,
    required this.amount,
    this.delay = 0,
  });
} 