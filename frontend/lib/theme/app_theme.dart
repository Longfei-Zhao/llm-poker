import 'package:flutter/material.dart';

class AppTheme {
  // 浅色主题（配色为浅色系，brightness需与之一致）
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: Color(0xFF1B5E20), // 深绿色
      scaffoldBackgroundColor: Color(0xFFF5F7FA), // 非常浅的灰蓝色背景
      cardColor: Color(0xFFE8EDF5), // 浅色卡片背景
      colorScheme: ColorScheme.light(
        primary: Color(0xFF1B5E20), // 深绿色
        secondary: Color(0xFFFFD700), // 金色作为点缀
        surface: Color(0xFFE8EDF5), // 浅色表面
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: Colors.black87),
        bodyMedium: TextStyle(color: Colors.black54),
      ),
      // 自定义德州扑克相关颜色
      extensions: [
        PokerThemeExtension(
          tableColor: Color(0xFF0B6623), // 牌桌绿色
          chipColor: Colors.red.shade800, // 筹码红色
          cardBackColor: Color(0xFF1E88E5), // 牌背蓝色
          buttonColor: Color(0xFFFFD700), // 金色按钮
          buttonTextColor: Colors.black, // 按钮文本颜色
        ),
      ],
    );
  }
}

class PokerThemeExtension extends ThemeExtension<PokerThemeExtension> {
  final Color tableColor;
  final Color chipColor;
  final Color cardBackColor;
  final Color buttonColor;
  final Color buttonTextColor;

  PokerThemeExtension({
    required this.tableColor,
    required this.chipColor,
    required this.cardBackColor,
    required this.buttonColor,
    required this.buttonTextColor,
  });

  @override
  PokerThemeExtension copyWith({
    Color? tableColor,
    Color? chipColor,
    Color? cardBackColor,
    Color? buttonColor,
    Color? buttonTextColor,
  }) {
    return PokerThemeExtension(
      tableColor: tableColor ?? this.tableColor,
      chipColor: chipColor ?? this.chipColor,
      cardBackColor: cardBackColor ?? this.cardBackColor,
      buttonColor: buttonColor ?? this.buttonColor,
      buttonTextColor: buttonTextColor ?? this.buttonTextColor,
    );
  }

  @override
  PokerThemeExtension lerp(ThemeExtension<PokerThemeExtension>? other, double t) {
    if (other is! PokerThemeExtension) {
      return this;
    }
    return PokerThemeExtension(
      tableColor: Color.lerp(tableColor, other.tableColor, t)!,
      chipColor: Color.lerp(chipColor, other.chipColor, t)!,
      cardBackColor: Color.lerp(cardBackColor, other.cardBackColor, t)!,
      buttonColor: Color.lerp(buttonColor, other.buttonColor, t)!,
      buttonTextColor: Color.lerp(buttonTextColor, other.buttonTextColor, t)!,
    );
  }
} 