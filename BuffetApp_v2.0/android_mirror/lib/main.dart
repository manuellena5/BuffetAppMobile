import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'ui/pages/pos_main_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/state/cart_model.dart';
import 'services/caja_service.dart';
import 'data/dao/db.dart';
import 'ui/state/app_settings.dart';
import 'services/usb_printer_service.dart';
import 'services/supabase_sync_service.dart';

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
          s.load();
          return s;
        }),
      ],
      child: Consumer<AppSettings>(
        builder: (_, settings, __) => MaterialApp(
          title: 'BuffetApp',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blueGrey,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: settings.materialThemeMode,
          home: const _SeedGate(),
        ),
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
              AppDatabase.logLocalError(scope: 'startup.timeout', error: 'Timeout esperando getCajaAbierta()', payload: {
                'elapsed_ms': DateTime.now().difference(started).inMilliseconds,
              });
              return null;
            });
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      if (elapsed > 1500) {
        AppDatabase.logLocalError(scope: 'startup.slow', error: 'getCajaAbierta lento', payload: {
          'elapsed_ms': elapsed,
        });
      }
      return r;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'startup.error', error: e, stackTrace: st);
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
                  const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  const Text('Error al iniciar'),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.redAccent),
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
        return caja == null ? const HomePage() : const PosMainPage();
      },
    );
  }
}
