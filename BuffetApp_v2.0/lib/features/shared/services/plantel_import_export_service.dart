import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/dao/db.dart';
import 'plantel_service.dart';

/// Servicio para importar/exportar jugadores desde/hacia Excel.
/// 
/// Formato del Excel:
/// - Columna A: Nombre (requerido)
/// - Columna B: Rol (JUGADOR/DT/AYUDANTE/PF/OTRO, requerido)
/// - Columna C: Contacto (opcional)
/// - Columna D: DNI (opcional)
/// - Columna E: Fecha Nacimiento (opcional, formato DD/MM/YYYY)
/// - Columna F: Observaciones (opcional)
class PlantelImportExportService {
  PlantelImportExportService._();
  static final PlantelImportExportService instance = PlantelImportExportService._();

  final _plantelSvc = PlantelService.instance;

  /// Roles válidos para validación
  static const rolesValidos = ['JUGADOR', 'DT', 'AYUDANTE', 'PF', 'OTRO'];

  /// Genera un archivo Excel de template con instrucciones y ejemplos.
  /// Retorna la ruta del archivo generado.
  Future<String> generarTemplate() async {
    try {
      final excel = Excel.createExcel();
      
      // Usar Sheet1 por defecto para Instrucciones
      final sheet = excel['Sheet1'];

      // Estilo para encabezados
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: "FF0000FF",
        fontColorHex: "FFFFFFFF",
      );

      // Instrucciones
      sheet.cell(CellIndex.indexByString('A1')).value = 'INSTRUCCIONES PARA IMPORTAR JUGADORES/STAFF';
      sheet.cell(CellIndex.indexByString('A1')).cellStyle = headerStyle;
      
      sheet.cell(CellIndex.indexByString('A3')).value = '1. Complete la hoja "Jugadores" con los datos';
      sheet.cell(CellIndex.indexByString('A4')).value = '2. Columnas requeridas: Nombre, Rol';
      sheet.cell(CellIndex.indexByString('A5')).value = '3. Roles válidos: JUGADOR, DT, AYUDANTE, PF, OTRO';
      sheet.cell(CellIndex.indexByString('A6')).value = '4. Fecha Nacimiento formato: DD/MM/YYYY (ejemplo: 15/03/1995)';
      sheet.cell(CellIndex.indexByString('A7')).value = '5. Nombres duplicados serán ignorados';

      // Hoja de jugadores con ejemplos
      final jugadoresSheet = excel['Jugadores'];
      
      // Encabezados
      jugadoresSheet.cell(CellIndex.indexByString('A1')).value = 'Nombre';
      jugadoresSheet.cell(CellIndex.indexByString('B1')).value = 'Rol';
      jugadoresSheet.cell(CellIndex.indexByString('C1')).value = 'Contacto';
      jugadoresSheet.cell(CellIndex.indexByString('D1')).value = 'DNI';
      jugadoresSheet.cell(CellIndex.indexByString('E1')).value = 'Fecha Nacimiento';
      jugadoresSheet.cell(CellIndex.indexByString('F1')).value = 'Observaciones';

      for (var col in ['A', 'B', 'C', 'D', 'E', 'F']) {
        jugadoresSheet.cell(CellIndex.indexByString('${col}1')).cellStyle = headerStyle;
      }

      // Ejemplos
      jugadoresSheet.cell(CellIndex.indexByString('A2')).value = 'Juan Pérez';
      jugadoresSheet.cell(CellIndex.indexByString('B2')).value = 'JUGADOR';
      jugadoresSheet.cell(CellIndex.indexByString('C2')).value = '3512345678';
      jugadoresSheet.cell(CellIndex.indexByString('D2')).value = '12345678';
      jugadoresSheet.cell(CellIndex.indexByString('E2')).value = '15/03/1995';
      jugadoresSheet.cell(CellIndex.indexByString('F2')).value = 'Delantero';

      jugadoresSheet.cell(CellIndex.indexByString('A3')).value = 'Carlos Díaz';
      jugadoresSheet.cell(CellIndex.indexByString('B3')).value = 'DT';
      jugadoresSheet.cell(CellIndex.indexByString('C3')).value = '3519876543';
      jugadoresSheet.cell(CellIndex.indexByString('D3')).value = '87654321';
      jugadoresSheet.cell(CellIndex.indexByString('E3')).value = '20/08/1975';
      jugadoresSheet.cell(CellIndex.indexByString('F3')).value = 'Director Técnico';

      // Guardar
      final dir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${dir.path}/plantel_template_$timestamp.xlsx';
      
      final bytes = excel.encode();
      if (bytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        return filePath;
      } else {
        throw Exception('Error al generar archivo Excel');
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'plantel_import_export.generar_template',
        error: e.toString(),
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Lee un archivo Excel y retorna una lista de jugadores validados.
  /// Retorna un Map con:
  /// - 'jugadores': List<Map<String, dynamic>> con datos validados
  /// - 'errores': List<String> con mensajes de error por fila
  Future<Map<String, dynamic>> leerArchivoExcel(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      final jugadores = <Map<String, dynamic>>[];
      final errores = <String>[];

      // Buscar hoja "Jugadores" o usar la primera disponible
      String? sheetName;
      if (excel.sheets.containsKey('Jugadores')) {
        sheetName = 'Jugadores';
      } else {
        sheetName = excel.sheets.keys.firstOrNull;
      }

      if (sheetName == null) {
        throw Exception('El archivo no contiene hojas válidas');
      }

      final sheet = excel.sheets[sheetName];
      if (sheet == null) {
        throw Exception('No se pudo leer la hoja $sheetName');
      }

      // Leer desde fila 2 (saltar encabezados)
      for (var i = 1; i < sheet.maxRows; i++) {
        try {
          final nombre = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i)).value?.toString().trim();
          final rol = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i)).value?.toString().trim().toUpperCase();
          final contacto = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i)).value?.toString().trim();
          final dni = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i)).value?.toString().trim();
          final fechaNacStr = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i)).value?.toString().trim();
          final observaciones = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i)).value?.toString().trim();

          // Saltar filas vacías
          if (nombre == null || nombre.isEmpty) continue;

          // Validar rol
          if (rol == null || !rolesValidos.contains(rol)) {
            errores.add('Fila ${i + 1}: Rol inválido "$rol". Debe ser: ${rolesValidos.join(", ")}');
            continue;
          }

          // Parsear fecha de nacimiento
          String? fechaNacimiento;
          if (fechaNacStr != null && fechaNacStr.isNotEmpty) {
            try {
              // Intentar parsear DD/MM/YYYY
              final parts = fechaNacStr.split('/');
              if (parts.length == 3) {
                final dia = int.parse(parts[0]);
                final mes = int.parse(parts[1]);
                final anio = int.parse(parts[2]);
                final fecha = DateTime(anio, mes, dia);
                fechaNacimiento = DateFormat('yyyy-MM-dd').format(fecha);
              }
            } catch (_) {
              errores.add('Fila ${i + 1}: Fecha de nacimiento inválida "$fechaNacStr". Use formato DD/MM/YYYY');
              continue;
            }
          }

          jugadores.add({
            'nombre': nombre,
            'rol': rol,
            'contacto': contacto,
            'dni': dni,
            'fecha_nacimiento': fechaNacimiento,
            'observaciones': observaciones,
            'fila_excel': i + 1, // Para referencia en errores
          });
        } catch (e) {
          errores.add('Fila ${i + 1}: Error al leer datos - ${e.toString()}');
        }
      }

      return {
        'jugadores': jugadores,
        'errores': errores,
      };
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'plantel_import_export.leer_archivo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'file_path': filePath},
      );
      rethrow;
    }
  }

  /// Importa jugadores validando duplicados.
  /// Retorna un Map con:
  /// - 'creados': int cantidad de jugadores creados
  /// - 'duplicados': List<String> nombres de jugadores duplicados
  /// - 'errores': List<String> errores durante la importación
  Future<Map<String, dynamic>> importarJugadores(List<Map<String, dynamic>> jugadores) async {
    int creados = 0;
    final duplicados = <String>[];
    final errores = <String>[];

    for (final jugador in jugadores) {
      try {
        await _plantelSvc.crearEntidad(
          nombre: jugador['nombre'],
          rol: jugador['rol'],
          contacto: jugador['contacto'],
          dni: jugador['dni'],
          fechaNacimiento: jugador['fecha_nacimiento'],
          observaciones: jugador['observaciones'],
        );
        creados++;
      } catch (e) {
        if (e.toString().contains('Ya existe')) {
          duplicados.add(jugador['nombre']);
        } else {
          errores.add('${jugador['nombre']}: ${e.toString()}');
          await AppDatabase.logLocalError(
            scope: 'plantel_import_export.importar_jugador',
            error: e.toString(),
            payload: {'jugador': jugador},
          );
        }
      }
    }

    return {
      'creados': creados,
      'duplicados': duplicados,
      'errores': errores,
    };
  }

  /// Exporta el listado actual de jugadores a Excel.
  /// Retorna la ruta del archivo generado.
  Future<String> exportarJugadores({
    String? rol,
    bool soloActivos = true,
  }) async {
    try {
      final jugadores = await _plantelSvc.listarEntidades(
        rol: rol,
        soloActivos: soloActivos,
      );

      final excel = Excel.createExcel();
      
      // Usar Sheet1 por defecto para Plantel
      final sheet = excel['Sheet1'];

      // Estilo para encabezados
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: "FF0000FF",
        fontColorHex: "FFFFFFFF",
      );

      // Encabezados
      final headers = ['Nombre', 'Rol', 'Estado', 'Contacto', 'DNI', 'Fecha Nacimiento', 'Observaciones'];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = headers[i];
        cell.cellStyle = headerStyle;
      }

      // Datos
      for (var i = 0; i < jugadores.length; i++) {
        final jugador = jugadores[i];
        final row = i + 1;

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = 
            jugador['nombre']?.toString() ?? '';
        
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = 
            jugador['rol']?.toString() ?? '';
        
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = 
            (jugador['estado_activo'] as int?) == 1 ? 'Activo' : 'Baja';
        
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = 
            jugador['contacto']?.toString() ?? '';
        
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = 
            jugador['dni']?.toString() ?? '';

        // Formatear fecha de nacimiento
        final fechaNac = jugador['fecha_nacimiento']?.toString();
        if (fechaNac != null && fechaNac.isNotEmpty) {
          try {
            final fecha = DateTime.parse(fechaNac);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = 
                DateFormat('dd/MM/yyyy').format(fecha);
          } catch (_) {
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = 
                fechaNac;
          }
        }
        
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = 
            jugador['observaciones']?.toString() ?? '';
      }

      // Guardar
      final dir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final estadoStr = soloActivos ? 'activos' : 'todos';
      final rolStr = rol ?? 'todos';
      final filePath = '${dir.path}/plantel_${rolStr}_${estadoStr}_$timestamp.xlsx';
      
      final bytes = excel.encode();
      if (bytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        return filePath;
      } else {
        throw Exception('Error al generar archivo Excel');
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'plantel_import_export.exportar',
        error: e.toString(),
        stackTrace: stack,
        payload: {'rol': rol, 'solo_activos': soloActivos},
      );
      rethrow;
    }
  }

  /// Comparte el archivo Excel generado.
  Future<void> compartirArchivo(String filePath) async {
    try {
      final xFile = XFile(filePath);
      await Share.shareXFiles(
        [xFile],
        subject: 'Plantel - Exportación',
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'plantel_import_export.compartir',
        error: e.toString(),
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
