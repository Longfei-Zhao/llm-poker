import 'package:flutter/material.dart';
import '../models/poker_card.dart';
import '../theme/app_theme.dart';

class CardView extends StatelessWidget {
  final PokerCard? card;
  final bool faceUp;
  final double width;
  final double height;
  final double borderRadius;
  final double elevation;
  
  const CardView({
    Key? key,
    this.card,
    this.faceUp = true,
    this.width = 80.0,
    this.height = 120.0,
    this.borderRadius = 8.0,
    this.elevation = 4.0,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (card == null) {
      return _buildEmptyCard(context);
    }
    
    return faceUp ? _buildFaceUpCard(context) : _buildFaceDownCard(context);
  }
  
  Widget _buildFaceUpCard(BuildContext context) {
    final isRed = card!.isRed;
    final color = isRed ? Colors.red : Colors.black;
    
    return Card(
      elevation: elevation,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Colors.black26, width: 1),
      ),
      color: Colors.white,
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.grey[50]!],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左上角花色和点数
            Row(
              children: [
                Text(
                  card!.rankSymbol,
                  style: TextStyle(
                    fontSize: width * 0.25,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                SizedBox(width: 2),
                Text(
                  card!.suitSymbol,
                  style: TextStyle(
                    fontSize: width * 0.25,
                    color: color,
                  ),
                ),
              ],
            ),
            
            // 中间位置留空
            Spacer(),
            
            // 右下角大花色图标
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.only(right: 4.0, bottom: 4.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      card!.rankSymbol,
                      style: TextStyle(
                        fontSize: width * 0.25,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFaceDownCard(BuildContext context) {
    final pokerTheme = Theme.of(context).extension<PokerThemeExtension>();
    final cardBackColor = pokerTheme?.cardBackColor ?? Colors.blue.shade800;
    
    return Card(
      elevation: elevation,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Colors.black26, width: 1),
      ),
      color: cardBackColor,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cardBackColor, Colors.blue.shade900],
          ),
        ),
        child: Stack(
          children: [
            // 卡牌背面图案
            Center(
              child: Container(
                width: width * 0.7,
                height: height * 0.7,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white30,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(width * 0.1),
                ),
                child: Center(
                  child: Icon(
                    Icons.psychology,
                    size: width * 0.4,
                    color: Colors.white30,
                  ),
                ),
              ),
            ),
            // 卡牌四角装饰
            ...List.generate(4, (index) {
              final isTopLeft = index == 0;
              final isTopRight = index == 1;
              final isBottomLeft = index == 2;
              final isBottomRight = index == 3;
              
              return Positioned(
                top: isTopLeft || isTopRight ? 6 : null,
                bottom: isBottomLeft || isBottomRight ? 6 : null,
                left: isTopLeft || isBottomLeft ? 6 : null,
                right: isTopRight || isBottomRight ? 6 : null,
                child: Icon(
                  Icons.auto_awesome,
                  size: width * 0.15,
                  color: Colors.white24,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyCard(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white24,
          width: 1,
          style: BorderStyle.solid,
        ),
        color: Colors.black12,
      ),
      child: Center(
        child: Icon(
          Icons.help_outline,
          color: Colors.white24,
          size: width * 0.25,
        ),
      ),
    );
  }
}

class CommunityCardsView extends StatelessWidget {
  final List<PokerCard> cards;
  final double spacing;
  final double cardWidth;
  final double cardHeight;
  
  const CommunityCardsView({
    Key? key,
    required this.cards,
    this.spacing = 8.0,
    this.cardWidth = 70.0,
    this.cardHeight = 100.0,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    
    // 先填充所有社区牌位置
    List<Widget> cardWidgets = [];
    
    // 填充已有牌
    for (var i = 0; i < 5; i++) {
      if (i < cards.length) {
        cardWidgets.add(
          CardView(
            card: cards[i],
            faceUp: true,
            width: cardWidth,
            height: cardHeight,
          ),
        );
      } else {
        // 空牌位
        cardWidgets.add(
          CardView(
            width: cardWidth,
            height: cardHeight,
          ),
        );
      }
      
      // 添加间隔
      if (i < 4) {
        cardWidgets.add(SizedBox(width: spacing));
      }
    }
    
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(cardHeight * 0.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 5,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: cardWidgets,
      ),
    );
  }
}

class PlayerCardsView extends StatelessWidget {
  final List<PokerCard> cards;
  final bool isCurrentPlayer;
  final bool showCards;
  final double spacing;
  final double overlap;
  final double cardWidth;
  final double cardHeight;
  
  const PlayerCardsView({
    Key? key,
    required this.cards,
    this.isCurrentPlayer = false,
    this.showCards = false,
    this.spacing = 5.0,
    this.overlap = 20.0,
    this.cardWidth = 60.0,
    this.cardHeight = 90.0,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 3,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 2; i++)
            Transform.translate(
              offset: Offset(i * overlap, 0),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                child: i < cards.length
                    ? CardView(
                        card: cards[i],
                        faceUp: isCurrentPlayer || showCards,
                        width: cardWidth,
                        height: cardHeight,
                      )
                    : CardView(
                        card: null,
                        width: cardWidth,
                        height: cardHeight,
                      ),
              ),
            ),
        ],
      ),
    );
  }
} 