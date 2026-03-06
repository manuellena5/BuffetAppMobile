import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Jerarquía tipográfica del Design System ERP (fuente Inter).
class AppTextStyles {
  AppTextStyles._();

  /// Base de Inter para usar como fontFamily global.
  static TextStyle get _inter => GoogleFonts.inter();

  // ─── Jerarquía ───

  /// Título de pantalla: 28px / w600
  static TextStyle screenTitle({Color? color}) => _inter.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.textPrimaryLight,
      );

  /// Subtítulo de sección: 20px / w600
  static TextStyle sectionSubtitle({Color? color}) => _inter.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.textPrimaryLight,
      );

  /// Texto normal: 14px / w400
  static TextStyle body({Color? color}) => _inter.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimaryLight,
      );

  /// Texto de tabla/datos: 13px / w400
  static TextStyle tableText({Color? color}) => _inter.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimaryLight,
      );

  /// Texto secundario/caption: 12px / gris
  static TextStyle caption({Color? color}) => _inter.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textSecondaryLight,
      );

  /// Sidebar item: 14px / w500
  static TextStyle sidebarItem({Color? color}) => _inter.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.sidebarItemText,
      );

  /// Monto / dato grande: 24px / w700
  static TextStyle bigNumber({Color? color}) => _inter.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimaryLight,
      );

  /// Label de formulario: 13px / w500
  static TextStyle label({Color? color}) => _inter.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.textSecondaryLight,
      );
}
