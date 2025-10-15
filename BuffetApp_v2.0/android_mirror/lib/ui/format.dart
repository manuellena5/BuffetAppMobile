import 'package:intl/intl.dart';

final _formatter = NumberFormat.currency(locale: 'es_AR', symbol: '\$');
String formatCurrency(num value) => _formatter.format(value);
