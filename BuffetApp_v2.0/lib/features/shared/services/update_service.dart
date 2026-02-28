import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/dao/db.dart';

class UpdateService {
  final Dio _dio = Dio();

  /// Espera una URL completa al JSON de metadata.
  /// El JSON debe contener al menos: { "versionCode": 20001, "versionName": "2.0.1", "apk_url": "https://..." }
  Future<Map<String, dynamic>?> fetchRemoteMeta(Uri metaUrl) async {
    try {
      final r = await _dio.getUri(metaUrl);
      if (r.statusCode == 200) {
        if (r.data is Map<String, dynamic>) return r.data as Map<String, dynamic>;
        // Si viene como texto/JSON string
        if (r.data is String) return json.decode(r.data as String) as Map<String, dynamic>;
      }
      return null;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'update.fetch_meta', error: e, stackTrace: st, payload: {'url': metaUrl.toString()});
      return null;
    }
  }

  Future<int> currentVersionCode() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'update.current_version', error: e, stackTrace: st);
      return 0;
    }
  }

  /// Descarga el APK y lo guarda en el directorio de descargas de la app.
  /// onProgress recibe (received, total)
  Future<File?> downloadApk(String apkUrl, String fileName, void Function(int, int)? onProgress) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/$fileName');
      await _dio.download(apkUrl, out.path, onReceiveProgress: onProgress);
      return out;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'update.download_apk', error: e, stackTrace: st, payload: {'apkUrl': apkUrl});
      return null;
    }
  }

  Future<void> openApk(File apkFile) async {
    try {
      await OpenFilex.open(apkFile.path);
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'update.open_apk', error: e, stackTrace: st, payload: {'path': apkFile.path});
      rethrow;
    }
  }
}
