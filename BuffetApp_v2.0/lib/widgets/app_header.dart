import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Header de pantalla estilo ERP.
/// Título grande + botón de acción principal opcional.
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final List<Widget>? trailing;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      height: AppSpacing.topbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      decoration: BoxDecoration(
        color: c.bgSurface,
        border: Border(
          bottom: BorderSide(color: c.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.displayMd),
                if (subtitle != null)
                  Text(subtitle!, style: AppText.caption),
              ],
            ),
          ),
          if (trailing != null)
            ...trailing!.map((w) => Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: w,
                )),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
