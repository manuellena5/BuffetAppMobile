import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estado del Drawer mejorado (menú lateral)
/// 
/// Maneja dos configuraciones independientes:
/// - isFixed: si el drawer está fijo (siempre visible) o flotante (overlay)
/// - isExpanded: si el drawer está expandido (con labels) o colapsado (solo iconos)
/// 
/// El estado se persiste en SharedPreferences para mantener la preferencia del usuario.
class DrawerState extends ChangeNotifier {
  static const String _keyIsFixed = 'drawer_is_fixed';
  static const String _keyIsExpanded = 'drawer_is_expanded';

  bool _isFixed = false;
  bool _isExpanded = true;
  bool _isLoaded = false;

  /// Drawer fijo (siempre visible) o flotante (overlay)
  bool get isFixed => _isFixed;

  /// Drawer expandido (con labels) o colapsado (solo iconos)
  bool get isExpanded => _isExpanded;

  /// Estado cargado desde SharedPreferences
  bool get isLoaded => _isLoaded;

  /// Ancho del drawer según estado
  double get drawerWidth {
    if (!_isExpanded) {
      return 72.0; // Colapsado: solo iconos
    }
    return 280.0; // Expandido: iconos + labels
  }

  /// Cargar estado desde SharedPreferences
  Future<void> loadState() async {
    if (_isLoaded) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _isFixed = prefs.getBool(_keyIsFixed) ?? false;
      _isExpanded = prefs.getBool(_keyIsExpanded) ?? true;
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error cargando estado del drawer: $e');
      _isLoaded = true;
    }
  }

  /// Guardar estado en SharedPreferences
  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsFixed, _isFixed);
      await prefs.setBool(_keyIsExpanded, _isExpanded);
    } catch (e) {
      debugPrint('Error guardando estado del drawer: $e');
    }
  }

  /// Alternar entre fijo y flotante
  Future<void> toggleFixed() async {
    _isFixed = !_isFixed;
    notifyListeners();
    await _saveState();
  }

  /// Alternar entre expandido y colapsado
  Future<void> toggleExpanded() async {
    _isExpanded = !_isExpanded;
    notifyListeners();
    await _saveState();
  }

  /// Setear fijo/flotante directamente
  Future<void> setFixed(bool value) async {
    if (_isFixed == value) return;
    _isFixed = value;
    notifyListeners();
    await _saveState();
  }

  /// Setear expandido/colapsado directamente
  Future<void> setExpanded(bool value) async {
    if (_isExpanded == value) return;
    _isExpanded = value;
    notifyListeners();
    await _saveState();
  }
}
