import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Dialog de ayuda que explica las diferencias entre Acuerdo, Compromiso y Movimiento.
///
/// Reutilizable desde cualquier pantalla de tesorería.
/// Uso: `AyudaTesoreriaDialog.show(context);`
class AyudaTesoreriaDialog extends StatelessWidget {
  const AyudaTesoreriaDialog({super.key});

  /// Muestra el dialog de ayuda. Método estático para facilitar el uso.
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const AyudaTesoreriaDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.school, color: AppColors.info),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '¿Qué debo crear?',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildConcepto(
              icon: Icons.handshake,
              color: AppColors.accentDim,
              titulo: 'Acuerdo',
              descripcion:
                  'Una regla o contrato que se repite o tiene cuotas.\n'
                  'NO impacta saldo directamente.',
              ejemplos: const [
                'Sueldo del DT: \$50.000/mes por 12 meses',
                'Compra de camisetas: \$100.000 en 5 cuotas',
                'Alquiler de cancha: \$30.000/mes indefinido',
              ],
              resultado:
                  '→ Genera compromisos automáticamente según la frecuencia y cuotas configuradas.',
            ),
            const Divider(height: 24),
            _buildConcepto(
              icon: Icons.event_note,
              color: AppColors.info,
              titulo: 'Compromiso',
              descripcion:
                  'Un pago o cobro puntual que se espera en una fecha específica.',
              ejemplos: const [
                'Pago de árbitro del sábado: \$15.000',
                'Inscripción de torneo: \$5.000',
                'Compra de hielo para el buffet: \$3.000',
              ],
              resultado:
                  '→ Se confirma cuando el pago realmente ocurre, lo cual genera un movimiento.',
            ),
            const Divider(height: 24),
            _buildConcepto(
              icon: Icons.receipt_long,
              color: AppColors.ingreso,
              titulo: 'Movimiento',
              descripcion:
                  'Un hecho real confirmado: dinero que ya entró o salió.\n'
                  'Es lo que impacta el saldo.',
              ejemplos: const [
                'Se pagaron \$50.000 al DT el 5 de marzo',
                'Se cobró inscripción de Juan: \$5.000',
                'Se compró hielo: \$3.000 en efectivo',
              ],
              resultado:
                  '→ Se genera automáticamente al confirmar un compromiso.',
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🧭 Regla rápida:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  _buildRegla(
                    '¿Se repite cada mes o tiene cuotas?',
                    '→ Crear ACUERDO',
                    AppColors.accentDim,
                  ),
                  const SizedBox(height: 6),
                  _buildRegla(
                    '¿Es un pago/cobro puntual que no se repite?',
                    '→ Crear COMPROMISO',
                    AppColors.info,
                  ),
                  const SizedBox(height: 6),
                  _buildRegla(
                    '¿Ya se pagó o cobró?',
                    '→ Confirmar el COMPROMISO',
                    AppColors.ingreso,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.advertenciaDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.advertencia),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb,
                      color: AppColors.advertencia, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'El flujo típico es:\n'
                      'Acuerdo → genera Compromisos → al confirmar cada compromiso se genera el Movimiento real.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    );
  }

  Widget _buildConcepto({
    required IconData icon,
    required Color color,
    required String titulo,
    required String descripcion,
    required List<String> ejemplos,
    required String resultado,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(descripcion, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        ...ejemplos.map((e) => Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 13)),
                  Expanded(
                      child: Text(e, style: const TextStyle(fontSize: 13))),
                ],
              ),
            )),
        const SizedBox(height: 6),
        Text(
          resultado,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  static Widget _buildRegla(String pregunta, String respuesta, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              children: [
                TextSpan(text: pregunta),
                const TextSpan(text: '\n'),
                TextSpan(
                  text: respuesta,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
