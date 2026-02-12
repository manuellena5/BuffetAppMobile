import 'package:flutter/material.dart';

/// Widget que centra el contenido con un ancho máximo en pantallas grandes.
/// Diseñado para mejorar la experiencia en tablets horizontales y desktop.
class ResponsiveContainer extends StatelessWidget {
  /// El widget hijo a mostrar centrado
  final Widget child;
  
  /// Ancho máximo del contenedor (por defecto 800px para formularios)
  final double maxWidth;
  
  /// Padding personalizado. Si no se provee, usa padding responsivo automático
  final EdgeInsetsGeometry? padding;
  
  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 800,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(
            horizontal: screenWidth > 600 ? 16.0 : 8.0,
            vertical: 8.0,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Centra el contenido con un ancho máximo **sólo cuando la pantalla está
/// en modo horizontal (landscape)**. En portrait ocupa todo el ancho.
///
/// Ideal para formularios y listados del módulo Buffet que deben verse
/// compactos en landscape pero aprovechar el ancho completo en portrait.
class LandscapeCenteredBody extends StatelessWidget {
  final Widget child;

  /// Ancho máximo en landscape (default 600 px).
  final double maxWidth;

  const LandscapeCenteredBody({
    super.key,
    required this.child,
    this.maxWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) return child;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
