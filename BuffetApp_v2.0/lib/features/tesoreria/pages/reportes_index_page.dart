import 'package:flutter/material.dart';
import '../../shared/widgets/tesoreria_scaffold.dart';
import 'reporte_categorias_page.dart';
import 'reporte_resumen_anual_page.dart';
import 'reporte_resumen_mensual_page.dart';
import 'reporte_plantel_mensual_page.dart';

/// Pantalla índice de reportes de Tesorería
class ReportesIndexPage extends StatelessWidget {
  const ReportesIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TesoreriaScaffold(
      title: 'Reportes',
      currentRouteName: '/reportes',
      appBarColor: Colors.blue,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Título
              const Text(
                '📊 Reportes de Tesorería',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Seleccioná el tipo de reporte que necesitás',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // Cards de reportes
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  children: [
                    _buildReporteCard(
                      context: context,
                      titulo: 'Reporte por Categorías',
                      descripcion: 'Análisis detallado de ingresos y egresos agrupados por categoría',
                      icono: Icons.category,
                      color: Colors.blue,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReporteCategoriasPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildReporteCard(
                      context: context,
                      titulo: 'Resumen Anual',
                      descripcion: 'Totales acumulados del año: saldo inicial, ingresos, egresos y saldo actual',
                      icono: Icons.calendar_today,
                      color: Colors.orange,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReporteResumenAnualPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildReporteCard(
                      context: context,
                      titulo: 'Resumen por Mes',
                      descripcion: 'Tabla mensual con ingresos, egresos y saldo de cada mes del año',
                      icono: Icons.table_chart,
                      color: Colors.purple,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReporteResumenMensualPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildReporteCard(
                      context: context,
                      titulo: 'Plantel Mensual',
                      descripcion: 'Estado de pagos por jugador/staff CT mes a mes con exportación a Excel',
                      icono: Icons.people,
                      color: Colors.teal,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReportePlantelMensualPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReporteCard({
    required BuildContext context,
    required String titulo,
    required String descripcion,
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Icono
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icono,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(width: 16),
              
              // Textos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      descripcion,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Icono de flecha
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
