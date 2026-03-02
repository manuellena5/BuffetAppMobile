import 'dart:io';

import 'package:flutter/material.dart';

import '../../../env/supabase_env.dart';
import '../../../app_version.dart';
import '../services/update_service.dart';
import '../../../data/dao/db.dart';

/// Pantalla que verifica si hay una nueva versión disponible en Supabase Storage.
/// No requiere que el usuario pegue URLs: la metadata se obtiene automáticamente
/// del bucket público "releases/update.json".
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  static const _bucket = 'releases';
  static const _metaFile = 'update.json';

  final _service = UpdateService();

  bool _checking = false;
  String? _status;
  double _progress = 0.0;

  String get _metaUrl =>
      '${SupabaseEnv.url}/storage/v1/object/public/$_bucket/$_metaFile';

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() { _checking = true; _status = 'Consultando...'; _progress = 0.0; });

    try {
      final meta = await _service.fetchRemoteMeta(Uri.parse(_metaUrl));
      if (!mounted) return;

      if (meta == null) {
        setState(() { _status = 'No se pudo obtener información de versión.'; _checking = false; });
        return;
      }

      final int remoteCode = (meta['versionCode'] is int)
          ? meta['versionCode']
          : int.tryParse('${meta['versionCode']}') ?? 0;
      final String remoteName = '${meta['versionName'] ?? ''}';
      final String? apkUrl = meta['apk_url'] ?? meta['apkUrl'];
      final String? notes = meta['notes'] as String?;

      final currentCode = AppBuildInfo.buildNumber;

      if (remoteCode <= currentCode) {
        setState(() {
          _status = 'Ya tenés la última versión (v${AppBuildInfo.version}+$currentCode).';
          _checking = false;
        });
        return;
      }

      // ── Modal de confirmación ──
      final doInstall = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update, color: Theme.of(c).colorScheme.primary, size: 28),
              const SizedBox(width: 10),
              const Expanded(child: Text('Actualización disponible')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nueva versión: $remoteName', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Versión actual: v${AppBuildInfo.version}+$currentCode'),
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Notas:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(notes),
              ],
              const SizedBox(height: 16),
              const Text('¿Deseás descargar e instalar ahora?'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ahora no')),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(c, true),
              icon: const Icon(Icons.download),
              label: const Text('Descargar'),
            ),
          ],
        ),
      );

      if (doInstall != true) {
        setState(() { _status = 'Actualización pospuesta.'; _checking = false; });
        return;
      }

      if (apkUrl == null || apkUrl.isEmpty) {
        setState(() { _status = 'Metadata incompleta: falta apk_url.'; _checking = false; });
        return;
      }

      // ── Descarga ──
      setState(() { _status = 'Descargando APK...'; _progress = 0.0; });
      final fileName = 'buffet_update_${remoteName.replaceAll('.', '_')}.apk';
      final file = await _service.downloadApk(apkUrl, fileName, (r, t) {
        if (mounted) setState(() { _progress = t > 0 ? r / t : 0.0; });
      });

      if (!mounted) return;
      if (file == null) {
        setState(() { _status = 'No se pudo descargar el APK. Intentá de nuevo.'; _checking = false; });
        return;
      }

      setState(() { _status = 'Descarga completa. Abriendo instalador...'; _progress = 1.0; });
      try {
        await _service.openApk(file);
        if (mounted) {
          setState(() { _status = 'Instalador abierto. Completá la instalación en el dispositivo.'; _checking = false; });
        }
      } catch (e) {
        if (mounted) {
          setState(() { _status = 'No se pudo abrir el instalador.'; _checking = false; });
        }
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'update_page.check', error: e, stackTrace: st);
      if (mounted) {
        setState(() { _status = 'Error inesperado. Intentá de nuevo.'; _checking = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Actualizaciones')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.system_update_alt, size: 72, color: cs.primary.withValues(alpha: 0.6)),
              const SizedBox(height: 20),

              Text('v${AppBuildInfo.version}+${AppBuildInfo.buildNumber}',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              Text('Versión actual instalada',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 32),

              // ── Botón principal ──
              SizedBox(
                width: 260,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _checking ? null : _checkForUpdate,
                  icon: _checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(_checking ? 'Verificando...' : 'Buscar actualizaciones'),
                ),
              ),

              const SizedBox(height: 24),

              // ── Barra de progreso ──
              if (_progress > 0 && _progress < 1.0) ...[
                SizedBox(
                  width: 260,
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 6),
                      Text('${(_progress * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Mensaje de estado ──
              if (_status != null)
                Text(_status!, textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _status!.contains('Error') || _status!.contains('No se pudo')
                        ? Colors.red.shade700
                        : cs.onSurface.withValues(alpha: 0.8),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
