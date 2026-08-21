import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'design_tokens.dart';

/// 로컬 퀘스트 디자인 시스템 v1.0 — 앱 전역 테마
///
/// main.dart 의 `ThemeData(...)` 를 이걸로 교체한다:
///   theme: AppTheme.light,
class AppTheme {
  const AppTheme._();

  /// 상태바 아이콘을 어둡게 (밝은 크림 배경 위)
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.quest500,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.quest500,
      onPrimary: AppColors.textOnDark,
      secondary: AppColors.amber500,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.quest600,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: AppType.family,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,

      // 머티리얼 기본 그림자는 회색이라 크림 배경에서 탁하다. 잉크색으로 교체.
      shadowColor: AppColors.shadowBase.withValues(alpha: 0.18),

      textTheme: const TextTheme(
        displaySmall: AppType.display,
        headlineSmall: AppType.h1,
        titleLarge: AppType.h2,
        titleMedium: AppType.h3,
        bodyMedium: AppType.body,
        bodySmall: AppType.caption,
        labelSmall: AppType.micro,
        labelLarge: AppType.button,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: const BorderSide(color: AppColors.hairline, width: 1),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheet),
        showDragHandle: false,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppType.caption.copyWith(color: AppColors.textDisabled),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.hairline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.quest500, width: 1.5),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.quest500,
        linearTrackColor: AppColors.ink200,
        circularTrackColor: AppColors.ink200,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        titleTextStyle: AppType.body,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink900,
        contentTextStyle: AppType.body.copyWith(color: AppColors.textOnDark),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
