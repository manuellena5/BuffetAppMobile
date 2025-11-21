import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:buffet_mirror/ui/pages/reportes_page.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('ReportesPage muestra calendario y KPIs aunque no haya datos', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReportesPage()));
    // Esperar a que loading se apague (máx ~2s en ciclos de 100ms)
    for (var i = 0; i < 60; i++) { // hasta ~6s
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'No debe quedar spinner al terminar inicialización vacía');
    expect(find.text('Filtros'), findsOneWidget, reason: 'Debe mostrar panel de filtros');
    expect(find.text('KPIs'), findsOneWidget, reason: 'Debe mostrar tarjeta KPIs vacía');
    expect(find.textContaining('Sin datos disponibles'), findsWidgets, reason: 'Debe mostrar mensaje de ausencia de datos');
  });
}
