import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/categoria_movimiento_service.dart';
import '../services/categoria_iconos.dart';
import '../../shared/utils/category_icon_helper.dart';
import '../../shared/widgets/responsive_container.dart';

/// Formulario de Categoría (según mockup)
class CategoriaMovimientoFormPage extends StatefulWidget {
  final Map<String, dynamic>? categoria;

  const CategoriaMovimientoFormPage({super.key, this.categoria});

  @override
  State<CategoriaMovimientoFormPage> createState() =>
      _CategoriaMovimientoFormPageState();
}

class _CategoriaMovimientoFormPageState
    extends State<CategoriaMovimientoFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _codigoController = TextEditingController();
  final _observacionController = TextEditingController();

  String _tipo = 'INGRESO';
  bool _activa = true;
  bool _codigoEditado = false;
  bool _guardando = false;
  String? _iconoSeleccionado;

  @override
  void initState() {
    super.initState();

    if (widget.categoria != null) {
      _nombreController.text = widget.categoria!['nombre'] as String;
      _codigoController.text = widget.categoria!['codigo'] as String;
      _tipo = widget.categoria!['tipo'] as String;
      _activa = (widget.categoria!['activa'] as int) == 1;
      final iconoDB = widget.categoria!['icono'] as String?;
      // Validar que el icono exista en el catálogo; si no, dejarlo null
      _iconoSeleccionado = (iconoDB != null && CategoriaIconos.isValidIcon(iconoDB))
          ? iconoDB
          : null;
      _observacionController.text = widget.categoria!['observacion'] as String? ?? '';
      _codigoEditado = true;
    }

    _nombreController.addListener(_onNombreChanged);
  }

  @override
  void dispose() {
    _nombreController.removeListener(_onNombreChanged);
    _nombreController.dispose();
    _codigoController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  void _onNombreChanged() {
    if (!_codigoEditado) {
      final codigo =
          CategoriaMovimientoService.generarCodigo(_nombreController.text);
      _codigoController.text = codigo;
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    // Si estamos desactivando una categoría, verificar si tiene datos asociados
    if (widget.categoria != null && !_activa) {
      final categoria = widget.categoria!['codigo'] as String;
      final count =
          await CategoriaMovimientoService.contarMovimientosAsociados(categoria);

      if (count > 0 && mounted) {
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Advertencia'),
            content: Text(
              'Esta categoría tiene $count movimiento(s) asociado(s).\n\n'
              'Si la desactivás, esos movimientos no se visualizarán en los reportes.\n\n'
              '¿Deseas continuar?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.egreso),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );

        if (confirmar != true) return;
      }
    }

    setState(() => _guardando = true);

    try {
      final codigo = _codigoController.text.trim().toUpperCase();
      final nombre = _nombreController.text.trim();
      final observacion = _observacionController.text.trim().isEmpty 
          ? null 
          : _observacionController.text.trim();

      if (widget.categoria == null) {
        await CategoriaMovimientoService.crearCategoria(
          codigo: codigo,
          nombre: nombre,
          tipo: _tipo,
          icono: _iconoSeleccionado,
          observacion: observacion,
          activa: _activa,
        );
      } else {
        await CategoriaMovimientoService.actualizarCategoria(
          id: widget.categoria!['id'] as int,
          codigo: codigo,
          nombre: nombre,
          tipo: _tipo,
          icono: _iconoSeleccionado,
          observacion: observacion,
          activa: _activa,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.categoria == null
                ? 'Categoría creada'
                : 'Categoría actualizada'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al guardar. Intente nuevamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.bgBase,
      appBar: AppBar(
        backgroundColor: c.bgBase,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.categoria == null ? 'Nueva Categoría' : 'Editar Categoría',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: c.border,
          ),
        ),
      ),
      body: ResponsiveContainer(
        maxWidth: 800,
        child: Form(
          key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sección: Información General
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  'INFORMACIÓN GENERAL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              // Campo: Nombre
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nombre',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nombreController,
                      decoration: InputDecoration(
                        hintText: 'Ej. Cuotas Sociales',
                        hintStyle: TextStyle(color: c.textMuted),
                        filled: true,
                        fillColor: c.bgElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide: BorderSide(color: c.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide:
                              const BorderSide(color: AppColors.accent, width: 2),
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Requerido' : null,
                    ),
                  ],
                ),
              ),

              // Campo: Código
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Código',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _codigoController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 10,
                      decoration: InputDecoration(
                        hintText: 'Ej. CUOT',
                        hintStyle: TextStyle(color: c.textMuted),
                        filled: true,
                        fillColor: c.bgElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide: BorderSide(color: c.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide:
                              const BorderSide(color: AppColors.accent, width: 2),
                        ),
                      ),
                      onChanged: (_) {
                        _codigoEditado = true;
                      },
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requerido';
                        if (v.trim().length > 10) return 'Máximo 10 caracteres';
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              // Campo: Observación
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Observación',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _observacionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Descripción de qué movimientos van en esta categoría (opcional)',
                        hintStyle: TextStyle(color: c.textMuted),
                        filled: true,
                        fillColor: c.bgElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide: BorderSide(color: c.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide:
                              const BorderSide(color: AppColors.accent, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Sección: Tipo de Categoría
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(
                  'Tipo de Categoría',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Segmented Buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.bgElevated,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      _buildSegmentButton('Ingreso', 'INGRESO'),
                      const SizedBox(width: 6),
                      _buildSegmentButton('Egreso', 'EGRESO'),
                      const SizedBox(width: 6),
                      _buildSegmentButton('Ambos', 'AMBOS'),
                    ],
                  ),
                ),
              ),

              // Sección: Icono
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  'ICONO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: DropdownButtonFormField<String>(
                  value: _iconoSeleccionado,
                  decoration: InputDecoration(
                    labelText: 'Seleccionar Icono',
                    filled: true,
                    fillColor: c.bgElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide(color: c.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: const BorderSide(color: AppColors.accent, width: 2),
                    ),
                  ),
                  items: CategoriaIconos.iconos.map((icono) {
                    final code = icono['code']!;
                    final label = icono['label']!;
                    return DropdownMenuItem<String>(
                      value: code,
                      child: Row(
                        children: [
                          Icon(CategoryIconHelper.fromName(code), size: 20, color: AppColors.accent),
                          const SizedBox(width: 12),
                          Text(label),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _iconoSeleccionado = value);
                  },
                  hint: Row(
                    children: [
                      Icon(Icons.category, size: 20, color: c.textMuted),
                      const SizedBox(width: 12),
                      const Text('Seleccionar icono'),
                    ],
                  ),
                  selectedItemBuilder: (context) {
                    return CategoriaIconos.iconos.map((icono) {
                      final code = icono['code']!;
                      final label = icono['label']!;
                      return Row(
                        children: [
                          Icon(CategoryIconHelper.fromName(code), size: 20, color: AppColors.accent),
                          const SizedBox(width: 12),
                          Text(label),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),

              // Sección: Configuración
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'CONFIGURACIÓN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              // Switch de Estado
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: c.border,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estado',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Activa / Inactiva',
                          style: TextStyle(
                            fontSize: 14,
                            color: c.textMuted,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: _activa,
                      onChanged: (value) => setState(() => _activa = value),
                      activeColor: AppColors.accent,
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return Colors.white;
                        return c.textMuted;
                      }),
                      trackColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return AppColors.accent;
                        return c.bgElevated;
                      }),
                      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return Colors.transparent;
                        return c.border;
                      }),
                    ),
                  ],
                ),
              ),

              // Ilustración decorativa
              //Padding(
                // padding: const EdgeInsets.all(32),
                // child: Container(
                //   width: double.infinity,
                //   height: 120,
                //   decoration: BoxDecoration(
                //     gradient: LinearGradient(
                //       colors: [
                //         const Color(0xFF2E7D32).withOpacity(0.1),
                //         const Color(0xFF2E7D32).withOpacity(0.05),
                //       ],
                //       begin: Alignment.topLeft,
                //       end: Alignment.bottomRight,
                //     ),
                //     borderRadius: BorderRadius.circular(16),
                //     border: Border.all(
                //       color: const Color(0xFF2E7D32).withOpacity(0.2),
                //     ),
                //   ),
                  // child: Stack(
                  //   children: [
                  //     Center(
                  //       child: Icon(
                  //         Icons.category,
                  //         size: 60,
                  //         color: const Color(0xFF2E7D32).withOpacity(0.4),
                  //       ),
                  //     ),
                  //     const Positioned(
                  //       bottom: 16,
                  //       left: 16,
                  //       child: Text(
                  //         'Organiza tus finanzas con claridad',
                  //         style: TextStyle(
                  //           fontSize: 12,
                  //           color: Color(0xFF2E7D32),
                  //           fontWeight: FontWeight.w500,
                  //         ),
                  //       ),
                  //     ),
                  //   ],
                  // ),
                //),
              //),

              const SizedBox(height: 100),
            ],
          ),
          ),
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appColors.bgBase.withValues(alpha: 0.95),
          boxShadow: AppShadows.cardFor(context),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                elevation: 4,
                shadowColor: AppColors.accent.withValues(alpha: 0.3),
              ),
              child: _guardando
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child:
                          CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Guardar Categoría',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentButton(String label, String value) {
    final isSelected = _tipo == value;
    final c = context.appColors;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tipo = value),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: isSelected ? c.bgSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected ? AppShadows.card : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? c.textPrimary : c.textMuted,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

}
