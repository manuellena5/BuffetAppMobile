import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../data/dao/db.dart';

/// Servicio para guardar, redimensionar y gestionar imágenes de productos.
///
/// Las imágenes se almacenan en `<app_docs>/product_images/` con nombre
/// determinístico basado en el ID del producto para facilitar futura
/// sincronización con Supabase Storage.
class ProductImageService {
  ProductImageService._();
  static final ProductImageService _instance = ProductImageService._();
  factory ProductImageService() => _instance;

  /// Tamaño máximo en píxeles (lado mayor).
  static const int maxDimension = 400;

  /// Calidad JPEG (0-100).
  static const int jpegQuality = 80;

  /// Directorio donde se guardan las imágenes.
  Future<Directory> _imageDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final picsDir = Directory(p.join(dir.path, 'product_images'));
    if (!await picsDir.exists()) {
      await picsDir.create(recursive: true);
    }
    return picsDir;
  }

  /// Nombre determinístico para futuro sync.
  /// Formato: `prod_{productId}.jpg`
  /// Si el producto es nuevo (aún sin ID), usa un timestamp temporal
  /// que se renombra después del insert.
  String _fileName(int? productId) {
    if (productId != null) {
      return 'prod_$productId.jpg';
    }
    return 'prod_tmp_${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  /// Procesa y guarda una imagen desde un path de origen (cámara/galería).
  ///
  /// Redimensiona a [maxDimension] y comprime como JPEG.
  /// Retorna el path final donde quedó guardada o `null` si hubo error.
  Future<String?> saveImage({
    required String sourcePath,
    int? productId,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return null;

      final bytes = await sourceFile.readAsBytes();
      final resized = await _resizeAndCompress(bytes);
      if (resized == null) return null;

      final dir = await _imageDir();
      final destPath = p.join(dir.path, _fileName(productId));

      // Si ya existía una imagen anterior para este producto, la reemplazamos
      final destFile = File(destPath);
      await destFile.writeAsBytes(resized, flush: true);

      return destPath;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'product_image.save',
        error: e.toString(),
        stackTrace: stack,
        payload: {'source': sourcePath, 'productId': productId},
      );
      return null;
    }
  }

  /// Renombra una imagen temporal al nombre definitivo con el ID del producto.
  /// Se usa después de crear un producto nuevo (insert) cuando ya tenemos el ID.
  Future<String?> renameToProductId({
    required String currentPath,
    required int productId,
  }) async {
    try {
      final file = File(currentPath);
      if (!await file.exists()) return currentPath;

      final dir = await _imageDir();
      final newPath = p.join(dir.path, _fileName(productId));

      // Si el nombre ya es correcto, no hacer nada
      if (currentPath == newPath) return currentPath;

      final renamed = await file.rename(newPath);
      return renamed.path;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'product_image.rename',
        error: e.toString(),
        stackTrace: stack,
        payload: {'currentPath': currentPath, 'productId': productId},
      );
      // Retornar path original si falla el rename
      return currentPath;
    }
  }

  /// Elimina la imagen de un producto del disco.
  Future<void> deleteImage(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return;
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'product_image.delete',
        error: e.toString(),
        stackTrace: stack,
        payload: {'path': imagePath},
      );
    }
  }

  /// Verifica si una imagen existe en disco.
  bool imageExists(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return false;
    return File(imagePath).existsSync();
  }

  /// Redimensiona y comprime la imagen a JPEG.
  Future<Uint8List?> _resizeAndCompress(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      img.Image resized;
      if (decoded.width > maxDimension || decoded.height > maxDimension) {
        // Mantener aspect ratio, ajustar al lado mayor
        if (decoded.width >= decoded.height) {
          resized = img.copyResize(decoded, width: maxDimension);
        } else {
          resized = img.copyResize(decoded, height: maxDimension);
        }
      } else {
        resized = decoded;
      }

      return Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality));
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'product_image.resize',
        error: e.toString(),
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Limpia imágenes huérfanas (en disco pero no referenciadas en DB).
  /// Útil para mantenimiento periódico.
  Future<int> cleanOrphanImages() async {
    try {
      final dir = await _imageDir();
      if (!await dir.exists()) return 0;

      final db = await AppDatabase.instance();
      final products = await db.query('products', columns: ['imagen']);
      final usedPaths = products
          .map((r) => r['imagen'] as String?)
          .where((p) => p != null && p.isNotEmpty)
          .toSet();

      int removed = 0;
      await for (final entity in dir.list()) {
        if (entity is File && !usedPaths.contains(entity.path)) {
          await entity.delete();
          removed++;
        }
      }
      return removed;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'product_image.clean_orphans',
        error: e.toString(),
        stackTrace: stack,
      );
      return 0;
    }
  }
}
