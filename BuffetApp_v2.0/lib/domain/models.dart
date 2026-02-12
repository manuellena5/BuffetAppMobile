class Categoria {
  final int id;
  final String descripcion;
  Categoria(this.id, this.descripcion);
}

class MetodoPago {
  final int id;
  final String descripcion;
  MetodoPago(this.id, this.descripcion);
}

class Producto {
  final int id;
  final String? codigo;
  final String nombre;
  final int? precioCompra;
  final int precioVenta;
  final int stockActual;
  final int stockMinimo;
  final int? categoriaId;
  final int visible;
  final String? color;
  Producto(
      {required this.id,
      this.codigo,
      required this.nombre,
      this.precioCompra,
      required this.precioVenta,
      this.stockActual = 0,
      this.stockMinimo = 3,
      this.categoriaId,
      this.visible = 1,
      this.color});
}

class Caja {
  final int id;
  final String codigoCaja;
  final String? disciplina;
  final String fecha;
  final String usuarioApertura;
  final String horaApertura;
  final String? aperturaDt;
  final double fondoInicial;
  final String estado;
  final double ingresos;
  final double retiros;
  final double? diferencia;
  final int? totalTickets;
  final String? horaCierre;
  final String? cierreDt;
  final String? obsApertura;
  final String? obsCierre;
  Caja(
      {required this.id,
      required this.codigoCaja,
      this.disciplina,
      required this.fecha,
      required this.usuarioApertura,
      required this.horaApertura,
      this.aperturaDt,
      required this.fondoInicial,
      required this.estado,
      this.ingresos = 0,
      this.retiros = 0,
      this.diferencia,
      this.totalTickets,
      this.horaCierre,
      this.cierreDt,
      this.obsApertura,
      this.obsCierre});
}

class Venta {
  final int id;
  final String uuid;
  final String fechaHora;
  final double total;
  final String status;
  final int activo;
  final int metodoPagoId;
  final int cajaId;
  Venta(
      {required this.id,
      required this.uuid,
      required this.fechaHora,
      required this.total,
      this.status = 'No impreso',
      this.activo = 1,
      required this.metodoPagoId,
      required this.cajaId});
}

class VentaItem {
  final int id;
  final int ventaId;
  final int productoId;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;
  VentaItem(
      {required this.id,
      required this.ventaId,
      required this.productoId,
      required this.cantidad,
      required this.precioUnitario,
      required this.subtotal});
}

class Movimiento {
  final int id;
  final int cajaId;
  final String tipo;
  final double monto;
  final String? observacion;
  final String creadoTs;
  Movimiento(
      {required this.id,
      required this.cajaId,
      required this.tipo,
      required this.monto,
      this.observacion,
      required this.creadoTs});
}

/// Saldo Inicial: representa el balance disponible al comienzo de un período
/// (anual o mensual). NO se registra como movimiento.
/// Se usa como base para el cálculo del saldo del primer mes del período.
class SaldoInicial {
  final int id;
  final int unidadGestionId;
  final String periodoTipo; // 'ANIO' | 'MES'
  final String periodoValor; // '2026' o '2026-01'
  final double monto;
  final String? observacion;
  final String fechaCarga; // YYYY-MM-DD HH:MM:SS

  SaldoInicial({
    required this.id,
    required this.unidadGestionId,
    required this.periodoTipo,
    required this.periodoValor,
    required this.monto,
    this.observacion,
    required this.fechaCarga,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'unidad_gestion_id': unidadGestionId,
      'periodo_tipo': periodoTipo,
      'periodo_valor': periodoValor,
      'monto': monto,
      'observacion': observacion,
      'fecha_carga': fechaCarga,
    };
  }

  factory SaldoInicial.fromMap(Map<String, dynamic> map) {
    return SaldoInicial(
      id: map['id'] as int,
      unidadGestionId: map['unidad_gestion_id'] as int,
      periodoTipo: map['periodo_tipo'] as String,
      periodoValor: map['periodo_valor'] as String,
      monto: (map['monto'] as num).toDouble(),
      observacion: map['observacion'] as String?,
      fechaCarga: map['fecha_carga'] as String,
    );
  }
}

/// Cuenta de Fondos: representa una cuenta bancaria, billetera digital,
/// caja de efectivo o inversión. El saldo se calcula dinámicamente.
class CuentaFondos {
  final int id;
  final String nombre;
  final String tipo; // 'BANCO' | 'BILLETERA' | 'CAJA' | 'INVERSION'
  final int unidadGestionId;
  final double saldoInicial;
  final bool tieneComision;
  final double? comisionPorcentaje;
  final bool activa;
  final String? observaciones;
  final String? moneda;
  final String? bancoNombre;
  final String? cbuAlias;
  final String? dispositivoId;
  final bool eliminado;
  final String syncEstado;
  final int createdTs;
  final int? updatedTs;

  CuentaFondos({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.unidadGestionId,
    required this.saldoInicial,
    required this.tieneComision,
    this.comisionPorcentaje,
    required this.activa,
    this.observaciones,
    this.moneda,
    this.bancoNombre,
    this.cbuAlias,
    this.dispositivoId,
    required this.eliminado,
    required this.syncEstado,
    required this.createdTs,
    this.updatedTs,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'tipo': tipo,
      'unidad_gestion_id': unidadGestionId,
      'saldo_inicial': saldoInicial,
      'tiene_comision': tieneComision ? 1 : 0,
      'comision_porcentaje': comisionPorcentaje,
      'activa': activa ? 1 : 0,
      'observaciones': observaciones,
      'moneda': moneda,
      'banco_nombre': bancoNombre,
      'cbu_alias': cbuAlias,
      'dispositivo_id': dispositivoId,
      'eliminado': eliminado ? 1 : 0,
      'sync_estado': syncEstado,
      'created_ts': createdTs,
      'updated_ts': updatedTs,
    };
  }

  factory CuentaFondos.fromMap(Map<String, dynamic> map) {
    return CuentaFondos(
      id: map['id'] as int,
      nombre: map['nombre'] as String,
      tipo: map['tipo'] as String,
      unidadGestionId: map['unidad_gestion_id'] as int,
      saldoInicial: (map['saldo_inicial'] as num?)?.toDouble() ?? 0.0,
      tieneComision: (map['tiene_comision'] as int?) == 1,
      comisionPorcentaje: (map['comision_porcentaje'] as num?)?.toDouble(),
      activa: (map['activa'] as int?) == 1,
      observaciones: map['observaciones'] as String?,
      moneda: map['moneda'] as String?,
      bancoNombre: map['banco_nombre'] as String?,
      cbuAlias: map['cbu_alias'] as String?,
      dispositivoId: map['dispositivo_id'] as String?,
      eliminado: (map['eliminado'] as int?) == 1,
      syncEstado: map['sync_estado'] as String? ?? 'PENDIENTE',
      createdTs: map['created_ts'] as int,
      updatedTs: map['updated_ts'] as int?,
    );
  }

  /// Calcula el saldo actual de la cuenta en base a:
  /// saldo_inicial + ingresos_confirmados - egresos_confirmados
  /// 
  /// IMPORTANTE: Las transferencias NO afectan el saldo total del sistema,
  /// solo mueven dinero entre cuentas.
  Future<double> calcularSaldoActual(dynamic db) async {
    final result = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN tipo='INGRESO' THEN monto ELSE 0 END), 0) as ingresos,
        COALESCE(SUM(CASE WHEN tipo='EGRESO' THEN monto ELSE 0 END), 0) as egresos
      FROM evento_movimiento
      WHERE cuenta_id = ? 
        AND estado = 'CONFIRMADO'
        AND eliminado = 0
    ''', [id]);
    
    final ingresos = (result[0]['ingresos'] as num?)?.toDouble() ?? 0.0;
    final egresos = (result[0]['egresos'] as num?)?.toDouble() ?? 0.0;
    
    return saldoInicial + ingresos - egresos;
  }

  /// Calcula el monto de comisión bancaria para un movimiento
  double? calcularComision(double monto) {
    if (!tieneComision || comisionPorcentaje == null || comisionPorcentaje! <= 0) {
      return null;
    }
    return monto * (comisionPorcentaje! / 100);
  }
}
