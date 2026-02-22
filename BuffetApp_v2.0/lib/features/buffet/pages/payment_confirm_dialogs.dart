import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/format.dart';

// ═══════════════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════════════

/// Muestra el modal de pago en efectivo con sugerencias de billetes y
/// cálculo de cambio.  Retorna `true` si el usuario confirma la compra.
///
/// Si [showChangeHelper] es `false`, muestra un diálogo simplificado
/// (solo monto + confirmar/cancelar, sin calculador de vuelto).
Future<bool> showCashPaymentDialog(BuildContext context, double total,
    {bool showChangeHelper = true}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => showChangeHelper
        ? _CashPaymentDialog(total: total)
        : _SimpleCashPaymentDialog(total: total),
  );
  return result ?? false;
}

/// Muestra el modal de confirmación para pago por transferencia.
/// Retorna `true` si el usuario confirma la compra.
Future<bool> showTransferPaymentDialog(
    BuildContext context, double total) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TransferPaymentDialog(total: total),
  );
  return result ?? false;
}

// ═══════════════════════════════════════════════════════════════════
//  Cash Payment Dialog
// ═══════════════════════════════════════════════════════════════════

class _CashPaymentDialog extends StatefulWidget {
  final double total;
  const _CashPaymentDialog({required this.total});

  @override
  State<_CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<_CashPaymentDialog> {
  double? _selectedAmount;
  bool _showCustomInput = false;
  final _customCtrl = TextEditingController();
  final _customFocus = FocusNode();

  // Montos prácticos que un cliente podría entregar
  // (billetes reales: 100, 200, 1000, 2000, 10000, 20000 y combinaciones
  //  habituales como 500 = 2×200+100, 5000 = 2×2000+1000, etc.)
  static const _quickAmounts = [
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    20000,
    50000,
  ];

  /// Devuelve montos sugeridos mayores al total.
  /// Si el total < 10000, siempre incluye 10000 y 20000 (billetes comunes).
  /// Además combina billetes fijos con montos redondeados (ej. 7000 para $6500).
  List<int> get _suggestions {
    final t = widget.total.ceil();
    final candidates = <int>{};

    // Si el monto es menor a 10000, siempre ofrecer 10000 y 20000
    // ya que son billetes muy comunes con los que el cliente puede pagar
    if (t < 10000) {
      candidates.add(10000);
      candidates.add(20000);
    }

    // Montos redondeados al siguiente múltiplo de pasos comunes
    // (cubre combinaciones prácticas de billetes: ej. 7000 para $6500)
    for (final step in [500, 1000, 2000, 5000, 10000]) {
      final rounded = ((t / step).ceil()) * step;
      if (rounded > t) candidates.add(rounded);
    }

    // Montos fijos de la lista de billetes / combinaciones habituales
    for (final a in _quickAmounts) {
      if (a > t) candidates.add(a);
    }

    final sorted = candidates.toList()..sort();

    // Si total < 10000, asegurar que 10000 y 20000 estén entre los mostrados
    if (t < 10000) {
      // Tomar hasta 2 sugerencias intermedias (entre total y 10000) + 10000 + 20000
      final intermedios = sorted.where((v) => v < 10000).take(2).toList();
      final fijos = sorted.where((v) => v == 10000 || v == 20000).toList();
      return [...intermedios, ...fijos];
    }

    return sorted.take(3).toList();
  }

  double get _change => (_selectedAmount ?? 0) - widget.total;
  bool get _canConfirm =>
      _selectedAmount != null && _selectedAmount! >= widget.total;

  // ── Acciones ───────────────────────────────────────────────────

  void _selectAmount(double amount) {
    setState(() {
      _selectedAmount = amount;
      _showCustomInput = false;
    });
  }

  void _selectExact() => _selectAmount(widget.total);

  void _showCustom() {
    setState(() {
      _showCustomInput = true;
      _selectedAmount = null;
      _customCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _customFocus.requestFocus();
    });
  }

  void _onCustomChanged(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = double.tryParse(digits) ?? 0;
    setState(() {
      _selectedAmount = parsed > 0 ? parsed : null;
    });
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = _suggestions;

    // En landscape, centrar el diálogo con máximo 480 px de ancho
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final horizontalInset = isLandscape
        ? ((screenWidth - 480) / 2).clamp(20.0, screenWidth * 0.3)
        : 20.0;

    return AlertDialog(
      insetPadding:
          EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Icon(Icons.payments_outlined, color: Colors.green[700], size: 28),
          const SizedBox(width: 10),
          const Text('Pago en Efectivo'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Total ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text('Total a cobrar',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Text(
                      formatCurrency(widget.total),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Label ────────────────────────────────────────
              const Text(
                'El cliente paga con:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),

              // ── Quick buttons ────────────────────────────────
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AmountChip(
                    label: 'Exacto',
                    selected:
                        _selectedAmount == widget.total && !_showCustomInput,
                    onTap: _selectExact,
                  ),
                  for (final amount in suggestions)
                    _AmountChip(
                      label: formatCurrencyNoDecimals(amount),
                      selected: _selectedAmount == amount.toDouble() &&
                          !_showCustomInput,
                      onTap: () => _selectAmount(amount.toDouble()),
                    ),
                  _AmountChip(
                    label: 'Otro',
                    selected: _showCustomInput,
                    onTap: _showCustom,
                    isOther: true,
                  ),
                ],
              ),

              // ── Custom input ────────────────────────────────
              if (_showCustomInput) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customCtrl,
                  focusNode: _customFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    hintText: 'Ingrese el monto',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: _onCustomChanged,
                ),
              ],

              // ── Change display ──────────────────────────────
              if (_selectedAmount != null) ...[
                const SizedBox(height: 16),
                _ChangeDisplay(
                  selectedAmount: _selectedAmount!,
                  total: widget.total,
                  canConfirm: _canConfirm,
                  change: _change,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirmar Compra',
              style: TextStyle(fontSize: 15)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Change Display
// ═══════════════════════════════════════════════════════════════════

class _ChangeDisplay extends StatelessWidget {
  final double selectedAmount;
  final double total;
  final bool canConfirm;
  final double change;

  const _ChangeDisplay({
    required this.selectedAmount,
    required this.total,
    required this.canConfirm,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    final ok = canConfirm;
    final color = ok ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Paga con:', style: TextStyle(fontSize: 14)),
              Text(
                formatCurrency(selectedAmount),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ok ? 'Cambio:' : 'Falta:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: ok ? Colors.green[800] : Colors.red[800],
                ),
              ),
              Text(
                ok
                    ? formatCurrency(change)
                    : formatCurrency(total - selectedAmount),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: ok ? Colors.green[800] : Colors.red[800],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Amount Chip Button
// ═══════════════════════════════════════════════════════════════════

class _AmountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isOther;

  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isOther = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    if (selected) {
      bg = Colors.green;
      fg = Colors.white;
    } else if (isOther) {
      bg = Colors.grey[200]!;
      fg = Colors.grey[700]!;
    } else {
      bg = Colors.blue[50]!;
      fg = Colors.blue[900]!;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Transfer Payment Dialog
// ═══════════════════════════════════════════════════════════════════

class _TransferPaymentDialog extends StatelessWidget {
  final double total;
  const _TransferPaymentDialog({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // En landscape, centrar el diálogo con máximo 480 px de ancho
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final horizontalInset = isLandscape
        ? ((screenWidth - 480) / 2).clamp(20.0, screenWidth * 0.3)
        : 20.0;

    return AlertDialog(
      insetPadding:
          EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Icon(Icons.account_balance_outlined,
              color: Colors.blue[700], size: 28),
          const SizedBox(width: 10),
          const Text('Transferencia'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Total
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text('Total a cobrar',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(total),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Verifique que la transferencia fue recibida antes de confirmar.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirmar Compra',
              style: TextStyle(fontSize: 15)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Simple Cash Payment Dialog (sin calculador de vuelto)
// ═══════════════════════════════════════════════════════════════════

class _SimpleCashPaymentDialog extends StatelessWidget {
  final double total;
  const _SimpleCashPaymentDialog({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // En landscape, centrar el diálogo con máximo 480 px de ancho
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final horizontalInset = isLandscape
        ? ((screenWidth - 480) / 2).clamp(20.0, screenWidth * 0.3)
        : 20.0;

    return AlertDialog(
      insetPadding:
          EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Icon(Icons.payments_outlined, color: Colors.green[700], size: 28),
          const SizedBox(width: 10),
          const Text('Pago en Efectivo'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Total
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text('Total a cobrar',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(total),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirmar Compra',
              style: TextStyle(fontSize: 15)),
        ),
      ],
    );
  }
}
