import 'package:flutter/material.dart';

/// Paleta de colores del Design System ERP.
/// Incluye variantes light y dark.
class AppColors {
  AppColors._();

  // ─── Primarios ───
  static const primary = Color(0xFF2563EB);
  static const primaryLight = Color(0xFF3B82F6);
  static const primaryDark = Color(0xFF1D4ED8);

  // ─── Superficies LIGHT ───
  static const backgroundLight = Color(0xFFF5F7FA);
  static const cardLight = Color(0xFFFFFFFF);
  static const formSurfaceLight = Color(0xFFF8FAFC); // contraste sutil para formularios
  static const borderLight = Color(0xFFE5E7EB);
  static const textPrimaryLight = Color(0xFF111827);
  static const textSecondaryLight = Color(0xFF6B7280);

  // ─── Superficies DARK ───
  static const backgroundDark = Color(0xFF0F172A);
  static const cardDark = Color(0xFF1E293B);
  static const formSurfaceDark = Color(0xFF253348); // contraste sutil para formularios
  static const borderDark = Color(0xFF334155);
  static const textPrimaryDark = Color(0xFFF1F5F9);
  static const textSecondaryDark = Color(0xFF94A3B8);

  // ─── Sidebar ───
  static const sidebarBg = Color(0xFF111827);
  static const sidebarItemText = Color(0xFF9CA3AF);
  static const sidebarItemHover = Color(0xFF1F2937);
  static const sidebarItemSelected = Color(0xFF2563EB);
  static const sidebarItemSelectedText = Color(0xFFFFFFFF);

  // ─── Estados financieros ───
  static const success = Color(0xFF16A34A);     // pagado
  static const successLight = Color(0xFFDCFCE7); // fondo pagado
  static const warning = Color(0xFFF59E0B);     // hoy/proximo
  static const warningLight = Color(0xFFFEF3C7); // fondo hoy
  static const danger = Color(0xFFDC2626);      // vencido
  static const dangerLight = Color(0xFFFEE2E2); // fondo vencido
  static const info = Color(0xFF2563EB);        // pendiente
  static const infoLight = Color(0xFFDBEAFE);   // fondo pendiente
}
