import 'package:flutter/material.dart';

class AppColors {
  static const darkBlue = Color(0xFF06152F);
  static const navy = Color(0xFF0B1E3D);
  static const purple = Color(0xFF4B22B8);
  static const green = Color(0xFF00C878);
  static const blue = Color(0xFF2F80ED);
  static const cardWhite = Color(0xFFF7F4FF);
  static const textLight = Colors.white;
  static const textDark = Color(0xFF1E1E2F);
}

class AppGradients {
  static const studentBg = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF071A3A),
      Color(0xFF30106B),
      Color(0xFF050814),
    ],
  );

  static const teacherBg = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF06312E),
      Color(0xFF008A5C),
      Color(0xFF061B26),
    ],
  );

  static const adminBg = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0E3A8A),
      Color(0xFF1E63D6),
      Color(0xFF08204D),
    ],
  );
}

class AppDecorations {
  static BoxDecoration glassCard({
    Color color = Colors.white,
    double opacity = 0.12,
    double radius = 22,
  }) {
    return BoxDecoration(
      color: color.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withOpacity(0.15),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.18),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static BoxDecoration whiteCard() {
    return BoxDecoration(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class AppTheme {
  static ThemeData theme = ThemeData(
    useMaterial3: true,
    fontFamilyFallback: const [
      'Arial',
      'Roboto',
      'Noto Sans',
      'sans-serif',
    ],
    scaffoldBackgroundColor: AppColors.darkBlue,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.purple,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: Colors.white,
    ),
  );
}