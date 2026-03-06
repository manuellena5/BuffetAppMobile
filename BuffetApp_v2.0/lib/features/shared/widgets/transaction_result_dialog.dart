import 'package:flutter/material.dart';

/// Diálogo reutilizable para mostrar el resultado de una transacción.
///
/// Sigue el patrón de las instrucciones del proyecto:
/// - TODA transacción muestra un modal final con resultado detallado.
/// - Mensajes amigables en español.
/// - Icono + título según tipo de resultado.
///
/// Uso:
/// ```dart
/// await TransactionResultDialog.showSuccess(
///   context: context,
///   title: 'Acuerdo Creado',
///   details: [
///     TransactionDetail(label: 'Nombre', value: 'Sueldos Plantel'),
///     TransactionDetail(label: 'Acuerdos', value: '12'),
///     TransactionDetail(label: 'Compromisos', value: '144'),
///   ],
///   onDismiss: () => Navigator.pop(context, resultado),
/// );
/// ```
class TransactionResultDialog {
  TransactionResultDialog._();

  /// Muestra diálogo de éxito con detalles de la transacción.
  static Future<void> showSuccess({
    required BuildContext context,
    required String title,
    String? message,
    List<TransactionDetail>? details,
    List<TransactionWarning>? warnings,
    VoidCallback? onDismiss,
    String dismissText = 'Aceptar',
  }) async {
    return _show(
      context: context,
      type: _ResultType.success,
      title: title,
      message: message,
      details: details,
      warnings: warnings,
      onDismiss: onDismiss,
      dismissText: dismissText,
    );
  }

  /// Muestra diálogo de error con mensaje amigable.
  static Future<void> showError({
    required BuildContext context,
    required String title,
    String? message,
    String? technicalDetail,
    List<TransactionDetail>? details,
    VoidCallback? onDismiss,
    String dismissText = 'Cerrar',
  }) async {
    final allDetails = <TransactionDetail>[
      ...?details,
      if (technicalDetail != null)
        TransactionDetail(
          label: 'Detalle técnico',
          value: technicalDetail,
          style: TransactionDetailStyle.error,
        ),
    ];

    return _show(
      context: context,
      type: _ResultType.error,
      title: title,
      message: message ?? 'No se pudo completar la operación. Por favor, intente nuevamente.',
      details: allDetails.isEmpty ? null : allDetails,
      onDismiss: onDismiss,
      dismissText: dismissText,
    );
  }

  /// Muestra diálogo de advertencia/parcial.
  static Future<void> showWarning({
    required BuildContext context,
    required String title,
    String? message,
    List<TransactionDetail>? details,
    List<TransactionWarning>? warnings,
    VoidCallback? onDismiss,
    String dismissText = 'Aceptar',
  }) async {
    return _show(
      context: context,
      type: _ResultType.warning,
      title: title,
      message: message,
      details: details,
      warnings: warnings,
      onDismiss: onDismiss,
      dismissText: dismissText,
    );
  }

  // === IMPLEMENTACIÓN INTERNA ===

  static Future<void> _show({
    required BuildContext context,
    required _ResultType type,
    required String title,
    String? message,
    List<TransactionDetail>? details,
    List<TransactionWarning>? warnings,
    VoidCallback? onDismiss,
    required String dismissText,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TransactionResultContent(
        type: type,
        title: title,
        message: message,
        details: details,
        warnings: warnings,
        onDismiss: () {
          Navigator.of(ctx).pop();
          onDismiss?.call();
        },
        dismissText: dismissText,
      ),
    );
  }
}

// =============================================================================
// WIDGET INTERNO
// =============================================================================

class _TransactionResultContent extends StatelessWidget {
  final _ResultType type;
  final String title;
  final String? message;
  final List<TransactionDetail>? details;
  final List<TransactionWarning>? warnings;
  final VoidCallback onDismiss;
  final String dismissText;

  const _TransactionResultContent({
    required this.type,
    required this.title,
    this.message,
    this.details,
    this.warnings,
    required this.onDismiss,
    required this.dismissText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Icono grande
            _buildIcon(),
            const SizedBox(height: 16),

            // Título
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            // Mensaje
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Detalles
            if (details != null && details!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildDetailsCard(theme),
            ],

            // Advertencias
            if (warnings != null && warnings!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildWarnings(theme),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onDismiss,
            style: FilledButton.styleFrom(
              backgroundColor: _buttonColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(dismissText),
          ),
        ),
      ],
    );
  }

  Widget _buildIcon() {
    IconData iconData;
    Color color;
    Color bgColor;

    switch (type) {
      case _ResultType.success:
        iconData = Icons.check_circle_outline;
        color = Colors.green;
        bgColor = Colors.green.shade50;
        break;
      case _ResultType.error:
        iconData = Icons.error_outline;
        color = Colors.red;
        bgColor = Colors.red.shade50;
        break;
      case _ResultType.warning:
        iconData = Icons.warning_amber_outlined;
        color = Colors.orange;
        bgColor = Colors.orange.shade50;
        break;
    }

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: color, size: 36),
    );
  }

  Color get _buttonColor {
    switch (type) {
      case _ResultType.success:
        return Colors.green;
      case _ResultType.error:
        return Colors.red;
      case _ResultType.warning:
        return Colors.orange;
    }
  }

  Widget _buildDetailsCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: details!.map((d) => _buildDetailRow(d, theme)).toList(),
      ),
    );
  }

  Widget _buildDetailRow(TransactionDetail detail, ThemeData theme) {
    Color valueColor;
    FontWeight valueWeight;

    switch (detail.style) {
      case TransactionDetailStyle.normal:
        valueColor = theme.colorScheme.onSurface;
        valueWeight = FontWeight.w600;
        break;
      case TransactionDetailStyle.highlight:
        valueColor = theme.colorScheme.primary;
        valueWeight = FontWeight.bold;
        break;
      case TransactionDetailStyle.success:
        valueColor = Colors.green.shade700;
        valueWeight = FontWeight.bold;
        break;
      case TransactionDetailStyle.error:
        valueColor = Colors.red.shade700;
        valueWeight = FontWeight.w500;
        break;
      case TransactionDetailStyle.muted:
        valueColor = Colors.grey;
        valueWeight = FontWeight.normal;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              detail.label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              detail.value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: valueWeight,
                color: valueColor,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarnings(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 6),
              Text(
                'Advertencias',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...warnings!.map((w) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '• ${w.message}',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          )),
        ],
      ),
    );
  }
}

// =============================================================================
// MODELOS
// =============================================================================

enum _ResultType { success, error, warning }

/// Estilo visual de una línea de detalle.
enum TransactionDetailStyle {
  normal,
  highlight,
  success,
  error,
  muted,
}

/// Línea de detalle (label: valor) del resultado de la transacción.
class TransactionDetail {
  final String label;
  final String value;
  final TransactionDetailStyle style;

  const TransactionDetail({
    required this.label,
    required this.value,
    this.style = TransactionDetailStyle.normal,
  });
}

/// Advertencia a mostrar en el diálogo.
class TransactionWarning {
  final String message;

  const TransactionWarning(this.message);
}
