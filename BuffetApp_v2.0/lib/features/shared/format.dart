import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _formatter = NumberFormat.currency(locale: 'es_AR', symbol: '\$');
String formatCurrency(num value) => _formatter.format(value);

final _formatter0 =
  NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);
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

/// Clase utilitaria para formateo de moneda
class Format {
  /// Formatea un número como moneda con 2 decimales
  static String money(num value) => formatCurrency(value);
  
  /// Formatea un número como moneda sin decimales
  static String moneyNoDecimals(num value) => formatCurrencyNoDecimals(value);
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
