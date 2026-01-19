import '../../../data/dao/db.dart';

/// Servicio para gestión de categorías de movimientos de tesorería
class CategoriaMovimientoService {
  /// Obtiene todas las categorías (activas o todas según parámetro)
  static Future<List<Map<String, dynamic>>> obtenerCategorias({
    bool soloActivas = true,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      String? where;
      if (soloActivas) {
        where = 'activa = 1';
      }
      
      final rows = await db.query(
        'categoria_movimiento',
        where: where,
        orderBy: 'nombre ASC',
      );
      
      return rows;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.obtener',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Obtiene categorías filtradas por tipo
  static Future<List<Map<String, dynamic>>> obtenerCategoriasPorTipo({
    required String tipo,
    bool soloActivas = true,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      final where = soloActivas
          ? "(tipo = ? OR tipo = 'AMBOS') AND activa = 1"
          : "(tipo = ? OR tipo = 'AMBOS')";
      
      final rows = await db.query(
        'categoria_movimiento',
        where: where,
        whereArgs: [tipo],
        orderBy: 'nombre ASC',
      );
      
      return rows;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.obtenerPorTipo',
        error: e,
        stackTrace: st,
        payload: {'tipo': tipo},
      );
      rethrow;
    }
  }

  /// Obtiene una categoría por ID
  static Future<Map<String, dynamic>?> obtenerCategoriaPorId(int id) async {
    try {
      final db = await AppDatabase.instance();
      
      final rows = await db.query(
        'categoria_movimiento',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      
      return rows.isEmpty ? null : rows.first;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.obtenerPorId',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Obtiene el nombre de una categoría por su código
  /// Retorna el nombre si existe, o null si no se encuentra
  static Future<String?> obtenerNombrePorCodigo(String codigo) async {
    try {
      final db = await AppDatabase.instance();
      
      final rows = await db.query(
        'categoria_movimiento',
        columns: ['nombre'],
        where: 'codigo = ?',
        whereArgs: [codigo.toUpperCase()],
        limit: 1,
      );
      
      return rows.isEmpty ? null : (rows.first['nombre'] as String?);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.obtenerNombrePorCodigo',
        error: e,
        stackTrace: st,
        payload: {'codigo': codigo},
      );
      return null; // Error silencioso, retornar null
    }
  }

  /// Valida si un código ya existe (para evitar duplicados)
  /// Retorna true si el código ya está en uso
  static Future<bool> existeCodigo(String codigo, {int? excluyendoId}) async {
    try {
      final db = await AppDatabase.instance();
      
      String where = 'codigo = ?';
      List<dynamic> whereArgs = [codigo.toUpperCase()];
      
      if (excluyendoId != null) {
        where += ' AND id != ?';
        whereArgs.add(excluyendoId);
      }
      
      final rows = await db.query(
        'categoria_movimiento',
        where: where,
        whereArgs: whereArgs,
        limit: 1,
      );
      
      return rows.isNotEmpty;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.existeCodigo',
        error: e,
        stackTrace: st,
        payload: {'codigo': codigo, 'excluyendoId': excluyendoId},
      );
      rethrow;
    }
  }

  /// Genera un código automático a partir del nombre
  /// Toma las 4 primeras letras de cada palabra, en mayúsculas
  static String generarCodigo(String nombre) {
    if (nombre.trim().isEmpty) return '';
    
    final palabras = nombre.trim().split(RegExp(r'\s+'));
    final buffer = StringBuffer();
    
    for (final palabra in palabras) {
      if (palabra.isNotEmpty) {
        // Tomar hasta 4 caracteres de cada palabra
        final chars = palabra.substring(0, palabra.length < 4 ? palabra.length : 4);
        buffer.write(chars);
      }
    }
    
    return buffer.toString().toUpperCase();
  }

  /// Crea una nueva categoría
  static Future<int> crearCategoria({
    required String codigo,
    required String nombre,
    required String tipo,
    String? icono,
    String? observacion,
    bool activa = true,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Validar que el código no exista
      final existe = await existeCodigo(codigo);
      if (existe) {
        throw Exception('El código $codigo ya está en uso');
      }
      
      final id = await db.insert('categoria_movimiento', {
        'codigo': codigo.toUpperCase(),
        'nombre': nombre.trim(),
        'tipo': tipo,
        'icono': icono,
        'observacion': observacion?.trim(),
        'activa': activa ? 1 : 0,
        'created_ts': DateTime.now().millisecondsSinceEpoch,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
      });
      
      return id;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.crear',
        error: e,
        stackTrace: st,
        payload: {
          'codigo': codigo,
          'nombre': nombre,
          'tipo': tipo,
          'icono': icono,
          'observacion': observacion,
          'activa': activa,
        },
      );
      rethrow;
    }
  }

  /// Actualiza una categoría existente
  static Future<void> actualizarCategoria({
    required int id,
    required String codigo,
    required String nombre,
    required String tipo,
    String? icono,
    String? observacion,
    required bool activa,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Validar que el código no exista (excluyendo la categoría actual)
      final existe = await existeCodigo(codigo, excluyendoId: id);
      if (existe) {
        throw Exception('El código $codigo ya está en uso');
      }
      
      await db.update(
        'categoria_movimiento',
        {
          'codigo': codigo.toUpperCase(),
          'nombre': nombre.trim(),
          'tipo': tipo,
          'icono': icono,
          'observacion': observacion?.trim(),
          'activa': activa ? 1 : 0,
          'updated_ts': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.actualizar',
        error: e,
        stackTrace: st,
        payload: {
          'id': id,
          'codigo': codigo,
          'nombre': nombre,
          'tipo': tipo,
          'icono': icono,
          'activa': activa,
        },
      );
      rethrow;
    }
  }

  /// Elimina una categoría (soft delete: marca como inactiva)
  static Future<void> eliminarCategoria(int id) async {
    try {
      final db = await AppDatabase.instance();
      
      await db.update(
        'categoria_movimiento',
        {
          'activa': 0,
          'updated_ts': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.eliminar',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Reactiva una categoría
  static Future<void> activarCategoria(int id) async {
    try {
      final db = await AppDatabase.instance();
      
      await db.update(
        'categoria_movimiento',
        {
          'activa': 1,
          'updated_ts': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.activar',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Verifica si una categoría tiene movimientos asociados
  /// Retorna el número de movimientos asociados
  static Future<int> contarMovimientosAsociados(String categoria) async {
    try {
      final db = await AppDatabase.instance();
      
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM evento_movimiento WHERE categoria = ? AND eliminado = 0',
        [categoria],
      );
      
      return (result.first['count'] as int?) ?? 0;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.contarMovimientos',
        error: e,
        stackTrace: st,
        payload: {'categoria': categoria},
      );
      rethrow;
    }
  }

  /// Elimina físicamente una categoría (solo si no tiene movimientos asociados)
  static Future<void> eliminarCategoriaFisicamente(int id) async {
    try {
      final db = await AppDatabase.instance();
      
      // Primero obtener el código para verificar movimientos
      final cat = await obtenerCategoriaPorId(id);
      if (cat == null) {
        throw Exception('Categoría no encontrada');
      }
      
      final codigo = cat['codigo'] as String;
      final count = await contarMovimientosAsociados(codigo);
      
      if (count > 0) {
        throw Exception('No se puede eliminar una categoría con movimientos asociados');
      }
      
      // Eliminar físicamente
      await db.delete(
        'categoria_movimiento',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'categoria_movimiento.eliminarFisicamente',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }
}
