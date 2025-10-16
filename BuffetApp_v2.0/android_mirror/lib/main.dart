import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'services/seed_service.dart';
import 'ui/pages/pos_main_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/state/cart_model.dart';
import 'services/caja_service.dart';
import 'ui/state/app_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_AR', null);
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

class _SeedGate extends StatelessWidget {
  const _SeedGate();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SeedService().ensureSeedData(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return FutureBuilder(
          future: CajaService().getCajaAbierta(),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            final caja = snap.data;
            if (caja == null) {
              return const HomePage();
            }
            return const PosMainPage();
          },
        );
      },
    );
  }
}
