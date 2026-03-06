import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';

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
    final (bgColor, fgColor) = _colors();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  (Color bg, Color fg) _colors() {
    return switch (type) {
      StatusType.success => (AppColors.successLight, AppColors.success),
      StatusType.warning => (AppColors.warningLight, AppColors.warning),
      StatusType.danger => (AppColors.dangerLight, AppColors.danger),
      StatusType.info => (AppColors.infoLight, AppColors.info),
      StatusType.neutral => (const Color(0xFFF3F4F6), const Color(0xFF6B7280)),
    };
  }
}
