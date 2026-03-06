/// Extension para casteos seguros de filas de base de datos (Map<String, dynamic>).
///
/// Evita crashes por tipos inesperados (int donde se espera double, null inseguro, etc.)
/// centralizando todos los casteos en un solo lugar.
///
/// Ejemplo:
/// ```dart
/// final row = {'monto': 1500, 'nombre': null, 'activo': 1};
/// row.safeDouble('monto');     // 1500.0
/// row.safeString('nombre');    // ''
/// row.safeBool('activo');      // true
/// row.safeInt('no_existe');    // 0
/// ```
extension SafeMap on Map<String, dynamic> {
  /// Obtiene un int seguro. Convierte num→int, devuelve [defaultValue] si es null o no convertible.
  int safeInt(String key, [int defaultValue = 0]) {
    final v = this[key];
    if (v == null) return defaultValue;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? defaultValue;
    return defaultValue;
  }

  /// Obtiene un double seguro. Convierte num→double, devuelve [defaultValue] si es null.
  double safeDouble(String key, [double defaultValue = 0.0]) {
    final v = this[key];
    if (v == null) return defaultValue;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? defaultValue;
    return defaultValue;
  }

  /// Obtiene un String seguro. Devuelve [defaultValue] si es null.
  String safeString(String key, [String defaultValue = '']) {
    final v = this[key];
    if (v == null) return defaultValue;
    if (v is String) return v;
    return v.toString();
  }

  /// Obtiene un String? (nullable). Retorna null si la clave no existe o el valor es null.
  String? safeStringOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  /// Obtiene un bool seguro. Interpreta int (0/1) como bool.
  bool safeBool(String key, [bool defaultValue = false]) {
    final v = this[key];
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return defaultValue;
  }

  /// Obtiene un DateTime seguro desde una fecha ISO (yyyy-MM-dd o yyyy-MM-ddTHH:mm:ss).
  /// Retorna null si no se puede parsear.
  DateTime? safeDateTime(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  /// Obtiene un int? nullable. Retorna null si la clave no existe o el valor es null.
  int? safeIntOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Obtiene un double? nullable. Retorna null si la clave no existe o el valor es null.
  double? safeDoubleOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
