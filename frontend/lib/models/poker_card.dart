enum CardSuit {
  spades, // 黑桃
  hearts, // 红心
  diamonds, // 方块
  clubs, // 梅花
}

enum CardRank {
  ace, // A
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack, // J
  queen, // Q
  king, // K
}

class PokerCard {
  final CardSuit suit;
  final CardRank rank;
  final bool faceUp;

  PokerCard({
    required this.suit,
    required this.rank,
    this.faceUp = true,
  });

  // 从字符串创建扑克牌，例如 "AS" 表示黑桃A，"10H"/"TH" 均表示红心10
  factory PokerCard.fromString(String code) {
    if (code.length != 2 && code.length != 3) {
      throw ArgumentError('无效的卡牌代码: $code');
    }

    final rankChar = code.substring(0, code.length - 1).toUpperCase();
    final suitChar = code[code.length - 1].toUpperCase();

    CardRank rank;
    switch (rankChar) {
      case 'A':
        rank = CardRank.ace;
        break;
      case '2':
        rank = CardRank.two;
        break;
      case '3':
        rank = CardRank.three;
        break;
      case '4':
        rank = CardRank.four;
        break;
      case '5':
        rank = CardRank.five;
        break;
      case '6':
        rank = CardRank.six;
        break;
      case '7':
        rank = CardRank.seven;
        break;
      case '8':
        rank = CardRank.eight;
        break;
      case '9':
        rank = CardRank.nine;
        break;
      case 'T':
      case '10':
        rank = CardRank.ten;
        break;
      case 'J':
        rank = CardRank.jack;
        break;
      case 'Q':
        rank = CardRank.queen;
        break;
      case 'K':
        rank = CardRank.king;
        break;
      default:
        throw ArgumentError('无效的卡牌等级: $rankChar');
    }

    CardSuit suit;
    switch (suitChar) {
      case 'S':
        suit = CardSuit.spades;
        break;
      case 'H':
        suit = CardSuit.hearts;
        break;
      case 'D':
        suit = CardSuit.diamonds;
        break;
      case 'C':
        suit = CardSuit.clubs;
        break;
      default:
        throw ArgumentError('无效的卡牌花色: $suitChar');
    }

    return PokerCard(suit: suit, rank: rank);
  }

  // 将牌转换为字符串表示
  String toShortString() {
    String rankStr;
    switch (rank) {
      case CardRank.ace:
        rankStr = 'A';
        break;
      case CardRank.two:
        rankStr = '2';
        break;
      case CardRank.three:
        rankStr = '3';
        break;
      case CardRank.four:
        rankStr = '4';
        break;
      case CardRank.five:
        rankStr = '5';
        break;
      case CardRank.six:
        rankStr = '6';
        break;
      case CardRank.seven:
        rankStr = '7';
        break;
      case CardRank.eight:
        rankStr = '8';
        break;
      case CardRank.nine:
        rankStr = '9';
        break;
      case CardRank.ten:
        rankStr = '10';
        break;
      case CardRank.jack:
        rankStr = 'J';
        break;
      case CardRank.queen:
        rankStr = 'Q';
        break;
      case CardRank.king:
        rankStr = 'K';
        break;
    }

    String suitStr;
    switch (suit) {
      case CardSuit.spades:
        suitStr = 'S';
        break;
      case CardSuit.hearts:
        suitStr = 'H';
        break;
      case CardSuit.diamonds:
        suitStr = 'D';
        break;
      case CardSuit.clubs:
        suitStr = 'C';
        break;
    }

    return rankStr + suitStr;
  }

  // 序列化时使用短字符串表示（与fromString互逆）
  @override
  String toString() => toShortString();

  // 获取花色符号
  String get suitSymbol {
    switch (suit) {
      case CardSuit.spades:
        return '♠';
      case CardSuit.hearts:
        return '♥';
      case CardSuit.diamonds:
        return '♦';
      case CardSuit.clubs:
        return '♣';
    }
  }

  // 获取花色颜色
  bool get isRed {
    return suit == CardSuit.hearts || suit == CardSuit.diamonds;
  }

  // 获取牌面值的符号表示
  String get rankSymbol {
    switch (rank) {
      case CardRank.ace:
        return 'A';
      case CardRank.jack:
        return 'J';
      case CardRank.queen:
        return 'Q';
      case CardRank.king:
        return 'K';
      default:
        return (rank.index + 1).toString();
    }
  }

  // 获取牌的完整中文名称
  String getCardName() {
    String suitName;
    switch (suit) {
      case CardSuit.spades:
        suitName = '黑桃';
        break;
      case CardSuit.hearts:
        suitName = '红心';
        break;
      case CardSuit.diamonds:
        suitName = '方块';
        break;
      case CardSuit.clubs:
        suitName = '梅花';
        break;
    }
    
    String rankName;
    switch (rank) {
      case CardRank.ace:
        rankName = 'A';
        break;
      case CardRank.jack:
        rankName = 'J';
        break;
      case CardRank.queen:
        rankName = 'Q';
        break;
      case CardRank.king:
        rankName = 'K';
        break;
      default:
        rankName = (rank.index + 1).toString();
    }
    
    return '$suitName$rankName';
  }
} 