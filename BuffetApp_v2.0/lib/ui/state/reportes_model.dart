import 'package:flutter/foundation.dart';
import '../../services/reportes_service.dart';

/// Tipo de agregación temporal para agrupar ventas.
enum AggregacionFecha { dia, mes, anio }

extension AggregacionFechaExt on AggregacionFecha {
  String get label {
    switch (this) {
      case AggregacionFecha.dia:
        return 'Día';
      case AggregacionFecha.mes:
        return 'Mes';
      case AggregacionFecha.anio:
        return 'Año';
    }
  }
}

class PeriodoVentas {
  final String periodo; // ej: 2025-07 o 2025-07-14
  final double totalVentas;
  PeriodoVentas({required this.periodo, required this.totalVentas});
}

class ProductoRanking {
  final int productoId;
  final String nombre;
  final int unidades;
  final double importe;
  ProductoRanking({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.importe,
  });
}

class MetodoPagoVentas {
  final String metodo;
  final double importe;
  MetodoPagoVentas({required this.metodo, required this.importe});
}

class ReportesKpis {
  final double totalVentas;
  final double ticketPromedio;
  final int cantidadVentas;
  final int ticketsActivos; // tickets no anulados
  final int ticketsAnulados;
  final int totalEntradasCount; // posible interpretación 1: cantidad tickets
  final double totalEntradasImporte; // posible interpretación 2: suma importe tickets
  ReportesKpis({
    required this.totalVentas,
    required this.ticketPromedio,
    required this.cantidadVentas,
    required this.ticketsActivos,
    required this.ticketsAnulados,
    required this.totalEntradasCount,
    required this.totalEntradasImporte,
  });
}

class ReportesModel extends ChangeNotifier {
  final ReportesService _service = ReportesService();

  DateTime? desde; // límite inferior rango
  DateTime? hasta; // límite superior rango
  AggregacionFecha agregacion = AggregacionFecha.mes;
  String? disciplina; // filtro disciplina caja_diaria

  bool loading = false;
  List<String> disciplinasDisponibles = [];
  List<DateTime> fechasCajas = [];

  List<PeriodoVentas> serie = [];
  ReportesKpis? kpis;
  List<MetodoPagoVentas> ventasPorMetodo = [];
  List<ProductoRanking> rankingProductos = [];

  Future<void> inicializar() async {
    loading = true;
    notifyListeners();
    fechasCajas = await _service.obtenerFechasCajas();
    disciplinasDisponibles = await _service.obtenerDisciplinas();
    if (fechasCajas.isNotEmpty) {
      desde = fechasCajas.first;
      hasta = fechasCajas.last;
    }
    await cargarDatos();
  }

  void actualizarFiltros({DateTime? nuevoDesde, DateTime? nuevoHasta, AggregacionFecha? nuevaAgregacion, String? nuevaDisciplina}) {
    if (nuevoDesde != null) desde = nuevoDesde;
    if (nuevoHasta != null) hasta = nuevoHasta;
    if (nuevaAgregacion != null) agregacion = nuevaAgregacion;
    disciplina = nuevaDisciplina;
    cargarDatos();
  }

  Future<void> cargarDatos() async {
    if (desde == null || hasta == null) return;
    loading = true;
    notifyListeners();

    serie = await _service.obtenerSerieVentas(
      desde: desde!,
      hasta: hasta!,
      agregacion: agregacion,
      disciplina: disciplina,
    );
    kpis = await _service.obtenerKpis(
      desde: desde!,
      hasta: hasta!,
      disciplina: disciplina,
    );
    ventasPorMetodo = await _service.obtenerVentasPorMetodo(
      desde: desde!,
      hasta: hasta!,
      disciplina: disciplina,
    );
    rankingProductos = await _service.obtenerRankingProductos(
      desde: desde!,
      hasta: hasta!,
      disciplina: disciplina,
      limit: 10,
    );

    loading = false;
    notifyListeners();
  }
}
