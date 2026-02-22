import 'package:flutter/material.dart';

/// Muestra el diálogo de conteo de billetes argentinos.
/// Retorna el total calculado (double) o null si se cancela.
Future<double?> showBillCounterDialog(BuildContext context) {
  return showDialog<double>(
    context: context,
    builder: (_) => const BillCounterDialog(),
  );
}

// ---------------------------------------------------------------------------
// Modal de conteo de billetes argentinos
// ---------------------------------------------------------------------------
class BillCounterDialog extends StatefulWidget {
  const BillCounterDialog({super.key});

  @override
  State<BillCounterDialog> createState() => _BillCounterDialogState();
}

class _BillCounterDialogState extends State<BillCounterDialog> {
  // Denominaciones vigentes en Argentina (2026)
  static const List<int> _denominations = [20000, 10000, 2000, 1000, 500, 200, 100];

  final Map<int, TextEditingController> _controllers = {};
  final Map<int, int> _quantities = {};

  @override
  void initState() {
    super.initState();
    for (final d in _denominations) {
      _quantities[d] = 0;
      _controllers[d] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total {
    double t = 0;
    for (final d in _denominations) {
      t += d * (_quantities[d] ?? 0);
    }
    return t;
  }

  void _updateQuantity(int denom, String value) {
    final parsed = int.tryParse(value);
    setState(() {
      _quantities[denom] = (parsed != null && parsed >= 0) ? parsed : 0;
    });
  }

  void _increment(int denom) {
    setState(() {
      _quantities[denom] = (_quantities[denom] ?? 0) + 1;
      _controllers[denom]!.text = _quantities[denom].toString();
    });
  }

  void _decrement(int denom) {
    final current = _quantities[denom] ?? 0;
    if (current <= 0) return;
    setState(() {
      _quantities[denom] = current - 1;
      _controllers[denom]!.text = _quantities[denom] == 0 ? '' : _quantities[denom].toString();
    });
  }

  void _limpiar() {
    setState(() {
      for (final d in _denominations) {
        _quantities[d] = 0;
        _controllers[d]!.text = '';
      }
    });
  }

  String _formatMoney(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      count++;
      if (count % 3 == 0 && i > 0 && s[i] != '-') buf.write('.');
    }
    return '\$ ${buf.toString().split('').reversed.join()}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments_outlined, color: theme.colorScheme.onPrimary),
                  const SizedBox(width: 10),
                  Text(
                    'Contar billetes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _limpiar,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

            // Bill rows
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _denominations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final denom = _denominations[index];
                  final qty = _quantities[denom] ?? 0;
                  final subtotal = denom * qty;
                  return _BillRow(
                    denomination: denom,
                    controller: _controllers[denom]!,
                    quantity: qty,
                    subtotal: subtotal.toDouble(),
                    onChanged: (v) => _updateQuantity(denom, v),
                    onIncrement: () => _increment(denom),
                    onDecrement: () => _decrement(denom),
                    formatMoney: _formatMoney,
                  );
                },
              ),
            ),

            // Total + actions
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('TOTAL', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        _formatMoney(total),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Aplicar'),
                          onPressed: () => Navigator.pop(context, total),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.denomination,
    required this.controller,
    required this.quantity,
    required this.subtotal,
    required this.onChanged,
    required this.onIncrement,
    required this.onDecrement,
    required this.formatMoney,
  });

  final int denomination;
  final TextEditingController controller;
  final int quantity;
  final double subtotal;
  final ValueChanged<String> onChanged;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String Function(double) formatMoney;

  String _denomLabel(int d) {
    if (d >= 1000) return '\$ ${(d ~/ 1000)}.000';
    return '\$ $d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = quantity > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: hasValue
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasValue
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Denomination label
          SizedBox(
            width: 72,
            child: Text(
              _denomLabel(denomination),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          // Decrement
          _CircleBtn(
            icon: Icons.remove,
            onTap: quantity > 0 ? onDecrement : null,
          ),

          // Quantity input
          SizedBox(
            width: 52,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: theme.hintColor.withValues(alpha: 0.4)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
              ),
              onChanged: onChanged,
            ),
          ),

          // Increment
          _CircleBtn(
            icon: Icons.add,
            onTap: onIncrement,
          ),

          const SizedBox(width: 4),

          // Subtotal
          Expanded(
            child: Text(
              hasValue ? formatMoney(subtotal) : '',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).disabledColor,
        ),
      ),
    );
  }
}
