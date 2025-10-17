import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _formatter = NumberFormat.currency(locale: 'es_AR', symbol: '\$');
String formatCurrency(num value) => _formatter.format(value);

double parseCurrencyToDouble(String text) {
  // Mantener sólo dígitos para un parser estable (2 decimales)
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0.0;
  final value = double.parse(digits) / 100.0;
  return value;
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
