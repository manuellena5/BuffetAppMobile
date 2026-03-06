import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/theme/app_spacing.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: AppSpacing.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.screenTitle(
                    color: isDark ? AppColors.textPrimaryDark : null,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTextStyles.caption(),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            ...trailing!.map((w) => Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: w,
                )),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.base),
            action!,
          ],
        ],
      ),
    );
  }
}
