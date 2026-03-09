import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/dao/evento_dao.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_header.dart';
import '../../shared/state/app_settings.dart';

/// Pantalla para crear o editar un evento del club (partido, cena, torneo, otro).
class CrearEventoCdmPage extends StatefulWidget {
  final Map<String, dynamic>? eventoExistente;

  const CrearEventoCdmPage({super.key, this.eventoExistente});

  @override
  State<CrearEventoCdmPage> createState() => _CrearEventoCdmPageState();
}

class _CrearEventoCdmPageState extends State<CrearEventoCdmPage> {
  final _formKey = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _rivalCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _lugarCtrl = TextEditingController();

  String _tipo = 'PARTIDO';
  String _estado = 'PROGRAMADO';
  String _localidad = 'LOCAL';
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  bool get _esEdicion => widget.eventoExistente != null;

  @override
  void initState() {
    super.initState();
    if (_esEdicion) {
      final ev = widget.eventoExistente!;
      _tipo = ev['tipo'] as String? ?? 'PARTIDO';
      _estado = ev['estado'] as String? ?? 'PROGRAMADO';
      _localidad = ev['localidad'] as String? ?? 'LOCAL';
      _tituloCtrl.text = ev['titulo'] as String? ?? '';
      _rivalCtrl.text = ev['rival'] as String? ?? '';
      _descripcionCtrl.text = ev['descripcion'] as String? ?? '';
      _lugarCtrl.text = ev['lugar'] as String? ?? '';
      final fechaStr = ev['fecha'] as String?;
      if (fechaStr != null && fechaStr.isNotEmpty) {
        _fecha = DateTime.tryParse(fechaStr) ?? DateTime.now();
      }
    }
    _rivalCtrl.addListener(_actualizarTituloAutoPartido);
  }

  void _actualizarTituloAutoPartido() {
    if (_tipo == 'PARTIDO' && !_esEdicion) {
      final rival = _rivalCtrl.text.trim();
      _tituloCtrl.text = rival.isNotEmpty ? 'vs $rival' : '';
    }
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _rivalCtrl.dispose();
    _descripcionCtrl.dispose();
    _lugarCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final settings = context.read<AppSettings>();
    final unidadId = settings.unidadGestionActivaId;
    if (unidadId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná una Unidad de Gestión primero')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final titulo = _tituloCtrl.text.trim();
      final fechaStr = _fecha.toIso8601String().substring(0, 10);

      final data = {
        'unidad_gestion_id': unidadId,
        'tipo': _tipo,
        'titulo': titulo,
        'estado': _estado,
        'fecha': fechaStr,
        if (_tipo == 'PARTIDO') 'rival': _rivalCtrl.text.trim().isEmpty ? null : _rivalCtrl.text.trim(),
        if (_tipo == 'PARTIDO') 'localidad': _localidad,
        if (_tipo != 'PARTIDO') 'descripcion': _descripcionCtrl.text.trim().isEmpty ? null : _descripcionCtrl.text.trim(),
        'lugar': _lugarCtrl.text.trim().isEmpty ? null : _lugarCtrl.text.trim(),
      };

      if (_esEdicion) {
        await EventoDao.updateEvento(widget.eventoExistente!['id'] as int, data);
      } else {
        await EventoDao.insertEvento(data);
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(Icons.check_circle, color: AppColors.ingreso, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(_esEdicion ? 'Evento actualizado' : 'Evento creado')),
          ]),
          content: Text('$titulo — $fechaStr'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'crear_evento_cdm.guardar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar el evento. Intentá nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;
    final pageTitle = _esEdicion ? 'Editar Evento' : 'Nuevo Evento';

    return ErpLayout(
      currentRoute: '/crear_evento_cdm',
      title: pageTitle,
      body: Column(
        children: [
          if (isDesktop) AppHeader(title: pageTitle),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSelectorTipo(),
                        const SizedBox(height: 16),
                        _buildCampoFecha(),
                        const SizedBox(height: 16),
                        if (_tipo == 'PARTIDO') ..._buildCamposPartido(),
                        if (_tipo != 'PARTIDO') ..._buildCamposOtros(),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tituloCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Título *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.title),
                            helperText: 'Para partidos se completa automáticamente',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _lugarCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Lugar (opcional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_esEdicion) _buildSelectorEstado(),
                        if (_esEdicion) const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _guardando ? null : _guardar,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _guardando ? 'Guardando...' : (_esEdicion ? 'Actualizar' : 'Crear evento'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorTipo() {
    const opciones = [
      {'tipo': 'PARTIDO', 'emoji': '⚽', 'label': 'Partido'},
      {'tipo': 'CENA', 'emoji': '🍽', 'label': 'Cena / Peña'},
      {'tipo': 'TORNEO', 'emoji': '🏆', 'label': 'Torneo'},
      {'tipo': 'OTRO', 'emoji': '📌', 'label': 'Otro'},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tipo de evento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: opciones.map((op) {
                final tipo = op['tipo']!;
                final emoji = op['emoji']!;
                final label = op['label']!;
                final sel = _tipo == tipo;
                return ChoiceChip(
                  label: Text('$emoji $label'),
                  selected: sel,
                  onSelected: (_) {
                    setState(() {
                      _tipo = tipo;
                      if (tipo == 'PARTIDO') {
                        _actualizarTituloAutoPartido();
                      }
                    });
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampoFecha() {
    final fechaStr =
        '${_fecha.day.toString().padLeft(2, '0')}/${_fecha.month.toString().padLeft(2, '0')}/${_fecha.year}';
    return InkWell(
      onTap: _seleccionarFecha,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Fecha del evento *',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.calendar_today),
        ),
        child: Text(fechaStr, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  List<Widget> _buildCamposPartido() {
    return [
      TextFormField(
        controller: _rivalCtrl,
        decoration: const InputDecoration(
          labelText: 'Rival *',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.sports_soccer),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido para partidos' : null,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        value: _localidad,
        decoration: const InputDecoration(
          labelText: 'Localidad',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.home_outlined),
        ),
        items: const [
          DropdownMenuItem(value: 'LOCAL', child: Text('🏠 Local')),
          DropdownMenuItem(value: 'VISITANTE', child: Text('✈ Visitante')),
        ],
        onChanged: (v) => setState(() => _localidad = v!),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildCamposOtros() {
    return [
      TextFormField(
        controller: _descripcionCtrl,
        decoration: const InputDecoration(
          labelText: 'Descripción (opcional)',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.description_outlined),
        ),
        maxLines: 2,
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildSelectorEstado() {
    return DropdownButtonFormField<String>(
      value: _estado,
      decoration: const InputDecoration(
        labelText: 'Estado',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.flag_outlined),
      ),
      items: const [
        DropdownMenuItem(value: 'PROGRAMADO', child: Text('📅 Programado')),
        DropdownMenuItem(value: 'REALIZADO', child: Text('✅ Realizado')),
        DropdownMenuItem(value: 'CANCELADO', child: Text('❌ Cancelado')),
      ],
      onChanged: (v) => setState(() => _estado = v!),
    );
  }
}
