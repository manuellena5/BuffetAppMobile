import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/categoria_movimiento_service.dart';
import '../services/categoria_import_export_service.dart';
import 'categoria_movimiento_form_page.dart';
import 'importar_categorias_page.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../../core/theme/app_theme.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_header.dart';
import '../../shared/utils/category_icon_helper.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../../data/dao/db.dart';

/// Pantalla de Gestión de Categorías de Movimientos (según mockup)
class CategoriasMovimientoPage extends StatefulWidget {
  const CategoriasMovimientoPage({super.key});

  @override
  State<CategoriasMovimientoPage> createState() =>
      _CategoriasMovimientoPageState();
}

class _CategoriasMovimientoPageState extends State<CategoriasMovimientoPage> {
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _categoriasFiltradas = [];
  bool _loading = true;
  
  String _filtroTipo = 'TODOS'; // TODOS, INGRESO, EGRESO, AMBOS, INACTIVAS
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
  }

  Future<void> _cargarCategorias() async {
    setState(() => _loading = true);
    try {
      // Cargar TODAS las categorías (activas e inactivas)
      final categorias = await CategoriaMovimientoService.obtenerCategorias(
        soloActivas: false,
      );
      setState(() {
        _categorias = categorias;
        _aplicarFiltros();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar categorías. Intente nuevamente.')),
        );
      }
    }
  }

  void _aplicarFiltros() {
    var filtradas = List<Map<String, dynamic>>.from(_categorias);
    
    // Filtro por tipo
    if (_filtroTipo == 'INGRESO') {
      filtradas = filtradas.where((c) {
        final tipo = c['tipo'] as String;
        final activa = (c['activa'] as int) == 1;
        return activa && (tipo == 'INGRESO' || tipo == 'AMBOS');
      }).toList();
    } else if (_filtroTipo == 'EGRESO') {
      filtradas = filtradas.where((c) {
        final tipo = c['tipo'] as String;
        final activa = (c['activa'] as int) == 1;
        return activa && (tipo == 'EGRESO' || tipo == 'AMBOS');
      }).toList();
    } else if (_filtroTipo == 'AMBOS') {
      filtradas = filtradas.where((c) {
        final tipo = c['tipo'] as String;
        final activa = (c['activa'] as int) == 1;
        return activa && tipo == 'AMBOS';
      }).toList();
    } else if (_filtroTipo == 'INACTIVAS') {
      filtradas = filtradas.where((c) => (c['activa'] as int) == 0).toList();
    } else {
      // TODOS - solo activas
      filtradas = filtradas.where((c) => (c['activa'] as int) == 1).toList();
    }
    
    // Búsqueda
    if (_busqueda.isNotEmpty) {
      final busq = _busqueda.toLowerCase();
      filtradas = filtradas.where((c) {
        final nombre = (c['nombre'] as String).toLowerCase();
        final codigo = (c['codigo'] as String).toLowerCase();
        return nombre.contains(busq) || codigo.contains(busq);
      }).toList();
    }
    
    setState(() => _categoriasFiltradas = filtradas);
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? categoria}) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CategoriaMovimientoFormPage(categoria: categoria),
      ),
    );
    
    if (resultado == true) {
      _cargarCategorias();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;
    
    return ErpLayout(
      currentRoute: '/categorias',
      title: 'Categorías',
      actions: [
        IconButton(
          icon: const Icon(Icons.upload),
          tooltip: 'Importar',
          onPressed: _importarCategorias,
        ),
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: 'Exportar',
          onPressed: _exportarCategorias,
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: ResponsiveContainer(
        maxWidth: 1000,
        child: Column(
          children: [
            // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: context.appColors.bgSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                boxShadow: AppShadows.cardFor(context),
              ),
              child: TextField(
                onChanged: (value) {
                  setState(() => _busqueda = value);
                  _aplicarFiltros();
                },
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código',
                  hintStyle: TextStyle(color: context.appColors.textMuted),
                  prefixIcon: Icon(Icons.search, color: context.appColors.textMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: context.appColors.bgSurface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          
          // Chips de filtro
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterChip('Todos', 'TODOS'),
                const SizedBox(width: 8),
                _buildFilterChip('Ingresos', 'INGRESO'),
                const SizedBox(width: 8),
                _buildFilterChip('Egresos', 'EGRESO'),
                const SizedBox(width: 8),
                _buildFilterChip('Ambos', 'AMBOS'),
                const SizedBox(width: 8),
                _buildFilterChip('Inactivas', 'INACTIVAS'),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Lista de categorías
          Expanded(
            child: _loading
                ? SkeletonLoader.table(rows: 5, columns: 4)
                : _categoriasFiltradas.isEmpty
                    ? _buildEmpty()
                    : _buildVistaTabla(),
          ),
        ],
      ),
      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filtroTipo == value;
    final cs = context.appColors;

    return InkWell(
      onTap: () {
        setState(() => _filtroTipo = value);
        _aplicarFiltros();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : cs.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.accent : cs.border,
          ),
          boxShadow: isSelected ? AppShadows.glowFor(AppColors.accent) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : cs.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return EmptyState(
      icon: Icons.category_outlined,
      title: 'No hay categorías',
      subtitle: _busqueda.isNotEmpty
          ? 'No se encontraron resultados'
          : 'Tocá + para crear una categoría',
    );
  }

  Widget _buildVistaTabla() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Código')),
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: _categoriasFiltradas.map((cat) {
            final activa = (cat['activa'] as int) == 1;
            final tipo = cat['tipo'] as String;
            final icono = cat['icono'] as String?;
            final nombre = cat['nombre'] as String;
            final codigo = cat['codigo'] as String;

            Color tipoColor;
            String tipoText;
            
            switch (tipo) {
              case 'INGRESO':
                tipoColor = AppColors.ingreso;
                tipoText = 'Ingreso';
                break;
              case 'EGRESO':
                tipoColor = AppColors.egreso;
                tipoText = 'Egreso';
                break;
              default:
                tipoColor = AppColors.advertencia;
                tipoText = 'Ambos';
            }

            return DataRow(
              cells: [
                DataCell(Text(codigo)),
                DataCell(
                  Row(
                    children: [
                      if (icono != null)
                        Icon(CategoryIconHelper.fromName(icono), size: 20, color: tipoColor),
                      const SizedBox(width: 8),
                      Text(nombre),
                    ],
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: tipoColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tipoColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      tipoText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tipoColor,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Builder(builder: (context) {
                    final cs = context.appColors;
                    return Chip(
                      label: Text(
                        activa ? 'Activa' : 'Inactiva',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: activa ? AppColors.ingreso : cs.textMuted,
                        ),
                      ),
                      backgroundColor: activa
                          ? AppColors.ingreso.withOpacity(0.12)
                          : cs.bgElevated,
                      side: BorderSide(
                        color: activa
                            ? AppColors.ingreso.withOpacity(0.4)
                            : cs.border,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  }),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: 'Editar',
                        onPressed: () => _abrirFormulario(categoria: cat),
                      ),
                      if (activa)
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: AppColors.egreso),
                          tooltip: 'Eliminar',
                          onPressed: () => _eliminarCategoria(cat),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.restore, size: 18, color: AppColors.ingreso),
                          tooltip: 'Reactivar',
                          onPressed: () async {
                            await CategoriaMovimientoService.activarCategoria(cat['id'] as int);
                            _cargarCategorias();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Categoría reactivada'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _eliminarCategoria(Map<String, dynamic> cat) async {
    final codigo = cat['codigo'] as String;
    final nombre = cat['nombre'] as String;
    
    // Verificar si tiene movimientos asociados
    final count = await CategoriaMovimientoService.contarMovimientosAsociados(codigo);
    
    if (count > 0) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No se puede eliminar'),
            content: Text(
              'La categoría "$nombre" tiene $count movimiento(s) asociado(s).\n\n'
              'No se puede eliminar una categoría con movimientos.\n\n'
              'Podés desactivarla en su lugar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
      return;
    }
    
    // Confirmar eliminación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Categoría'),
        content: Text(
          '¿Estás seguro de eliminar la categoría "$nombre"?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    
    if (confirmar != true) return;
    
    try {
      await CategoriaMovimientoService.eliminarCategoria(cat['id'] as int);
      _cargarCategorias();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Categoría eliminada correctamente'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al eliminar. Intente nuevamente.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _importarCategorias() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const ImportarCategoriasPage(),
      ),
    );
    
    if (resultado == true) {
      _cargarCategorias();
    }
  }

  Future<void> _exportarCategorias() async {
    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final suggestedName = 'categorias_export_$timestamp.xlsx';
      
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar archivo de categorías',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputPath == null) return;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Exportando categorías...'),
              ],
            ),
          ),
        );
      }

      final tempPath = await CategoriaImportExportService.instance.exportarCategorias();
      final tempFile = File(tempPath);
      await tempFile.copy(outputPath);
      await tempFile.delete();

      if (mounted) Navigator.pop(context);

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text('Exportación exitosa'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Las categorías se exportaron correctamente a:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    outputPath,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  final directory = File(outputPath).parent.path;
                  await Process.run('explorer', [directory]);
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Abrir carpeta'),
              ),
            ],
          ),
        );
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'categorias.exportar',
        error: e.toString(),
        stackTrace: stack,
      );

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red[700]),
                const SizedBox(width: 8),
                const Text('Error'),
              ],
            ),
            content: Text('Error al exportar categorías:\n\n${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }
}
