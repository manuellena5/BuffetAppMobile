import 'package:flutter/material.dart';
import 'caja_open_page.dart';
import 'caja_list_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buffet POS')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaOpenPage())),
              icon: const Icon(Icons.lock_open),
              label: const Text('Abrir caja'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaListPage())),
              icon: const Icon(Icons.history),
              label: const Text('Historial de cajas'),
            ),
          ],
        ),
      ),
    );
  }
}
