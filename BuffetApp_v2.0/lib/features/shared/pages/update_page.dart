import 'dart:io';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../../shared/state/app_settings.dart';
import '../services/update_service.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final _metaController = TextEditingController();
  final _service = UpdateService();

  String? _status;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    // Precargar URL desde AppSettings si existe
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<AppSettings>();
      final saved = settings.updateMetadataUrl ?? '';
      _metaController.text = saved;
    });
  }

  @override
  void dispose() {
    _metaController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final urlText = _metaController.text.trim();
    if (urlText.isEmpty) {
      setState(() => _status = 'Ingresá la URL del metadata (update.json)');
      return;
    }

    // Guardar la URL en AppSettings para futuras consultas
    try {
      final settings = context.read<AppSettings>();
      await settings.setUpdateMetadataUrl(urlText);
    } catch (_) {}

    setState(() { _status = 'Consultando metadata...'; _progress = 0.0; });
    final meta = await _service.fetchRemoteMeta(Uri.parse(urlText));
    if (meta == null) {
      setState(() => _status = 'No se pudo leer metadata.');
      return;
    }

    final int remoteCode = (meta['versionCode'] is int) ? meta['versionCode'] : int.tryParse('${meta['versionCode']}') ?? 0;
    final String remoteName = '${meta['versionName'] ?? ''}';
    final String? apkUrl = meta['apk_url'] ?? meta['apkUrl'] ?? meta['apk_path'];

    final currentCode = await _service.currentVersionCode();

    if (remoteCode <= currentCode) {
      setState(() => _status = 'La app ya está en la misma versión o más nueva.');
      return;
    }

    // Mostrar modal de confirmación
    final doInstall = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Actualización disponible'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versión: $remoteName'),
            const SizedBox(height: 8),
            if (meta['notes'] != null) Text('${meta['notes']}'),
            const SizedBox(height: 8),
            const Text('¿Deseás descargar e instalar ahora?'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Descargar')),
        ],
      ),
    );

    if (doInstall != true) {
      setState(() => _status = 'Actualización cancelada por el usuario.');
      return;
    }

    if (apkUrl == null) {
      setState(() => _status = 'Metadata incompleta: falta apk_url');
      return;
    }

    setState(() { _status = 'Descargando APK...'; _progress = 0.0; });
    final fileName = 'buffet_update_${remoteName.replaceAll('.', '_')}.apk';
    final file = await _service.downloadApk(apkUrl, fileName, (r, t) {
      setState(() { _progress = t > 0 ? r / t : 0.0; });
    });

    if (file == null) {
      setState(() => _status = 'Fallo la descarga.');
      return;
    }

    setState(() => _status = 'Descarga completa. Abriendo instalador...');
    try {
      await _service.openApk(file);
      setState(() => _status = 'Instalador abierto. Completá la instalación en el dispositivo.');
    } catch (_) {
      setState(() => _status = 'No se pudo abrir el instalador.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar actualizaciones')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('URL del metadata (update.json):'),
            const SizedBox(height: 8),
            TextField(
              controller: _metaController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://.../update.json',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _checkForUpdate,
                  child: const Text('Buscar actualizaciones'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () { _metaController.clear(); setState(() => _status = null); },
                  child: const Text('Limpiar'),
                ),
              ],
            ),

            const SizedBox(height: 20),
            if (_status != null) ...[
              Text(_status!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
            ],

            if (_progress > 0 && _progress < 1.0) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}%'),
            ],

            const Spacer(),
            Text('Notas:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('- La instalación requiere confirmación del usuario.'),
            const Text('- Asegurate que el APK esté firmado con la misma clave y que el versionCode sea mayor.'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
