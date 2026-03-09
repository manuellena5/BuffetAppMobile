import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/dao/evento_dao.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_header.dart';
import '../../shared/format.dart';
import '../../shared/state/app_settings.dart';
import 'evento_cdm_detalle_page.dart';
import 'crear_evento_cdm_page.dart';

/// Pantalla de Fixture: muestra solo los PARTIDOS del mes seleccionado
/// con proyección de costos (pagado + estimado por acuerdos POR_EVENTO activos).
class FixturePage extends StatefulWidget {
  const FixturePage({super.key});

  @override
  State<FixturePage> createState() => _FixturePageState();
}

class _FixturePageState extends State<FixturePage> {
  List<Map<String, dynamic>> _partidos = [];
  bool _cargando = true;
  DateTime _mesSeleccionado = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarPartidos());
  }

  Future<void> _cargarPartidos() async {
    setState(() => _cargando = true);
    try {
      final settings = context.read<AppSettings>();
      final unidadId = settings.unidadGestionActivaId;
      if (unidadId == null) {
        setState(() {
          _partidos = [];
          _cargando = false;
        });
        return;
      }
      final mesStr = '${_mesSeleccionado.year}-${_mesSeleccionado.month.toString().padLeft(2, '0')}';
      final eventos = await EventoDao.getEventosByMes(unidadId, mesStr);
      if (!mounted) return;
      setState(() {
        _partidos = eventos.where((e) => e['tipo'] == 'PARTIDO').toList()
          ..sort((a, b) {
            final fa = a['fecha'] as String? ?? '';
            final fb = b['fecha'] as String? ?? '';
            return fa.compareTo(fb);
          });
        _cargando = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'fixture.cargar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarMes(int delta) async {
    final nuevo = DateTime(_mesSeleccionado.year, _mesSeleccionado.month + delta);
    setState(() => _mesSeleccionado = nuevo);
    await _cargarPartidos();
  }

  double get _totalPagado => _partidos.fold(0.0, (s, p) {
        final egresos = (p['total_egresos'] as num?)?.toDouble() ?? 0.0;
        return s + egresos;
      });

  double get _totalIngresos => _partidos.fold(0.0, (s, p) {
        final ingresos = (p['total_ingresos'] as num?)?.toDouble() ?? 0.0;
        return s + ingresos;
      });

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;
    return ErpLayout(
      currentRoute: '/fixture',
      title: 'Fixture',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarPartido,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo partido'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: [
          if (isDesktop) const AppHeader(title: 'Fixture'),
          _buildNavMes(),
          _buildResumenMes(),
          if (_cargando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_partidos.isEmpty)
            Expanded(child: _buildEstadoVacio())
          else
            Expanded(child: _buildListaPartidos()),
        ],
      ),
    );
  }

  Widget _buildNavMes() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _cambiarMes(-1),
          ),
          Expanded(
            child: Text(
              Format.mesAnio(_mesSeleccionado),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _cambiarMes(1),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarPartidos,
          ),
        ],
      ),
    );
  }

  Widget _buildResumenMes() {
    final balance = _totalIngresos - _totalPagado;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildKpi('Partidos', '${_partidos.length}', Icons.sports_soccer, Colors.blue),
          const SizedBox(width: 8),
          _buildKpi('Ingresos', Format.money(_totalIngresos), Icons.arrow_downward, AppColors.ingreso),
          const SizedBox(width: 8),
          _buildKpi('Egresos', Format.money(_totalPagado), Icons.arrow_upward, AppColors.egreso),
          const SizedBox(width: 8),
          _buildKpi('Balance', Format.money(balance), Icons.account_balance,
              balance >= 0 ? AppColors.ingreso : AppColors.egreso),
        ],
      ),
    );
  }

  Widget _buildKpi(String label, String valor, IconData icono, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Icon(icono, size: 16, color: color),
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

  Widget _buildListaPartidos() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _partidos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        try {
          final partido = _partidos[index];
          return _PartidoCard(
            partido: partido,
            onTap: () => _abrirDetalle(partido),
          );
        } catch (e, st) {
          AppDatabase.logLocalError(
            scope: 'fixture.render_partido',
            error: e.toString(),
            stackTrace: st,
            payload: {'index': index},
          );
          return const Card(
            child: ListTile(leading: Icon(Icons.warning), title: Text('Error al mostrar partido')),
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
            const Text('Sin partidos este mes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Usá el botón + para cargar los partidos del mes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirDetalle(Map<String, dynamic> partido) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EventoCdmDetallePage(evento: partido)),
    );
    if (result == true) _cargarPartidos();
  }

  Future<void> _agregarPartido() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const CrearEventoCdmPage(),
      ),
    );
    if (result == true) _cargarPartidos();
  }
}

// ─── Card de partido ───

class _PartidoCard extends StatelessWidget {
  final Map<String, dynamic> partido;
  final VoidCallback onTap;

  const _PartidoCard({required this.partido, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final titulo = partido['titulo'] as String? ?? 'Partido';
    final fecha = partido['fecha'] as String? ?? '';
    final estado = partido['estado'] as String? ?? 'PROGRAMADO';
    final localidad = partido['localidad'] as String?;
    final rival = partido['rival'] as String?;
    final totalIngresos = (partido['total_ingresos'] as num?)?.toDouble() ?? 0.0;
    final totalEgresos = (partido['total_egresos'] as num?)?.toDouble() ?? 0.0;
    final balance = totalIngresos - totalEgresos;
    final esProgramado = estado == 'PROGRAMADO';

    Color estadoColor;
    switch (estado) {
      case 'REALIZADO':
        estadoColor = AppColors.ingreso;
        break;
      case 'CANCELADO':
        estadoColor = AppColors.egreso;
        break;
      default:
        estadoColor = AppColors.advertencia;
    }

    return Card(
      elevation: esProgramado ? 2 : 1,
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
                  const Text('⚽', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                        if (rival != null || localidad != null)
                          Text(
                            [
                              if (localidad != null) localidad == 'LOCAL' ? '🏠 Local' : '✈ Visitante',
                              if (rival != null) 'vs $rival',
                            ].join(' · '),
                            style: AppText.caption,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: estadoColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: estadoColor.withOpacity(0.5)),
                    ),
                    child: Text(
                      estado == 'PROGRAMADO'
                          ? 'Programado'
                          : estado == 'REALIZADO'
                              ? 'Realizado'
                              : 'Cancelado',
                      style: TextStyle(fontSize: 11, color: estadoColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const Divider(height: 14),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(fecha, style: AppText.caption),
                  const Spacer(),
                  // Barra de progreso ingreso/egreso
                  if (totalIngresos > 0 || totalEgresos > 0) ...[
                    Text('↓ ${Format.money(totalIngresos)}',
                        style: TextStyle(fontSize: 12, color: AppColors.ingreso)),
                    const SizedBox(width: 8),
                    Text('↑ ${Format.money(totalEgresos)}',
                        style: TextStyle(fontSize: 12, color: AppColors.egreso)),
                    const SizedBox(width: 8),
                    Text(
                      Format.money(balance),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: balance >= 0 ? AppColors.ingreso : AppColors.egreso,
                      ),
                    ),
                  ] else
                    Text('Sin movimientos', style: AppText.caption),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
