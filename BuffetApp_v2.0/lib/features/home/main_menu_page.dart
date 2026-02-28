import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/state/app_mode.dart';
import '../shared/state/app_settings.dart';
import '../shared/pages/update_page.dart';
import '../buffet/pages/buffet_home_page.dart';
import '../tesoreria/pages/tesoreria_home_page.dart';
import '../tesoreria/pages/unidad_gestion_selector_page.dart';
import 'home_page.dart';
import '../../app_version.dart';

/// Menú principal de la app. Siempre es la primera pantalla al abrir.
/// Permite elegir entre los módulos Buffet y Tesorería.
class MainMenuPage extends StatefulWidget {
  /// Si hay una caja buffet abierta, se muestra badge en la tarjeta.
  final bool hasCajaAbierta;

  const MainMenuPage({super.key, this.hasCajaAbierta = false});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _appVersion = AppBuildInfo.version;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.primary.withValues(alpha: 0.08),
              cs.surface,
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo de la app
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.primary.withValues(alpha: 0.18),
                            cs.secondary.withValues(alpha: 0.10),
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.sports_soccer,
                        size: 72,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'BuffetApp',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                    if (_appVersion != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'v$_appVersion',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => const UpdatePage()),
                                          );
                                        },
                                        child: const Text('Buscar actualizaciones'),
                                      ),
                                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Seleccioná un módulo para comenzar',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    // ── Tarjeta Buffet ──
                    _ModuleCard(
                      icon: Icons.restaurant_menu,
                      title: 'Buffet',
                      subtitle: 'Ventas y caja del partido',
                      description:
                          'Gestión de ventas, caja, tickets e impresión',
                      color: Colors.orange.shade700,
                      badgeText:
                          widget.hasCajaAbierta ? 'Caja abierta' : null,
                      onTap: () => _goToBuffet(context),
                    ),

                    // ── Tarjeta Tesorería (solo Windows/desktop) ──
                    if (!Platform.isAndroid) ...[
                      const SizedBox(height: 20),
                      _ModuleCard(
                        icon: Icons.account_balance_wallet,
                        title: 'Tesorería',
                        subtitle: 'Movimientos financieros',
                        description:
                            'Ingresos, egresos, compromisos y reportes',
                        color: Colors.teal.shade700,
                        onTap: () => _goToTesoreria(context),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Nota al pie
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline,
                            size: 14,
                            color: cs.onSurface.withValues(alpha: 0.4)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Podés volver acá desde el menú lateral',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────── Navegación ───────────────

  void _goToBuffet(BuildContext context) {
    final modeState = context.read<AppModeState>();
    modeState.setMode(AppMode.buffet);

    final Widget destination;
    if (widget.hasCajaAbierta) {
      destination = const BuffetHomePage();
    } else {
      destination = const HomePage();
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  Future<void> _goToTesoreria(BuildContext context) async {
    final modeState = context.read<AppModeState>();
    await modeState.setMode(AppMode.tesoreria);

    if (!context.mounted) return;

    final settings = context.read<AppSettings>();
    await settings.ensureLoaded();

    if (!context.mounted) return;

    final Widget destination;
    if (!settings.isUnidadGestionConfigured) {
      destination = UnidadGestionSelectorPage(
        isInitialFlow: true,
        onComplete: () {
          if (!context.mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TesoreriaHomePage()),
            (route) => false,
          );
        },
      );
    } else {
      destination = const TesoreriaHomePage();
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }
}

// ══════════════════════════════════════════════
// Widget privado: tarjeta de módulo
// ══════════════════════════════════════════════

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final Color color;
  final String? badgeText;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.color,
    this.badgeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 6,
      shadowColor: color.withValues(alpha: 0.30),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // ── Ícono grande ──
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(width: 16),

              // ── Texto ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badgeText!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),

              Icon(Icons.chevron_right,
                  color: color.withValues(alpha: 0.6), size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
