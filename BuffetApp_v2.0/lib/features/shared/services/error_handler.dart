import 'package:flutter/material.dart';
import '../../../data/dao/db.dart';

/// Servicio centralizado para manejo de errores en la aplicación
/// 
/// Responsabilidades:
/// - Capturar errores y guardarlos en la base de datos local
/// - Mostrar mensajes amigables al usuario
/// - Proporcionar helpers para operaciones comunes con manejo de errores
class ErrorHandler {
  ErrorHandler._();
  static final instance = ErrorHandler._();

  /// Registra un error en la base de datos y opcionalmente muestra un mensaje al usuario
  /// 
  /// Parámetros:
  /// - [scope]: identificador del contexto donde ocurrió el error (ej: 'tesoreria.crear_movimiento')
  /// - [error]: el objeto de error capturado
  /// - [stackTrace]: traza del stack (opcional)
  /// - [context]: contexto de Flutter para mostrar mensaje (opcional)
  /// - [userMessage]: mensaje amigable para mostrar al usuario (opcional)
  /// - [payload]: datos adicionales relevantes (opcional)
  /// - [showDialog]: si es true, muestra un diálogo modal en lugar de un SnackBar
  Future<void> handle({
    required String scope,
    required Object error,
    StackTrace? stackTrace,
    BuildContext? context,
    String? userMessage,
    Map<String, Object?>? payload,
    bool showDialog = false,
  }) async {
    // Guardar en base de datos
    await AppDatabase.logLocalError(
      scope: scope,
      error: error,
      stackTrace: stackTrace,
      payload: payload,
    );

    // Mostrar mensaje al usuario si hay contexto
    if (context != null && context.mounted) {
      final message = userMessage ?? _getDefaultMessage(scope);
      
      if (showDialog) {
        _showErrorDialog(context, message, error.toString());
      } else {
        _showErrorSnackBar(context, message);
      }
    }
  }

  /// Ejecuta una operación async con manejo de errores automático
  /// 
  /// Ejemplo:
  /// ```dart
  /// await ErrorHandler.instance.execute(
  ///   scope: 'tesoreria.crear_movimiento',
  ///   context: context,
  ///   userMessage: 'No se pudo crear el movimiento',
  ///   operation: () async {
  ///     await service.crearMovimiento(...);
  ///   },
  /// );
  /// ```
  Future<T?> execute<T>({
    required String scope,
    required Future<T> Function() operation,
    BuildContext? context,
    String? userMessage,
    Map<String, Object?>? payload,
    bool showDialog = false,
    T? defaultValue,
  }) async {
    try {
      return await operation();
    } catch (e, st) {
      await handle(
        scope: scope,
        error: e,
        stackTrace: st,
        context: context,
        userMessage: userMessage,
        payload: payload,
        showDialog: showDialog,
      );
      return defaultValue;
    }
  }

  /// Muestra un SnackBar con el mensaje de error
  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Muestra un diálogo modal con el mensaje de error
  void _showErrorDialog(BuildContext context, String message, String technicalDetails) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            const Text('Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text(
                'Detalles técnicos',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SelectableText(
                    technicalDetails,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Genera un mensaje por defecto basado en el scope
  String _getDefaultMessage(String scope) {
    final parts = scope.split('.');
    if (parts.isEmpty) return 'Ocurrió un error inesperado';

    final module = parts.first;
    final action = parts.length > 1 ? parts[1] : '';

    switch (module) {
      case 'tesoreria':
        return _getTesoreriaMessage(action);
      case 'buffet':
        return _getBuffetMessage(action);
      case 'sync':
        return 'Error al sincronizar datos con el servidor';
      case 'db':
        return 'Error al acceder a la base de datos';
      default:
        return 'Ocurrió un error inesperado';
    }
  }

  String _getTesoreriaMessage(String action) {
    switch (action) {
      case 'crear_movimiento':
        return 'No se pudo crear el movimiento';
      case 'editar_movimiento':
        return 'No se pudo editar el movimiento';
      case 'eliminar_movimiento':
        return 'No se pudo eliminar el movimiento';
      case 'cargar_movimientos':
        return 'No se pudieron cargar los movimientos';
      case 'crear_compromiso':
        return 'No se pudo crear el compromiso';
      case 'editar_compromiso':
        return 'No se pudo editar el compromiso';
      case 'eliminar_compromiso':
        return 'No se pudo eliminar el compromiso';
      case 'generar_cuotas':
        return 'No se pudieron generar las cuotas';
      case 'crear_categoria':
        return 'No se pudo crear la categoría';
      default:
        return 'Error en la operación de tesorería';
    }
  }

  String _getBuffetMessage(String action) {
    switch (action) {
      case 'abrir_caja':
        return 'No se pudo abrir la caja';
      case 'cerrar_caja':
        return 'No se pudo cerrar la caja';
      case 'crear_venta':
        return 'No se pudo registrar la venta';
      case 'anular_venta':
        return 'No se pudo anular la venta';
      case 'imprimir':
        return 'Error al imprimir';
      default:
        return 'Error en la operación de buffet';
    }
  }
}
