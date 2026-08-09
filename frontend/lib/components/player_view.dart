import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/player.dart';

// 在文件顶部添加一个方向枚举
enum PlayerDirection {
  top,    // 顶部玩家，名称显示在上方
  bottom, // 底部玩家，名称显示在下方
  left,   // 左侧玩家，名称显示在左侧
  right,  // 右侧玩家，名称显示在右侧
}

class PlayerView extends StatelessWidget {
  final Player player;
  final bool isCurrentPlayer;
  final bool isShowdown;
  final bool highlight;
  final bool isDealer; // 新增庄家标记属性
  final PlayerDirection direction; // 添加方向参数
  final Function(Player)? onTap; // 添加点击事件处理
  
  const PlayerView({
    super.key,
    required this.player,
    this.isCurrentPlayer = false,
    this.isShowdown = false,
    this.highlight = false,
    this.isDealer = false, // 默认不是庄家
    this.direction = PlayerDirection.bottom, // 默认为底部方向
    this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    // 根据方向选择不同的布局
    switch (direction) {
      case PlayerDirection.left:
        return _buildHorizontalLayout(context, isLeft: true);
      case PlayerDirection.right:
        return _buildHorizontalLayout(context, isLeft: false);
      case PlayerDirection.top:
        return _buildVerticalLayout(context, isTop: true);
      case PlayerDirection.bottom:
        return _buildVerticalLayout(context, isTop: false);
    }
  }
  
  // 水平布局（左右方向）
  Widget _buildHorizontalLayout(BuildContext context, {required bool isLeft}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 左侧玩家：先显示名称和筹码，再显示头像
        if (isLeft) ...[
          _buildPlayerInfo(context, isHorizontal: true),
          SizedBox(width: 8),
          _buildAvatar(context),
        ]
        // 右侧玩家：先显示头像，再显示名称和筹码
        else ...[
          _buildAvatar(context),
          SizedBox(width: 8),
          _buildPlayerInfo(context, isHorizontal: true),
        ],
      ],
    );
  }
  
  // 垂直布局（上下方向）
  Widget _buildVerticalLayout(BuildContext context, {required bool isTop}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部玩家：先显示名称和筹码，再显示头像
        if (isTop) ...[
          _buildPlayerInfo(context),
          SizedBox(height: 4),
          _buildAvatar(context),
        ]
        // 底部玩家：先显示头像，再显示名称和筹码
        else ...[
          _buildAvatar(context),
          SizedBox(height: 4),
          _buildPlayerInfo(context),
        ],
      ],
    );
  }
  
  // 玩家信息（名称和筹码）
  Widget _buildPlayerInfo(BuildContext context, {bool isHorizontal = false}) {
    return isHorizontal
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPlayerName(context),
              _buildChips(context),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPlayerName(context),
              _buildChips(context),
            ],
          );
  }
  
  // 构建头像内容
  Widget _buildAvatar(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;
    final avatarSize = isSmallScreen ? 60.0 : 70.0;
    
    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          onTap!(player);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 主要玩家视图容器
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getAvatarBackgroundColor(),
              border: Border.all(
                color: _getBorderColor(theme),
                width: highlight ? 3.0 : 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: highlight 
                      ? Colors.amber.withValues(alpha: 0.5) 
                      : Colors.black26,
                  spreadRadius: highlight ? 2 : 1,
                  blurRadius: highlight ? 8 : 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: _buildAvatarContent(),
            ),
          ),
          
          // 庄家位置标记 - 仅当玩家是庄家时显示
          if (isDealer)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.shade600,
                      Colors.red.shade900,
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.4),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'D',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 1.0,
                          offset: Offset(0.5, 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  // 构建头像内容
  Widget _buildAvatarContent() {
    if (player.isAI && player.aiModel != null) {
      return _buildAIAvatarLogo();
    } else {
      // 非AI玩家使用默认头像
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade800, Colors.blue.shade900],
          ),
        ),
        child: Icon(
          Icons.person,
          color: Colors.white,
          size: 24,
        ),
      );
    }
  }
  
  // AI头像Logo
  Widget _buildAIAvatarLogo() {
    // AI模型Logo映射
    final Map<String, String> aiModelLogos = {
      'ChatGPT-Mini': 'assets/images/llm_logos/openai.svg',
      'ChatGPT-4O': 'assets/images/llm_logos/openai.svg',
      'Claude': 'assets/images/llm_logos/anthropic.svg',
      'Grok': 'assets/images/llm_logos/xai.svg',
      'Gemini': 'assets/images/llm_logos/google.svg',
      'DeepSeek': 'assets/images/llm_logos/deepseek.svg',
      'Sonar': 'assets/images/llm_logos/perplexity.svg',
      'Qwen': 'assets/images/llm_logos/aliyun.svg',
    };
    
    // 获取AI模型名称
    String? aiModelName = player.aiModel;
    
    // 查找对应的Logo路径
    String? logoPath = aiModelName != null ? aiModelLogos[aiModelName] : null;
    
    // 检查玩家是否已弃牌或不活跃
    bool isInactive = !player.isActive;
    
    if (logoPath != null) {
      return Container(
        padding: EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Logo图片
            SvgPicture.asset(
              logoPath,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain,
            ),
            
            // 如果玩家不活跃，添加半透明黑色遮罩
            if (isInactive)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    
    // 如果没有找到对应的logo，使用模型首字母作为备用显示
    String displayText = '';
    if (aiModelName != null) {
      if (aiModelName.contains('ChatGPT')) {
        displayText = 'GPT';
      } else if (aiModelName.contains('DeepSeek')) {
        displayText = 'DS';
      } else if (aiModelName == 'Qwen') {
        displayText = 'QW';
      } else {
        final parts = aiModelName.split(' ');
        displayText = parts[0].substring(0, parts[0].length > 2 ? 2 : parts[0].length);
      }
    } else {
      // 如果无法获取模型名称，使用玩家名称的首字母
      displayText = player.name.substring(0, player.name.length > 2 ? 2 : player.name.length).toUpperCase();
    }
    
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isInactive ? Colors.grey.shade600 : Colors.indigo.shade800,
      ),
      child: Center(
        child: Text(
          displayText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  
  Color _getAvatarBackgroundColor() {
    if (!player.isActive) {
      return Colors.black38;
    }
    
    if (player.isCurrent) {
      return player.isAI 
          ? Colors.transparent  // AI玩家使用透明背景，显示logo
          : Colors.blue.shade800;
    }
    
    return player.isAI 
        ? Colors.transparent  // AI玩家使用透明背景，显示logo
        : Colors.black38;
  }
  
  Color _getBorderColor(ThemeData theme) {
    if (!player.isActive) {
      return Colors.grey;
    }

    if (player.isCurrent) {
      return Colors.amber; // 当前玩家使用琥珀色边框
    }

    if (highlight) {
      return theme.colorScheme.primary;
    }

    return Colors.white30; // 所有玩家统一使用相同边框颜色
  }

  Widget _buildPlayerName(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        player.name,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
  
  Widget _buildChips(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on,
            size: 12.0,
            color: Colors.amber,
          ),
          SizedBox(width: 2.0),
          Text(
            player.chips.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: player.chips > 0 ? Colors.amber : Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
