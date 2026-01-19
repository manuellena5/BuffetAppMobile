import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../data/dao/db.dart';
import 'categoria_movimiento_service.dart';

/// Servicio para importar y exportar categorías de movimientos en Excel
class CategoriaImportExportService {
  static final CategoriaImportExportService instance = CategoriaImportExportService._();
  CategoriaImportExportService._();

  /// Genera un archivo Excel de plantilla para importación
  Future<String> generarTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['Categorias'];

    // Headers
    sheet.appendRow([
      'Código',
      'Nombre',
      'Tipo',
      'Icono',
      'Observación',
    ]);

    // Ejemplos
    sheet.appendRow([
      'CUOT',
      'Cuotas Sociales',
      'INGRESO',
      'attach_money',
      'Ingresos mensuales de cuotas de socios',
    ]);

    sheet.appendRow([
      'GASTOS',
      'Gastos Generales',
      'EGRESO',
      'payment',
      'Gastos operativos varios del club',
    ]);

    sheet.appendRow([
      'VENTA',
      'Ventas de Buffet',
      'AMBOS',
      'restaurant',
      'Ingresos y gastos relacionados al buffet',
    ]);

    // Instrucciones en otra hoja
    final instrSheet = excel['Instrucciones'];
    instrSheet.appendRow(['INSTRUCCIONES DE IMPORTACIÓN']);
    instrSheet.appendRow(['']);
    instrSheet.appendRow(['1. Complete la hoja "Categorias" con sus datos']);
    instrSheet.appendRow(['2. Columnas REQUERIDAS: Código, Nombre, Tipo']);
    instrSheet.appendRow(['3. Tipos válidos: INGRESO, EGRESO, AMBOS']);
    instrSheet.appendRow(['4. Icono es opcional (usar nombres de Material Icons)']);
    instrSheet.appendRow(['5. Observación es opcional (descripción de la categoría)']);
    instrSheet.appendRow(['6. El Código debe ser único (máx. 10 caracteres)']);
    instrSheet.appendRow(['7. Categorías duplicadas serán ignoradas']);

    // Guardar
    final tempDir = await getTemporaryDirectory();
    final fileName = 'categorias_template_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = path.join(tempDir.path, fileName);
    
    final file = File(filePath);
    await file.writeAsBytes(excel.encode()!);

    return filePath;
  }

  /// Lee un archivo Excel y extrae categorías
  Future<Map<String, dynamic>> leerArchivoExcel(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      final categorias = <Map<String, dynamic>>[];
      final errores = <String>[];

      // Buscar hoja "Categorias"
      final sheetName = excel.tables.keys.firstWhere(
        (name) => name.toLowerCase().contains('categori'),
        orElse: () => excel.tables.keys.first,
      );

      final sheet = excel.tables[sheetName];
      if (sheet == null) {
        errores.add('No se encontró la hoja de datos');
        return {'categorias': categorias, 'errores': errores};
      }

      // Encontrar headers
      int headerRowIndex = -1;
      Map<String, int> columnIndexes = {};

      for (int i = 0; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final firstCell = row[0]?.value?.toString().toLowerCase() ?? '';
        
        if (firstCell.contains('código') || firstCell.contains('codigo')) {
          headerRowIndex = i;
          
          for (int j = 0; j < row.length; j++) {
            final header = row[j]?.value?.toString().toLowerCase() ?? '';
            if (header.contains('código') || header.contains('codigo')) {
              columnIndexes['codigo'] = j;
            } else if (header.contains('nombre')) {
              columnIndexes['nombre'] = j;
            } else if (header.contains('tipo')) {
              columnIndexes['tipo'] = j;
            } else if (header.contains('icono')) {
              columnIndexes['icono'] = j;
            } else if (header.contains('observación') || header.contains('observacion')) {
              columnIndexes['observacion'] = j;
            }
          }
          break;
        }
      }

      if (headerRowIndex == -1) {
        errores.add('No se encontraron las columnas requeridas (Código, Nombre, Tipo)');
        return {'categorias': categorias, 'errores': errores};
      }

      // Leer datos
      for (int i = headerRowIndex + 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        
        final codigo = row.elementAtOrNull(columnIndexes['codigo'] ?? 0)?.value?.toString().trim().toUpperCase();
        final nombre = row.elementAtOrNull(columnIndexes['nombre'] ?? 1)?.value?.toString().trim();
        final tipo = row.elementAtOrNull(columnIndexes['tipo'] ?? 2)?.value?.toString().trim().toUpperCase();
        final icono = row.elementAtOrNull(columnIndexes['icono'] ?? 3)?.value?.toString().trim();
        final observacion = row.elementAtOrNull(columnIndexes['observacion'] ?? 4)?.value?.toString().trim();

        // Validar campos requeridos
        if (codigo == null || codigo.isEmpty) {
          if (nombre != null && nombre.isNotEmpty) {
            errores.add('Fila ${i + 1}: Código vacío');
          }
          continue;
        }

        if (nombre == null || nombre.isEmpty) {
          errores.add('Fila ${i + 1}: Nombre vacío');
          continue;
        }

        if (tipo == null || tipo.isEmpty) {
          errores.add('Fila ${i + 1}: Tipo vacío');
          continue;
        }

        // Validar tipo
        if (!['INGRESO', 'EGRESO', 'AMBOS'].contains(tipo)) {
          errores.add('Fila ${i + 1}: Tipo "$tipo" no válido (use INGRESO, EGRESO o AMBOS)');
          continue;
        }

        // Validar longitud código
        if (codigo.length > 10) {
          errores.add('Fila ${i + 1}: Código "$codigo" muy largo (máx. 10 caracteres)');
          continue;
        }

        categorias.add({
          'codigo': codigo,
          'nombre': nombre,
          'tipo': tipo,
          'icono': icono?.isNotEmpty == true ? icono : null,
          'observacion': observacion?.isNotEmpty == true ? observacion : null,
        });
      }

      return {'categorias': categorias, 'errores': errores};
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'categoria_import.leer_excel',
        error: e.toString(),
        stackTrace: stack,
      );
      return {
        'categorias': <Map<String, dynamic>>[],
        'errores': ['Error al leer archivo: ${e.toString()}'],
      };
    }
  }

  /// Importa categorías validando duplicados
  Future<Map<String, dynamic>> importarCategorias(List<Map<String, dynamic>> categorias) async {
    int creadas = 0;
    final duplicados = <String>[];
    final errores = <String>[];

    try {
      // Obtener categorías existentes
      final existentes = await CategoriaMovimientoService.obtenerCategorias(soloActivas: false);
      final codigosExistentes = existentes.map((c) => (c['codigo'] as String).toUpperCase()).toSet();
      final nombresExistentes = existentes.map((c) => (c['nombre'] as String).toLowerCase()).toSet();

      for (final cat in categorias) {
        final codigo = cat['codigo'] as String;
        final nombre = cat['nombre'] as String;

        // Verificar duplicados
        if (codigosExistentes.contains(codigo.toUpperCase())) {
          duplicados.add('Código: $codigo');
          continue;
        }

        if (nombresExistentes.contains(nombre.toLowerCase())) {
          duplicados.add('Nombre: $nombre');
          continue;
        }

        // Crear categoría
        try {
          await CategoriaMovimientoService.crearCategoria(
            codigo: codigo,
            nombre: nombre,
            tipo: cat['tipo'] as String,
            icono: cat['icono'] as String?,
            observacion: cat['observacion'] as String?,
            activa: true,
          );
          creadas++;
          
          // Agregar a sets para evitar duplicados dentro del mismo import
          codigosExistentes.add(codigo.toUpperCase());
          nombresExistentes.add(nombre.toLowerCase());
        } catch (e) {
          errores.add('Error al crear "$nombre": ${e.toString()}');
        }
      }

      return {
        'creadas': creadas,
        'duplicados': duplicados,
        'errores': errores,
      };
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'categoria_import.importar',
        error: e.toString(),
        stackTrace: stack,
      );
      throw Exception('Error al importar categorías: ${e.toString()}');
    }
  }

  /// Exporta todas las categorías a Excel
  Future<String> exportarCategorias() async {
    try {
      final categorias = await CategoriaMovimientoService.obtenerCategorias(soloActivas: false);

      final excel = Excel.createExcel();
      final sheet = excel['Categorias'];

      // Headers
      sheet.appendRow([
        'Código',
        'Nombre',
        'Tipo',
        'Icono',
        'Observación',
        'Estado',
      ]);

      // Datos
      for (final cat in categorias) {
        sheet.appendRow([
          cat['codigo'] as String,
          cat['nombre'] as String,
          cat['tipo'] as String,
          cat['icono']?.toString() ?? '',
          cat['observacion']?.toString() ?? '',
          (cat['activa'] as int) == 1 ? 'ACTIVA' : 'INACTIVA',
        ]);
      }

      // Guardar
      final tempDir = await getTemporaryDirectory();
      final fileName = 'categorias_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final filePath = path.join(tempDir.path, fileName);
      
      final file = File(filePath);
      await file.writeAsBytes(excel.encode()!);

      return filePath;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'categoria_export.exportar',
        error: e.toString(),
        stackTrace: stack,
      );
      throw Exception('Error al exportar categorías: ${e.toString()}');
    }
  }
}
