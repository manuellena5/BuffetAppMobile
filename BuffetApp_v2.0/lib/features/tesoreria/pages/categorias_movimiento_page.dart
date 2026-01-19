import 'package:flutter/material.dart';
import '../services/categoria_movimiento_service.dart';
import 'categoria_movimiento_form_page.dart';

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
  
  String _filtroTipo = 'TODOS'; // TODOS, INGRESO, EGRESO, ARCHIVO
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
  }

  Future<void> _cargarCategorias() async {
    setState(() => _loading = true);
    try {
      final categorias = await CategoriaMovimientoService.obtenerCategorias(
        soloActivas: _filtroTipo != 'ARCHIVO',
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
          SnackBar(content: Text('Error al cargar categorías: $e')),
        );
      }
    }
  }

  void _aplicarFiltros() {
    var filtradas = List<Map<String, dynamic>>.from(_categorias);
    
    // Filtro por tipo
    if (_filtroTipo == 'INGRESO' || _filtroTipo == 'EGRESO') {
      filtradas = filtradas.where((c) {
        final tipo = c['tipo'] as String;
        return tipo == _filtroTipo || tipo == 'AMBOS';
      }).toList();
    } else if (_filtroTipo == 'ARCHIVO') {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111813) : const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF111813) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Categorías',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // Menú de opciones
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFF0F4F2),
          ),
        ),
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (value) {
                  setState(() => _busqueda = value);
                  _aplicarFiltros();
                },
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código',
                  hintStyle: const TextStyle(color: Color(0xFF61896F)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF61896F)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A2E1F) : Colors.white,
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
                _buildFilterChip('Archivo', 'ARCHIVO'),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Lista de categorías
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
                : _categoriasFiltradas.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _categoriasFiltradas.length,
                        itemBuilder: (context, index) {
                          return _buildCategoriaItem(_categoriasFiltradas[index], isDark);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: const Color(0xFF2E7D32),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nueva Categoría', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filtroTipo == value;
    
    return InkWell(
      onTap: () {
        setState(() => _filtroTipo = value);
        _aplicarFiltros();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2E7D32)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2E7D32)
                : const Color(0xFFE0E7E2),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriaItem(Map<String, dynamic> cat, bool isDark) {
    final activa = (cat['activa'] as int) == 1;
    final tipo = cat['tipo'] as String;
    final icono = cat['icono'] as String?;
    final nombre = cat['nombre'] as String;
    final codigo = cat['codigo'] as String;

    Color tipoColor;
    IconData tipoIcon;
    String tipoText;
    
    switch (tipo) {
      case 'INGRESO':
        tipoColor = const Color(0xFF4CAF50);
        tipoIcon = Icons.add_circle;
        tipoText = 'Ingreso';
        break;
      case 'EGRESO':
        tipoColor = const Color(0xFFF44336);
        tipoIcon = Icons.remove_circle;
        tipoText = 'Egreso';
        break;
      default:
        tipoColor = const Color(0xFFFF9800);
        tipoIcon = Icons.swap_vert;
        tipoText = 'Ambos';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: tipoColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tipoColor.withOpacity(0.3)),
          ),
          child: Icon(
            icono != null ? _getIconData(icono) : tipoIcon,
            color: tipoColor,
            size: 28,
          ),
        ),
        title: Text(
          nombre,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: activa ? null : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Código: $codigo',
              style: TextStyle(
                fontSize: 13,
                color: activa ? const Color(0xFF61896F) : Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tipoColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tipoColor.withOpacity(0.3), width: 1),
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
          ],
        ),
        trailing: activa
            ? IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue),
                onPressed: () => _abrirFormulario(categoria: cat),
              )
            : IconButton(
                icon: const Icon(Icons.restore, color: Colors.green),
                onPressed: () async {
                  await CategoriaMovimientoService.activarCategoria(cat['id'] as int);
                  _cargarCategorias();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Categoría reactivada')),
                    );
                  }
                },
              ),
        onTap: () => _abrirFormulario(categoria: cat),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.category_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No hay categorías',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _busqueda.isNotEmpty
                ? 'No se encontraron resultados'
                : 'Tocá + para crear una categoría',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconData(String iconName) {
    // Mapeo de nombres de iconos Material Symbols a IconData
    final iconMap = {
      'attach_money': Icons.attach_money,
      'account_balance': Icons.account_balance,
      'account_balance_wallet': Icons.account_balance_wallet,
      'confirmation_number': Icons.confirmation_number,
      'restaurant': Icons.restaurant,
      'sports_soccer': Icons.sports_soccer,
      'stadium': Icons.stadium,
      'campaign': Icons.campaign,
      'volunteer_activism': Icons.volunteer_activism,
      'groups': Icons.groups,
      'local_activity': Icons.local_activity,
      'gavel': Icons.gavel,
      'swap_horiz': Icons.swap_horiz,
      'sports': Icons.sports,
      'local_police': Icons.local_police,
      'pest_control': Icons.pest_control,
      'people': Icons.people,
      'directions_bus': Icons.directions_bus,
      'fitness_center': Icons.fitness_center,
      'medical_services': Icons.medical_services,
      'home': Icons.home,
      'restaurant_menu': Icons.restaurant_menu,
      'local_pharmacy': Icons.local_pharmacy,
      'local_laundry_service': Icons.local_laundry_service,
      'shield': Icons.shield,
      'paid': Icons.paid,
      'bolt': Icons.bolt,
      'local_fire_department': Icons.local_fire_department,
      'sports_basketball': Icons.sports_basketball,
      'hardware': Icons.hardware,
      'build': Icons.build,
      'construction': Icons.construction,
      'cleaning_services': Icons.cleaning_services,
      'engineering': Icons.engineering,
      'inventory_2': Icons.inventory_2,
      'fence': Icons.fence,
      'checkroom': Icons.checkroom,
      'ambulance': Icons.medical_services,
      'dinner_dining': Icons.dinner_dining,
      'card_membership': Icons.card_membership,
      'casino': Icons.casino,
      'category': Icons.category,
    };
    
    return iconMap[iconName] ?? Icons.category;
  }
}
