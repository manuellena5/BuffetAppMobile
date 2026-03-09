/// Re-exporta AppSpacing desde app_theme.dart (fuente única del Design System).
export 'app_theme.dart' show AppSpacing;

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Aliases de compatibilidad — usar AppSpacing directamente en código nuevo.
/// DEPRECADO: se eliminará cuando se complete la migración.
class AppSpacingLegacy {
  AppSpacingLegacy._();

  // Valores renombrados (old scale → new scale)
  static const double base = AppSpacing.lg; // 16
  static const double sectionGap = AppSpacing.xxl; // 24

  // Sidebar (valores legacy → nuevos)
  static const double sidebarExpandedWidth = AppSpacing.sidebarWidth;
  static const double sidebarCollapsedWidth = 72;
  static const double sidebarItemHeight = 44;
  static const double sidebarItemPaddingH = AppSpacing.lg;

  // Header
  static const double headerHeight = AppSpacing.topbarHeight;

  // Tabla
  static const double tableRowHeight = 44;

  // EdgeInsets helpers
  static const EdgeInsets paddingCard = EdgeInsets.all(AppSpacing.cardPadding);
  static const EdgeInsets paddingSection = EdgeInsets.all(AppSpacing.xxl);
  static const EdgeInsets paddingHorizontalBase = EdgeInsets.symmetric(horizontal: AppSpacing.lg);
  static const EdgeInsets paddingVerticalSm = EdgeInsets.symmetric(vertical: AppSpacing.sm);
}
