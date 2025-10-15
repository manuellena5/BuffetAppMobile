# Instrucciones para agentes – BuffetApp (Backoffice Windows + Espejo Android)

## Estilo de respuesta
- Responder siempre en español, con pasos accionables y ejemplos mínimos.
- Si hay dudas, cerrar con preguntas breves y numeradas.

## Contexto del repositorio (Windows/Python)
- UI: Tkinter. Controlador principal en `main.py` (clase `BarCanchaApp`) con importación perezosa de vistas.
- Datos: SQLite via `db_utils.get_connection()` (activa PRAGMA foreign_keys). Rutas en `%LOCALAPPDATA%\BuffetApp\` vía `utils_paths.py`.
- Tema/estilos centralizados en `theme.py` (COLORS, FONTS, CART).
- Vistas clave: `ventas_view_new.py`, `caja_operaciones.py`, `productos_view.py`, `historial_view.py`, `menu_view.py`.
- Packaging: `BuffetApp.spec` + `Instalador.txt` (PyInstaller). Recursos se resuelven con `resource_path()`.

Ejemplos de patrones locales:
```python
# Conexión a DB (usar siempre este helper)
from db_utils import get_connection
conn = get_connection(); cur = conn.cursor()
# ...
conn.commit(); conn.close()
```
```python
# Importación perezosa de vistas pesadas
def mostrar_productos(self):
    if not self.productos_view:
        from productos_view import ProductosView
        self.productos_view = ProductosView(self.root)
```

## Esquema de datos base (SQLite)
Definido en `init_db.py` (crear/migrar de forma idempotente):
- `metodos_pago(id, descripcion)` con semillas “Efectivo/Transferencia”.
- `Categoria_Producto(id, descripcion)`.
- `products(id, codigo_producto, nombre, precio_venta, stock_actual, stock_minimo, categoria_id, visible, color)`.
- `ventas(id, fecha_hora, total_venta, status, activo, metodo_pago_id, caja_id)`.
- `tickets(id, venta_id, categoria_id, producto_id, fecha_hora, status, total_ticket, identificador_ticket)`.
- `caja_diaria(id, codigo_caja, disciplina, fecha, usuario_apertura, hora_apertura, fondo_inicial, estado, ingresos, retiros, diferencia, total_tickets, …)`.
- `caja_movimiento(id, caja_id, tipo[INGRESO|RETIRO], monto, observacion, creado_ts)`.
Notas: hay índices y triggers que recalculan `ingresos/retiros` en `caja_diaria`. Evitar totales manuales: insertar movimiento y dejar que los triggers actualicen.

## Flujos críticos (backoffice)
- Apertura/cierre de caja: ver `main.py` y `caja_operaciones.py` (valida una sola caja abierta: `self.caja_abierta_id`).
- Ventas rápidas: `ventas_view_new.py` carga productos visibles, maneja carrito y método de pago; impresión es callback.
- Historial: `historial_view.py` (listar, reimprimir, anular del día).

## Build y ejecución (Windows)
- Ejecutar: `python main.py`.
- Empaquetar:
```powershell
pyinstaller BuffetApp_v1.4\BuffetApp.spec --clean
```

## App Android espejo (Flutter) – lineamientos para agentes
- Confirmado: funcionamiento sin internet (offline-first) y sincronización por archivos.
- Paquetes: `sqflite`, `path_provider`, `uuid` (persistir `device_id`), impresión en **PREVIEW** (PDF/imagen) y opcional `TCP_TEST`; USB OTG queda para fase 2.
- Modelos (alineados a SQLite): Caja, Producto, Venta (+items), Ticket (opcional), Movimiento; mantener nombres de columnas para facilitar sync.
- Páginas: login(opc), caja(apertura/cierre), venta, historial, productos (con **ABM** desde Android).
- Identidad del dispositivo: generar y persistir `device_id` (UUID) y permitir alias editable (se usan en el nombre del archivo exportado).
- Ver ejemplos de sync y esquema Android en `tools/sync_examples/*.json` y `tools/android_schema.sql`.

### Sincronización Backoffice ↔ Android (archivo JSON)
- Importar catálogo: `catalogo_vNN.json` → productos, categorías, métodos de pago (IDs estables).
- Exportar ventas: `ventas_YYYYMMDD_{deviceAlias}.json` con `device_id`, `device_alias`, ventas con `uuid`, items, anulaciones y `totales_por_mp`.
- Resolución de conflictos: fuente de verdad por día/caja en backoffice; Android no mergea, sólo exporta.
- Ejemplos iniciales incluidos en `tools/sync_examples/`.

## Convenciones del proyecto
- Usar helpers locales (`get_connection`, `resource_path`) y tema en `theme.py`.
- Evitar duplicar lógica de totales: confiar en triggers de `init_db.py`.
- Mantener importaciones perezosas en nuevas vistas para tiempos de arranque rápidos.

## Estado de definiciones (confirmado)
- Offline-first con sincronización por archivos.
- Impresión: PREVIEW primero; USB OTG en etapa posterior.
- Android con **ABM** de productos.
- Contrato JSON inicial provisto en `tools/sync_examples` (ajustable).

