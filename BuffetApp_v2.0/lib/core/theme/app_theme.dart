import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CDM GESTIÓN — DESIGN SYSTEM
// Todos los widgets deben referenciar estas constantes.
// NUNCA hardcodear Color(0x...), radios ni estilos de texto directamente.
//
// Colores que CAMBIAN entre Light/Dark → usar context.appColors.xxx
// Colores FIJOS en ambos modos       → usar AppColors.xxx
// ═══════════════════════════════════════════════════════════════════════════════

// ─── COLORES FIJOS (no cambian entre Light/Dark) ─────────────────────────────
class AppColors {
  AppColors._();

  // Acento principal
  static const accent       = Color(0xFF2563EB);
  static const accentLight  = Color(0xFF60A5FA);
  static const accentDim    = Color(0xFF1E40AF);

  // Semánticos financieros (iguales en ambos modos)
  static const ingreso      = Color(0xFF22C55E);
  static const ingresoLight = Color(0xFF86EFAC);

  static const egreso       = Color(0xFFEF4444);
  static const egresoLight  = Color(0xFFFCA5A5);

  static const advertencia       = Color(0xFFF59E0B);
  static const advertenciaLight  = Color(0xFFFDE68A);

  static const info      = Color(0xFF3B82F6);
  static const infoLight = Color(0xFF93C5FD);

  // Estados de compromiso / cuota
  static const estadoConfirmado = ingreso;
  static const estadoEsperado   = advertencia;
  static const estadoVencido    = egreso;
  static const estadoCancelado  = Color(0xFF475569);

  // Estados de sync
  static const syncPendiente     = advertencia;
  static const syncSincronizada  = ingreso;
  static const syncError         = egreso;

  // Colores por subcomisión
  static const futbolMayor = Color(0xFF2563EB);
  static const voley       = Color(0xFFF97316);
  static const tenis       = Color(0xFF22C55E);
  static const patin       = Color(0xFFA855F7);
  static const infantil    = Color(0xFF06B6D4);
  static const senior      = Color(0xFFEF4444);

  // Sidebar — siempre dark, no cambia con el tema
  static const sidebarBg              = Color(0xFF111520);
  static const sidebarItemText        = Color(0xFF64748B);
  static const sidebarItemHover       = Color(0xFF1A2035);
  static const sidebarItemSelected    = accent;
  static const sidebarItemSelectedText = Color(0xFFF1F5F9);

  // ─── VALORES DARK constantes (para compat y sidebar) ───
  static const bgBase       = Color(0xFF0B0E14);
  static const bgSurface    = Color(0xFF111520);
  static const bgElevated   = Color(0xFF1A2035);
  static const bgOverlay    = Color(0x99000000);
  static const border       = Color(0xFF1A2035);
  static const borderFocus  = Color(0xFF2563EB);
  static const textPrimary   = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted     = Color(0xFF64748B);
  static const textDisabled  = Color(0xFF2D3748);
  static const ingresoDim   = Color(0xFF14532D);
  static const egresoDim    = Color(0xFF450A0A);
  static const advertenciaDim    = Color(0xFF451A03);
  static const infoDim   = Color(0xFF1E3A8A);

  // ─── Aliases de compatibilidad (DEPRECADO — usar context.appColors) ───
  static const primary = accent;
  static const primaryLight = accentLight;
  static const primaryDark = accentDim;
  static const backgroundLight = bgBase;
  static const backgroundDark = bgBase;
  static const cardLight = bgSurface;
  static const cardDark = bgSurface;
  static const formSurfaceLight = bgElevated;
  static const formSurfaceDark = bgElevated;
  static const borderLight = border;
  static const borderDark = border;
  static const textPrimaryLight = textPrimary;
  static const textPrimaryDark = textPrimary;
  static const textSecondaryLight = textSecondary;
  static const textSecondaryDark = textSecondary;
  static const success = ingreso;
  static const successLight = ingresoDim;
  static const warning = advertencia;
  static const warningLight = advertenciaDim;
  static const danger = egreso;
  static const dangerLight = egresoDim;
}

// ─── COLORES POR MODO (ThemeExtension) ────────────────────────────────────────
@immutable
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  const AppColorScheme({
    required this.bgBase,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgOverlay,
    required this.border,
    required this.borderFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.ingresoDim,
    required this.egresoDim,
    required this.advertenciaDim,
    required this.infoDim,
    required this.accentDim,
    required this.accentLight,
    required this.isDark,
  });

  final Color bgBase;
  final Color bgSurface;
  final Color bgElevated;
  final Color bgOverlay;
  final Color border;
  final Color borderFocus;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;
  final Color ingresoDim;
  final Color egresoDim;
  final Color advertenciaDim;
  final Color infoDim;
  final Color accentDim;
  final Color accentLight;
  final bool isDark;

  // ─── Instancias predefinidas ───

  static const dark = AppColorScheme(
    bgBase:          Color(0xFF0B0E14),
    bgSurface:       Color(0xFF111520),
    bgElevated:      Color(0xFF1A2035),
    bgOverlay:       Color(0x99000000),
    border:          Color(0xFF1A2035),
    borderFocus:     Color(0xFF2563EB),
    textPrimary:     Color(0xFFF1F5F9),
    textSecondary:   Color(0xFF94A3B8),
    textMuted:       Color(0xFF64748B),
    textDisabled:    Color(0xFF2D3748),
    ingresoDim:      Color(0xFF14532D),
    egresoDim:       Color(0xFF450A0A),
    advertenciaDim:  Color(0xFF451A03),
    infoDim:         Color(0xFF1E3A8A),
    accentDim:       Color(0xFF1E40AF),
    accentLight:     Color(0xFF60A5FA),
    isDark: true,
  );

  static const light = AppColorScheme(
    bgBase:          Color(0xFFF8FAFC),
    bgSurface:       Color(0xFFFFFFFF),
    bgElevated:      Color(0xFFF1F5F9),
    bgOverlay:       Color(0x33000000),
    border:          Color(0xFFE2E8F0),
    borderFocus:     Color(0xFF2563EB),
    textPrimary:     Color(0xFF0F172A),
    textSecondary:   Color(0xFF475569),
    textMuted:       Color(0xFF94A3B8),
    textDisabled:    Color(0xFFCBD5E1),
    ingresoDim:      Color(0xFFDCFCE7),
    egresoDim:       Color(0xFFFEE2E2),
    advertenciaDim:  Color(0xFFFEF3C7),
    infoDim:         Color(0xFFDBEAFE),
    accentDim:       Color(0xFFDBEAFE),
    accentLight:     Color(0xFF2563EB),
    isDark: false,
  );

  @override
  AppColorScheme copyWith({
    Color? bgBase,
    Color? bgSurface,
    Color? bgElevated,
    Color? bgOverlay,
    Color? border,
    Color? borderFocus,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
    Color? ingresoDim,
    Color? egresoDim,
    Color? advertenciaDim,
    Color? infoDim,
    Color? accentDim,
    Color? accentLight,
    bool? isDark,
  }) => AppColorScheme(
    bgBase:          bgBase          ?? this.bgBase,
    bgSurface:       bgSurface       ?? this.bgSurface,
    bgElevated:      bgElevated      ?? this.bgElevated,
    bgOverlay:       bgOverlay       ?? this.bgOverlay,
    border:          border          ?? this.border,
    borderFocus:     borderFocus     ?? this.borderFocus,
    textPrimary:     textPrimary     ?? this.textPrimary,
    textSecondary:   textSecondary   ?? this.textSecondary,
    textMuted:       textMuted       ?? this.textMuted,
    textDisabled:    textDisabled    ?? this.textDisabled,
    ingresoDim:      ingresoDim      ?? this.ingresoDim,
    egresoDim:       egresoDim       ?? this.egresoDim,
    advertenciaDim:  advertenciaDim  ?? this.advertenciaDim,
    infoDim:         infoDim         ?? this.infoDim,
    accentDim:       accentDim       ?? this.accentDim,
    accentLight:     accentLight     ?? this.accentLight,
    isDark:          isDark          ?? this.isDark,
  );

  @override
  AppColorScheme lerp(AppColorScheme? other, double t) {
    if (other is! AppColorScheme) return this;
    return AppColorScheme(
      bgBase:          Color.lerp(bgBase,          other.bgBase,          t)!,
      bgSurface:       Color.lerp(bgSurface,       other.bgSurface,       t)!,
      bgElevated:      Color.lerp(bgElevated,      other.bgElevated,      t)!,
      bgOverlay:       Color.lerp(bgOverlay,       other.bgOverlay,       t)!,
      border:          Color.lerp(border,          other.border,          t)!,
      borderFocus:     Color.lerp(borderFocus,     other.borderFocus,     t)!,
      textPrimary:     Color.lerp(textPrimary,     other.textPrimary,     t)!,
      textSecondary:   Color.lerp(textSecondary,   other.textSecondary,   t)!,
      textMuted:       Color.lerp(textMuted,       other.textMuted,       t)!,
      textDisabled:    Color.lerp(textDisabled,     other.textDisabled,    t)!,
      ingresoDim:      Color.lerp(ingresoDim,      other.ingresoDim,      t)!,
      egresoDim:       Color.lerp(egresoDim,       other.egresoDim,       t)!,
      advertenciaDim:  Color.lerp(advertenciaDim,  other.advertenciaDim,  t)!,
      infoDim:         Color.lerp(infoDim,         other.infoDim,         t)!,
      accentDim:       Color.lerp(accentDim,       other.accentDim,       t)!,
      accentLight:     Color.lerp(accentLight,     other.accentLight,     t)!,
      isDark:          t < 0.5 ? isDark : other.isDark,
    );
  }
}

// ─── TIPOGRAFÍA ───────────────────────────────────────────────────────────────
class AppText {
  AppText._();

  /// En true, usa fuentes del sistema en lugar de Google Fonts.
  static bool useSystemFonts = false;

  static TextStyle _dmSans({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0,
  }) =>
      useSystemFonts
          ? TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
            )
          : GoogleFonts.dmSans(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
            );

  static TextStyle _dmMono({
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
  }) =>
      useSystemFonts
          ? TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: color)
          : GoogleFonts.dmMono(
              fontSize: fontSize, fontWeight: fontWeight, color: color);

  // Títulos y display (color: null → hereda del Theme)
  static TextStyle get displayLg => _dmSans(
    fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5,
  );
  static TextStyle get displayMd => _dmSans(
    fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3,
  );
  static TextStyle get titleLg => _dmSans(
    fontSize: 16, fontWeight: FontWeight.w700,
  );
  static TextStyle get titleMd => _dmSans(
    fontSize: 14, fontWeight: FontWeight.w700,
  );
  static TextStyle get titleSm => _dmSans(
    fontSize: 13, fontWeight: FontWeight.w600,
  );

  // Cuerpo (color: null → hereda del Theme / onSurface)
  static TextStyle get bodyLg => _dmSans(fontSize: 14);
  static TextStyle get bodyMd => _dmSans(fontSize: 13);
  static TextStyle get bodySm => _dmSans(fontSize: 12);

  // Labels (color: null → hereda del Theme)
  static TextStyle get label => _dmSans(
    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.08,
  );
  static TextStyle get labelMd => _dmSans(
    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.06,
  );
  static TextStyle get caption => _dmSans(fontSize: 11);

  // KPIs / valores numéricos grandes
  static TextStyle get kpiLg => _dmSans(
    fontSize: 22, fontWeight: FontWeight.w700,
  );
  static TextStyle get kpiMd => _dmSans(
    fontSize: 18, fontWeight: FontWeight.w700,
  );
  static TextStyle get kpiSm => _dmSans(
    fontSize: 15, fontWeight: FontWeight.w700,
  );

  // Monospaced — tablas financieras, montos, fechas
  static TextStyle get mono => _dmMono();
  static TextStyle get monoSm => _dmMono(fontSize: 11);
  static TextStyle get monoBold => _dmMono(
    fontSize: 13, fontWeight: FontWeight.w500,
  );
}

// ─── ESPACIADO Y RADIOS ───────────────────────────────────────────────────────
class AppSpacing {
  AppSpacing._();

  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 20;
  static const double xxl  = 24;
  static const double xxxl = 32;

  static const double radiusSm   = 6;
  static const double radiusMd   = 8;
  static const double radiusLg   = 12;
  static const double radiusXl   = 16;
  static const double radiusFull = 999;

  static const double sidebarWidth   = 220;
  static const double topbarHeight   = 56;
  static const double contentPadding = 22;
  static const double cardPadding    = 20;
  static const double cardPaddingSm  = 16;

  // Breakpoints
  static const double breakpointMobile = 600;
  static const double breakpointTablet = 900;
  static const double breakpointDesktop = 1200;

  // ─── Aliases de compatibilidad (DEPRECADO — usar nombres nuevos) ───
  static const double base = lg; // 16
  static const double sidebarExpandedWidth = sidebarWidth;
  static const double sidebarCollapsedWidth = 72;
  static const double sidebarItemHeight = 44;
  static const double sidebarItemPaddingH = lg;
  static const double headerHeight = topbarHeight;
  static const double tableRowHeight = 44;
  static const double sectionGap = xxl;
  static const double widgetGap = md;
  static const double inputFieldGap = lg;
  static const EdgeInsets paddingCard = EdgeInsets.all(cardPadding);
  static const EdgeInsets paddingSection = EdgeInsets.all(xxl);
  static const EdgeInsets paddingHorizontalBase = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingVerticalSm = EdgeInsets.symmetric(vertical: sm);
}

// ─── SOMBRAS ──────────────────────────────────────────────────────────────────
class AppShadows {
  AppShadows._();

  static List<BoxShadow> cardFor(BuildContext context) {
    final isDark = context.appColors.isDark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
        blurRadius: isDark ? 8 : 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> modalFor(BuildContext context) {
    final isDark = context.appColors.isDark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
        blurRadius: isDark ? 24 : 16,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> glowFor(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1),
  ];

  // Compat — usan colores dark
  static List<BoxShadow> get card => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> get modal => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8)),
  ];
}

// ─── DECORACIONES COMUNES ─────────────────────────────────────────────────────
class AppDecorations {
  AppDecorations._();

  // ─── Theme-aware (usar estos en código nuevo) ───

  static BoxDecoration cardOf(BuildContext context) {
    final c = context.appColors;
    return BoxDecoration(
      color: c.bgSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: c.border),
    );
  }

  static BoxDecoration cardElevatedOf(BuildContext context) {
    final c = context.appColors;
    return BoxDecoration(
      color: c.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: c.border),
    );
  }

  static BoxDecoration inputOf(BuildContext context) {
    final c = context.appColors;
    return BoxDecoration(
      color: c.bgBase,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: c.border),
    );
  }

  static BoxDecoration inputFocusedOf(BuildContext context) {
    final c = context.appColors;
    return BoxDecoration(
      color: c.bgBase,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.accent, width: 1.5),
    );
  }

  static BoxDecoration modalOf(BuildContext context) {
    final c = context.appColors;
    return BoxDecoration(
      color: c.bgSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      border: Border.all(color: c.border),
      boxShadow: AppShadows.modalFor(context),
    );
  }

  static BoxDecoration badgeFor(Color color) => BoxDecoration(
    color: color.withValues(alpha: 0.13),
    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    border: Border.all(color: color.withValues(alpha: 0.25)),
  );

  static BoxDecoration rowSelectedOf(BuildContext context) {
    final c = context.appColors;
    return BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
    );
  }

  static BoxDecoration accentBar(Color color) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(2),
  );

  // ─── Compat: getters estáticos (usan colores dark) ───

  static BoxDecoration get card => BoxDecoration(
    color: AppColors.bgSurface,
    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    border: Border.all(color: AppColors.border),
  );

  static BoxDecoration get cardElevated => BoxDecoration(
    color: AppColors.bgElevated,
    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    border: Border.all(color: AppColors.border),
  );

  static BoxDecoration get input => BoxDecoration(
    color: AppColors.bgBase,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    border: Border.all(color: AppColors.border),
  );

  static BoxDecoration get inputFocused => BoxDecoration(
    color: AppColors.bgBase,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    border: Border.all(color: AppColors.accent, width: 1.5),
  );

  static BoxDecoration get modal => BoxDecoration(
    color: AppColors.bgSurface,
    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
    border: Border.all(color: AppColors.border),
    boxShadow: AppShadows.modal,
  );

  static BoxDecoration get rowSelected => BoxDecoration(
    color: AppColors.accent.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
  );
}

// ─── HELPERS DE FORMATO ───────────────────────────────────────────────────────
class AppFormat {
  AppFormat._();

  static String moneda(double monto) {
    final abs = monto.abs();
    final formatted = abs.toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return monto < 0 ? '-\$$formatted' : '\$$formatted';
  }

  static String litros(double cantidad) =>
      '${cantidad.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} lts';

  static String pct(double valor) => '${valor.toStringAsFixed(1)}%';

  static String fecha(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  static String fechaCorta(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}';

  static String mesAnio(DateTime dt) {
    const m = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    return '${m[dt.month - 1]} ${dt.year}';
  }

  static String iniciales(String nombre) {
    final partes = nombre.trim().split(' ');
    if (partes.length >= 2) return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    return nombre.substring(0, nombre.length >= 2 ? 2 : 1).toUpperCase();
  }
}

// ─── COLORES Y LABELS POR ESTADO ─────────────────────────────────────────────
class AppEstado {
  AppEstado._();

  static Color colorDe(String estado) => switch (estado.toUpperCase()) {
    'CONFIRMADO'   => AppColors.estadoConfirmado,
    'ESPERADO'     => AppColors.estadoEsperado,
    'VENCIDO'      => AppColors.estadoVencido,
    'CANCELADO'    => AppColors.estadoCancelado,
    'INGRESO'      => AppColors.ingreso,
    'EGRESO'       => AppColors.egreso,
    'ACTIVO'       => AppColors.ingreso,
    'INACTIVO'     => AppColors.estadoCancelado,
    'PENDIENTE'    => AppColors.advertencia,
    'SINCRONIZADA' => AppColors.ingreso,
    'ERROR'        => AppColors.egreso,
    _              => AppColors.textMuted,
  };

  static String labelDe(String estado) => switch (estado.toUpperCase()) {
    'CONFIRMADO'   => 'Confirmado',
    'ESPERADO'     => 'Esperado',
    'VENCIDO'      => 'Vencido',
    'CANCELADO'    => 'Cancelado',
    'INGRESO'      => 'Ingreso',
    'EGRESO'       => 'Egreso',
    'ACTIVO'       => 'Activo',
    'INACTIVO'     => 'Inactivo',
    'PENDIENTE'    => 'Pendiente',
    'SINCRONIZADA' => 'Sincronizado',
    'ERROR'        => 'Error',
    _              => estado,
  };

  static String iconoDe(String tipo) => switch (tipo.toUpperCase()) {
    'INGRESO' => '↑',
    'EGRESO'  => '↓',
    _         => '·',
  };
}

// ─── THEME MATERIAL ───────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  /// Alias de compatibilidad para tests que usan AppTheme.useSystemFonts
  static bool get useSystemFonts => AppText.useSystemFonts;
  static set useSystemFonts(bool v) => AppText.useSystemFonts = v;

  // ─── DARK ───────────────────────────────────────────────────────────────────
  static ThemeData get dark {
    const c = AppColorScheme.dark;
    return _buildTheme(
      brightness: Brightness.dark,
      colors: c,
      baseSeed: ThemeData.dark(),
    );
  }

  // ─── LIGHT ──────────────────────────────────────────────────────────────────
  static ThemeData get light {
    const c = AppColorScheme.light;
    return _buildTheme(
      brightness: Brightness.light,
      colors: c,
      baseSeed: ThemeData.light(),
    );
  }

  // ─── Constructor compartido ─────────────────────────────────────────────────
  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppColorScheme colors,
    required ThemeData baseSeed,
  }) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.bgBase,

      extensions: [colors],

      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        surface:                   colors.bgSurface,
        onSurface:                 colors.textPrimary,
        primary:                   AppColors.accent,
        onPrimary:                 Colors.white,
        secondary:                 AppColors.accentLight,
        onSecondary:               isDark ? colors.bgBase : Colors.white,
        error:                     AppColors.egreso,
        onError:                   Colors.white,
        outline:                   colors.border,
        surfaceContainerHighest:   colors.bgElevated,
      ),

      textTheme: _buildTextTheme(baseSeed, colors),

      appBarTheme: AppBarTheme(
        backgroundColor: colors.bgSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.titleLg.copyWith(color: colors.textPrimary),
        iconTheme: IconThemeData(color: colors.textSecondary),
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: colors.border)),
      ),

      cardTheme: CardThemeData(
        color: colors.bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        margin: EdgeInsets.zero,
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: colors.bgSurface,
        scrimColor: colors.bgOverlay,
        elevation: 0,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? colors.bgBase : colors.bgElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 1,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.egreso),
        ),
        hintStyle: AppText.bodyMd.copyWith(color: colors.textDisabled),
        labelStyle: AppText.bodyMd.copyWith(color: colors.textMuted),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.bgElevated,
          disabledForegroundColor: colors.textDisabled,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: AppText.bodyMd.copyWith(fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textSecondary,
          side: BorderSide(color: colors.border),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: AppText.bodySm.copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.accentLight : AppColors.accent,
          textStyle: AppText.bodyMd,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: colors.border, thickness: 1, space: 0,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colors.bgElevated,
        selectedColor: AppColors.accent.withValues(alpha: 0.2),
        labelStyle: AppText.caption.copyWith(color: colors.textSecondary),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      ),

      dataTableTheme: DataTableThemeData(
        headingTextStyle: AppText.label.copyWith(color: colors.textMuted),
        dataTextStyle: AppText.bodyMd.copyWith(color: colors.textSecondary),
        headingRowColor: WidgetStateProperty.all(colors.bgSurface),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return colors.bgElevated.withValues(alpha: 0.5);
          }
          return Colors.transparent;
        }),
        dividerThickness: 1,
        columnSpacing: AppSpacing.lg,
        horizontalMargin: AppSpacing.lg,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colors.bgSurface,
        elevation: isDark ? 0 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: BorderSide(color: colors.border),
        ),
        titleTextStyle: AppText.titleMd.copyWith(color: colors.textPrimary),
        contentTextStyle: AppText.bodyMd.copyWith(color: colors.textSecondary),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? colors.bgElevated : colors.textPrimary,
        contentTextStyle: AppText.bodyMd.copyWith(
          color: isDark ? colors.textPrimary : colors.bgSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: isDark ? colors.border : Colors.transparent),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? Colors.white : colors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? AppColors.accent : colors.bgElevated;
        }),
        trackOutlineColor: WidgetStateProperty.all(colors.border),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? AppColors.accent : Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: BorderSide(color: colors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: AppColors.accent.withValues(alpha: 0.1),
        selectedColor: isDark ? AppColors.accentLight : AppColors.accent,
        textColor: colors.textSecondary,
        iconColor: colors.textMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs,
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: colors.bgSurface,
        elevation: isDark ? 0 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        textStyle: AppText.bodyMd.copyWith(color: colors.textSecondary),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: isDark ? AppColors.accentLight : AppColors.accent,
        unselectedLabelColor: colors.textMuted,
        labelStyle: AppText.bodyMd.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: AppText.bodyMd,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
        dividerColor: colors.border,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(colors.bgElevated),
        radius: const Radius.circular(3),
        thickness: WidgetStateProperty.all(5),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusXl)),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS:     CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme(ThemeData base, AppColorScheme colors) {
    final baseTextTheme = base.textTheme;
    final themed = AppText.useSystemFonts
        ? baseTextTheme
        : GoogleFonts.dmSansTextTheme(baseTextTheme);
    return themed.copyWith(
      displayLarge:  AppText.displayLg.copyWith(color: colors.textPrimary),
      displayMedium: AppText.displayMd.copyWith(color: colors.textPrimary),
      titleLarge:    AppText.titleLg.copyWith(color: colors.textPrimary),
      titleMedium:   AppText.titleMd.copyWith(color: colors.textPrimary),
      titleSmall:    AppText.titleSm.copyWith(color: colors.textPrimary),
      bodyLarge:     AppText.bodyLg.copyWith(color: colors.textSecondary),
      bodyMedium:    AppText.bodyMd.copyWith(color: colors.textSecondary),
      bodySmall:     AppText.bodySm.copyWith(color: colors.textMuted),
      labelSmall:    AppText.label.copyWith(color: colors.textMuted),
    );
  }

  /// Aplica escala de UI (density + iconos) al ThemeData existente.
  static ThemeData applyScale(ThemeData t, double scale) {
    if (scale == 1.0) return t;
    final density = ((scale - 1.0) * 2.0).clamp(-2.0, 2.0);
    final baseIconSize = t.iconTheme.size ?? 24.0;
    return t.copyWith(
      visualDensity: VisualDensity(horizontal: density, vertical: density),
      iconTheme: t.iconTheme.copyWith(size: baseIconSize * scale),
      primaryIconTheme: t.primaryIconTheme.copyWith(size: baseIconSize * scale),
      appBarTheme: t.appBarTheme.copyWith(
        iconTheme: (t.appBarTheme.iconTheme ?? t.iconTheme)
            .copyWith(size: baseIconSize * scale),
        actionsIconTheme: (t.appBarTheme.actionsIconTheme ?? t.iconTheme)
            .copyWith(size: baseIconSize * scale),
      ),
    );
  }
}

// ─── EXTENSIÓN DE CONTEXTO ────────────────────────────────────────────────────
extension AppThemeContext on BuildContext {
  ThemeData      get theme     => Theme.of(this);
  TextTheme      get tt        => Theme.of(this).textTheme;
  ColorScheme    get cs        => Theme.of(this).colorScheme;
  AppColorScheme get appColors => Theme.of(this).extension<AppColorScheme>()!;
}
