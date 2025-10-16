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
