import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _formatter = NumberFormat.currency(locale: 'es_AR', symbol: '\$');
/// Usar [Format.money] en código nuevo.
@Deprecated('Usar Format.money() en código nuevo')
String formatCurrency(num value) => _formatter.format(value);

final _formatter0 =
  NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);
/// Usar [Format.moneyNoDecimals] en código nuevo.
@Deprecated('Usar Format.moneyNoDecimals() en código nuevo')
String formatCurrencyNoDecimals(num value) => _formatter0.format(value);

double parseCurrencyToDouble(String text) {
  // Mantener sólo dígitos para un parser estable (2 decimales)
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0.0;
  final value = double.parse(digits) / 100.0;
  return value;
}

// Parser laxo para números sin formateo de moneda (admite "1234", "1234,50", "1234.50")
double parseLooseDouble(String text) {
  final match = RegExp(r'[-+]?\d+(?:[\.,]\d+)?').firstMatch(text.trim());
  if (match == null) return 0.0;
  final raw = match.group(0)!;
  final norm = raw.replaceAll(',', '.');
  return double.tryParse(norm) ?? 0.0;
}

/// Clase utilitaria para formateo centralizado (moneda, fecha, números).
class Format {
  // ───── Moneda ─────

  /// Formatea un número como moneda con 2 decimales (ej. `$1.234,56`).
  static String money(num value) => formatCurrency(value);

  /// Formatea un número como moneda sin decimales (ej. `$1.235`).
  static String moneyNoDecimals(num value) => formatCurrencyNoDecimals(value);

  /// Formato corto de moneda para espacios reducidos:
  /// - Menos de 1000 → `$500`
  /// - Miles → `$1,2k`
  /// - Millones → `$1,5M`
  static String moneyShort(num value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 1000000) {
      final m = abs / 1000000;
      return '$sign\$${m.toStringAsFixed(m.truncateToDouble() == m ? 0 : 1)}M';
    } else if (abs >= 1000) {
      final k = abs / 1000;
      return '$sign\$${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    } else {
      return '$sign\$${abs.toStringAsFixed(0)}';
    }
  }

  // ───── Fechas ─────

  static final _dfFecha = DateFormat('dd/MM/yyyy');
  static final _dfFechaHora = DateFormat('dd/MM/yyyy HH:mm');
  static final _dfMesCorto = DateFormat('MMM', 'es_AR');
  static final _dfMesLargo = DateFormat('MMMM yyyy', 'es_AR');
  static final _dfFechaDb = DateFormat('yyyy-MM-dd');

  /// Fecha para UI: `25/06/2025`.
  static String fecha(DateTime d) => _dfFecha.format(d);

  /// Fecha + hora para UI: `25/06/2025 14:30`.
  static String fechaHora(DateTime d) => _dfFechaHora.format(d);

  /// Nombre corto del mes capitalizado: `Jun`.
  static String mesCorto(DateTime d) {
    final s = _dfMesCorto.format(d);
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  /// Mes largo + año: `junio 2025`.
  static String mesAnio(DateTime d) => _dfMesLargo.format(d);

  /// Nombre del mes (1-12) en español: `Enero`, `Febrero`, …
  static String mes(int m) {
    const nombres = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    if (m < 1 || m > 12) return '';
    return nombres[m - 1];
  }

  /// Fecha en formato DB: `2025-06-25`.
  static String fechaDb(DateTime d) => _dfFechaDb.format(d);

  // ───── Números ─────

  static final _nfEntero = NumberFormat('#,##0', 'es_AR');
  static final _nfDecimal = NumberFormat('#,##0.00', 'es_AR');

  /// Número entero con separador de miles: `1.234`.
  static String numero(num value) => _nfEntero.format(value);

  /// Número con 2 decimales y separador de miles: `1.234,56`.
  static String decimal(num value) => _nfDecimal.format(value);

  // ───── Porcentaje ─────

  /// Formatea un número como porcentaje: `85,3%`.
  static String porcentaje(num value, {int decimales = 1}) {
    return '${value.toStringAsFixed(decimales).replaceAll('.', ',')}%';
  }

  // ───── Parseo ─────

  /// Parsea una fecha YYYY-MM-DD a DateTime (null si falla).
  static DateTime? parseFecha(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat numberFormat;
  CurrencyInputFormatter({String locale = 'es_AR', String symbol = '\$'})
      : numberFormat = NumberFormat.currency(locale: locale, symbol: symbol);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Permitir vaciar el campo: si no quedan dígitos, devolver texto vacío
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final value = double.parse(digits) / 100.0;
    final newText = numberFormat.format(value);
    return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length));
  }
}
