import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../data/dao/db.dart';

/// Servicio para manejo de archivos adjuntos a movimientos
class AttachmentService {
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB

  /// Seleccionar archivo desde galería
  Future<File?> pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile == null) return null;
      
      final file = File(pickedFile.path);
      await _validateFileSize(file);
      
      return file;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'attachment.pick_gallery',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Tomar foto con cámara
  Future<File?> pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);
      
      if (pickedFile == null) return null;
      
      final file = File(pickedFile.path);
      await _validateFileSize(file);
      
      return file;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'attachment.pick_camera',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Seleccionar archivo PDF
  Future<File?> pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      
      if (result == null || result.files.isEmpty) return null;
      
      final filePath = result.files.single.path;
      if (filePath == null) return null;
      
      final file = File(filePath);
      await _validateFileSize(file);
      
      return file;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'attachment.pick_pdf',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Validar tamaño del archivo
  Future<void> _validateFileSize(File file) async {
    final size = await file.length();
    if (size > maxFileSizeBytes) {
      throw Exception(
          'El archivo es demasiado grande (${_formatBytes(size)}). Máximo permitido: ${_formatBytes(maxFileSizeBytes)}');
    }
  }

  /// Guardar archivo en directorio persistente de la app
  /// Mantiene el nombre original del archivo y agrega autoincremental si ya existe
  Future<Map<String, dynamic>> saveAttachment(File file) async {
    try {
      await _validateFileSize(file);
      
      final appDir = await getApplicationDocumentsDirectory();
      final attachmentsDir = Directory(p.join(appDir.path, 'attachments'));
      
      if (!await attachmentsDir.exists()) {
        await attachmentsDir.create(recursive: true);
      }
      
      // Obtener nombre original del archivo
      final originalName = p.basename(file.path);
      final extension = p.extension(originalName);
      final nameWithoutExt = p.basenameWithoutExtension(originalName);
      
      // Verificar si el archivo ya existe y agregar autoincremental
      String fileName = originalName;
      String destinationPath = p.join(attachmentsDir.path, fileName);
      int counter = 1;
      
      while (await File(destinationPath).exists()) {
        fileName = '${nameWithoutExt}_$counter$extension';
        destinationPath = p.join(attachmentsDir.path, fileName);
        counter++;
      }
      
      // Copiar archivo
      final savedFile = await file.copy(destinationPath);
      final fileSize = await savedFile.length();
      
      return {
        'archivo_local_path': destinationPath,
        'archivo_nombre': fileName,
        'archivo_tipo': _getMimeType(extension),
        'archivo_size': fileSize,
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'attachment.save',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Eliminar archivo adjunto
  Future<void> deleteAttachment(String? localPath) async {
    if (localPath == null || localPath.isEmpty) return;
    
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'attachment.delete',
        error: e,
        stackTrace: st,
      );
      // No rethrow - no es crítico si falla el borrado
    }
  }

  /// Obtener MIME type básico según extensión
  String _getMimeType(String extension) {
    final ext = extension.toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.pdf':
        return 'application/pdf';
      case '.gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  /// Formatear bytes a texto legible
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Verificar si el archivo existe localmente
  Future<bool> fileExists(String? localPath) async {
    if (localPath == null || localPath.isEmpty) return false;
    
    try {
      final file = File(localPath);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }
}
