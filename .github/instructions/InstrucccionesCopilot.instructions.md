---
applyTo: '*BuffetApp_v1.4*'
---
# Instrucciones del Agente (VS Code)

> **Objetivo:** Ayudarme a desarrollar y mantener mi app de punto de venta **BuffetApp/Bar de Cancha** en **Python + Tkinter** (Windows), con foco en usabilidad para caja, responsive, compatibilidad offline y empaquetado con PyInstaller. Responde **siempre en español** y entrega cambios listos para pegar/copiar.

---

## 1) Contexto del Proyecto

* **Nombre interno:** BuffetApp / Bar de Cancha
* **Stack:** Python 3.11 (Windows 10/11), Tkinter, SQLite (barcancha.db), PyInstaller
* **Ejecución principal:** `main.py`
* **Módulos relevantes** (rutas relativas):

  * `main.py`, `login_view.py`, `menu_view.py`, `ventas_view_new.py`, `productos_view.py`, `caja_listado_view.py`,`caja_operaciones.py`
  *  `historial_view.py`, `herramientas_view.py`, `ajustes_view.py`
  * `db_utils.py`, `init_db.py`, `utils_paths.py`
* **Interfaz/UX:** Desktop (mouse/teclado). Más adelante: uso táctil en tablet Windows/Android.
* **Impresión:** Ticket térmico; alto de ticket lo más **fijo y corto** posible para la venta; tipografías legibles.
* **Preferencias de idioma:** Español (Argentina). Zona horaria `America/Argentina/Santa Fe`.
* **Estilo visual:** Moderno, limpio, con buen contraste. Botones bien grandes para uso rápido.

---

## 2) Qué espero de tus respuestas

1. **Breve resumen** de lo que harás.
2. **Plan/Checklist** paso a paso.
3. **Cambios de código** en formato fácil de aplicar:

   * Si el cambio es **corto**, usa bloque de código por **archivo**, indicando la **ruta** y **líneas** afectadas. Revisar si existe la funcionalidad y actualizarla, preguntar en caso de necesitar crear nuevos archivos o que no se encuentre alguna función que se pida.
   * Si es **extenso**, entrega el **archivo completo** actualizado (con ruta y nombre) para reemplazar.
   * Para refactors multi-archivo, entrega **orden de aplicación**.
4. **Pruebas manuales** (cómo verificar en 1–3 minutos).
5. **Notas de compatibilidad** (Windows/Tkinter/PyInstaller) cuando aplique.

> Evita explicaciones largas si no aportan. Prioriza código funcional, buenas prácticas, claro y probado.

---

## 3) Estándares de Código

* **PEP 8** donde sea razonable; nombres claros; funciones cortas.
* **Tkinter:**

  * Usa `grid` con pesos (row/columnconfigure) para que la UI sea **responsiva**.
  * Centraliza estilos/colores/ fuentes en un **módulo de tema** (por ej. `theme.py`).
  * Evita lógica de negocio dentro de callbacks de botones; extrae a funciones en `*_view.py` o `db_utils.py`.
* **SQLite:** usa conexiones context manager (`with sqlite3.connect(...) as conn:`); crea índices cuando corresponda.
* **Errores:** manejo con `try/except` y mensajes claros para el operador; no detengas la venta por errores recuperables.
* **Dependencias:** mantener al mínimo (stdlib + Tkinter; `Pillow` opcional si se usan imágenes).

---

## 4) Reglas de UX que priorizo

* **Flujo de venta rápido:** atajos de teclado (por ejemplo: `F1` productos, `Ctrl+Enter` cobrar, `Ctrl+<-` quitar ítem, `+/-` cantidad).
* **Carrito claro:** columnas alineadas, totales visibles, botones de acción **alineados a la derecha** dentro de cada ítem.
* **Catálogo dinámico:** grilla que se adapte a cantidad de productos y categorías; soporte de imágenes opcional.
* **Formato moneda:** mostrar en ARS con separadores; evitar que el valor cambie inesperadamente al foco.
* **Impresión ticket:**

  * Alto **constante** (no crecer por textos largos), márgenes reducidos, **título centrado** (“Buffet”).
  * Destacar ítem principal en **negrita** y tamaño mayor.
  * El ticket resumen de caja no tiene limite de tamaño.
* **Caja:** soporte de **ingresos** y **retiros** con observación; visibles en cierre/informe.

---

## 5) Tareas típicas que te voy a pedir


* **Listado de cajas** con columnas que hagan wrap para textos largos.
* **Detalle de caja/Cierre de caja** Brindar kpi y valores de la caja, imprimir tickets y exportar archivos con todos los mismos datos.
* **Ingresos/Retiros**: CRUD mínimo, almacenamiento en DB y visualización en el cierre.
* **Impresión de tickets**: fijar alto, alinear contenido, aumentar tamaño titular, cortar papel sin espacio extra.
* **PyInstaller**: ajustar `BuffetApp.spec`/comando para empaquetar; reducir tamaño final si es posible.
* **Backups de DB**: copia al cierre o al salir; opción de exportar CSV/JSON para reportes.

Cuando propongas cambios, **indica** si impactan: esquema de DB, datos existentes, o empaquetado. Tambien revisar si ya existe la funcionalidad o hay que crearla nueva.

---

## 6) Base de Datos (SQLite)

* Archivo: `barcancha.db` (ruta definida en `utils_paths.py` si aplica).
* Pide confirmación antes de migraciones que puedan romper compatibilidad.
* Sugerencias aceptadas: índices en claves de búsqueda, tablas para métodos de pago, ingresos/retiros de caja, histórico de ventas.
* Backups: copia con timestamp (`backup/barcancha_YYYYMMDD_HHMMSS.db`) al salir o al cerrar caja.

---

## 8) Impresión de tickets

* Proveer **función** única para render del ticket; evitar que textos largos cambien el alto.
* Centrales: título, ítem destacado; resto en tamaño regular.
* Permitir **config** de impresora/puerto desde `ajustes_view.py`.
* Añade **prueba rápida**: imprimir ticket de ejemplo.

---

## 9) Empaquetado y despliegue

* Objetivo: **.exe** portátil con PyInstaller.
* Consideraciones:

  * Incluir `barcancha.db` si corresponde o crearla en primera ejecución en `%APPDATA%/Buffet/`.
  * Revisar `BuffetApp.spec`. Evitar `--copy-microsoft-dlls` si da error de versión.
  * Documentar librerías dinámicas, rutas relativas y assets.

Entrega script de build reproducible y cómo probarlo en otra PC.

---

## 10) Formato de respuesta para cambios de UI

Cuando cambies la UI:

1. Dibuja la **estructura** (texto) de columnas/filas y pesos.
2. Entrega **código completo** del `Frame`/`View` afectado.
3. Indica **atajos** asociados.
4. Incluye mini **checklist** de verificación visual.

---

## 11) Seguridad y datos

* No exponer claves, ni rutas personales.
* Manejar errores de archivo/DB con mensajes claros.
* Ofrecer exportaciones (CSV/JSON) sin bloquear la UI.

---

## 12) Cómo quiero que me preguntes

* Si falta un dato **crítico** (ej.: nombre exacto de una tabla), haz **una** pregunta clara.
* En lo posible, propone un **valor por defecto** razonable para avanzar.
* Tratar de reusar funcionalidades, preguntar en caso de necesitar crear un archivo nuevo.
---

## 13) Ejemplo de petición bien respondida

> **Pedido:** “Alineá los botones del carrito a la derecha y fijá el ancho del panel del carrito a 1/4 de la ventana.”

**Respuesta esperada (esquema):**

1. Resumen breve. 2) Pasos. 3) Código para `ventas_view_new.py` (completo del Frame afectado). 4) Pruebas (abrir ventas, agregar ítems, verificar alineación y resize). 5) Notas (no requiere cambios en DB).

---

## 14) No hagas

* No introduzcas dependencias pesadas si no son imprescindibles.
* No cambies el esquema de DB **sin** avisar.
* No rompas el flujo de venta por validaciones menores.
* No cambies el ticket de impresión si no te lo pido.
* No cambies funcionalidades cuando se pidan cambios de interfaz o agregado de columnas o informacion.

---

## 15) Entregables rápidos útiles

* **Snippets** de formato de moneda estable (sin alterarse al cambiar foco).
* **Helper** de atajos de teclado y leyenda visual.
* **Función** de backup con timestamp.
* **Plantilla** de ticket con alto fijo.

---

## 16) Datos del entorno

* **SO:** Windows 10/11
* **Python:** 3.11.x
* **IDE:** VS Code
* **Distribución:** PyInstaller (onefolder) + carpeta `assets/` si aplica.

---

## 17) Modo de trabajo

* Siempre que toques varios archivos, incluye una **lista ordenada** de reemplazo.
* Señala **breaking changes**.
* Incluye **puntos de rollback** (qué revertir si algo falla).

---

## 18) Licencia y créditos

* Proyecto personal. Evitar assets con licencias restrictivas.

---

> **Listo.** Usa estas instrucciones como guía base para todas tus respuestas dentro de este repo. Si detectás inconsistencias, proponé correcciones concretas con el menor impacto posible.

