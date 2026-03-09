import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/dao/evento_dao.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_header.dart';
import '../../shared/format.dart';
import '../../shared/state/app_settings.dart';
import 'crear_evento_cdm_page.dart';
import 'evento_cdm_detalle_page.dart';

/// Pantalla principal de Eventos del Club. Muestra la lista de eventos
/// filtrada por mes y tipo, con KPIs y acceso rápido a detalle/creación.
class EventosCdmPage extends StatefulWidget {
  const EventosCdmPage({super.key});

  @override
  State<EventosCdmPage> createState() => _EventosCdmPageState();
}

class _EventosCdmPageState extends State<EventosCdmPage> {
  List<Map<String, dynamic>> _eventos = [];
  bool _cargando = true;

  DateTime _mesSeleccionado = DateTime(DateTime.now().year, DateTime.now().month);
  String? _filtroTipo; // null = todos
  String? _filtroEstado; // null = todos

  static const _tipos = ['PARTIDO', 'CENA', 'TORNEO', 'OTRO'];
  static const _estados = ['PROGRAMADO', 'REALIZADO', 'CANCELADO'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarEventos());
  }

  Future<void> _cargarEventos() async {
    setState(() => _cargando = true);
    try {
      final settings = context.read<AppSettings>();
      final unidadId = settings.unidadGestionActivaId;
      if (unidadId == null) {
        setState(() {
          _eventos = [];
          _cargando = false;
        });
        return;
      }
      final mesStr = '${_mesSeleccionado.year}-${_mesSeleccionado.month.toString().padLeft(2, '0')}';
      final eventos = await EventoDao.getEventosByMes(unidadId, mesStr);
      if (!mounted) return;
      setState(() {
        _eventos = eventos;
        _cargando = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'eventos_cdm.cargar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _eventosFiltrados {
    return _eventos.where((ev) {
      if (_filtroTipo != null && ev['tipo'] != _filtroTipo) return false;
      if (_filtroEstado != null && ev['estado'] != _filtroEstado) return false;
      return true;
    }).toList();
  }

  double _calcularTotalIngresos() =>
      _eventosFiltrados.fold(0.0, (s, e) => s + ((e['total_ingresos'] as num?)?.toDouble() ?? 0.0));

  double _calcularTotalEgresos() =>
      _eventosFiltrados.fold(0.0, (s, e) => s + ((e['total_egresos'] as num?)?.toDouble() ?? 0.0));

  Future<void> _cambiarMes(int delta) async {
    final nuevo = DateTime(_mesSeleccionado.year, _mesSeleccionado.month + delta);
    setState(() => _mesSeleccionado = nuevo);
    await _cargarEventos();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;
    return ErpLayout(
      currentRoute: '/eventos_cdm',
      title: 'Eventos',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirCrearEvento,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo evento'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: [
          _buildCabecera(),
          _buildFiltros(),
          _buildKpis(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _eventosFiltrados.isEmpty
                    ? _buildEstadoVacio()
                    : _buildListaEventos(),
          ),
        ],
      ),
    );
  }

  Widget _buildCabecera() {
    final mesNombre = Format.mesAnio(_mesSeleccionado);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Mes anterior',
            onPressed: () => _cambiarMes(-1),
          ),
          Expanded(
            child: Text(
              mesNombre,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Mes siguiente',
            onPressed: () => _cambiarMes(1),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargarEventos,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Todos'),
            selected: _filtroTipo == null && _filtroEstado == null,
            onSelected: (_) => setState(() {
              _filtroTipo = null;
              _filtroEstado = null;
            }),
          ),
          const SizedBox(width: 8),
          ..._tipos.map((t) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_labelTipo(t)),
                  selected: _filtroTipo == t,
                  onSelected: (sel) => setState(() => _filtroTipo = sel ? t : null),
                ),
              )),
          const VerticalDivider(width: 16),
          ..._estados.map((e) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_labelEstado(e)),
                  selected: _filtroEstado == e,
                  onSelected: (sel) => setState(() => _filtroEstado = sel ? e : null),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildKpis() {
    final ingresos = _calcularTotalIngresos();
    final egresos = _calcularTotalEgresos();
    final balance = ingresos - egresos;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildKpiCard('Eventos', '${_eventosFiltrados.length}', Icons.event, Colors.blue),
          const SizedBox(width: 8),
          _buildKpiCard('Ingresos', Format.money(ingresos), Icons.arrow_downward, AppColors.ingreso),
          const SizedBox(width: 8),
          _buildKpiCard('Egresos', Format.money(egresos), Icons.arrow_upward, AppColors.egreso),
          const SizedBox(width: 8),
          _buildKpiCard('Balance', Format.money(balance), Icons.account_balance,
              balance >= 0 ? AppColors.ingreso : AppColors.egreso),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String valor, IconData icono, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icono, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 11, color: color)),
              ]),
              const SizedBox(height: 4),
              Text(valor,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaEventos() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _eventosFiltrados.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        try {
          final ev = _eventosFiltrados[index];
          return _EventoCard(
            evento: ev,
            onTap: () => _abrirDetalle(ev),
          );
        } catch (e, st) {
          AppDatabase.logLocalError(
            scope: 'eventos_cdm.render_item',
            error: e.toString(),
            stackTrace: st,
            payload: {'index': index},
          );
          return const Card(
            child: ListTile(
              leading: Icon(Icons.warning),
              title: Text('Error al mostrar evento'),
            ),
          );
        }
      },
    );
  }

  Widget _buildEstadoVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_soccer_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Sin eventos este mes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Usá el botón + para agregar un partido, peña, cena u otro evento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirCrearEvento() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CrearEventoCdmPage()),
    );
    if (result == true) _cargarEventos();
  }

  Future<void> _abrirDetalle(Map<String, dynamic> evento) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EventoCdmDetallePage(evento: evento)),
    );
    if (result == true) _cargarEventos();
  }

  String _labelTipo(String t) {
    const m = {'PARTIDO': '⚽ Partido', 'CENA': '🍽 Cena', 'TORNEO': '🏆 Torneo', 'OTRO': '📌 Otro'};
    return m[t] ?? t;
  }

  String _labelEstado(String e) {
    const m = {'PROGRAMADO': '📅 Programado', 'REALIZADO': '✅ Realizado', 'CANCELADO': '❌ Cancelado'};
    return m[e] ?? e;
  }
}

// ─── Card de evento ───

class _EventoCard extends StatelessWidget {
  final Map<String, dynamic> evento;
  final VoidCallback onTap;

  const _EventoCard({required this.evento, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tipo = evento['tipo'] as String? ?? 'OTRO';
    final titulo = evento['titulo'] as String? ?? 'Sin título';
    final fecha = evento['fecha'] as String? ?? '';
    final estado = evento['estado'] as String? ?? 'PROGRAMADO';
    final rival = evento['rival'] as String?;
    final localidad = evento['localidad'] as String?;
    final totalIngresos = (evento['total_ingresos'] as num?)?.toDouble() ?? 0.0;
    final totalEgresos = (evento['total_egresos'] as num?)?.toDouble() ?? 0.0;
    final balance = totalIngresos - totalEgresos;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_iconoTipo(tipo), style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _EstadoBadge(estado: estado),
                ],
              ),
              if (tipo == 'PARTIDO' && (rival != null || localidad != null)) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if (localidad != null) localidad == 'LOCAL' ? '🏠 Local' : '✈ Visitante',
                    if (rival != null) 'vs $rival',
                  ].join(' · '),
                  style: AppText.caption,
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(fecha, style: AppText.caption),
                  const Spacer(),
                  Text(
                    '↓ ${Format.money(totalIngresos)}',
                    style: TextStyle(fontSize: 12, color: AppColors.ingreso),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '↑ ${Format.money(totalEgresos)}',
                    style: TextStyle(fontSize: 12, color: AppColors.egreso),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Format.money(balance),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: balance >= 0 ? AppColors.ingreso : AppColors.egreso,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _iconoTipo(String tipo) {
    const m = {'PARTIDO': '⚽', 'CENA': '🍽', 'TORNEO': '🏆', 'OTRO': '📌'};
    return m[tipo] ?? '📌';
  }
}

class _EstadoBadge extends StatelessWidget {
  final String estado;
  const _EstadoBadge({required this.estado});

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
