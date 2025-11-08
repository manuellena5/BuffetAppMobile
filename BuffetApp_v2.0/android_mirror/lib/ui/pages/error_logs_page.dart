import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/dao/db.dart';

class ErrorLogsPage extends StatefulWidget {
  const ErrorLogsPage({super.key});

  @override
  State<ErrorLogsPage> createState() => _ErrorLogsPageState();
}

class _ErrorLogsPageState extends State<ErrorLogsPage> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await AppDatabase.ultimosErrores(limit: 500);
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar logs'),
        content: const Text('¿Seguro que querés borrar todos los registros?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
  await AppDatabase.clearErrorLogs();
  if (!mounted) return;
  await _load();
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs borrados')));
  }

  Future<void> _share() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'app_error_log.json'));
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_rows), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'app_error_log.json'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo compartir: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs de errores'),
        actions: [
          IconButton(onPressed: _share, icon: const Icon(Icons.share)),
          IconButton(onPressed: _clearAll, icon: const Icon(Icons.delete_forever)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: Text('Sin registros')),
                    ])
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final r = _rows[i];
                        final scope = (r['scope'] ?? '-').toString();
                        final msg = (r['message'] ?? '').toString();
                        final ts = (r['created_ts'] ?? '').toString();
                        final payload = (r['payload'] ?? '').toString();
                        final stack = (r['stacktrace'] ?? '').toString();
                        return ExpansionTile(
                          title: Text(scope, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis),
                          children: [
                            _kv('Fecha', ts),
                            if (payload.isNotEmpty) _kv('Payload', payload),
                            if (stack.isNotEmpty) _kv('Stacktrace', stack),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
            ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(v, style: TextStyle(color: Colors.grey.shade800, fontSize: 13)),
        ],
      ),
    );
  }
}
