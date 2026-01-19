import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'features/buffet/pages/buffet_home_page.dart';
import 'features/home/home_page.dart';
import 'features/home/mode_selector_page.dart';
import 'features/tesoreria/pages/tesoreria_home_page.dart';
import 'features/buffet/state/cart_model.dart';
import 'features/buffet/services/caja_service.dart';
import 'data/dao/db.dart';
import 'features/shared/state/app_settings.dart';
import 'features/shared/state/app_mode.dart';
import 'features/shared/services/usb_printer_service.dart';
import 'features/shared/services/supabase_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_AR', null);
  // Supabase init (sin auth, anon)
  await SupaSyncService.init();
  // Autoconectar impresora térmica USB si hay una guardada
  try {
    await UsbPrinterService().autoConnectSaved();
  } catch (_) {}
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartModel()),
        ChangeNotifierProvider(create: (_) {
          final s = AppSettings();
          s.ensureLoaded();
          return s;
        }),
        ChangeNotifierProvider(create: (_) {
          final m = AppModeState();
          m.loadMode();
          return m;
        }),
      ],
      child: Consumer<AppSettings>(
        builder: (_, settings, __) {
          final scale = settings.uiScale <= 0 ? 1.0 : settings.uiScale;
          // VisualDensity: valores negativos compactan, positivos expanden.
          // Queremos que scale<1 compacte un poco, y scale>1 expanda un poco.
          final density = ((scale - 1.0) * 2.0).clamp(-2.0, 2.0);

          final baseTheme = ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
            useMaterial3: true,
          );
          final baseDarkTheme = ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blueGrey,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          );

          ThemeData applyScale(ThemeData t) {
            final baseIconSize = t.iconTheme.size ?? 24.0;
            return t.copyWith(
              visualDensity:
                  VisualDensity(horizontal: density, vertical: density),
              iconTheme: t.iconTheme.copyWith(size: baseIconSize * scale),
              primaryIconTheme:
                  t.primaryIconTheme.copyWith(size: baseIconSize * scale),
              appBarTheme: t.appBarTheme.copyWith(
                iconTheme: (t.appBarTheme.iconTheme ?? t.iconTheme)
                    .copyWith(size: baseIconSize * scale),
                actionsIconTheme:
                    (t.appBarTheme.actionsIconTheme ?? t.iconTheme)
                        .copyWith(size: baseIconSize * scale),
              ),
            );
          }

          return MaterialApp(
            title: 'BuffetApp',
            theme: applyScale(baseTheme),
            darkTheme: applyScale(baseDarkTheme),
            themeMode: settings.materialThemeMode,
            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();
              final mq = MediaQuery.of(context);
              // Escala de texto global sin achicar el canvas (evita márgenes negros).
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child,
              );
            },
            home: const _SeedGate(),
          );
        },
      ),
    );
  }
}

class _SeedGate extends StatefulWidget {
  const _SeedGate();
  @override
  State<_SeedGate> createState() => _SeedGateState();
}

class _SeedGateState extends State<_SeedGate> {
  late final Future<dynamic> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<dynamic> _load() async {
    // Solo verificar si hay caja abierta (para ir directo a Buffet)
    // NO validar punto de venta aquí - cada módulo valida sus propios requisitos
    final isTest = Platform.environment['FLUTTER_TEST'] == 'true';
    // En tests NO usamos timeout para evitar timers pendientes
    final timeout = isTest ? null : const Duration(seconds: 8);
    final started = DateTime.now();
    try {
      final Future<dynamic> f = CajaService().getCajaAbierta();
      final r = timeout == null
          ? await f
          : await f.timeout(timeout, onTimeout: () {
              // Log timeout y continuar como si no hubiera caja abierta
              AppDatabase.logLocalError(
                  scope: 'startup.timeout',
                  error: 'Timeout esperando getCajaAbierta()',
                  payload: {
                    'elapsed_ms':
                        DateTime.now().difference(started).inMilliseconds,
                  });
              return null;
            });
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      if (elapsed > 1500) {
        AppDatabase.logLocalError(
            scope: 'startup.slow',
            error: 'getCajaAbierta lento',
            payload: {
              'elapsed_ms': elapsed,
            });
      }
      return r;
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'startup.error', error: e, stackTrace: st);
      return null; // fallback a HomePage
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Inicializando base de datos...'),
                ],
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  const Text('Error al iniciar'),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.redAccent),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // Forzar continuar aunque haya error
                      Navigator.of(ctx).pushReplacement(
                        MaterialPageRoute(builder: (_) => const HomePage()),
                      );
                    },
                    child: const Text('Continuar'),
                  )
                ],
              ),
            ),
          );
        }
        final caja = snap.data;
        
        // Determinar pantalla inicial según modo y estado de caja
        return Consumer<AppModeState>(
          builder: (context, modeState, _) {
            // Si no se ha cargado el modo, mostrar loading
            if (!modeState.isLoaded) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            
            // Si hay caja abierta, ir directo a Buffet (modo caja)
            if (caja != null) {
              return const BuffetHomePage();
            }
            
            // Sin caja abierta: verificar si hay modo configurado
            // Si es la primera vez (no hay modo configurado), mostrar selector
            if (!modeState.hasConfiguredMode) {
              return const ModeSelectorPage();
            }
            
            // Si ya hay modo configurado, ir según el modo seleccionado
            if (modeState.isBuffetMode) {
              return const HomePage(); // Home de buffet (antigua)
            } else {
              return const TesoreriaHomePage();
            }
          },
        );
      },
    );
  }
}
