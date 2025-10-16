import 'package:flutter/foundation.dart';

class CartItem {
  final int productoId;
  final String nombre;
  final double precioUnitario;
  int cantidad;
  CartItem(
      {required this.productoId,
      required this.nombre,
      required this.precioUnitario,
      this.cantidad = 1});
  double get subtotal => precioUnitario * cantidad;
}

class CartModel extends ChangeNotifier {
  final List<CartItem> _items = [];
  List<CartItem> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (acc, it) => acc + it.cantidad);
  double get total => _items.fold(0.0, (acc, it) => acc + it.subtotal);
  bool get isEmpty => _items.isEmpty;

  void add(int id, String nombre, double precio) {
    final idx = _items.indexWhere((e) => e.productoId == id);
    if (idx >= 0) {
      _items[idx].cantidad += 1;
    } else {
      _items.add(
          CartItem(productoId: id, nombre: nombre, precioUnitario: precio));
    }
    notifyListeners();
  }

  void inc(int id) {
    final idx = _items.indexWhere((e) => e.productoId == id);
    if (idx >= 0) {
      _items[idx].cantidad += 1;
      notifyListeners();
    }
  }

  void dec(int id) {
    final idx = _items.indexWhere((e) => e.productoId == id);
    if (idx >= 0) {
      _items[idx].cantidad -= 1;
      if (_items[idx].cantidad <= 0) _items.removeAt(idx);
      notifyListeners();
    }
  }

  void remove(int id) {
    _items.removeWhere((e) => e.productoId == id);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
