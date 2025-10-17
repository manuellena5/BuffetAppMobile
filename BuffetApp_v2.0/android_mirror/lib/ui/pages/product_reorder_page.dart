import 'package:flutter/material.dart';
import '../../data/dao/db.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductReorderPage extends StatefulWidget {
  const ProductReorderPage({super.key});
  @override
  State<ProductReorderPage> createState() => _ProductReorderPageState();
}

class _ProductReorderPageState extends State<ProductReorderPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
    _maybeShowHint();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final rows = await db.rawQuery(
      'SELECT id, nombre, orden_visual FROM products WHERE visible=1 ORDER BY orden_visual ASC, id ASC',
    );
    setState(() {
      _items = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      _loading = false;
      _dirty = false;
    });
  }

  Future<void> _maybeShowHint() async {
    try {
      final sp = await SharedPreferences.getInstance();
      const key = 'reorder_hint_shown';
      final shown = sp.getBool(key) ?? false;
      if (!shown && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cómo ordenar'),
            content: const Text('Mantené presionado un producto y arrastralo para cambiar el orden. Luego tocá "Guardar" para aplicar.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
            ],
          ),
        );
        await sp.setBool(key, true);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final db = await AppDatabase.instance();
    // Guardar nuevos valores de orden_visual según la posición (1..n)
    for (var i = 0; i < _items.length; i++) {
      final id = _items[i]['id'] as int;
      final orden = i + 1;
      await db.update('products', {'orden_visual': orden}, where: 'id=?', whereArgs: [id]);
    }
    setState(() => _dirty = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orden guardado')));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordenar productos'),
        actions: [
          if (_dirty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: const StadiumBorder(),
                ),
                onPressed: _save,
                child: const Text('Guardar'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final p in _items)
                  ListTile(
                    key: ValueKey('p_${p['id']}'),
                    title: Text(p['nombre'] as String),
                    leading: const Icon(Icons.drag_indicator),
                    trailing: Text('#${(_items.indexOf(p) + 1)}'),
                  ),
              ],
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _items.removeAt(oldIndex);
                  _items.insert(newIndex, item);
                  _dirty = true;
                });
              },
            ),
    );
  }
}
