import 'package:flutter/material.dart';

/// Item individual del breadcrumb
class BreadcrumbItem {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  BreadcrumbItem({
    required this.label,
    this.onTap,
    this.icon,
  });
}

/// Widget de breadcrumb para navegación jerárquica
/// 
/// Ejemplo de uso:
/// ```dart
/// Breadcrumb(
///   items: [
///     BreadcrumbItem(label: 'Inicio', onTap: () => Navigator.pop(context)),
///     BreadcrumbItem(label: 'Plantel', onTap: () => Navigator.pop(context)),
///     BreadcrumbItem(label: 'Juan Pérez'), // Actual (no clickeable)
///   ],
/// )
/// ```
class Breadcrumb extends StatelessWidget {
  final List<BreadcrumbItem> items;
  final double fontSize;
  final Color? activeColor;
  final Color? inactiveColor;
  final double spacing;

  const Breadcrumb({
    super.key,
    required this.items,
    this.fontSize = 14,
    this.activeColor,
    this.inactiveColor,
    this.spacing = 4,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultActiveColor = activeColor ?? theme.colorScheme.onSurface;
    final defaultInactiveColor =
        inactiveColor ?? theme.colorScheme.onSurface.withOpacity(0.6);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing),
                child: Icon(
                  Icons.chevron_right,
                  size: fontSize + 2,
                  color: defaultInactiveColor,
                ),
              ),
            _buildItem(
              context,
              items[i],
              isLast: i == items.length - 1,
              activeColor: defaultActiveColor,
              inactiveColor: defaultInactiveColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    BreadcrumbItem item, {
    required bool isLast,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final color = isLast ? activeColor : inactiveColor;
    final fontWeight = isLast ? FontWeight.w600 : FontWeight.normal;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.icon != null) ...[
          Icon(item.icon, size: fontSize, color: color),
          SizedBox(width: spacing),
        ],
        Text(
          item.label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          ),
        ),
      ],
    );

    // Si es el último item o no tiene onTap, no es clickeable
    if (isLast || item.onTap == null) {
      return content;
    }

    // Item clickeable
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: content,
      ),
    );
  }
}

/// Widget compacto de breadcrumb para AppBar
/// Muestra solo los últimos N items para ahorrar espacio
class AppBarBreadcrumb extends StatelessWidget {
  final List<BreadcrumbItem> items;
  final int maxVisible;

  const AppBarBreadcrumb({
    super.key,
    required this.items,
    this.maxVisible = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    // Si hay más items que maxVisible, mostrar "..." al inicio
    final visibleItems = items.length > maxVisible
        ? [
            BreadcrumbItem(label: '...', icon: Icons.more_horiz),
            ...items.sublist(items.length - maxVisible),
          ]
        : items;

    return Breadcrumb(
      items: visibleItems,
      fontSize: 16,
      activeColor: Colors.white,
      inactiveColor: Colors.white.withOpacity(0.85), // Más contraste
    );
  }
}
