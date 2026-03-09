import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/dao/evento_dao.dart';
import '../../../layout/erp_layout.dart';
import '../../shared/format.dart';
import '../../shared/widgets/breadcrumb.dart';
import '../../shared/state/app_settings.dart';
import '../../tesoreria/pages/crear_movimiento_page.dart';
import 'crear_evento_cdm_page.dart';
import 'asistencia_partido_page.dart';

/// Pantalla de detalle de un evento del club.
/// Muestra movimientos asociados, KPIs y acciones rápidas.
class EventoCdmDetallePage extends StatefulWidget {
  final Map<String, dynamic> evento;

  const EventoCdmDetallePage({super.key, required this.evento});

  @override
  State<EventoCdmDetallePage> createState() => _EventoCdmDetallePageState();
}

class _EventoCdmDetallePageState extends State<EventoCdmDetallePage> {
  List<Map<String, dynamic>> _movimientos = [];
  Map<String, dynamic>? _eventoActual;
  bool _cargando = true;
  bool _guardandoEstado = false;

  @override
  void initState() {
    super.initState();
    _eventoActual = Map.from(widget.evento);
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarDatos());
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final eventoId = _eventoActual!['id'] as int;

    // Cargar movimientos (operación crítica — siempre debe actualizar la lista)
    List<Map<String, dynamic>> movs = [];
    try {
      movs = await EventoDao.getMovimientosByEventoCdm(eventoId);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'evento_cdm_detalle.cargar_movimientos',
        error: e.toString(),
        stackTrace: st,
        payload: {'evento_id': eventoId},
      );
    }

    // Refrescar cabecera del evento (operación opcional — no bloquea la lista)
    Map<String, dynamic>? eventoFresh;
    try {
      eventoFresh = await EventoDao.getEventoById(eventoId);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'evento_cdm_detalle.cargar_evento',
        error: e.toString(),
        stackTrace: st,
        payload: {'evento_id': eventoId},
      );
    }

    if (!mounted) return;
    setState(() {
      _movimientos = movs;
      if (eventoFresh != null) _eventoActual = eventoFresh;
      _cargando = false;
    });
  }

  double get _totalIngresos => _movimientos
      .where((m) => m['tipo'] == 'INGRESO')
      .fold(0.0, (s, m) => s + ((m['monto'] as num?)?.toDouble() ?? 0.0));

  double get _totalEgresos => _movimientos
      .where((m) => m['tipo'] == 'EGRESO')
      .fold(0.0, (s, m) => s + ((m['monto'] as num?)?.toDouble() ?? 0.0));

  @override
  Widget build(BuildContext context) {
    final titulo = _eventoActual!['titulo'] as String? ?? 'Evento';
    final tipo = _eventoActual!['tipo'] as String? ?? 'OTRO';
    final esPartido = tipo == 'PARTIDO';
    final estado = _eventoActual!['estado'] as String? ?? 'PROGRAMADO';
    final esProgramado = estado == 'PROGRAMADO';

    return ErpLayout(
      currentRoute: '/evento_cdm_detalle',
      title: titulo,
      actions: [
        IconButton(
          tooltip: 'Editar evento',
          icon: const Icon(Icons.edit_outlined),
          onPressed: _abrirEdicion,
        ),
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
          onPressed: _cargarDatos,
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Breadcrumb(
              items: [
                BreadcrumbItem(
                  label: 'Eventos',
                  icon: Icons.event,
                  onTap: () => Navigator.of(context).pop(),
                ),
                BreadcrumbItem(label: titulo),
              ],
            ),
          ),
          _buildHeader(tipo, estado),
          if (_cargando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            _buildKpis(),
            _buildBotonesAccion(esPartido, esProgramado),
            Expanded(child: _buildListaMovimientos()),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarMovimiento,
        icon: const Icon(Icons.add),
        label: const Text('Agregar movimiento'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildHeader(String tipo, String estado) {
    final fecha = _eventoActual!['fecha'] as String? ?? '';
    final rival = _eventoActual!['rival'] as String?;
    final localidad = _eventoActual!['localidad'] as String?;
    final lugar = _eventoActual!['lugar'] as String?;
    final descripcion = _eventoActual!['descripcion'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_iconoTipo(tipo), style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _eventoActual!['titulo'] as String? ?? '',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    if (fecha.isNotEmpty)
                      Text(fecha, style: AppText.caption),
                  ],
                ),
              ),
              _buildEstadoBadge(estado),
            ],
          ),
          if (tipo == 'PARTIDO' && (rival != null || localidad != null || lugar != null)) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              children: [
                if (localidad != null)
                  Text(localidad == 'LOCAL' ? '🏠 Local' : '✈ Visitante', style: AppText.caption),
                if (rival != null) Text('vs $rival', style: AppText.caption),
                if (lugar != null) Text('📍 $lugar', style: AppText.caption),
              ],
            ),
          ],
          if (descripcion != null && descripcion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(descripcion, style: AppText.caption),
          ],
        ],
      ),
    );
  }

  Widget _buildKpis() {
    final balance = _totalIngresos - _totalEgresos;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _buildKpi('Movimientos', '${_movimientos.length}', Icons.receipt_long, Colors.blue),
          const SizedBox(width: 8),
          _buildKpi('Ingresos', Format.money(_totalIngresos), Icons.arrow_downward, AppColors.ingreso),
          const SizedBox(width: 8),
          _buildKpi('Egresos', Format.money(_totalEgresos), Icons.arrow_upward, AppColors.egreso),
          const SizedBox(width: 8),
          _buildKpi('Balance', Format.money(balance), Icons.account_balance,
              balance >= 0 ? AppColors.ingreso : AppColors.egreso),
        ],
      ),
    );
  }

  Widget _buildKpi(String label, String valor, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 4),
              Text(valor,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                  overflow: TextOverflow.ellipsis),
              Text(label, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBotonesAccion(bool esPartido, bool esProgramado) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (esPartido)
            OutlinedButton.icon(
              icon: const Icon(Icons.people_outline),
              label: const Text('Asistencia'),
              onPressed: _abrirAsistencia,
            ),
          if (esProgramado)
            OutlinedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Marcar realizado'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.ingreso),
              onPressed: _marcarRealizado,
            ),
        ],
      ),
    );
  }

  Widget _buildListaMovimientos() {
    if (_movimientos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('Sin movimientos registrados',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Usá el botón + para agregar ingresos o egresos de este evento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final ingresos = _movimientos.where((m) => m['tipo'] == 'INGRESO').toList();
    final egresos = _movimientos.where((m) => m['tipo'] == 'EGRESO').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (ingresos.isNotEmpty) ...[
          _buildSubtituloSeccion('Ingresos', AppColors.ingreso),
          ...ingresos.map((m) => _MovimientoCard(mov: m, onRefresh: _cargarDatos)),
          const SizedBox(height: 16),
        ],
        if (egresos.isNotEmpty) ...[
          _buildSubtituloSeccion('Egresos', AppColors.egreso),
          ...egresos.map((m) => _MovimientoCard(mov: m, onRefresh: _cargarDatos)),
        ],
      ],
    );
  }

  Widget _buildSubtituloSeccion(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildEstadoBadge(String estado) {
    Color color;
    String label;
    switch (estado) {
      case 'REALIZADO':
        color = AppColors.ingreso;
        label = 'Realizado';
        break;
      case 'CANCELADO':
        color = AppColors.egreso;
        label = 'Cancelado';
        break;
      default:
        color = AppColors.advertencia;
        label = 'Programado';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  String _iconoTipo(String tipo) {
    const m = {'PARTIDO': '⚽', 'CENA': '🍽', 'TORNEO': '🏆', 'OTRO': '📌'};
    return m[tipo] ?? '📌';
  }

  Future<void> _agregarMovimiento() async {
    final eventoId = _eventoActual!['id'] as int;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CrearMovimientoPage(eventoCdmIdInicial: eventoId),
      ),
    );
    // Siempre recargar al volver, independientemente de si se guardó o no
    if (mounted) _cargarDatos();
  }

  Future<void> _abrirEdicion() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CrearEventoCdmPage(eventoExistente: _eventoActual),
      ),
    );
    if (result == true) _cargarDatos();
  }

  Future<void> _abrirAsistencia() async {
    final settings = context.read<AppSettings>();
    final unidadId = settings.unidadGestionActivaId;
    if (unidadId == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AsistenciaPartidoPage(
          evento: _eventoActual!,
          unidadGestionId: unidadId,
        ),
      ),
    );
    if (result == true) _cargarDatos();
  }

  Future<void> _marcarRealizado() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como realizado'),
        content: const Text('¿Querés marcar este evento como REALIZADO? Esta acción no bloquea ediciones futuras.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _guardandoEstado = true);
    try {
      await EventoDao.updateEstadoEvento(_eventoActual!['id'] as int, 'REALIZADO');
      if (!mounted) return;
      setState(() {
        _eventoActual = {..._eventoActual!, 'estado': 'REALIZADO'};
        _guardandoEstado = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Evento marcado como Realizado'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'evento_cdm_detalle.marcar_realizado',
        error: e.toString(),
        stackTrace: st,
        payload: {'evento_id': _eventoActual!['id']},
      );
      if (mounted) {
        setState(() => _guardandoEstado = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo actualizar el estado. Intentá nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ─── Card de movimiento ───

class _MovimientoCard extends StatelessWidget {
  final Map<String, dynamic> mov;
  final VoidCallback onRefresh;

  const _MovimientoCard({required this.mov, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final tipo = mov['tipo'] as String? ?? 'INGRESO';
    final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;
    final categoria = mov['categoria'] as String? ?? '–';
    final categoriaNombre = mov['categoria_nombre'] as String? ?? categoria;
    final medioPago = mov['medio_pago_desc'] as String? ?? '–';
    final fecha = mov['fecha'] as String? ?? '';
    final obs = mov['observacion'] as String?;
    final entidad = mov['entidad_nombre'] as String?;
    final color = tipo == 'INGRESO' ? AppColors.ingreso : AppColors.egreso;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(
            tipo == 'INGRESO' ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
            size: 18,
          ),
        ),
        title: Text(
          Format.money(monto),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: Text(
          [categoriaNombre, medioPago, if (entidad != null) entidad, if (obs != null) obs].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(fecha, style: AppText.caption),
      ),
    );
  }
}
