import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/dao/db.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/tesoreria_scaffold.dart';
import '../../shared/state/app_settings.dart';

/// Página/Diálogo para seleccionar la Unidad de Gestión activa.
/// Se muestra al entrar a Tesorería si no hay una seleccionada.
/// También se puede acceder desde configuración para cambiar la selección.
class UnidadGestionSelectorPage extends StatefulWidget {
  /// Si es true, se muestra como pantalla inicial (no se puede cancelar)
  final bool isInitialFlow;
  
  /// Callback opcional para cuando se completa la selección
  final VoidCallback? onComplete;

  const UnidadGestionSelectorPage({
    super.key,
    this.isInitialFlow = false,
    this.onComplete,
  });

  @override
  State<UnidadGestionSelectorPage> createState() =>
      _UnidadGestionSelectorPageState();
}

class _UnidadGestionSelectorPageState extends State<UnidadGestionSelectorPage> {
  List<Map<String, dynamic>> _unidades = [];
  bool _loading = true;
  int? _selectedId;
  String? _selectedNombre;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance();
      // Obtener unidades de gestión activas, ordenadas por tipo y nombre
      final rows = await db.rawQuery('''
        SELECT id, nombre, tipo, disciplina_ref
        FROM unidades_gestion
        WHERE activo = 1
        ORDER BY 
          CASE tipo 
            WHEN 'DISCIPLINA' THEN 1 
            WHEN 'COMISION' THEN 2 
            WHEN 'EVENTO' THEN 3 
          END,
          nombre ASC
      ''');
      
      // Cargar selección actual si existe
      final settings = context.read<AppSettings>();
      await settings.ensureLoaded();
      
      setState(() {
        _unidades = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        _selectedId = settings.unidadGestionActivaId;
        if (_selectedId != null) {
          final found = _unidades.where((u) => u['id'] == _selectedId);
          if (found.isNotEmpty) {
            _selectedNombre = found.first['nombre'] as String?;
          }
        }
        _loading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'unidad_gestion_selector.load',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_selectedId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione una Unidad de Gestión')),
      );
      return;
    }

    try {
      final settings = context.read<AppSettings>();
      await settings.setUnidadGestionActivaId(_selectedId);

      if (!mounted) return;

      // Navegación según el flujo
      if (widget.onComplete != null) {
        // Si hay callback, ejecutarlo (el parent maneja la navegación)
        widget.onComplete!();
      } else if (!widget.isInitialFlow) {
        // Si NO es flujo inicial y NO hay callback, hacer pop normal
        Navigator.of(context).pop(true);
      }
      // Si ES flujo inicial sin callback, no hacer nada (el parent maneja)
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'unidad_gestion_selector.save',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    }
  }

  Widget _buildTipoHeader(String tipo) {
    final label = switch (tipo) {
      'DISCIPLINA' => '🏆 Disciplinas Deportivas',
      'COMISION' => '🏛️ Comisiones',
      'EVENTO' => '📅 Eventos Especiales',
      _ => tipo,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildUnidadTile(Map<String, dynamic> unidad) {
    final id = unidad['id'] as int;
    final nombre = unidad['nombre'] as String;
    final isSelected = id == _selectedId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: isSelected ? 4 : 1,
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: Icon(
          isSelected ? Icons.check_circle : Icons.circle_outlined,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey,
        ),
        title: Text(
          nombre,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () {
          setState(() {
            _selectedId = id;
            _selectedNombre = nombre;
          });
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Si es flujo inicial, mantener Column+Expanded (pantalla completa)
    if (widget.isInitialFlow) {
      return ResponsiveContainer(
        maxWidth: 800,
        child: Column(
          children: [
            // Descripción
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Qué Unidad de Gestión administrarás?',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Los movimientos que registres se asociarán a esta unidad. Podrás cambiarla más tarde desde la configuración.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            // Lista de unidades agrupadas por tipo
            Expanded(
              child: _unidades.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 64,
                              color: Colors.orange,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No hay unidades de gestión configuradas',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Las unidades de gestión deberían cargarse automáticamente. Por favor, reinicie la aplicación.',
                              style: TextStyle(fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            if (widget.isInitialFlow)
                              ElevatedButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Volver a Inicio'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(200, 48),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: _unidades.length,
                      itemBuilder: (context, index) {
                        final unidad = _unidades[index];
                        final tipo = unidad['tipo'] as String;
                        // Mostrar header si es el primero de su tipo
                        final isFirst = index == 0 ||
                            _unidades[index - 1]['tipo'] != tipo;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isFirst) _buildTipoHeader(tipo),
                            _buildUnidadTile(unidad),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }
    // Si NO es flujo inicial, usar ListView (sin Expanded)
    return ResponsiveContainer(
      maxWidth: 800,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Qué Unidad de Gestión administrarás?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Los movimientos que registres se asociarán a esta unidad. Podrás cambiarla más tarde desde la configuración.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (_unidades.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 64,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No hay unidades de gestión configuradas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Las unidades de gestión deberían cargarse automáticamente. Por favor, reinicie la aplicación.',
                    style: TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else ...[
            for (int index = 0; index < _unidades.length; index++)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index == 0 || _unidades[index - 1]['tipo'] != _unidades[index]['tipo'])
                    _buildTipoHeader(_unidades[index]['tipo'] as String),
                  _buildUnidadTile(_unidades[index]),
                ],
              ),
            const SizedBox(height: 80),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Si NO es flujo inicial, usar TesoreriaScaffold con drawer
    if (!widget.isInitialFlow) {
      return TesoreriaScaffold(
        title: 'Seleccionar Unidad de Gestión',
        currentRouteName: '/unidad_gestion',
        appBarColor: Colors.orange,
        body: _buildBody(context),
        floatingActionButton: _selectedId != null
            ? FloatingActionButton.extended(
                onPressed: _save,
                backgroundColor: Colors.teal,
                icon: const Icon(Icons.check),
                label: const Text('Confirmar'),
              )
            : null,
      );
    }
    
    // Si ES flujo inicial, usar Scaffold normal (sin drawer)
    return WillPopScope(
      onWillPop: () async {
        // Si es flujo inicial y hay unidades disponibles, requerir selección
        if (widget.isInitialFlow && _selectedId == null && _unidades.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Debe seleccionar una Unidad de Gestión para continuar'),
            ),
          );
          return false;
        }
        // Si no hay unidades disponibles O no es flujo inicial O ya seleccionó, permitir retroceder
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Seleccionar Unidad de Gestión'),
          backgroundColor: Colors.orange,
          // Permitir retroceder si no hay unidades o no es flujo inicial
          automaticallyImplyLeading: !widget.isInitialFlow || _unidades.isEmpty,
        ),
        body: _buildBody(context),
        floatingActionButton: _selectedId != null
            ? FloatingActionButton.extended(
                onPressed: _save,
                backgroundColor: Colors.teal,
                icon: const Icon(Icons.check),
                label: const Text('Confirmar'),
              )
            : null,
        bottomNavigationBar: _loading
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: _selectedId != null ? _save : null,
                    icon: const Icon(Icons.check),
                    label: Text(_selectedId != null
                        ? 'Continuar con "$_selectedNombre"'
                        : 'Seleccione una opción'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
