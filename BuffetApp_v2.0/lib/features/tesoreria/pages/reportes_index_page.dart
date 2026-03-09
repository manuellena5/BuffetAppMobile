import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_header.dart';
import 'reporte_categorias_page.dart';
import 'reporte_resumen_anual_page.dart';
import 'reporte_resumen_mensual_page.dart';
import 'reporte_plantel_mensual_page.dart';
import 'dashboard_page.dart';
import 'presupuesto_page.dart';
import 'comparativa_presupuesto_page.dart';
import 'proyeccion_flujo_page.dart';

/// Pantalla índice de reportes de Tesorería
class ReportesIndexPage extends StatelessWidget {
  const ReportesIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;

    return ErpLayout(
      currentRoute: '/reportes',
      title: 'Reportes',
      body: Column(
        children: [
          Expanded(
            child: Center(
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
                      titulo: 'Dashboard',
                      descripcion: 'Vista general con gráficos: barras, línea de saldo y torta de egresos',
                      icono: Icons.dashboard,
                      color: Colors.indigo,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DashboardPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 24),
                    // ─── Fase E: Presupuesto y Proyección ───
                    const Divider(),
                    const Text(
                      'Presupuesto y Proyección',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                    ),
                    const SizedBox(height: 12),
                    _buildReporteCard(
                      context: context,
                      titulo: 'Presupuesto Anual',
                      descripcion: 'Definir partidas presupuestarias mensuales por categoría',
                      icono: Icons.account_balance_wallet,
                      color: Colors.teal,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PresupuestoPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildReporteCard(
                      context: context,
                      titulo: 'Presupuesto vs Ejecución',
                      descripcion: 'Comparativa mes a mes entre lo presupuestado y lo ejecutado',
                      icono: Icons.compare_arrows,
                      color: Colors.deepPurple,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ComparativaPresupuestoPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildReporteCard(
                      context: context,
                      titulo: 'Proyección Flujo de Caja',
                      descripcion: 'Saldo proyectado a 3, 6 y 12 meses con compromisos y presupuesto',
                      icono: Icons.show_chart,
                      color: Colors.deepOrange,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProyeccionFlujoPage(),
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
          ),
        ],
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
                  color: color.withValues(alpha: 0.1),
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
