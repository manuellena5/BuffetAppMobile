import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/drawer_state.dart';
import '../state/app_mode.dart';

/// MenuItem para el CustomDrawer
class DrawerMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color? activeColor;

  const DrawerMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.activeColor,
  });
}

/// Drawer mejorado con soporte para:
/// - Modo fijo (siempre visible) o flotante (overlay)
/// - Modo expandido (con labels) o colapsado (solo iconos)
/// - Persistencia de preferencias
class CustomDrawer extends StatelessWidget {
  final String title;
  final List<DrawerMenuItem> items;
  final Widget? header;
  final Widget? footer;

  const CustomDrawer({
    super.key,
    required this.title,
    required this.items,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawerState>(
      builder: (context, drawerState, _) {
        final isExpanded = drawerState.isExpanded;
        final width = drawerState.drawerWidth;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: width,
          child: Drawer(
            child: Column(
              children: [
                // Header
                _buildHeader(context, drawerState, isExpanded),
                
                const Divider(height: 1),
                
                // Menu items
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: items.map((item) {
                      return _buildMenuItem(
                        context,
                        item,
                        isExpanded,
                      );
                    }).toList(),
                  ),
                ),
                
                // Footer (controles)
                if (footer != null) ...[
                  const Divider(height: 1),
                  footer!,
                ] else ...[
                  const Divider(height: 1),
                  _buildControls(context, drawerState, isExpanded),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, DrawerState drawerState, bool isExpanded) {
    if (header != null) return header!;

    final theme = Theme.of(context);
    final modeState = context.watch<AppModeState>();
    final modeIcon = modeState.isBuffetMode ? Icons.restaurant : Icons.account_balance;
    final modeLabel = modeState.isBuffetMode ? 'Buffet' : 'Tesorería';

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        bottom: 16,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: isExpanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo/Icono
          Icon(
            modeIcon,
            size: isExpanded ? 48 : 32,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          
          if (isExpanded) ...[
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  modeIcon,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Modo $modeLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, DrawerMenuItem item, bool isExpanded) {
    final theme = Theme.of(context);
    final activeColor = item.activeColor ?? theme.colorScheme.primary;
    
    if (!isExpanded) {
      // Modo colapsado: solo icono
      return Tooltip(
        message: item.label,
        child: InkWell(
          onTap: item.onTap,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: item.isActive
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: activeColor,
                        width: 4,
                      ),
                    ),
                  )
                : null,
            child: Icon(
              item.icon,
              color: item.isActive ? activeColor : theme.iconTheme.color,
            ),
          ),
        ),
      );
    }

    // Modo expandido: icono + label
    return ListTile(
      leading: Icon(
        item.icon,
        color: item.isActive ? activeColor : theme.iconTheme.color,
      ),
      title: Text(
        item.label,
        style: TextStyle(
          color: item.isActive ? activeColor : null,
          fontWeight: item.isActive ? FontWeight.bold : null,
        ),
      ),
      selected: item.isActive,
      selectedTileColor: activeColor.withOpacity(0.1),
      onTap: item.onTap,
    );
  }

  Widget _buildControls(BuildContext context, DrawerState drawerState, bool isExpanded) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botón expandir/colapsar
          Tooltip(
            message: isExpanded ? 'Colapsar menú' : 'Expandir menú',
            child: InkWell(
              onTap: drawerState.toggleExpanded,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isExpanded ? Icons.chevron_left : Icons.chevron_right,
                      color: theme.colorScheme.primary,
                    ),
                    if (isExpanded) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Colapsar',
                          style: TextStyle(color: theme.colorScheme.primary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 4),
          
          // Botón fijar/desfijar
          Tooltip(
            message: drawerState.isFixed ? 'Desfijar menú' : 'Fijar menú',
            child: InkWell(
              onTap: drawerState.toggleFixed,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      drawerState.isFixed ? Icons.push_pin : Icons.push_pin_outlined,
                      color: theme.colorScheme.secondary,
                    ),
                    if (isExpanded) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          drawerState.isFixed ? 'Desfijar' : 'Fijar',
                          style: TextStyle(color: theme.colorScheme.secondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
