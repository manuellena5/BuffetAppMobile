import 'package:flutter_test/flutter_test.dart';
import 'package:buffet_mirror/ui/state/cart_model.dart';

void main() {
  group('CartModel', () {
    test('nuevo carrito inicia vacío', () {
      final cart = CartModel();
      expect(cart.isEmpty, isTrue);
      expect(cart.count, 0);
      expect(cart.total, 0);
    });

    test('agregar incrementa cantidad y total', () {
      final cart = CartModel();
      cart.add(1, 'Producto', 1000);
      cart.add(1, 'Producto', 1000); // mismo id -> suma cantidad
      expect(cart.items.length, 1);
      expect(cart.count, 2);
      expect(cart.total, 2000);
    });

    test('inc y dec funcionan y eliminan en cero', () {
      final cart = CartModel();
      cart.add(10, 'Item', 500);
      cart.inc(10);
      expect(cart.count, 2);
      cart.dec(10); // vuelve a 1
      expect(cart.count, 1);
      cart.dec(10); // llega a 0 -> se elimina
      expect(cart.isEmpty, isTrue);
    });

    test('clear vacía carrito', () {
      final cart = CartModel();
      cart.add(2, 'X', 10);
      cart.clear();
      expect(cart.count, 0);
      expect(cart.items, isEmpty);
    });
  });
}
