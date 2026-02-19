import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../../../data/dao/db.dart';
import '../../shared/format.dart';
import '../../shared/widgets/responsive_container.dart';
import 'buffet_home_page.dart';
import 'products_page.dart';

/// Pantalla de edición masiva de precios, stock y visibilidad de productos.
/// Permite buscar/filtrar, editar inline y guardar todos los cambios de una vez.
class BulkEditProductsPage extends StatefulWidget {
  const BulkEditProductsPage({super.key});
  @override
  State<BulkEditProductsPage> createState() => _BulkEditProductsPageState();
}

class _BulkEditProductsPageState extends State<BulkEditProductsPage> {
  List<_ProductEdit> _products = [];
  List<_ProductEdit> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  int? _selectedCatId; // null = todas
  final _changeCount = ValueNotifier<int>(0);

  static const _cats = [
    {'id': 1, 'descripcion': 'Comida'},
    {'id': 2, 'descripcion': 'Bebida'},
    {'id': 3, 'descripcion': 'Otros'},
  ];

  static IconData catIcon(int? catId) {
    switch (catId) {
      case 1:
        return Icons.lunch_dining;
      case 2:
        return Icons.local_drink;
      default:
        return Icons.category;
    }
  }

  static Color catColor(int? catId) {
    switch (catId) {
      case 1:
        return Colors.orange;
      case 2:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _changeCount.dispose();
    _searchCtrl.dispose();
    for (final p in _products) {
      p.disposeControllers();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance();
      // Asegurar categorías existen
      for (final c in _cats) {
        await db.insert('Categoria_Producto', Map<String, Object?>.from(c),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final rows = await db.rawQuery('''
        SELECT p.id, p.nombre, p.precio_compra, p.precio_venta, p.stock_actual,
               p.visible, p.categoria_id,
               COALESCE(c.descripcion,'Sin cat.') as categoria
        FROM products p
        LEFT JOIN Categoria_Producto c ON c.id = p.categoria_id
        ORDER BY p.orden_visual ASC, p.id ASC
      ''');
      // Limpiar controllers anteriores
      for (final p in _products) {
        p.disposeControllers();
      }
      final items = rows.map((r) {
        final precioCompra = (r['precio_compra'] as num?)?.toInt();
        final precio = ((r['precio_venta'] as num?) ?? 0).toInt();
        final stock = ((r['stock_actual'] as num?) ?? 0).toInt();
        // Calcular ganancia inicial
        String gananciaInicial = '';
        if (precioCompra != null && precioCompra > 0 && precio > 0) {
          gananciaInicial =
              ((precio - precioCompra) / precioCompra * 100)
                  .toStringAsFixed(1);
        }
        return _ProductEdit(
          id: r['id'] as int,
          nombre: (r['nombre'] as String?) ?? '',
          categoriaId: r['categoria_id'] as int?,
          categoriaNombre: (r['categoria'] as String?) ?? '',
          originalPrecioCompra: precioCompra,
          originalPrecio: precio,
          originalStock: stock,
          originalVisible: (r['visible'] as int?) == 1,
          precioCompraCtrl: TextEditingController(
              text: precioCompra != null && precioCompra > 0
                  ? precioCompra.toString()
                  : ''),
          gananciaCtrl: TextEditingController(text: gananciaInicial),
          precioCtrl: TextEditingController(text: precio.toString()),
          stockCtrl: TextEditingController(
              text: stock == 999 ? '' : stock.toString()),
          visible: (r['visible'] as int?) == 1,
          tracksStock: stock != 999,
        );
      }).toList();
      setState(() {
        _products = items;
        _loading = false;
      });
      _applyFilter();
      _updateChangeCount();
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'bulk_edit.load', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error al cargar productos'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _products.where((p) {
        final matchCat =
            _selectedCatId == null || p.categoriaId == _selectedCatId;
        final matchSearch =
            query.isEmpty || p.nombre.toLowerCase().contains(query);
        return matchCat && matchSearch;
      }).toList();
    });
  }

  void _updateChangeCount() {
    _changeCount.value = _changed.length;
  }

  // --- Contar cambios ---
  List<_ProductEdit> get _changed {
    return _products.where((p) {
      final newPrecioCompra = int.tryParse(p.precioCompraCtrl.text.trim());
      final origCompra = p.originalPrecioCompra;
      final precioCompraChanged = (newPrecioCompra ?? 0) != (origCompra ?? 0);
      final newPrecio =
          int.tryParse(p.precioCtrl.text.trim()) ?? p.originalPrecio;
      final newStock = p.tracksStock
          ? (int.tryParse(p.stockCtrl.text.trim()) ?? p.originalStock)
          : 999;
      return precioCompraChanged ||
          newPrecio != p.originalPrecio ||
          newStock != p.originalStock ||
          p.visible != p.originalVisible;
    }).toList();
  }

  bool get _hasChanges => _changed.isNotEmpty;

  // --- Guardar masivo ---
  Future<void> _saveAll() async {
    final changes = _changed;
    if (changes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cambios para guardar')),
      );
      return;
    }

    // Preview
    final confirm = await _showPreview(changes);
    if (confirm != true || !mounted) return;

    try {
      final db = await AppDatabase.instance();
      final batch = db.batch();
      for (final p in changes) {
        final newPrecioCompra = int.tryParse(p.precioCompraCtrl.text.trim());
        final newPrecio =
            int.tryParse(p.precioCtrl.text.trim()) ?? p.originalPrecio;
        final newStock = p.tracksStock
            ? (int.tryParse(p.stockCtrl.text.trim()) ?? p.originalStock)
            : 999;
        batch.update(
          'products',
          {
            'precio_compra': newPrecioCompra,
            'precio_venta': newPrecio,
            'stock_actual': newStock,
            'visible': p.visible ? 1 : 0,
          },
          where: 'id=?',
          whereArgs: [p.id],
        );
      }
      await batch.commit(noResult: true);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              const Text('Cambios guardados'),
            ],
          ),
          content: Text(
              'Se actualizaron ${changes.length} producto${changes.length == 1 ? '' : 's'}.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );

      // Redirigir al menú principal de buffet
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BuffetHomePage()),
        );
      }
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'bulk_edit.save', error: e, stackTrace: st);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 32),
                const SizedBox(width: 12),
                const Text('Error'),
              ],
            ),
            content: const Text(
                'No se pudieron guardar los cambios. Intente nuevamente.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }

  // --- Preview de cambios ---
  Future<bool?> _showPreview(List<_ProductEdit> changes) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cambios'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${changes.length} producto${changes.length == 1 ? '' : 's'} modificado${changes.length == 1 ? '' : 's'}:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: changes.length,
                  itemBuilder: (_, i) {
                    final p = changes[i];
                    final newPrecioCompra =
                        int.tryParse(p.precioCompraCtrl.text.trim());
                    final newPrecio =
                        int.tryParse(p.precioCtrl.text.trim()) ??
                            p.originalPrecio;
                    final newStock = p.tracksStock
                        ? (int.tryParse(p.stockCtrl.text.trim()) ??
                            p.originalStock)
                        : 999;
                    final diffs = <String>[];
                    final origCompra = p.originalPrecioCompra ?? 0;
                    if ((newPrecioCompra ?? 0) != origCompra) {
                      final oldC = origCompra > 0
                          ? formatCurrencyNoDecimals(origCompra)
                          : '—';
                      final newC =
                          newPrecioCompra != null && newPrecioCompra > 0
                              ? formatCurrencyNoDecimals(newPrecioCompra)
                              : '—';
                      diffs.add('P.Compra: $oldC → $newC');
                    }
                    if (newPrecio != p.originalPrecio) {
                      diffs.add(
                          'P.Venta: ${formatCurrencyNoDecimals(p.originalPrecio)} → ${formatCurrencyNoDecimals(newPrecio)}');
                    }
                    if (newStock != p.originalStock) {
                      final oldS = p.originalStock == 999
                          ? 'Sin control'
                          : p.originalStock.toString();
                      final newS =
                          newStock == 999 ? 'Sin control' : newStock.toString();
                      diffs.add('Stock: $oldS → $newS');
                    }
                    if (p.visible != p.originalVisible) {
                      diffs.add(p.visible ? 'Mostrar' : 'Ocultar');
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.nombre,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                ...diffs.map((d) => Text(d,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700]))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // --- Descartar cambios ---
  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: Text(
            'Hay ${_changed.length} cambio(s) sin guardar. ¿Qué querés hacer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Salir sin guardar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Guardar y salir'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await _saveAll();
      // _saveAll navega a BuffetHomePage si fue exitoso.
      // Si el usuario canceló el preview o falló, queda en esta pantalla.
      return false;
    }
    return result == 'discard';
  }

  // --- Agregar producto nuevo ---
  Future<void> _addNewProduct() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _AddProductDialog(),
    );
    if (result == true) {
      // Guardar cambios pendientes en un map para reaplicar después de reload
      final pendingChanges = <int, _PendingChange>{};
      for (final p in _products) {
        final newCompra = int.tryParse(p.precioCompraCtrl.text.trim());
        final origCompra = p.originalPrecioCompra ?? 0;
        final newPrecio =
            int.tryParse(p.precioCtrl.text.trim()) ?? p.originalPrecio;
        final newStock = p.tracksStock
            ? (int.tryParse(p.stockCtrl.text.trim()) ?? p.originalStock)
            : 999;
        final hasChange = (newCompra ?? 0) != origCompra ||
            newPrecio != p.originalPrecio ||
            newStock != p.originalStock ||
            p.visible != p.originalVisible;
        if (hasChange) {
          pendingChanges[p.id] = _PendingChange(
            precioCompra: p.precioCompraCtrl.text,
            ganancia: p.gananciaCtrl.text,
            precioVenta: p.precioCtrl.text,
            stock: p.stockCtrl.text,
            tracksStock: p.tracksStock,
            visible: p.visible,
          );
        }
      }

      await _load();

      // Restaurar cambios pendientes
      if (pendingChanges.isNotEmpty) {
        for (final p in _products) {
          final pending = pendingChanges[p.id];
          if (pending != null) {
            p.precioCompraCtrl.text = pending.precioCompra;
            p.gananciaCtrl.text = pending.ganancia;
            p.precioCtrl.text = pending.precioVenta;
            p.stockCtrl.text = pending.stock;
            p.tracksStock = pending.tracksStock;
            p.visible = pending.visible;
          }
        }
        setState(() {});
      }
      _updateChangeCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANTE: No envolver el Scaffold entero en ValueListenableBuilder.
    // Solo envolver los widgets puntuales que muestran el conteo de cambios.
    // Así el ListView NO se reconstruye al cambiar el contador y el foco
    // se preserva correctamente en los TextFields de cada fila.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_hasChanges) {
          Navigator.pop(context);
          return;
        }
        final canPop = await _confirmDiscard();
        if (canPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Precios y Stock'),
          actions: [
            // Badge con conteo — solo este widget se reconstruye
            ValueListenableBuilder<int>(
              valueListenable: _changeCount,
              builder: (_, count, __) => count > 0
                  ? Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Badge(
                        label: Text('$count'),
                        child: IconButton(
                          tooltip: 'Guardar cambios',
                          icon: const Icon(Icons.save),
                          onPressed: _saveAll,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton(
              tooltip: 'Ir a gestión de Productos',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () async {
                final canGo =
                    _hasChanges ? await _confirmDiscard() : true;
                if (canGo && mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProductsPage()),
                  );
                }
              },
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ResponsiveContainer(
                maxWidth: 700,
                child: Column(
                  children: [
                    // Barra de búsqueda + filtro categoría
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Buscar producto...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                        },
                                      )
                                    : null,
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<int?>(
                            value: _selectedCatId,
                            hint: const Text('Categoría'),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Todas'),
                              ),
                              ..._cats.map(
                                  (c) => DropdownMenuItem<int?>(
                                        value: c['id'] as int,
                                        child: Text(
                                            c['descripcion'] as String),
                                      )),
                            ],
                            onChanged: (v) {
                              _selectedCatId = v;
                              _applyFilter();
                            },
                          ),
                        ],
                      ),
                    ),
                    // Info bar + leyenda ojo
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            '${_filtered.length} de ${_products.length} productos',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const Spacer(),
                          // Solo el texto de cambios se reconstruye
                          ValueListenableBuilder<int>(
                            valueListenable: _changeCount,
                            builder: (_, count, __) => count > 0
                                ? Padding(
                                    padding:
                                        const EdgeInsets.only(right: 8),
                                    child: Text(
                                      '$count cambio${count == 1 ? '' : 's'}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange[800],
                                          fontWeight: FontWeight.w600),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Icon(Icons.visibility_off,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Text(
                            'oculta del menú',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Lista de productos — NO se reconstruye al cambiar _changeCount
                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(
                              child: Text(
                                _products.isEmpty
                                    ? 'No hay productos cargados'
                                    : 'Sin resultados para la búsqueda',
                                style:
                                    TextStyle(color: Colors.grey[500]),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 4),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) => _ProductRowWidget(
                                key: ValueKey(_filtered[i].id),
                                product: _filtered[i],
                                onChanged: _updateChangeCount,
                              ),
                            ),
                    ),
                    // Barra inferior
                    SafeArea(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Fila: Agregar nuevo + Gestión
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _addNewProduct,
                                    icon: const Icon(Icons.add),
                                    label:
                                        const Text('Nuevo Producto'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final canGo = _hasChanges
                                          ? await _confirmDiscard()
                                          : true;
                                      if (canGo && mounted) {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const ProductsPage()),
                                        );
                                      }
                                    },
                                    icon:
                                        const Icon(Icons.inventory_2),
                                    label: const Text('Gestión'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Botón guardar — solo este se reconstruye
                            ValueListenableBuilder<int>(
                              valueListenable: _changeCount,
                              builder: (_, count, __) => SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 14),
                                  ),
                                  onPressed: count > 0
                                      ? _saveAll
                                      : null,
                                  icon: const Icon(Icons.save),
                                  label: Text(count > 0
                                      ? 'Guardar ($count)'
                                      : 'Sin cambios'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ─── Widget individual para cada fila de producto ─────────────────────────
// Cada fila es un StatefulWidget independiente para que setState() solo
// reconstruya esta fila, sin afectar al resto del ListView ni perder el foco.

class _ProductRowWidget extends StatefulWidget {
  final _ProductEdit product;
  final VoidCallback onChanged;

  const _ProductRowWidget({
    required super.key,
    required this.product,
    required this.onChanged,
  });

  @override
  State<_ProductRowWidget> createState() => _ProductRowWidgetState();
}

class _ProductRowWidgetState extends State<_ProductRowWidget> {
  _ProductEdit get p => widget.product;

  // FocusNodes para detectar cuándo el usuario SALE de un campo.
  // La recalculación cruzada (P.Compra → %Gan / P.Venta) SOLO ocurre
  // al perder foco. Así NO se modifica ningún otro controller mientras
  // el usuario escribe, y el foco nunca se roba.
  late final FocusNode _precioCompraFocus;
  late final FocusNode _gananciaFocus;
  late final FocusNode _precioVentaFocus;
  late final FocusNode _stockFocus;

  @override
  void initState() {
    super.initState();
    _precioCompraFocus = FocusNode()
      ..addListener(() {
        if (!_precioCompraFocus.hasFocus) _recalcFromCompra();
      });
    _gananciaFocus = FocusNode()
      ..addListener(() {
        if (!_gananciaFocus.hasFocus) _recalcFromGanancia();
      });
    _precioVentaFocus = FocusNode()
      ..addListener(() {
        if (!_precioVentaFocus.hasFocus) _recalcFromVenta();
      });
    _stockFocus = FocusNode()
      ..addListener(() {
        if (!_stockFocus.hasFocus) _notifyAndRebuild();
      });
  }

  @override
  void dispose() {
    _precioCompraFocus.dispose();
    _gananciaFocus.dispose();
    _precioVentaFocus.dispose();
    _stockFocus.dispose();
    super.dispose();
  }

  // ── Recalculaciones cruzadas (solo al perder foco) ──────────────

  void _recalcFromCompra() {
    final compra = int.tryParse(p.precioCompraCtrl.text.trim());
    final gan = double.tryParse(p.gananciaCtrl.text.trim());
    if (compra != null && compra > 0 && gan != null) {
      p.precioCtrl.text = (compra * (1 + gan / 100)).round().toString();
    } else if (compra != null && compra > 0) {
      final venta = int.tryParse(p.precioCtrl.text.trim());
      if (venta != null && venta > 0) {
        p.gananciaCtrl.text =
            ((venta - compra) / compra * 100).toStringAsFixed(1);
      }
    } else {
      p.gananciaCtrl.text = '';
    }
    _notifyAndRebuild();
  }

  void _recalcFromVenta() {
    final compra = int.tryParse(p.precioCompraCtrl.text.trim());
    final venta = int.tryParse(p.precioCtrl.text.trim());
    if (compra != null && compra > 0 && venta != null && venta > 0) {
      p.gananciaCtrl.text =
          ((venta - compra) / compra * 100).toStringAsFixed(1);
    } else {
      p.gananciaCtrl.text = '';
    }
    _notifyAndRebuild();
  }

  void _recalcFromGanancia() {
    final compra = int.tryParse(p.precioCompraCtrl.text.trim());
    final gan = double.tryParse(p.gananciaCtrl.text.trim());
    if (compra != null && compra > 0 && gan != null) {
      p.precioCtrl.text = (compra * (1 + gan / 100)).round().toString();
    }
    _notifyAndRebuild();
  }

  /// Actualiza visual (highlight) y conteo de cambios del padre.
  void _notifyAndRebuild() {
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final compra = int.tryParse(p.precioCompraCtrl.text.trim());
    final origCompra = p.originalPrecioCompra ?? 0;
    final precioCompraChanged = (compra ?? 0) != origCompra;
    final precioChanged =
        (int.tryParse(p.precioCtrl.text.trim()) ?? p.originalPrecio) !=
            p.originalPrecio;
    final newStockVal = p.tracksStock
        ? (int.tryParse(p.stockCtrl.text.trim()) ?? p.originalStock)
        : 999;
    final stockChanged = newStockVal != p.originalStock;
    final visChanged = p.visible != p.originalVisible;
    final hasRowChange =
        precioCompraChanged || precioChanged || stockChanged || visChanged;
    final hasCompra = compra != null && compra > 0;

    return Container(
      color: hasRowChange ? Colors.amber.withValues(alpha: 0.08) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila 1: icono cat + ojo + nombre + stock switch + campo stock
          Row(
            children: [
              // Icono categoría
              Icon(_BulkEditProductsPageState.catIcon(p.categoriaId),
                  size: 20,
                  color:
                      _BulkEditProductsPageState.catColor(p.categoriaId)),
              const SizedBox(width: 6),
              // Visibilidad toggle
              GestureDetector(
                onTap: () {
                  setState(() => p.visible = !p.visible);
                  widget.onChanged();
                },
                child: Icon(
                  p.visible ? Icons.visibility : Icons.visibility_off,
                  color: p.visible ? Colors.green : Colors.grey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 6),
              // Nombre
              Expanded(
                child: Text(
                  p.nombre,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    decoration:
                        p.visible ? null : TextDecoration.lineThrough,
                    color: p.visible ? null : Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Switch contabilizar stock + campo
              const SizedBox(width: 4),
              SizedBox(
                height: 28,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Stock',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600])),
                    SizedBox(
                      width: 40,
                      height: 28,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Switch(
                          value: p.tracksStock,
                          onChanged: (v) {
                            setState(() {
                              p.tracksStock = v;
                              if (!v) {
                                p.stockCtrl.text = '';
                              } else {
                                p.stockCtrl.text = p.originalStock == 999
                                    ? '0'
                                    : p.originalStock.toString();
                              }
                            });
                            widget.onChanged();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (p.tracksStock)
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: p.stockCtrl,
                    focusNode: _stockFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: stockChanged ? Colors.orange[800] : null,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      filled: stockChanged,
                      fillColor: stockChanged
                          ? Colors.orange.withValues(alpha: 0.08)
                          : null,
                    ),
                    // Sin onChanged — la actualización visual ocurre al perder foco
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Fila 2: P.Compra | % Ganancia | P.Venta
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: p.precioCompraCtrl,
                  focusNode: _precioCompraFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        precioCompraChanged ? Colors.orange[800] : null,
                  ),
                  decoration: InputDecoration(
                    labelText: 'P.Compra',
                    labelStyle: const TextStyle(fontSize: 11),
                    prefixText: '\$ ',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    filled: precioCompraChanged,
                    fillColor: precioCompraChanged
                        ? Colors.orange.withValues(alpha: 0.08)
                        : null,
                  ),
                  // Sin onChanged — la recalculación ocurre al perder foco
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: p.gananciaCtrl,
                  focusNode: _gananciaFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[\d.,\-]')),
                  ],
                  textAlign: TextAlign.end,
                  enabled: hasCompra,
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        hasCompra ? Colors.blueGrey[700] : Colors.grey,
                  ),
                  decoration: InputDecoration(
                    labelText: '% Gan.',
                    labelStyle: const TextStyle(fontSize: 11),
                    suffixText: '%',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  // Sin onChanged — la recalculación ocurre al perder foco
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: p.precioCtrl,
                  focusNode: _precioVentaFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: precioChanged ? Colors.orange[800] : null,
                  ),
                  decoration: InputDecoration(
                    labelText: 'P.Venta',
                    labelStyle: const TextStyle(fontSize: 11),
                    prefixText: '\$ ',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    filled: precioChanged,
                    fillColor: precioChanged
                        ? Colors.orange.withValues(alpha: 0.08)
                        : null,
                  ),
                  // Sin onChanged — la recalculación ocurre al perder foco
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Modelo interno para tracking de cambios ─────────────────────────────

class _ProductEdit {
  final int id;
  final String nombre;
  final int? categoriaId;
  final String categoriaNombre;
  final int? originalPrecioCompra;
  final int originalPrecio;
  final int originalStock;
  final bool originalVisible;
  final TextEditingController precioCompraCtrl;
  final TextEditingController gananciaCtrl;
  final TextEditingController precioCtrl;
  final TextEditingController stockCtrl;
  bool visible;
  bool tracksStock; // true = controla stock, false = ilimitado (999)

  _ProductEdit({
    required this.id,
    required this.nombre,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.originalPrecioCompra,
    required this.originalPrecio,
    required this.originalStock,
    required this.originalVisible,
    required this.precioCompraCtrl,
    required this.gananciaCtrl,
    required this.precioCtrl,
    required this.stockCtrl,
    required this.visible,
    required this.tracksStock,
  });

  void disposeControllers() {
    precioCompraCtrl.dispose();
    gananciaCtrl.dispose();
    precioCtrl.dispose();
    stockCtrl.dispose();
  }
}

class _PendingChange {
  final String precioCompra;
  final String ganancia;
  final String precioVenta;
  final String stock;
  final bool tracksStock;
  final bool visible;
  const _PendingChange({
    required this.precioCompra,
    required this.ganancia,
    required this.precioVenta,
    required this.stock,
    required this.tracksStock,
    required this.visible,
  });
}

// ─── Diálogo para agregar producto nuevo ────────────────────────────────

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog();
  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _precioVentaCtrl = TextEditingController();
  final _precioCompraCtrl = TextEditingController();
  int _catId = 1;
  bool _saving = false;
  String? _errorMsg;
  /// true si el usuario editó manualmente el código → no pisarlo.
  bool _codigoManual = false;
  /// Códigos existentes en DB, cargados una sola vez al abrir el diálogo.
  Set<String> _existingCodes = {};

  static const _cats = [
    {'id': 1, 'descripcion': 'Comida'},
    {'id': 2, 'descripcion': 'Bebida'},
    {'id': 3, 'descripcion': 'Otros'},
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingCodes();
  }

  Future<void> _loadExistingCodes() async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.query('products', columns: ['codigo_producto']);
      _existingCodes = rows
          .map((r) => (r['codigo_producto'] as String?)?.toUpperCase() ?? '')
          .where((c) => c.isNotEmpty)
          .toSet();
    } catch (_) {
      // No bloquear si falla; la validación en _save() lo atrapará.
    }
  }

  /// Genera un código de hasta 4 caracteres a partir de las iniciales
  /// del nombre. Si ya existe, reemplaza el último carácter por un dígito
  /// incremental (1-9).
  String _generateCode(String nombre) {
    final words = nombre.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '';

    String base;
    if (words.length >= 4) {
      // 4+ palabras → 1 letra de cada una de las primeras 4
      base = words.take(4).map((w) => w[0]).join();
    } else if (words.length >= 2) {
      // 2-3 palabras → primeras letras hasta completar 4
      final buf = StringBuffer();
      for (final w in words) {
        final take = (4 - buf.length) ~/ (words.length - words.indexOf(w));
        buf.write(w.substring(0, take.clamp(1, w.length).clamp(1, 4 - buf.length)));
        if (buf.length >= 4) break;
      }
      base = buf.toString();
    } else {
      // 1 palabra → primeros 4 caracteres
      base = words.first.substring(0, words.first.length.clamp(0, 4));
    }
    base = base.toUpperCase();
    if (base.length > 4) base = base.substring(0, 4);

    // Si no existe, usar tal cual
    if (!_existingCodes.contains(base)) return base;

    // Colisión: recortar a 3 chars y agregar dígito
    final prefix = base.substring(0, (base.length - 1).clamp(1, 3));
    for (int i = 1; i <= 9; i++) {
      final candidate = '$prefix$i';
      if (!_existingCodes.contains(candidate)) return candidate;
    }
    // Fallback: devolver base original y dejar que la validación lo atrape
    return base;
  }

  void _onNombreChanged(String value) {
    setState(() => _errorMsg = null);
    if (!_codigoManual) {
      final code = _generateCode(value);
      _codigoCtrl.text = code;
    }
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _precioVentaCtrl.dispose();
    _precioCompraCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nombre = _nombreCtrl.text.trim();
    final codigo = _codigoCtrl.text.trim().toUpperCase();
    final precioVenta = int.tryParse(_precioVentaCtrl.text.trim());
    final precioCompra = int.tryParse(_precioCompraCtrl.text.trim());

    if (nombre.isEmpty) {
      setState(() => _errorMsg = 'Nombre es obligatorio');
      return;
    }
    if (codigo.isEmpty || codigo.length > 4) {
      setState(() => _errorMsg = 'Código obligatorio (máx. 4 caracteres)');
      return;
    }
    if (precioVenta == null || precioVenta <= 0) {
      setState(() => _errorMsg = 'Precio de venta inválido');
      return;
    }

    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    try {
      final db = await AppDatabase.instance();

      // Unicidad código
      final dupCode = await db.query('products',
          columns: ['id'],
          where: 'UPPER(codigo_producto) = ?',
          whereArgs: [codigo]);
      if (dupCode.isNotEmpty) {
        setState(() {
          _errorMsg = 'Código ya existe en otro producto';
          _saving = false;
        });
        return;
      }

      // Unicidad nombre
      final dupName = await db.query('products',
          columns: ['id'],
          where: 'UPPER(nombre) = UPPER(?)',
          whereArgs: [nombre]);
      if (dupName.isNotEmpty) {
        setState(() {
          _errorMsg = 'Nombre de producto ya existente';
          _saving = false;
        });
        return;
      }

      // Orden visual
      final r = await db.rawQuery(
          'SELECT COALESCE(MAX(orden_visual),0) as maxo FROM products');
      final nextOrder = ((r.first['maxo'] as num?)?.toInt() ?? 0) + 1;

      await db.insert('products', {
        'codigo_producto': codigo,
        'nombre': nombre,
        'precio_venta': precioVenta,
        'precio_compra': precioCompra,
        'stock_actual': 999,
        'stock_minimo': 3,
        'categoria_id': _catId,
        'visible': 1,
        'orden_visual': nextOrder,
        'color': null,
        'imagen': null,
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'bulk_edit.add_product', error: e, stackTrace: st);
      setState(() {
        _errorMsg = 'Error al guardar el producto';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Preview data
    final nombre = _nombreCtrl.text.trim();
    final codigo = _codigoCtrl.text.trim().toUpperCase();
    final precioVenta = int.tryParse(_precioVentaCtrl.text.trim());
    final precioCompra = int.tryParse(_precioCompraCtrl.text.trim());
    final catDesc =
        _cats.firstWhere((c) => c['id'] == _catId)['descripcion'] as String;
    final showPreview = nombre.isNotEmpty;

    return AlertDialog(
      title: const Text('Nuevo Producto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mensaje de error inline
            if (_errorMsg != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: TextStyle(
                            color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            // 1. Nombre (primero)
            TextField(
              controller: _nombreCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                hintText: 'Ej: Hamburguesa',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onNombreChanged,
            ),
            const SizedBox(height: 12),
            // 2. Código (auto-generado desde nombre, editable)
            TextField(
              controller: _codigoCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: 'Código *',
                hintText: 'Ej: HAMB',
                counterText: '',
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: _codigoManual ? 'Editado manualmente' : 'Generado automáticamente',
                helperStyle: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
              onChanged: (v) {
                if (v.isNotEmpty) _codigoManual = true;
                setState(() => _errorMsg = null);
              },
            ),
            const SizedBox(height: 12),
            // 3. Categoría
            DropdownButtonFormField<int>(
              value: _catId,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _cats
                  .map((c) => DropdownMenuItem<int>(
                        value: c['id'] as int,
                        child: Text(c['descripcion'] as String),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _catId = v);
              },
            ),
            const SizedBox(height: 12),
            // 4. Precio Compra
            TextField(
              controller: _precioCompraCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Precio Compra (opcional)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _errorMsg = null),
            ),
            const SizedBox(height: 12),
            // 5. Precio Venta
            TextField(
              controller: _precioVentaCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Precio Venta *',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _errorMsg = null),
            ),
            // Vista previa del producto
            if (showPreview) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 4),
              Text('Vista previa',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      _BulkEditProductsPageState.catIcon(_catId),
                      size: 22,
                      color: _BulkEditProductsPageState.catColor(_catId),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre.isNotEmpty ? nombre : '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          Text(
                            '${codigo.isNotEmpty ? codigo : '—'} · $catDesc',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          precioVenta != null && precioVenta > 0
                              ? '\$ $precioVenta'
                              : '\$ —',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (precioCompra != null && precioCompra > 0)
                          Text(
                            'Costo: \$ $precioCompra',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Crear'),
        ),
      ],
    );
  }
}
