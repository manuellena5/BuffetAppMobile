import 'package:flutter/material.dart';
import '../../data/dao/db.dart';
import 'package:sqflite/sqflite.dart';
import '../format.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final _cats = const [
    {'id': 1, 'descripcion': 'Comida'},
    {'id': 2, 'descripcion': 'Bebida'},
    {'id': 3, 'descripcion': 'Otros'},
  ];

  @override
  void initState() {
    super.initState();
    _ensureCategories().then((_) => _load());
  }

  Future<void> _ensureCategories() async {
    final db = await AppDatabase.instance();
    for (final c in _cats) {
      await db.insert('Categoria_Producto', c, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final r = await db.rawQuery('''
      SELECT p.id, p.codigo_producto, p.nombre, p.precio_venta, p.stock_actual, p.visible, p.categoria_id,
             COALESCE(c.descripcion,'') as categoria
      FROM products p
      LEFT JOIN Categoria_Producto c ON c.id = p.categoria_id
      ORDER BY p.id DESC
    ''');
    setState(() { _items = r; _loading = false; });
  }

  Future<void> _toggleVisible(int id, int current) async {
    final db = await AppDatabase.instance();
    final next = current == 1 ? 0 : 1;
    await db.update('products', {'visible': next}, where: 'id=?', whereArgs: [id]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Productos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async { final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const _ProductForm())); if (ok == true) _load(); },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final p = _items[i];
            final visible = ((p['visible'] as int?) ?? 1) == 1;
            return ListTile(
              title: Text(p['nombre'] as String),
              subtitle: Text('${p['categoria'] ?? ''} • ${formatCurrency(p['precio_venta'] as num)} • Stock: ${p['stock_actual']}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () async { final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => _ProductForm(data: p))); if (ok == true) _load(); }),
                IconButton(
                  tooltip: visible ? 'Ocultar' : 'Mostrar',
                  icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => _toggleVisible(p['id'] as int, visible ? 1 : 0),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _ProductForm extends StatefulWidget {
  final Map<String, dynamic>? data;
  const _ProductForm({this.data});
  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _codigo = TextEditingController();
  final _precio = TextEditingController();
  final _stock = TextEditingController(text: '999');
  int? _catId = 3; // Otros por defecto
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    if (d != null) {
      _nombre.text = (d['nombre'] as String?) ?? '';
  _codigo.text = (d['codigo_producto'] as String?) ?? '';
      _precio.text = '${d['precio_venta'] ?? ''}';
      _stock.text = '${d['stock_actual'] ?? '0'}';
      _catId = d['categoria_id'] as int? ?? 3;
      _visible = ((d['visible'] as int?) ?? 1) == 1;
    }
  }

  @override
  void dispose() {
    _nombre.dispose(); _codigo.dispose(); _precio.dispose(); _stock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final db = await AppDatabase.instance();
  final codigo = _codigo.text.trim().toUpperCase();
  final nombre = _nombre.text.trim();
    final precio = int.tryParse(_precio.text.trim()) ?? -1;
    final stock = int.tryParse(_stock.text.trim()) ?? -1;

    // Validaciones extra: precio/stock >= 0
    if (precio < 0) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Precio debe ser >= 0'))); return; }
    if (stock < 0) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock debe ser >= 0'))); return; }

    // Validación de código obligatorio, máx 4 y único
    if (codigo.isEmpty) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código es obligatorio'))); return; }
    if (codigo.length > 4) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código debe tener hasta 4 caracteres'))); return; }

    // Unicidad de código
  final argsCodigo = [codigo, if (widget.data != null) widget.data!['id']];
  final whereCodigo = widget.data == null ? 'UPPER(codigo_producto) = ?' : 'UPPER(codigo_producto) = ? AND id <> ?';
    final dupCode = await db.query('products', columns: ['id'], where: whereCodigo, whereArgs: argsCodigo);
    if (dupCode.isNotEmpty) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código ya existe en otro producto'))); return; }

    // Unicidad de nombre
  final argsNombre = [nombre, if (widget.data != null) widget.data!['id']];
  final whereNombre = widget.data == null ? 'UPPER(nombre) = UPPER(?)' : 'UPPER(nombre) = UPPER(?) AND id <> ?';
    final dupName = await db.query('products', columns: ['id'], where: whereNombre, whereArgs: argsNombre);
    if (dupName.isNotEmpty) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre de producto ya existente'))); return; }

    final payload = {
      'codigo_producto': codigo,
      'nombre': _nombre.text.trim(),
      'precio_venta': precio,
      'stock_actual': stock,
      'stock_minimo': 3,
      'categoria_id': _catId,
      'visible': _visible ? 1 : 0,
      'color': null,
    };
    if (widget.data == null) {
      // create
      await db.insert('products', payload);
    } else {
      // update
      await db.update('products', payload, where: 'id=?', whereArgs: [widget.data!['id']]);
    }
    if (context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.data == null ? 'Nuevo producto' : 'Editar producto')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: ListView(
            children: [
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => (v==null||v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _codigo,
                decoration: const InputDecoration(labelText: 'Código (máx 4, obligatorio)'),
                maxLength: 4,
                validator: (v) {
                  final t = (v??'').trim();
                  if (t.isEmpty) return 'Requerido';
                  if (t.length > 4) return 'Máx 4 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _precio,
                decoration: const InputDecoration(labelText: 'Precio de venta'),
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v??'')==null) ? 'Ingrese un número' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _stock,
                decoration: const InputDecoration(labelText: 'Stock actual (use 999 para ilimitado)'),
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v??'')==null) ? 'Ingrese un número' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _catId,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Comida')),
                  DropdownMenuItem(value: 2, child: Text('Bebida')),
                  DropdownMenuItem(value: 3, child: Text('Otros')),
                ],
                onChanged: (v) => setState(() => _catId = v),
                decoration: const InputDecoration(labelText: 'Categoría'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _visible,
                onChanged: (v) => setState(() => _visible = v),
                title: const Text('Visible en POS'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _save, child: Text(widget.data == null ? 'Crear' : 'Guardar')),
            ],
          ),
        ),
      ),
    );
  }
}
