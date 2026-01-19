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
