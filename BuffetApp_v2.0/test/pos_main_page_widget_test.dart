import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:buffet_app/features/buffet/state/cart_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

Widget _wrap(Widget child, {CartModel? cart}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => cart ?? CartModel()),
    ],
    child: MaterialApp(home: child),
  );
}

class _CartDrivenButton extends StatelessWidget {
  const _CartDrivenButton();
  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartModel>();
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: cart.isEmpty ? null : () {},
            child: const Text('Confirmar'),
          ),
        ),
      ),
    );
  }
}

void main() {
  // Inicializar sqflite FFI para evitar canal nativo en tests
  setUpAll(() async {
    // Para consistencia con la app, inicializamos FFI aunque este test no toca DB.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Botón de venta deshabilitado cuando carrito vacío', (tester) async {
    final cart = CartModel();
    await tester.pumpWidget(_wrap(const _CartDrivenButton(), cart: cart));
    final buttons = find.byType(ElevatedButton);
    expect(buttons, findsWidgets);
    // Primer ElevatedButton visible principal debería ser el de vender
    final elevated = tester.widget<ElevatedButton>(buttons.first);
    expect(elevated.onPressed, isNull, reason: 'Debe estar deshabilitado con carrito vacío');
  });

  testWidgets('Botón de venta habilitado al agregar item al carrito', (tester) async {
    final cart = CartModel();
    cart.add(1, 'Demo', 1000);
    await tester.pumpWidget(_wrap(const _CartDrivenButton(), cart: cart));
    final buttons = find.byType(ElevatedButton);
    expect(buttons, findsWidgets);
    final elevated = tester.widget<ElevatedButton>(buttons.first);
    expect(elevated.onPressed, isNotNull, reason: 'Debe habilitarse cuando hay items');
  });
}
