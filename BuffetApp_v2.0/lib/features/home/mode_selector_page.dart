import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/state/app_mode.dart';
import '../buffet/pages/buffet_home_page.dart';
import '../tesoreria/pages/tesoreria_home_page.dart';
import 'home_page.dart';
import '../buffet/services/caja_service.dart';
import '../../app_version.dart';

/// Pantalla de selección de modo (Buffet / Tesorería)
/// Se muestra solo cuando no hay un modo activo seleccionado
/// o cuando el usuario quiere cambiar de modo explícitamente
class ModeSelectorPage extends StatefulWidget {
  const ModeSelectorPage({super.key});

  @override
  State<ModeSelectorPage> createState() => _ModeSelectorPageState();
}

class _ModeSelectorPageState extends State<ModeSelectorPage> {
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = AppBuildInfo.version;
    if (mounted) {
      setState(() => _appVersion = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.1),
              cs.secondary.withOpacity(0.05),
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo o título de la app
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    size: 80,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'BuffetApp',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (_appVersion != null)
                  Text(
                    'v$_appVersion',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.4),
                    ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 16),
                Text(
                  'Selecciona un módulo para comenzar',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // Botón Buffet
                _ModeCard(
                  icon: Icons.store,
                  title: 'Buffet',
                  subtitle: 'Ventas y caja del partido',
                  description: 'Gestiona el buffet durante eventos deportivos',
                  color: Colors.blue,
                  onTap: () => _selectMode(context, AppMode.buffet),
                ),
                
                const SizedBox(height: 20),
                
                // Botón Tesorería
                _ModeCard(
                  icon: Icons.account_balance,
                  title: 'Tesorería',
                  subtitle: 'Movimientos financieros',
                  description: 'Registra ingresos y egresos de la subcomisión',
                  color: Colors.green,
                  onTap: () => _selectMode(context, AppMode.tesoreria),
                ),
                
                const Spacer(),
                
                // Info adicional
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Podés cambiar de módulo desde Configuración',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectMode(BuildContext context, AppMode mode) async {
    final modeState = context.read<AppModeState>();
    await modeState.setMode(mode);
    
    if (!context.mounted) return;
    
    // Para Buffet, verificar si hay caja abierta
    Widget destination;
    if (mode == AppMode.buffet) {
      // Verificar si hay caja abierta
      final caja = await CajaService().getCajaAbierta();
      if (caja != null) {
        // Si hay caja abierta, ir directo a BuffetHomePage
        destination = const BuffetHomePage();
      } else {
        // Sin caja abierta, ir a HomePage (pantalla de inicio de buffet)
        destination = const HomePage();
      }
    } else {
      destination = const TesoreriaHomePage();
    }
    
    if (!context.mounted) return;
    
    // Navegar reemplazando toda la pila
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }
}

/// Card individual para cada modo
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 8,
      shadowColor: color.withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: color.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.05),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: color.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: color,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: color,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
