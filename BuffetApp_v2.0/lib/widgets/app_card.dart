import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Tarjeta base del Design System.
/// Fondo oscuro, border radius 12, sombra suave, borde sutil.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final double borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bgColor = color ?? c.bgSurface;

    final card = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: c.border),
        boxShadow: AppShadows.cardFor(context),
      ),
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: card,
      );
    }
    return card;
  }
}
