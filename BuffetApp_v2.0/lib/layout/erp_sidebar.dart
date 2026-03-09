import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Item de menú del sidebar ERP.
class ErpMenuItem {
  final IconData icon;
  final String label;
  final String routeName;
  final VoidCallback onTap;

  const ErpMenuItem({
    required this.icon,
    required this.label,
    required this.routeName,
    required this.onTap,
  });
}

/// Grupo de items con un título de sección opcional.
class ErpMenuSection {
  final String? title;
  final List<ErpMenuItem> items;

  const ErpMenuSection({this.title, required this.items});
}

/// Sidebar ERP moderno.
///
/// - Expandido: 240px con icono + texto.
/// - Colapsado: 72px solo iconos.
/// - Fondo oscuro (#111827), hover y selección con colores del design system.
/// - Soporta light/dark sin cambiar — el sidebar siempre es oscuro.
class ErpSidebar extends StatefulWidget {
  final List<ErpMenuSection> sections;
  final String? currentRoute;
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;
  final Widget? header;
  final Widget? footer;

  const ErpSidebar({
    super.key,
    required this.sections,
    this.currentRoute,
    this.isExpanded = true,
    this.onToggleExpanded,
    this.header,
    this.footer,
  });

  @override
  State<ErpSidebar> createState() => _ErpSidebarState();
}

class _ErpSidebarState extends State<ErpSidebar> {
  String? _hoveredRoute;

  double get _width => widget.isExpanded
      ? AppSpacing.sidebarWidth
      : 72;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: _width,
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
      ),
      child: Column(
        children: [
          // Header
          widget.header ?? _buildDefaultHeader(),
          const SizedBox(height: AppSpacing.sm),

          // Menu items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              children: _buildSections(),
            ),
          ),

          // Footer / toggle
          widget.footer ?? _buildToggle(),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }

  Widget _buildDefaultHeader() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + AppSpacing.lg,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(Icons.account_balance, color: Colors.white, size: 20),
          ),
          if (widget.isExpanded) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'CDM Gestión',
                style: AppText.titleLg.copyWith(color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildSections() {
    final widgets = <Widget>[];
    for (final section in widget.sections) {
      // Título de sección
      if (section.title != null && widget.isExpanded) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              top: AppSpacing.lg,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              section.title!.toUpperCase(),
              style: AppText.label.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),
        );
      } else if (section.title != null && !widget.isExpanded) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Divider(color: AppColors.bgElevated, height: 1),
          ),
        );
      }

      for (final item in section.items) {
        widgets.add(_buildItem(item));
      }
    }
    return widgets;
  }

  Widget _buildItem(ErpMenuItem item) {
    final isSelected = item.routeName == widget.currentRoute;
    final isHovered = item.routeName == _hoveredRoute;

    Color bgColor;
    Color iconColor;
    Color textColor;

    if (isSelected) {
      bgColor = AppColors.accent;
      iconColor = AppColors.textPrimary;
      textColor = AppColors.textPrimary;
    } else if (isHovered) {
      bgColor = AppColors.bgElevated;
      iconColor = AppColors.textPrimary;
      textColor = AppColors.textPrimary;
    } else {
      bgColor = Colors.transparent;
      iconColor = AppColors.textSecondary;
      textColor = AppColors.textSecondary;
    }

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 44,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: widget.isExpanded ? AppSpacing.md : 0,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: widget.isExpanded
          ? Row(
              children: [
                Icon(item.icon, size: 20, color: iconColor),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    item.label,
                    style: AppText.bodyMd.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : Center(
              child: Icon(item.icon, size: 20, color: iconColor),
            ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRoute = item.routeName),
      onExit: (_) => setState(() => _hoveredRoute = null),
      child: GestureDetector(
        onTap: item.onTap,
        child: widget.isExpanded
            ? content
            : Tooltip(
                message: item.label,
                child: content,
              ),
      ),
    );
  }

  Widget _buildToggle() {
    if (widget.onToggleExpanded == null) return const SizedBox.shrink();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onToggleExpanded,
        child: Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            mainAxisAlignment:
                widget.isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              if (widget.isExpanded) const SizedBox(width: AppSpacing.md),
              Icon(
                widget.isExpanded ? Icons.chevron_left : Icons.chevron_right,
                size: 20,
                color: AppColors.textMuted,
              ),
              if (widget.isExpanded) ...[
                const SizedBox(width: AppSpacing.md),
                Text(
                  'Colapsar',
                  style: AppText.bodySm.copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
