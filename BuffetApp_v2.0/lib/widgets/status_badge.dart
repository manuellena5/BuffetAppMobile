import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Tipo de estado para el badge.
enum StatusType { success, warning, danger, info, neutral }

/// Badge de estado reutilizable estilo ERP.
/// Muestra un label con color de fondo según el tipo de estado.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusType type;
  final IconData? icon;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.label,
    required this.type,
    this.icon,
    this.fontSize = 12,
  });

  /// Helpers rápidos para estados financieros comunes.
  const StatusBadge.pagado({super.key, this.icon})
      : label = 'PAGADO',
        type = StatusType.success,
        fontSize = 12;

  const StatusBadge.pendiente({super.key, this.icon})
      : label = 'PENDIENTE',
        type = StatusType.info,
        fontSize = 12;

  const StatusBadge.vencido({super.key, this.icon})
      : label = 'VENCIDO',
        type = StatusType.danger,
        fontSize = 12;

  const StatusBadge.proximo({super.key, this.icon})
      : label = 'PRÓXIMO',
        type = StatusType.warning,
        fontSize = 12;

  @override
  Widget build(BuildContext context) {
    final (bgColor, fgColor) = _colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: AppDecorations.badgeFor(fgColor),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppText.label.copyWith(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  (Color bg, Color fg) _colorsOf(BuildContext context) {
    final c = context.appColors;
    return switch (type) {
      StatusType.success => (c.ingresoDim, AppColors.ingreso),
      StatusType.warning => (c.advertenciaDim, AppColors.advertencia),
      StatusType.danger => (c.egresoDim, AppColors.egreso),
      StatusType.info => (c.infoDim, AppColors.info),
      StatusType.neutral => (c.bgElevated, c.textMuted),
    };
  }
}
