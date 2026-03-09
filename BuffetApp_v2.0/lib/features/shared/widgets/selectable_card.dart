import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Tarjeta seleccionable estilo Enterprise (Dynamics 365 / SAP).
///
/// Reemplaza RadioButtons / ListTiles básicos con tarjetas visualmente
/// claras y táctiles. Ideal para selecciones de tipo, modalidad, etc.
///
/// Uso:
/// ```dart
/// SelectableCard<String>(
///   value: 'EGRESO',
///   groupValue: _tipo,
///   onChanged: (v) => setState(() => _tipo = v),
///   icon: Icons.trending_down,
///   iconColor: Colors.red,
///   title: 'Egreso',
///   subtitle: 'Sueldos, viáticos, premios',
/// )
/// ```
class SelectableCard<T> extends StatelessWidget {
  /// Valor que representa esta opción
  final T value;

  /// Valor actualmente seleccionado del grupo
  final T groupValue;

  /// Callback al seleccionar
  final ValueChanged<T> onChanged;

  /// Icono principal (opcional)
  final IconData? icon;

  /// Color del icono (se usa color primario por defecto)
  final Color? iconColor;

  /// Título de la opción
  final String title;

  /// Descripción breve
  final String? subtitle;

  /// Widget adicional a mostrar debajo del subtítulo cuando está seleccionado
  final Widget? expandedContent;

  const SelectableCard({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.expandedContent,
  });

  bool get _isSelected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isSelected
                  ? primary.withValues(alpha: 0.06)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isSelected ? primary : context.appColors.border,
                width: _isSelected ? 2 : 1,
              ),
              boxShadow: _isSelected
                  ? [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Icono
                if (icon != null) ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isSelected
                          ? (iconColor ?? primary).withValues(alpha: 0.12)
                          : context.appColors.bgElevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: _isSelected
                          ? (iconColor ?? primary)
                          : context.appColors.textMuted,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],

                // Textos
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              _isSelected ? FontWeight.bold : FontWeight.w500,
                          color: _isSelected
                              ? theme.colorScheme.onSurface
                              : context.appColors.textSecondary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.appColors.textMuted,
                          ),
                        ),
                      ],
                      if (_isSelected && expandedContent != null) ...[
                        const SizedBox(height: 8),
                        expandedContent!,
                      ],
                    ],
                  ),
                ),

                // Check indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _isSelected ? primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isSelected ? primary : context.appColors.textMuted,
                      width: _isSelected ? 0 : 2,
                    ),
                  ),
                  child: _isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
