/// Re-exporta AppColors desde app_theme.dart (fuente única del Design System).
/// Los aliases de compatibilidad permiten compilar sin migrar cada archivo de golpe.
export 'app_theme.dart' show AppColors;

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Aliases de compatibilidad — usar los nuevos nombres de AppColors directamente.
/// DEPRECADO: se eliminará cuando se complete la migración de todas las pantallas.
extension AppColorsCompat on Never {
  // Estos getters no se usan en runtime, se proveen como constantes estáticas
  // a través de la clase AppColorsLegacy.
}

class AppColorsLegacy {
  AppColorsLegacy._();

  static const Color primary = AppColors.accent;
  static const Color primaryLight = AppColors.accentLight;
  static const Color primaryDark = AppColors.accentDim;

  static const Color backgroundLight = AppColors.bgBase;
  static const Color backgroundDark = AppColors.bgBase;
  static const Color cardLight = AppColors.bgSurface;
  static const Color cardDark = AppColors.bgSurface;
  static const Color formSurfaceLight = AppColors.bgElevated;
  static const Color formSurfaceDark = AppColors.bgElevated;
  static const Color borderLight = AppColors.border;
  static const Color borderDark = AppColors.border;
  static const Color textPrimaryLight = AppColors.textPrimary;
  static const Color textPrimaryDark = AppColors.textPrimary;
  static const Color textSecondaryLight = AppColors.textSecondary;
  static const Color textSecondaryDark = AppColors.textSecondary;

  static const Color sidebarBg = AppColors.bgSurface;
  static const Color sidebarItemText = AppColors.textMuted;
  static const Color sidebarItemHover = AppColors.bgElevated;
  static const Color sidebarItemSelected = AppColors.accent;
  static const Color sidebarItemSelectedText = AppColors.textPrimary;

  static const Color success = AppColors.ingreso;
  static const Color successLight = AppColors.ingresoDim;
  static const Color warning = AppColors.advertencia;
  static const Color warningLight = AppColors.advertenciaDim;
  static const Color danger = AppColors.egreso;
  static const Color dangerLight = AppColors.egresoDim;
  static const Color info = AppColors.info;
  static const Color infoLight = AppColors.infoDim;
}
