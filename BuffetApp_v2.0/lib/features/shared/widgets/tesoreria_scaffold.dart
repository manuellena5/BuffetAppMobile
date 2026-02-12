import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../state/drawer_state.dart';
import '../state/app_mode.dart';
import 'tesoreria_drawer_helper.dart';
import 'buffet_drawer_helper.dart';

/// Scaffold reutilizable con drawer integrado que se adapta al modo activo
/// (Tesorería o Buffet). Facilita la integración consistente del drawer
/// en todas las pantallas compartidas (ej: Configuración).
class TesoreriaScaffold extends StatefulWidget {
  final String title;
  final Widget body;
  final String? currentRouteName;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final Color? appBarColor;
  final PreferredSizeWidget? bottom;
  final bool showBackButton;
  final String? unidadGestionNombre;
  final bool? showAdvanced; // Nullable - se lee desde SharedPreferences si es null
  final VoidCallback? onLoadVersion;

  const TesoreriaScaffold({
    super.key,
    required this.title,
    required this.body,
    this.currentRouteName,
    this.actions,
    this.floatingActionButton,
    this.backgroundColor,
    this.appBarColor,
    this.bottom,
    this.showBackButton = true,
    this.unidadGestionNombre,
    this.showAdvanced, // Null = auto-detectar desde SharedPreferences
    this.onLoadVersion,
  });

  @override
  State<TesoreriaScaffold> createState() => _TesoreriaScaffoldState();
}

class _TesoreriaScaffoldState extends State<TesoreriaScaffold> {
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadShowAdvanced();
  }

  Future<void> _loadShowAdvanced() async {
    if (widget.showAdvanced != null) {
      // Si se provee explícitamente, usarlo
      setState(() => _showAdvanced = widget.showAdvanced!);
      return;
    }
    
    // Leer desde SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool('show_advanced_options') ?? false;
      if (mounted) {
        setState(() => _showAdvanced = value);
      }
    } catch (_) {
      // Si falla, usar false por defecto
    }
  }

  @override
  void didUpdateWidget(TesoreriaScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si showAdvanced cambia explícitamente, recargar
    if (widget.showAdvanced != oldWidget.showAdvanced) {
      _loadShowAdvanced();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveShowAdvanced = widget.showAdvanced ?? _showAdvanced;
    final modeState = context.watch<AppModeState>();
    
    // Elegir el drawer según el modo activo
    Widget Function({
      required BuildContext context,
      String? currentRouteName,
      String? unidadGestionNombre,
      bool showAdvanced,
      VoidCallback? onLoadVersion,
    }) drawerBuilder;
    
    if (modeState.isBuffetMode) {
      drawerBuilder = ({
        required BuildContext context,
        String? currentRouteName,
        String? unidadGestionNombre,
        bool showAdvanced = false,
        VoidCallback? onLoadVersion,
      }) => BuffetDrawerHelper.build(
        context: context,
        currentRouteName: currentRouteName,
        unidadGestionNombre: unidadGestionNombre,
        showAdvanced: showAdvanced,
        onLoadVersion: onLoadVersion,
      );
    } else {
      drawerBuilder = ({
        required BuildContext context,
        String? currentRouteName,
        String? unidadGestionNombre,
        bool showAdvanced = false,
        VoidCallback? onLoadVersion,
      }) => TesoreriaDrawerHelper.build(
        context: context,
        currentRouteName: currentRouteName,
        unidadGestionNombre: unidadGestionNombre,
        showAdvanced: showAdvanced,
        onLoadVersion: onLoadVersion,
      );
    }
    
    return Consumer<DrawerState>(
      builder: (context, drawerState, _) {
        final drawer = drawerBuilder(
          context: context,
          currentRouteName: widget.currentRouteName,
          unidadGestionNombre: widget.unidadGestionNombre,
          showAdvanced: effectiveShowAdvanced,
          onLoadVersion: widget.onLoadVersion,
        );
        
        return Scaffold(
          backgroundColor: widget.backgroundColor,
          appBar: AppBar(
            title: Text(widget.title),
            backgroundColor: widget.appBarColor ?? Colors.teal,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: !drawerState.isFixed && widget.showBackButton,
            actions: widget.actions,
            bottom: widget.bottom,
          ),
          drawer: drawerState.isFixed ? null : drawer,
          body: Row(
            children: [
              if (drawerState.isFixed) drawer,
              Expanded(child: widget.body),
            ],
          ),
          floatingActionButton: widget.floatingActionButton,
        );
      },
    );
  }
}
