import 'package:flutter/material.dart';

/// Sistema de espaciado consistente para todo el Design System ERP.
class AppSpacing {
  AppSpacing._();

  // ─── Escala base (multiplos de 4) ───
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double xxxl = 48;

  // ─── Semánticos ───
  static const double cardPadding = 16;
  static const double sectionGap = 24;
  static const double widgetGap = 12;
  static const double inputFieldGap = 16;

  // ─── Sidebar ───
  static const double sidebarExpandedWidth = 240;
  static const double sidebarCollapsedWidth = 72;
  static const double sidebarItemHeight = 44;
  static const double sidebarItemPaddingH = 16;

  // ─── Header ───
  static const double headerHeight = 72;

  // ─── Tabla ERP ───
  static const double tableRowHeight = 44;

  // ─── Breakpoints ───
  static const double breakpointMobile = 600;
  static const double breakpointTablet = 900;
  static const double breakpointDesktop = 1200;

  // ─── Helpers de EdgeInsets ───
  static const EdgeInsets paddingCard = EdgeInsets.all(cardPadding);
  static const EdgeInsets paddingSection = EdgeInsets.all(sectionGap);
  static const EdgeInsets paddingHorizontalBase = EdgeInsets.symmetric(horizontal: base);
  static const EdgeInsets paddingVerticalSm = EdgeInsets.symmetric(vertical: sm);
}
