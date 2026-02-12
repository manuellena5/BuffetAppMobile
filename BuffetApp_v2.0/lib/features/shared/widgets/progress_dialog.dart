import 'package:flutter/material.dart';

/// Diálogo de progreso con indicador y mensaje
/// 
/// Ejemplo de uso:
/// ```dart
/// ProgressDialog.show(context, 'Cargando datos...');
/// // ... operación ...
/// ProgressDialog.hide(context);
/// ```
class ProgressDialog {
  /// Muestra un diálogo de progreso simple
  static void show(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  /// Oculta el diálogo de progreso actual
  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Diálogo de progreso con contador (X/Y)
/// Útil para operaciones batch/masivas
class ProgressCounterDialog extends StatelessWidget {
  final int current;
  final int total;
  final String message;
  final String? subtitle;

  const ProgressCounterDialog({
    super.key,
    required this.current,
    required this.total,
    required this.message,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? current / total : 0.0;
    final percentage = (progress * 100).toStringAsFixed(0);

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicador circular con porcentaje
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey[300],
                ),
              ),
              Text(
                '$percentage%',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Mensaje principal
          Text(
            message,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Contador
          Text(
            '$current / $total',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          // Subtitle opcional
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Método helper para mostrar el diálogo
  static void show(
    BuildContext context, {
    required int current,
    required int total,
    required String message,
    String? subtitle,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProgressCounterDialog(
        current: current,
        total: total,
        message: message,
        subtitle: subtitle,
      ),
    );
  }

  /// Actualiza el diálogo existente (requiere StatefulBuilder)
  static void update(BuildContext context) {
    // El caller debe usar StatefulBuilder y llamar setState
  }
}

/// Diálogo de progreso con barra lineal
/// Mejor para operaciones donde se puede medir el progreso exacto
class LinearProgressDialog extends StatelessWidget {
  final double progress; // 0.0 a 1.0
  final String message;
  final String? subtitle;

  const LinearProgressDialog({
    super.key,
    required this.progress,
    required this.message,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (progress * 100).toStringAsFixed(0);

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mensaje
          Text(
            message,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          // Barra de progreso
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 8),
          // Porcentaje
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$percentage%',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Subtitle opcional
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Método helper para mostrar el diálogo
  static void show(
    BuildContext context, {
    required double progress,
    required String message,
    String? subtitle,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LinearProgressDialog(
        progress: progress,
        message: message,
        subtitle: subtitle,
      ),
    );
  }
}
