/// Re-exporta AppText desde app_theme.dart (fuente única del Design System).
export 'app_theme.dart' show AppText;

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Wrapper de compatibilidad — usar AppText directamente en código nuevo.
/// DEPRECADO: se eliminará cuando se complete la migración.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle screenTitle({Color? color}) =>
      AppText.displayMd.copyWith(color: color);

  static TextStyle sectionSubtitle({Color? color}) =>
      AppText.titleLg.copyWith(color: color);

  static TextStyle body({Color? color}) =>
      AppText.bodyMd.copyWith(color: color ?? AppColors.textPrimary);

  static TextStyle tableText({Color? color}) =>
      AppText.bodyMd.copyWith(color: color ?? AppColors.textPrimary);

  static TextStyle caption({Color? color}) =>
      AppText.caption.copyWith(color: color);

  static TextStyle sidebarItem({Color? color}) =>
      AppText.bodyMd.copyWith(
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.textMuted,
      );

  static TextStyle bigNumber({Color? color}) =>
      AppText.kpiLg.copyWith(color: color);

  static TextStyle label({Color? color}) =>
      AppText.labelMd.copyWith(color: color ?? AppColors.textMuted);
}
