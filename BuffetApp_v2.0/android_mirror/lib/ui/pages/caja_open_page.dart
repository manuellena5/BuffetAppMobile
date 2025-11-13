import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../format.dart';
import 'pos_main_page.dart';
import 'products_page.dart';
import '../../data/dao/db.dart';

class CajaOpenPage extends StatefulWidget {
  const CajaOpenPage({super.key});
  @override
  State<CajaOpenPage> createState() => _CajaOpenPageState();
}

class _CajaOpenPageState extends State<CajaOpenPage> {
  final _form = GlobalKey<FormState>();
  final _usuario = TextEditingController(text: '');
  final _fondo = TextEditingController(text: '');
  final _desc = TextEditingController();
  final _obs = TextEditingController();
  String? _disciplina;
  String? _puntoVentaCodigo; // Caj01/Caj02/Caj03
  List<String> _disciplinas = const [];
  List<Map<String, String>> _puntos = const []; // {codigo, nombre}
  final _svc = CajaService();

  @override
  void dispose() {
    _usuario.dispose();
    _fondo.dispose();
    _desc.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarCatalogos();
  }

  Future<void> _cargarCatalogos() async {
    List<String> dis = const [];
    List<Map<String, dynamic>> pv = const [];
    try {
      dis = await _svc.listarDisciplinas();
      pv = await _svc.listarPuntosVenta();
    } catch (e, st) {
      AppDatabase.logLocalError(scope: 'caja_open.load_catalogs', error: e, stackTrace: st);
    }
    if (!mounted) return;
    setState(() {
      _disciplinas = dis;
      _puntos = pv
          .map((e) => {
                'codigo': (e['codigo'] as String),
                'nombre': (e['nombre'] as String),
              })
          .toList();
      _disciplina = _disciplinas.isNotEmpty ? _disciplinas.first : null;
      _puntoVentaCodigo = _puntos.isNotEmpty ? _puntos.first['codigo'] : null;
    });
  }

  Future<void> _abrir() async {
    if (!_form.currentState!.validate()) return;
    final fondo = parseLooseDouble(_fondo.text);
  final pvCode = _puntoVentaCodigo ?? 'Caj01';

    try {
      // Verificar si ya hay una caja abierta
      final abierta = await _svc.getCajaAbierta();
      if (abierta != null) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Caja ya abierta'),
            content: Text(
                'Ya existe una caja abierta: ${abierta['codigo_caja']}. Cerrala o usá otra.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido')),
            ],
          ),
        );
        return;
      }

      await _svc.abrirCaja(
        usuario: _usuario.text.trim(),
        fondoInicial: fondo,
  disciplina: _disciplina ?? 'Otros',
        descripcionEvento: _desc.text.trim(),
        observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
        puntoVentaCodigo: pvCode,
      );
      if (!mounted) return;
      // Preguntar si desea cargar stock ahora
      final goToStock = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Caja abierta'),
          content: const Text('¿Querés cargar stock ahora?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Ir a ventas')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cargar stock')),
          ],
        ),
      );
      if (!mounted) return;
      if (goToStock == true) {
        // Ir a Productos
        // Importación perezosa para evitar dependencias circulares
        // ignore: use_build_context_synchronously
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const ProductsPage()));
      } else {
        if (!context.mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const PosMainPage()));
      }
    } catch (e, st) {
      AppDatabase.logLocalError(scope: 'caja_open.abrir_caja', error: e, stackTrace: st);
      if (!context.mounted) return;
      final msg = e.toString();
      String uiMsg = 'No se pudo abrir la caja.';
      if (msg.contains('UNIQUE') && msg.contains('codigo_caja')) {
        uiMsg =
            'Ya existe una caja con el mismo código para hoy. Probá con otro Punto de venta o disciplina.';
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error al abrir caja'),
          content: Text(uiMsg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'))
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apertura de caja')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: ListView(
            children: [
              TextFormField(
        controller: _usuario,
        decoration:
          const InputDecoration(labelText: 'Cajero apertura'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fondo,
                decoration: const InputDecoration(labelText: 'Fondo inicial'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final val = parseLooseDouble(v ?? '');
                  return (val < 0) ? '>= 0' : null;
                },
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<String>>(
                future: _svc.listarDisciplinas(),
                builder: (ctx, snap) {
                  final items = snap.data ?? _disciplinas;
                  final value = _disciplina ?? (items.isNotEmpty ? items.first : null);
                  return DropdownButtonFormField<String>(
                    key: ValueKey('disciplina_${items.length}_${value ?? ''}'),
                    initialValue: value,
                    items: [
                      for (final d in items)
                        DropdownMenuItem(value: d, child: Text(d))
                    ],
                    onChanged: (v) => setState(() => _disciplina = v),
                    decoration: const InputDecoration(labelText: 'Disciplina'),
                  );
                },
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _svc.listarPuntosVenta(),
                builder: (ctx, snap) {
                  final items = snap.data ?? _puntos;
                  final value = _puntoVentaCodigo ?? (items.isNotEmpty ? items.first['codigo'] as String : null);
                  return DropdownButtonFormField<String>(
                    key: ValueKey('pv_${items.length}_${value ?? ''}'),
                    initialValue: value,
                    items: [
                      for (final e in items)
                        DropdownMenuItem(
                          value: e['codigo'] as String,
                          child: Text('${e['nombre']} (${e['codigo']})'),
                        )
                    ],
                    onChanged: (v) => setState(() => _puntoVentaCodigo = v),
                    decoration: const InputDecoration(labelText: 'Punto de venta'),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _desc,
                decoration:
                    const InputDecoration(labelText: 'Descripción del evento'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _obs,
                decoration: const InputDecoration(labelText: 'Observación'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _abrir, child: const Text('Abrir caja')),
            ],
          ),
        ),
      ),
    );
  }
}
