import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modos disponibles en la aplicación
enum AppMode {
  buffet,
  tesoreria,
}

/// Estado global del modo activo de la aplicación
/// Persiste en SharedPreferences para mantener la selección entre sesiones
class AppModeState extends ChangeNotifier {
  static const String _modeKey = 'app_current_mode';
  
  AppMode _currentMode = AppMode.buffet; // Default
  bool _loaded = false;
  bool _hasConfiguredMode = false; // true si alguna vez se guardó un modo

  AppMode get currentMode => _currentMode;
  bool get isLoaded => _loaded;
  bool get isBuffetMode => _currentMode == AppMode.buffet;
  bool get isTesoreriaMode => _currentMode == AppMode.tesoreria;
  bool get hasConfiguredMode => _hasConfiguredMode;

  /// Carga el modo guardado de SharedPreferences
  Future<void> loadMode() async {
    if (_loaded) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_modeKey);
      
      if (savedMode != null) {
        _hasConfiguredMode = true;
        if (savedMode == 'tesoreria') {
          _currentMode = AppMode.tesoreria;
        } else {
          _currentMode = AppMode.buffet;
        }
      } else {
        _hasConfiguredMode = false;
      }
      
      _loaded = true;
      notifyListeners();
    } catch (e) {
      // Si falla, usar el modo por defecto (Buffet)
      _hasConfiguredMode = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// Cambia el modo activo y lo persiste
  Future<void> setMode(AppMode mode) async {
    _currentMode = mode;
    _hasConfiguredMode = true;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode == AppMode.buffet ? 'buffet' : 'tesoreria');
    } catch (e) {
      // Error guardando, pero el cambio en memoria se mantiene
      debugPrint('Error guardando modo: $e');
    }
  }

  /// Alterna entre buffet y tesorería
  Future<void> toggleMode() async {
    final newMode = _currentMode == AppMode.buffet 
        ? AppMode.tesoreria 
        : AppMode.buffet;
    await setMode(newMode);
  }

  /// Limpia el modo guardado (útil para testing o reset)
  Future<void> clearMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_modeKey);
      _currentMode = AppMode.buffet;
      _hasConfiguredMode = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error limpiando modo: $e');
    }
  }
}
