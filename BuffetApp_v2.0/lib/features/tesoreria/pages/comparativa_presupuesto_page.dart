import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../../layout/erp_layout.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/format.dart';
import '../services/presupuesto_service.dart';
import '../../../data/dao/db.dart';

/// Pantalla de comparativa Presupuesto vs Ejecución real (mes a mes).
///
/// Muestra para cada mes del año:
/// - Presupuesto de ingresos y egresos
/// - Ejecución real de ingresos y egresos
/// - Desvío (diferencia real − presupuesto)
class ComparativaPresupuestoPage extends StatefulWidget {
  const ComparativaPresupuestoPage({super.key});

  @override
  State<ComparativaPresupuestoPage> createState() =>
      _ComparativaPresupuestoPageState();
}

class _ComparativaPresupuestoPageState
    extends State<ComparativaPresupuestoPage> {
  final _service = PresupuestoService.instance;

  int _anio = DateTime.now().year;
  int? _unidadGestionId;
  String? _unidadNombre;

  List<Map<String, dynamic>> _datos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    try {
      final settings = context.read<AppSettings>();
      _unidadGestionId = settings.unidadGestionActivaId;

      if (_unidadGestionId != null) {
        final db = await AppDatabase.instance();
        final rows = await db.query('unidades_gestion',
            columns: ['nombre'],
            where: 'id=?',
            whereArgs: [_unidadGestionId],
            limit: 1);
        if (rows.isNotEmpty) {
          _unidadNombre = rows.first['nombre']?.toString();
        }
      }
    } catch (_) {}

    await _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    if (_unidadGestionId == null) {
      setState(() {
        _datos = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final datos = await _service.comparativaVsEjecucion(
        anio: _anio,
        unidadGestionId: _unidadGestionId!,
      );

      if (mounted) {
        setState(() {
          _datos = datos;
          _loading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'comparativa_page.cargar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Error al cargar comparativa. Intente nuevamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpLayout(
      title: 'Presupuesto vs Ejecución $_anio',
      currentRoute: '/reportes/comparativa_presupuesto',
      body: ResponsiveContainer(
        maxWidth: 1100,
        child: Column(
          children: [
            _buildSelectorAnio(),
            if (_unidadNombre != null) _buildUnidadHeader(),
            _buildTotalesHeader(),
            Expanded(
              child: _loading
                  ? SkeletonLoader.table(rows: 5, columns: 4)
                  : _datos.isEmpty
                      ? const EmptyState(
                          icon: Icons.inbox,
                          title: 'No hay datos para comparar',
                        )
                      : _buildTabla(),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────── Selector de Año ───────────
  Widget _buildSelectorAnio() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() => _anio--);
              _cargarDatos();
            },
          ),
          Text(
            '$_anio',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _anio >= DateTime.now().year
                ? null
                : () {
                    setState(() => _anio++);
                    _cargarDatos();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() => _anio = DateTime.now().year);
              _cargarDatos();
            },
            tooltip: 'Año actual',
          ),
        ],
      ),
    );
  }

  Widget _buildUnidadHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: Colors.purple.shade50,
      child: Text(
        _unidadNombre!,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.purple,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─────────── Totales acumulados ───────────
  Widget _buildTotalesHeader() {
    if (_datos.isEmpty) return const SizedBox.shrink();

    double totalPresIng = 0, totalPresEgr = 0;
    double totalRealIng = 0, totalRealEgr = 0;

    for (final d in _datos) {
      totalPresIng += (d['presupuesto_ingresos'] as num?)?.toDouble() ?? 0.0;
      totalPresEgr += (d['presupuesto_egresos'] as num?)?.toDouble() ?? 0.0;
      totalRealIng += (d['real_ingresos'] as num?)?.toDouble() ?? 0.0;
      totalRealEgr += (d['real_egresos'] as num?)?.toDouble() ?? 0.0;
    }

    final desvioIng = totalRealIng - totalPresIng;
    final desvioEgr = totalRealEgr - totalPresEgr;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: _miniKpi(
              'Desvío Ingresos',
              Format.money(desvioIng),
              desvioIng >= 0 ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniKpi(
              'Desvío Egresos',
              Format.money(desvioEgr),
              // Para egresos, un desvío negativo (gastamos menos) es BUENO
              desvioEgr <= 0 ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniKpi(
              'Ejecución Ing.',
              totalPresIng > 0
                  ? '${(totalRealIng / totalPresIng * 100).toStringAsFixed(0)}%'
                  : '—',
              Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniKpi(
              'Ejecución Egr.',
              totalPresEgr > 0
                  ? '${(totalRealEgr / totalPresEgr * 100).toStringAsFixed(0)}%'
                  : '—',
              Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniKpi(String label, String value, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────── Tabla comparativa ───────────
  Widget _buildTabla() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Card(
          elevation: 3,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(Colors.deepPurple.shade50),
              border: TableBorder.all(color: Colors.grey.shade300, width: 1),
              columnSpacing: 16,
              columns: const [
                DataColumn(
                    label:
                        Text('Mes', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Pres. Ing.',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
                DataColumn(
                    label: Text('Real Ing.',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
                DataColumn(
                    label: Text('Desvío',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
                DataColumn(
                    label: Text('Pres. Egr.',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
                DataColumn(
                    label: Text('Real Egr.',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
                DataColumn(
                    label: Text('Desvío',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
              ],
              rows: _datos.map((d) {
                final mes = d['mes'] as int;
                final mesNombre = DateFormat('MMM', 'es_AR')
                    .format(DateTime(_anio, mes));
                final presIng =
                    (d['presupuesto_ingresos'] as num?)?.toDouble() ?? 0.0;
                final realIng =
                    (d['real_ingresos'] as num?)?.toDouble() ?? 0.0;
                final desvIng =
                    (d['desvio_ingresos'] as num?)?.toDouble() ?? 0.0;
                final presEgr =
                    (d['presupuesto_egresos'] as num?)?.toDouble() ?? 0.0;
                final realEgr =
                    (d['real_egresos'] as num?)?.toDouble() ?? 0.0;
                final desvEgr =
                    (d['desvio_egresos'] as num?)?.toDouble() ?? 0.0;

                return DataRow(cells: [
                  DataCell(Text(
                    '${mesNombre[0].toUpperCase()}${mesNombre.substring(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )),
                  DataCell(Text(Format.money(presIng),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600))),
                  DataCell(Text(Format.money(realIng),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.green))),
                  DataCell(Text(
                    _formatDesvio(desvIng),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: desvIng >= 0 ? Colors.green : Colors.red,
                    ),
                  )),
                  DataCell(Text(Format.money(presEgr),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600))),
                  DataCell(Text(Format.money(realEgr),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.red))),
                  DataCell(Text(
                    _formatDesvio(desvEgr),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      // Para egresos, desvío negativo = gastamos menos = bueno
                      color: desvEgr <= 0 ? Colors.green : Colors.red,
                    ),
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDesvio(double valor) {
    final prefix = valor >= 0 ? '+' : '';
    return '$prefix${Format.money(valor)}';
  }
}
