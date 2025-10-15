# Buffet Mirror (Android)

App espejo Android, offline-first, para operar ventas rápidas y sincronizar con el backoffice BuffetApp (Windows).

## Requisitos
- Flutter 3.22+
- Android SDK / dispositivo de prueba

## Ejecutar
- Instalar dependencias
- Correr app en emulador o dispositivo

## Sincronización
- Importar catálogo desde JSON (ver tools/sync_examples)
- Exportar ventas del día a JSON para el backoffice

## Estructura
- lib/domain: modelos
- lib/data/dao: DAOs de SQLite (sqflite)
- lib/services: sync e impresión (PREVIEW)
- lib/ui/pages: pantallas (caja, venta, historial, productos)
