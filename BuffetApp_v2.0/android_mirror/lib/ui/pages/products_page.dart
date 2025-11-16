import 'package:flutter/material.dart';
import '../../data/dao/db.dart';
import 'package:sqflite/sqflite.dart';
import '../format.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'product_reorder_page.dart';

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
      await db.insert('Categoria_Producto', c,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final r = await db.rawQuery('''
      SELECT p.id, p.codigo_producto, p.nombre, p.precio_venta, p.stock_actual, p.visible, p.categoria_id,
             p.imagen, p.precio_compra,
             COALESCE(c.descripcion,'') as categoria
      FROM products p
      LEFT JOIN Categoria_Producto c ON c.id = p.categoria_id
      ORDER BY p.orden_visual ASC
    ''');
    setState(() {
      _items = r;
      _loading = false;
    });
  }

  Future<void> _toggleVisible(int id, int current) async {
    final db = await AppDatabase.instance();
    final next = current == 1 ? 0 : 1;
    await db.update('products', {'visible': next},
        where: 'id=?', whereArgs: [id]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'reorder') {
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductReorderPage()),
                );
                if (changed == true && mounted) {
                  await _load();
                }
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'reorder', child: Text('Ordenar productos')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final ok = await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const _ProductForm()));
          if (ok == true) _load();
        },
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
              leading: _buildLeadingImage(p['imagen'] as String?),
              title: Text(p['nombre'] as String),
              subtitle: Text(
                  '${p['categoria'] ?? ''} • ${formatCurrencyNoDecimals(p['precio_venta'] as num)} • Stock: ${p['stock_actual']}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final ok = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => _ProductForm(data: p)));
                      if (ok == true) _load();
                    }),
                IconButton(
                  tooltip: visible ? 'Ocultar' : 'Mostrar',
                  icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
                  onPressed: () =>
                      _toggleVisible(p['id'] as int, visible ? 1 : 0),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

Widget _buildLeadingImage(String? imgPath) {
  if (imgPath == null || imgPath.isEmpty) {
    return const CircleAvatar(
        backgroundColor: Colors.grey, child: Icon(Icons.image, color: Colors.white));
  }
  final file = File(imgPath);
  if (!file.existsSync()) {
    return const CircleAvatar(
        backgroundColor: Colors.grey, child: Icon(Icons.image, color: Colors.white));
  }
  return CircleAvatar(backgroundImage: FileImage(file));
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
  final _precioCompra = TextEditingController();
  final _porcGanancia = TextEditingController();
  final _stock = TextEditingController(text: '999');
  bool _contabilizaStock = false;
  int? _catId = 3; // Otros por defecto
  bool _visible = true;
  String? _imagenPath; // ruta local a la imagen
  bool _updatingFields = false; // evita bucles entre listeners

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    if (d != null) {
      _nombre.text = (d['nombre'] as String?) ?? '';
      _codigo.text = (d['codigo_producto'] as String?) ?? '';
  final pv = d['precio_venta'] as num?;
  _precio.text = pv == null ? '' : pv.toString();
  final pc = d['precio_compra'] as num?;
  _precioCompra.text = pc == null ? '' : pc.toString();
  final st = d['stock_actual'] as int?;
  _stock.text = '${st ?? 999}';
  _contabilizaStock = (st != null && st != 999);
      _catId = d['categoria_id'] as int? ?? 3;
      _visible = ((d['visible'] as int?) ?? 1) == 1;
      _imagenPath = d['imagen'] as String?;
    }
    // Inicializar % ganancia si hay compra y venta
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalcFromSale();
    });
    // Listeners de sincronización
    _porcGanancia.addListener(_recalcFromPercent);
    _precio.addListener(_recalcFromSale);
    _precioCompra.addListener(() {
      // si hay % cargado, recalcular venta
      if (_porcGanancia.text.trim().isNotEmpty) {
        _recalcFromPercent();
      } else {
        // si no hay %, y venta está vacía, por defecto copiar compra
        if (_precio.text.trim().isEmpty) {
          _setTextSafely(_precio, _precioCompra.text);
        }
      }
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
    _precio.dispose();
    _precioCompra.dispose();
    _porcGanancia.dispose();
    _stock.dispose();
    super.dispose();
  }

  void _setTextSafely(TextEditingController c, String v) {
    if (c.text == v) return;
    _updatingFields = true;
    final sel = TextSelection.collapsed(offset: v.length);
    c.value = TextEditingValue(text: v, selection: sel);
    _updatingFields = false;
  }

  void _recalcFromPercent() {
    if (_updatingFields) return;
    final pc = parseLooseDouble(_precioCompra.text.trim());
    final per = parseLooseDouble(_porcGanancia.text.trim());
    if (pc.isNaN || per.isNaN) return;
    final sale = (pc * (1 + per / 100)).round();
    _setTextSafely(_precio, sale.toString());
  }

  void _recalcFromSale() {
    if (_updatingFields) return;
    final pc = parseLooseDouble(_precioCompra.text.trim());
    final pv = parseLooseDouble(_precio.text.trim());
    if (pc.isNaN || pv.isNaN) return;
    if (pc <= 0) return; // evita división por cero o negativos
    final per = ((pv - pc) / pc * 100);
    final perRounded = per.isNaN ? '' : per.toStringAsFixed(2);
    _setTextSafely(_porcGanancia, perRounded);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (!_form.currentState!.validate()) return;
    final db = await AppDatabase.instance();
    final codigo = _codigo.text.trim().toUpperCase();
    final nombre = _nombre.text.trim();
  final precioParsed = parseLooseDouble(_precio.text.trim());
  final precio = precioParsed.isNaN ? -1 : precioParsed.round();
  // Precio de compra: opcional, si no está se toma = precio_venta
  final compraText = _precioCompra.text.trim();
  int precioCompra;
  if (compraText.isEmpty) {
    precioCompra = precio;
  } else {
    final compraParsed = parseLooseDouble(compraText);
    if (compraParsed.isNaN) {
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Precio de compra inválido')));
      }
      return;
    }
    precioCompra = compraParsed.round();
  }
    int stock;
    if (!_contabilizaStock) {
      stock = 999; // no contabiliza => ilimitado
    } else {
      stock = int.tryParse(_stock.text.trim()) ?? -1;
      if (stock == 999) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Si contabiliza stock, no puede ser 999. Ingrese otro valor.')));
        }
        return;
      }
    }

    // Validaciones extra: precio/stock >= 0
    if (precio < 0) {
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Precio debe ser >= 0')));
      }
      return;
    }
    // Validación: compra <= venta
    if (precioCompra > precio) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('El precio de compra no puede ser mayor al de venta')));
      }
      return;
    }
    if (stock < 0) {
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Stock debe ser >= 0')));
      }
      return;
    }

    // Validación de código obligatorio, máx 4 y único
    if (codigo.isEmpty) {
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Código es obligatorio')));
      }
      return;
    }
    if (codigo.length > 4) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Código debe tener hasta 4 caracteres')));
      }
      return;
    }

    // Unicidad de código
    final argsCodigo = [codigo, if (widget.data != null) widget.data!['id']];
    final whereCodigo = widget.data == null
        ? 'UPPER(codigo_producto) = ?'
        : 'UPPER(codigo_producto) = ? AND id <> ?';
    final dupCode = await db.query('products',
        columns: ['id'], where: whereCodigo, whereArgs: argsCodigo);
    if (dupCode.isNotEmpty) {
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Código ya existe en otro producto')));
      }
      return;
    }

    // Unicidad de nombre
    final argsNombre = [nombre, if (widget.data != null) widget.data!['id']];
    final whereNombre = widget.data == null
        ? 'UPPER(nombre) = UPPER(?)'
        : 'UPPER(nombre) = UPPER(?) AND id <> ?';
    final dupName = await db.query('products',
        columns: ['id'], where: whereNombre, whereArgs: argsNombre);
    if (dupName.isNotEmpty) {
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Nombre de producto ya existente')));
      }
      return;
    }

    final payload = {
      'codigo_producto': codigo,
      'nombre': _nombre.text.trim(),
      'precio_venta': precio,
      'precio_compra': precioCompra,
      'stock_actual': stock,
      'stock_minimo': 3,
      'categoria_id': _catId,
      'visible': _visible ? 1 : 0,
      'color': null,
      'imagen': _imagenPath,
    };
    if (widget.data == null) {
      // create: asignar orden_visual = max(orden_visual)+1
      final r = await db.rawQuery('SELECT COALESCE(MAX(orden_visual),0) as maxo FROM products');
      final next = ((r.first['maxo'] as num?)?.toInt() ?? 0) + 1;
      await db.insert('products', {...payload, 'orden_visual': next});
    } else {
      // update
      await db.update('products', payload,
          where: 'id=?', whereArgs: [widget.data!['id']]);
    }
  if (mounted) nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              Text(widget.data == null ? 'Nuevo producto' : 'Editar producto')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: ListView(
            children: [
              // Imagen del producto (preview y selector)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _imagenPath != null && _imagenPath!.isNotEmpty && File(_imagenPath!).existsSync()
                        ? Image.file(File(_imagenPath!), fit: BoxFit.cover)
                        : const Icon(Icons.image, color: Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Agregar imagen'),
                    onPressed: () async {
                      final src = await showModalBottomSheet<ImageSource>(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Wrap(children: [
                            ListTile(
                              leading: const Icon(Icons.photo_library),
                              title: const Text('Galería'),
                              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_camera),
                              title: const Text('Cámara'),
                              onTap: () => Navigator.pop(ctx, ImageSource.camera),
                            ),
                          ]),
                        ),
                      );
                      if (src == null) return;
                      final picker = ImagePicker();
                      final x = await picker.pickImage(source: src, imageQuality: 85);
                      if (x == null) return;
                      // Copiar a carpeta de documentos de la app para persistencia
                      final dir = await getApplicationDocumentsDirectory();
                      final picsDir = Directory(p.join(dir.path, 'product_images'));
                      if (!await picsDir.exists()) await picsDir.create(recursive: true);
                      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(x.path)}';
                      final destPath = p.join(picsDir.path, fileName);
                      await File(x.path).copy(destPath);
                      if (!mounted) return;
                      setState(() => _imagenPath = destPath);
                    },
                  ),
                  const SizedBox(width: 8),
                  if (_imagenPath != null && _imagenPath!.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() => _imagenPath = null),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Quitar'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _codigo,
                decoration: const InputDecoration(
                    labelText: 'Código (máx 4, obligatorio)'),
                maxLength: 4,
                onChanged: (v) {
                  final upper = v.toUpperCase();
                  if (upper != v) {
                    final pos = _codigo.selection.base.offset;
                    _codigo.value = TextEditingValue(
                      text: upper,
                      selection: TextSelection.collapsed(
                        offset: pos < 0 ? upper.length : pos,
                      ),
                    );
                  }
                },
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Requerido';
                  if (t.length > 4) return 'Máx 4 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              // Reordenado: compra primero
              TextFormField(
                controller: _precioCompra,
                decoration: const InputDecoration(labelText: 'Precio de compra (opcional)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null; // opcional
                  final val = parseLooseDouble(t);
                  if (val.isNaN) return 'Ingrese un número';
                  final pv = parseLooseDouble(_precio.text.trim());
                  if (!pv.isNaN && val > pv) {
                    return 'No puede ser mayor al precio de venta';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              // Venta y % ganancia lado a lado
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _precio,
                      decoration: const InputDecoration(labelText: 'Precio de venta'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Ingrese un número';
                        final val = parseLooseDouble(v);
                        if (val.isNaN) return 'Ingrese un número';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _porcGanancia,
                      decoration: const InputDecoration(labelText: '% Ganancia'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null; // opcional
                        final val = parseLooseDouble(t);
                        if (val.isNaN) return 'Ingrese un número';
                        if (val < 0) return 'Debe ser >= 0';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _stock,
                decoration: const InputDecoration(
                    labelText: 'Stock actual (use 999 para ilimitado)'),
                keyboardType: TextInputType.number,
                enabled: _contabilizaStock,
                validator: (v) {
                  if (!_contabilizaStock) return null; // deshabilitado
                  if (v == null || v.isEmpty) return 'Ingrese un número';
                  final iv = int.tryParse(v);
                  if (iv == null) return 'Ingrese un número';
                  if (iv == 999) return 'Use un valor distinto a 999 si contabiliza stock';
                  if (iv < 0) return 'Stock debe ser >= 0';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Contabilizar stock'),
                subtitle: const Text('Si está apagado, no se descuenta stock (999)'),
                value: _contabilizaStock,
                onChanged: (v) {
                  setState(() {
                    _contabilizaStock = v;
                    if (!v) {
                      _stock.text = '999';
                    } else {
                      if (_stock.text.trim() == '999') _stock.text = '0';
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _catId,
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
                title: const Text('Visible'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _save,
                  child: Text(widget.data == null ? 'Crear' : 'Guardar')),
            ],
          ),
        ),
      ),
    );
  }
}
