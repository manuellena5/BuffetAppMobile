import tkinter as tk
from menu_view import MenuView
import datetime
from tkinter import simpledialog, messagebox
from init_db import init_db, log_error
from login_view import LoginView
from utils_paths import CONFIG_PATH, DB_PATH
from db_utils import get_connection



# ----------- INTERFAZ PRINCIPAL -----------
class BarCanchaApp:
    def imprimir_ticket(self, carrito):
        # TODO: Implementar lógica real de impresión de ticket si es necesario
        print("[DEBUG] imprimir_ticket llamado con carrito:", carrito)
        # Aquí puedes llamar a la lógica de impresión real si existe
    def __init__(self, root):
        import json, os
        self.root = root
        try:
            from theme import APP_VERSION
            self.root.title(f"Sistema de Ventas - Bar de Cancha - {APP_VERSION}")
        except Exception:
            self.root.title("Sistema de Ventas - Bar de Cancha")
        # Establecer icono de la aplicación
        try:
            icon_path = os.path.join(os.path.dirname(__file__), "cdm_mitre_white_app_256.png")
            if os.path.exists(icon_path):
                self.root.iconphoto(True, tk.PhotoImage(file=icon_path))
        except Exception as e:
            print(f"No se pudo cargar el icono: {e}")

        # Inicializar DB en AppData sólo si no existe
        if not os.path.exists(DB_PATH) or os.path.getsize(DB_PATH) == 0:
            init_db()

        # Leer/crear config en AppData
        if not os.path.exists(CONFIG_PATH):
            default_config = {"ancho_boton": 20, "alto_boton": 2, "color_boton": "#f0f0f0", "fuente_boton": "Arial", "lenguaje": "es"}
            with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                json.dump(default_config, f, indent=2)
            self.configuracion = default_config
        else:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                self.configuracion = json.load(f)

        # Maximizar ventana principal al iniciar
        try:
            self.root.state('zoomed')  # Windows
        except Exception:
            # Fallback: centrar y agrandar ventana principal
            ancho = 1300
            alto = 750
            x = (self.root.winfo_screenwidth() // 2) - (ancho // 2)
            y = (self.root.winfo_screenheight() // 2) - (alto // 2)
            self.root.geometry(f"{ancho}x{alto}+{x}+{y}")
        # Increase menu font size for easier access
        self.menu_bar = tk.Menu(self.root, font=("Arial", 16))
        # No mostrar la barra de menú hasta que el usuario se loguee
        self.root.config(menu=None)
        self.menu_bar.add_command(label="Menú Principal", command=self.mostrar_menu_principal, state=tk.DISABLED)
        self.menu_bar.add_command(label="Ventas", command=self.mostrar_ventas, state=tk.DISABLED)
        self.menu_bar.add_command(label="Historial ventas", command=self.mostrar_historial, state=tk.DISABLED)
        self.menu_bar.add_command(label="Productos", command=self.mostrar_productos, state=tk.DISABLED)
        from herramientas_view import HerramientasView
        self.herramientas_view = HerramientasView(self)
        self.herramientas_menu = tk.Menu(self.menu_bar, tearoff=0)
        self.herramientas_menu.add_command(
            label="Test Impresora", command=self.herramientas_view.test_impresora, state=tk.DISABLED
        )

        # Menú de caja: permite abrir y cerrar la caja diaria
        self.caja_menu = tk.Menu(self.menu_bar, tearoff=0)
        self.caja_menu.add_command(label="Abrir Caja", command=self.abrir_caja_window)
        self.caja_menu.add_command(label="Cerrar Caja", command=self.cerrar_caja_window, state=tk.DISABLED)
        # Ingreso/Retiro de efectivo se manejan desde la pantalla de Detalle/Cierre de caja.
        # Eliminamos las entradas del menú para evitar duplicación de flujos.
        self.caja_menu.add_command(label="Listado de Cajas", command=self.mostrar_listado_cajas)
        self.menu_bar.add_cascade(label="Cajas", menu=self.caja_menu)

        # Herramientas como último elemento del menú
        self.menu_bar.add_cascade(label="Herramientas", menu=self.herramientas_menu)

        self.logged_user = None
        self.logged_role = None

        self.menu_view = MenuView(
            self.root,
            get_caja_info=self.get_caja_info,
            on_cerrar_caja=self.cerrar_caja_window,
            on_ver_cierre=self.ver_cierre_caja,
            on_abrir_caja=self.abrir_caja_window,
            controller=self
        )

        # Vistas cargadas a demanda
        self.ventas_view = None
        self.historial_view = None
        self.cajas_view = None
        self.informe_view = None
        self.ajustes_view = None
        self.productos_view = None

        self.caja_abierta_id = None
        
        self.ocultar_frames()
        self.login_view = LoginView(self.root, self.on_login)
        self.login_view.pack(fill=tk.BOTH, expand=True)


    def caja_abierta_bool(self):
        return bool(getattr(self, "caja_abierta_id", None))
    def mostrar_listado_cajas(self):
        """Muestra el listado general de cajas"""
        # Unificar con mostrar_cajas para evitar duplicidad y superposiciones
        self.mostrar_cajas()
        try:
            self.cajas_view.cargar_cajas()
        except Exception:
            pass

    def habilitar_menu(self):
        # Habilita todos los comandos del menú principal
        self.menu_bar.entryconfig("Menú Principal", state=tk.NORMAL)
        self.menu_bar.entryconfig("Ventas", state=tk.NORMAL)
        self.menu_bar.entryconfig("Historial ventas", state=tk.NORMAL)
        self.menu_bar.entryconfig("Productos", state=tk.NORMAL)
        self.herramientas_menu.entryconfig("Test Impresora", state=tk.NORMAL)


    def actualizar_menu_caja(self):
        info = self.get_caja_info()
        abierta = bool(info)
        self.caja_menu.entryconfig("Abrir Caja",  state=(tk.DISABLED if abierta else tk.NORMAL))
        self.caja_menu.entryconfig("Cerrar Caja", state=(tk.NORMAL if abierta else tk.DISABLED))
        # Las operaciones de Ingreso/Retiro se gestionan desde Detalle/Cierre de Caja
        # por lo que ya no existen entradas dedicadas en este menú.
        self.menu_bar.entryconfig("Ventas", state=(tk.NORMAL if abierta else tk.DISABLED))

    def on_caja_cerrada(self):
        """Actualiza el estado global cuando una caja se cierra."""
        self.caja_abierta_id = None
        self.actualizar_menu_caja()
        if hasattr(self, 'menu_view'):
            self.menu_view.actualizar_caja_info()
            self.mostrar_pie_caja(self.menu_view)

    def get_caja_info(self):
        caja_id = getattr(self, 'caja_abierta_id', None)
        if not caja_id:
            return None
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT cd.codigo_caja, COALESCE(d.descripcion, cd.disciplina) AS disciplina,
                   cd.hora_apertura, cd.usuario_apertura, cd.fondo_inicial
              FROM caja_diaria cd
              LEFT JOIN disciplinas d ON d.codigo = cd.disciplina
             WHERE cd.id=?
            """,
            (caja_id,)
        )
        row = cursor.fetchone()
        info = None
        if row:
            info = {
                'codigo': row[0],
                'disciplina': row[1],
                'hora_apertura': row[2],
                'usuario_apertura': row[3],
                'fondo_inicial': row[4],
            }
            cursor.execute("SELECT tipo FROM caja_movimiento WHERE caja_id=?", (caja_id,))
            tipos = {r[0] for r in cursor.fetchall()}
            info['tiene_ingreso'] = 'INGRESO' in tipos
            info['tiene_retiro'] = 'RETIRO' in tipos
        conn.close()
        return info

    def ver_cierre_caja(self):

        """Muestra la pantalla de informe del día."""
        if not self.informe_view:
            from informe_dia_view import InformeDiaView
            self.informe_view = InformeDiaView(self.root)
        self.ocultar_frames()
        self.informe_view.reset()
        self.informe_view.pack(fill=tk.BOTH, expand=True)
        self.mostrar_pie_caja(self.informe_view)

    # ----- Movimientos manuales de caja -----
    def _informar_movimiento(self, tipo):
        caja_id = getattr(self, 'caja_abierta_id', None)
        if not caja_id:
            messagebox.showerror("Caja", "No hay caja abierta.")
            return
        win = tk.Toplevel(self.root)
        win.title(f"Informar {tipo}")






        ancho, alto = 360, 300
        x = self.root.winfo_screenwidth() // 2 - ancho // 2
        y = self.root.winfo_screenheight() // 2 - alto // 2
        win.geometry(f"{ancho}x{alto}+{x}+{y}")
        win.transient(self.root)
        win.grab_set()





        tk.Label(win, text=f"Monto del {tipo}:", font=("Arial", 12)).pack(pady=6)
        entry = tk.Entry(win, font=("Arial", 12))
        entry.pack(pady=2)
        lbl = tk.Label(win, text="", font=("Arial", 11), fg="#388e3c")
        lbl.pack(pady=(0,4))
        tk.Label(win, text="Observación:", font=("Arial", 12)).pack(pady=6)
        obs_entry = tk.Text(win, font=("Arial", 12), width=40, height=4)
        obs_entry.pack(pady=2)


        def fmt(event=None):
            val = entry.get().replace(",", ".")
            try:
                if val:
                    m = float(val)
                    lbl.config(text=f"$ {m:,.2f}")
                else:
                    lbl.config(text="")
            except Exception:
                lbl.config(text="")

        entry.bind("<KeyRelease>", fmt)

        def confirmar():
            try:
                monto = float(entry.get().strip().replace(",", "."))
            except Exception:
                messagebox.showerror("Error", "El monto debe ser numérico.")
                return

            obs = obs_entry.get("1.0", tk.END).strip()
            if len(obs) > 50:
                messagebox.showerror("Error", "La observación no debe superar 50 caracteres.")
                return

            conn = get_connection(); cur = conn.cursor()
            cur.execute(
                """
                INSERT INTO caja_movimiento (caja_id, tipo, monto, observacion)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(caja_id, tipo) DO UPDATE SET
                  monto=excluded.monto,
                  observacion=excluded.observacion,
                  creado_ts=CURRENT_TIMESTAMP
                """,
                (caja_id, tipo.upper(), monto, obs)
            )
            if tipo == 'ingreso':
                cur.execute("UPDATE caja_diaria SET ingresos=? WHERE id=?", (monto, caja_id))
            else:
                cur.execute("UPDATE caja_diaria SET retiros=? WHERE id=?", (monto, caja_id))
            conn.commit(); conn.close()
            win.destroy()
            messagebox.showinfo("Caja", f"{tipo.capitalize()} registrado.")
            self.actualizar_menu_caja()
            self.menu_view.actualizar_caja_info()

        tk.Button(win, text="Guardar", command=confirmar, width=14).pack(pady=8)
        tk.Button(win, text="Cancelar", command=win.destroy, width=14).pack(pady=(0,8))

    def informar_ingreso(self):
        self._informar_movimiento('ingreso')

    def informar_retiro(self):
        self._informar_movimiento('retiro')

    
    def on_login(self, usuario, rol):
        self.logged_user = usuario
        self.logged_role = rol
        self.login_view.pack_forget()
        # Mostrar la barra de menú una vez autenticado el usuario
        self.root.config(menu=self.menu_bar)
        self.habilitar_menu()
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, codigo_caja FROM caja_diaria WHERE estado='abierta'")
        rows = cursor.fetchall()
        conn.close()

        if not rows:
            messagebox.showinfo("Caja", "No hay caja abierta. Abra una caja desde el menú Caja para habilitar ventas.")
            self.caja_abierta_id = None
        elif len(rows) == 1:
            self.caja_abierta_id = rows[0][0]
        else:
            self.resolver_cajas_abiertas(rows)

        self.actualizar_menu_caja()
        self.mostrar_menu_principal()

    def verificar_caja_abierta(self):
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, codigo_caja FROM caja_diaria WHERE estado='abierta'")
        rows = cursor.fetchall()
        conn.close()

        if not rows:
            messagebox.showinfo("Caja", "No hay caja abierta.")
            self.caja_abierta_id = None
        elif len(rows) == 1:
            self.caja_abierta_id = rows[0][0]
        else:
            self.resolver_cajas_abiertas(rows)
        self.actualizar_menu_caja()
        self.mostrar_menu_principal()

    def resolver_cajas_abiertas(self, rows):
        win = tk.Toplevel(self.root)
        win.title("Cajas abiertas")
        tk.Label(win, text="Seleccione la caja a usar:" ).pack(padx=10, pady=5)
        lista = tk.Listbox(win, width=40)
        lista.pack(padx=10, pady=5)
        for cid, codigo in rows:
            lista.insert(tk.END, codigo)

        def usar():
            sel = lista.curselection()
            if not sel:
                messagebox.showwarning("Caja", "Debe seleccionar una caja.")
                return
            self.caja_abierta_id = rows[sel[0]][0]
            win.destroy()

        def cerrar_todas():
            if messagebox.askyesno("Cerrar", "¿Cerrar todas las cajas abiertas?" ):
                import datetime
                now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                conn = get_connection()
                cur = conn.cursor()
                cur.execute("UPDATE caja_diaria SET estado='cerrada', hora_cierre=?, cierre_dt=? WHERE estado='abierta'", (now.split(' ')[1], now))
                conn.commit()
                conn.close()
                self.caja_abierta_id = None
                win.destroy()

        tk.Button(win, text="Usar caja", command=usar).pack(side=tk.LEFT, padx=10, pady=10)
        tk.Button(win, text="Cerrar todas", command=cerrar_todas).pack(side=tk.RIGHT, padx=10, pady=10)
        win.grab_set()
        self.root.wait_window(win)

    def actualizar_configuracion(self, nueva_config):
        import json
        self.configuracion.update(nueva_config)
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(self.configuracion, f, indent=2)
        if self.ventas_view:
            try:
                self.ventas_view.actualizar_estilos(self.configuracion)
            except Exception:
                pass
        if self.productos_view:
            try:
                self.productos_view.actualizar_estilos(self.configuracion)
            except Exception:
                pass

    def ocultar_frames(self):
        self.menu_view.pack_forget()
        if self.ventas_view:
            self.ventas_view.pack_forget()
        if self.historial_view:
            self.historial_view.pack_forget()
        if self.cajas_view:
            try:
                self.cajas_view.cerrar_detalle()
            except Exception:
                pass
            self.cajas_view.pack_forget()
        if self.informe_view:
            self.informe_view.pack_forget()
        if self.productos_view:
            self.productos_view.pack_forget()
        if self.ajustes_view:
            try:
                self.ajustes_view.pack_forget()
            except Exception:
                pass

    def mostrar_cajas(self):
        if not self.cajas_view:
            try:
                from BuffetApp.caja_listado_view import CajaListadoView
            except Exception:
                from caja_listado_view import CajaListadoView
            self.cajas_view = CajaListadoView(self.root, self.on_caja_cerrada)
        self.ocultar_frames()
        self.cajas_view.pack(fill=tk.BOTH, expand=True)
        self.mostrar_pie_caja(self.cajas_view)  # si tenés este pie en otras vistas

    def mostrar_menu_principal(self):
        self.ocultar_frames()
        self.menu_view.actualizar_caja_info()
        self.menu_view.pack(fill=tk.BOTH, expand=True)
        self.mostrar_pie_caja(self.menu_view)

    def mostrar_pie_caja(self, parent):
        # Elimina barras previas si existen
        for widget in getattr(parent, '_pie_caja_widgets', []):
            widget.destroy()
        info = self.get_caja_info()
        if info:
            texto = f"🟢 Caja {info['codigo']} abierta - Apertura: {info['hora_apertura']}"
            pie = tk.Label(parent, text=texto, font=("Arial", 11), bg="#e8f5e9", anchor="w", justify="left")
        else:
            pie = tk.Label(parent, text="🔴 Caja cerrada", font=("Arial", 11), bg="#ffebee", anchor="w", justify="left")

        # Evitar mezclar managers: usar grid si el parent ya utiliza grid
        if parent.grid_slaves():
            cols, rows = parent.grid_size()
            pie.grid(row=rows, column=0, columnspan=cols, sticky="ew")
        else:
            pie.pack(side=tk.BOTTOM, fill=tk.X)
        parent._pie_caja_widgets = [pie]

    def mostrar_ventas(self):
        # Solo permitir ventas si hay caja abierta
        if not getattr(self, 'caja_abierta_id', None):
            messagebox.showwarning("Caja", "Debe abrir la caja antes de realizar ventas.")
            return
        if not self.ventas_view:
            from ventas_view_new import VentasViewNew
            self.ventas_view = VentasViewNew(
                self.root,
                cobrar_callback=self.on_cobrar,
                imprimir_ticket_callback=self.imprimir_ticket
            )
        # No es necesario llamar a actualizar_productos, la vista nueva se actualiza sola
        self.ocultar_frames()
        self.ventas_view.pack(fill=tk.BOTH, expand=True)
        # Ajusta el frame del carrito para que ocupe todo el alto disponible
        if hasattr(self.ventas_view, 'frame_carrito'):
            self.ventas_view.frame_carrito.pack(fill=tk.BOTH, expand=True)
            self.mostrar_pie_caja(self.ventas_view.frame_carrito)
        else:
            self.mostrar_pie_caja(self.ventas_view)
        # Bloquea acciones si la caja está cerrada
        if not getattr(self, 'caja_abierta_id', None):
            if hasattr(self.ventas_view, 'bloquear_acciones'): self.ventas_view.bloquear_acciones()

    def obtener_resumen_caja(self, caja_id):
        """Recopila datos resumidos filtrando por la caja indicada."""

        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT cd.codigo_caja, COALESCE(d.descripcion, cd.disciplina) AS disciplina,
                   cd.usuario_apertura, cd.fecha, cd.hora_apertura, cd.fondo_inicial, cd.estado
              FROM caja_diaria cd
              LEFT JOIN disciplinas d ON d.codigo = cd.disciplina
             WHERE cd.id=?
            """,
            (caja_id,),
        )
        info = cursor.fetchone()
        if info:
            codigo_caja, disciplina, usuario_apertura, fecha, hora_apertura, fondo_inicial, estado = info
        else:
            codigo_caja = disciplina = usuario_apertura = fecha = hora_apertura = estado = ''
            fondo_inicial = 0

        cursor.execute("SELECT tipo, monto, observacion FROM caja_movimiento WHERE caja_id=?", (caja_id,))
        ingresos = retiros = 0
        obs_ing = obs_ret = ''
        for tipo, monto, obs in cursor.fetchall():
            if tipo == 'INGRESO':
                ingresos = monto
                obs_ing = obs or ''
            elif tipo == 'RETIRO':
                retiros = monto
                obs_ret = obs or ''

        cursor.execute(
            """
            SELECT COALESCE(SUM(t.total_ticket),0)
              FROM tickets t JOIN ventas v ON v.id = t.venta_id
             WHERE v.caja_id=? AND t.status!='Anulado'
            """,
            (caja_id,),
        )
        total_ventas = cursor.fetchone()[0] or 0
        cursor.execute(
            """
            SELECT COUNT(*) FROM tickets t JOIN ventas v ON v.id=t.venta_id
             WHERE v.caja_id=? AND t.status!='Anulado'
            """,
            (caja_id,),
        )
        total_tickets = cursor.fetchone()[0] or 0
        cursor.execute(
            """
            SELECT COUNT(*) FROM tickets t JOIN ventas v ON v.id=t.venta_id
             WHERE v.caja_id=? AND t.status='Anulado'
            """,
            (caja_id,),
        )
        tickets_anulados = cursor.fetchone()[0] or 0

        cursor.execute(
            """
            SELECT c.descripcion, COALESCE(SUM(t.total_ticket),0)
              FROM tickets t
              JOIN ventas v ON v.id = t.venta_id
              LEFT JOIN Categoria_Producto c ON c.id = t.categoria_id
             WHERE v.caja_id=? AND t.status!='Anulado'
             GROUP BY c.descripcion
             ORDER BY c.descripcion
            """,
            (caja_id,),
        )
        por_categoria = cursor.fetchall()

        # Productos vendidos agrupados para mostrar resumen
        cursor.execute(
            """
            SELECT c.descripcion, p.nombre, SUM(vi.cantidad) AS cant
              FROM venta_items vi
              JOIN tickets t ON t.id = vi.ticket_id
              JOIN ventas v ON v.id = t.venta_id
              JOIN products p ON p.id = vi.producto_id
              LEFT JOIN Categoria_Producto c ON p.categoria_id = c.id
             WHERE v.caja_id=? AND t.status!='Anulado'
             GROUP BY c.descripcion, p.nombre
             ORDER BY c.descripcion, p.nombre
            """,
            (caja_id,),
        )
        rows_items = cursor.fetchall()
        items_por_categoria = {}
        for cat, prod, cant in rows_items:
            cat = cat or "Sin categoría"
            items_por_categoria.setdefault(cat, []).append((prod, cant))

        # Cantidad de ventas por método de pago
        cursor.execute(
            """
            SELECT mp.descripcion, COUNT(*), COALESCE(SUM(t.total_ticket),0)
              FROM ventas v
              JOIN tickets t ON t.venta_id = v.id
              LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
             WHERE v.caja_id=? AND t.status!='Anulado'
             GROUP BY mp.descripcion
            """,
            (caja_id,),
        )
        metodos_pago = cursor.fetchall()
        conn.close()
        total_teorico = fondo_inicial + total_ventas + ingresos - retiros
        return {
            'codigo': codigo_caja,
            'disciplina': disciplina,
            'usuario_apertura': usuario_apertura,
            'fecha': fecha,
            'hora_apertura': hora_apertura,
            'fondo_inicial': fondo_inicial,
            'total_ventas': total_ventas,
            'total_tickets': total_tickets,
            'por_categoria': por_categoria,
            'items_por_categoria': items_por_categoria,
            'metodos_pago': metodos_pago,
            'tickets_anulados': tickets_anulados,
            'ingresos': ingresos,
            'retiros': retiros,
            'obs_ingreso': obs_ing,
            'obs_retiro': obs_ret,
            'total_teorico': total_teorico,
            'estado': estado
        }
    def mostrar_historial(self):
        if not self.historial_view:
            from historial_view import HistorialView
            self.historial_view = HistorialView(self.root)
        self.ocultar_frames()
        self.historial_view.pack(fill=tk.BOTH, expand=True)
        # Asegurar que los botones de paginación/filtro estén visibles
        if hasattr(self.historial_view, 'frame_botones_tabla'):
            # Solo llamar pack si no está visible
            if not self.historial_view.frame_botones_tabla.winfo_ismapped():
                self.historial_view.frame_botones_tabla.pack(pady=5)
        self.historial_view.cargar_historial()
        # Habilitar/deshabilitar acciones según estado de caja
        if hasattr(self.historial_view, 'set_acciones_habilitadas'):
            habilitar = bool(getattr(self, 'caja_abierta_id', None))
            self.historial_view.set_acciones_habilitadas(habilitar)
        self.mostrar_pie_caja(self.historial_view)

    def mostrar_productos(self):
        self.ocultar_frames()
        from productos_view import ProductosView
        if not self.productos_view:
            self.productos_view = ProductosView(self.root)
        self.productos_view.pack(fill=tk.BOTH, expand=True)
        self.productos_view.cargar_productos()
        self.mostrar_pie_caja(self.productos_view)

    def mostrar_ajustes(self):
        self.ocultar_frames()
        if self.ajustes_view is None:
            from ajustes_view import AjustesView
            # Pasar la instancia principal para poder actualizar la configuración global
            self.ajustes_view = AjustesView(self.root, self)
        self.ajustes_view.pack(fill=tk.BOTH, expand=True)

    def on_cobrar(self, carrito, metodo_pago="Efectivo"):
        # Guardar la venta en la base de datos
        if not carrito:
            return
        try:
            conn = get_connection()
            cursor = conn.cursor()
            total = sum(item[2]*item[3] for item in carrito)
            fecha_hora = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            # Obtener o crear método de pago y su id
            metodo_id = None
            try:
                # si se pasó un id numérico, usarlo directamente
                if isinstance(metodo_pago, int) or (isinstance(metodo_pago, str) and metodo_pago.isdigit()):
                    metodo_id = int(metodo_pago)
                    cursor.execute("SELECT id FROM metodos_pago WHERE id = ?", (metodo_id,))
                    if not cursor.fetchone():
                        metodo_id = None
                else:
                    # buscar por descripción
                    cursor.execute("SELECT id FROM metodos_pago WHERE descripcion = ?", (metodo_pago,))
                    row = cursor.fetchone()
                    if row:
                        metodo_id = row[0]
            except Exception:
                metodo_id = None
            if metodo_id is None:
                # si no existe, crear nuevo registro usando la descripcion si es string
                if isinstance(metodo_pago, str):
                    cursor.execute("INSERT INTO metodos_pago (descripcion) VALUES (?)", (metodo_pago,))
                    metodo_id = cursor.lastrowid
                else:
                    # fallback: usar 1 (Efectivo) si existe
                    cursor.execute("SELECT id FROM metodos_pago WHERE descripcion LIKE 'Efectivo' LIMIT 1")
                    row = cursor.fetchone()
                    metodo_id = row[0] if row else None

            # Insertar venta
            cursor.execute(
                "INSERT INTO ventas (fecha_hora, total_venta, metodo_pago_id, caja_id) VALUES (?, ?, ?, ?)",
                (fecha_hora, total, metodo_id, getattr(self, 'caja_abierta_id', None)),
            )
            venta_id = cursor.lastrowid
            # Persistir la venta inmediatamente para evitar perder el registro si
            # falla la inserción posterior de tickets/venta_items (p. ej. por FK)
            conn.commit()

            # Crear un ticket por cada unidad vendida (un ticket por item x cantidad)
            prod_ids = [item[0] for item in carrito]
            # Obtener datos necesarios de products: codigo_producto, categoria_id, stock_actual
            cursor.execute(
                f"SELECT id, codigo_producto, categoria_id, stock_actual FROM products WHERE id IN ({','.join('?' for _ in prod_ids)})",
                prod_ids,
            )
            prod_rows = cursor.fetchall()
            prod_info = {r[0]: {'codigo': r[1], 'categoria': r[2], 'stock': r[3]} for r in prod_rows}

            # Para la secuencia por caja: si hay caja abierta, usaremos y actualizaremos total_tickets en caja_diaria
            def next_ticket_seq():
                caja_id = getattr(self, 'caja_abierta_id', None)
                if caja_id:
                    cursor.execute("UPDATE caja_diaria SET total_tickets = COALESCE(total_tickets,0)+1 WHERE id=?", (caja_id,))
                    cursor.execute("SELECT total_tickets FROM caja_diaria WHERE id=?", (caja_id,))
                    return cursor.fetchone()[0]
                else:
                    # fallback: use ticket autoincrement (will be available after insert) — but we need a seq before insert
                    # Use a per-sale incrementing counter
                    nonlocal_ticket_seq = getattr(self, '_temp_ticket_seq', 0) + 1
                    self._temp_ticket_seq = nonlocal_ticket_seq
                    return nonlocal_ticket_seq

            # Insertar tickets y items; si alguna inserción falla, registrar y continuar
            for prod_id, nombre, precio, cantidad in carrito:
                info = prod_info.get(prod_id, {})
                codigo = info.get('codigo') or str(prod_id)
                categoria_id = info.get('categoria')
                stock_actual = info.get('stock')
                for _ in range(int(cantidad)):
                    try:
                        seq = next_ticket_seq()
                        date_str = datetime.datetime.now().strftime('%d%m%Y')
                        identificador = f"{codigo}-{date_str}-{seq}"
                        # Insertar ticket por unidad
                        cursor.execute(
                            "INSERT INTO tickets (venta_id, categoria_id, producto_id, fecha_hora, total_ticket, identificador_ticket) VALUES (?, ?, ?, ?, ?, ?)",
                            (venta_id, categoria_id, prod_id, fecha_hora, precio, identificador),
                        )
                        ticket_id = cursor.lastrowid
                        # Insertar un item con cantidad=1
                        cursor.execute(
                            "INSERT INTO venta_items (ticket_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (?, ?, ?, ?, ?)",
                            (ticket_id, prod_id, 1, precio, precio),
                        )
                        # Actualizar stock sólo si no es infinito (999)
                        try:
                            if stock_actual is not None and int(stock_actual) != 999:
                                cursor.execute("UPDATE products SET stock_actual = stock_actual - 1 WHERE id = ?", (prod_id,))
                                stock_actual -= 1
                        except Exception:
                            # no crítico; continuar
                            pass
                    except Exception as e:
                        # Registrar el error y continuar con el siguiente item en lugar de abortar toda la venta
                        try:
                            import traceback
                            traceback.print_exc()
                        except Exception:
                            pass
                        # continue to next unit
                        continue
            # Asegurar que cualquier ticket/venta_items escritos se persistan
            try:
                conn.commit()
            except Exception:
                pass

            # Collect tickets info to return for printing
            tickets_info = []
            try:
                cursor.execute("SELECT id, identificador_ticket, producto_id, total_ticket FROM tickets WHERE venta_id=? ORDER BY id", (venta_id,))
                for t in cursor.fetchall():
                    tid, identificador, pid, total_ticket = t
                    # obtener nombre producto
                    cursor.execute("SELECT nombre FROM products WHERE id=?", (pid,))
                    rowp = cursor.fetchone()
                    nombre_prod = rowp[0] if rowp else ''
                    codigo_caja = None
                    if getattr(self, 'caja_abierta_id', None):
                        cursor.execute("SELECT codigo_caja FROM caja_diaria WHERE id=?", (getattr(self, 'caja_abierta_id', None),))
                        rc = cursor.fetchone()
                        codigo_caja = rc[0] if rc else None
                    tickets_info.append({
                        'ticket_id': tid,
                        'identificador': identificador,
                        'producto_id': pid,
                        'producto_nombre': nombre_prod,
                        'total_ticket': total_ticket,
                        'codigo_caja': codigo_caja,
                    })
            except Exception:
                tickets_info = []
            conn.close()
            # Mostrar descripción del método de pago al usuario
            try:
                cursor = get_connection().cursor()
                cursor.execute("SELECT descripcion FROM metodos_pago WHERE id=?", (metodo_id,))
                row = cursor.fetchone()
                descripcion_mp = row[0] if row else str(metodo_pago)
            except Exception:
                descripcion_mp = str(metodo_pago)
            messagebox.showinfo("Venta registrada", f"Venta guardada correctamente.\nMétodo de pago: {descripcion_mp}")
            return {'venta_id': venta_id, 'tickets': tickets_info}
        except Exception as e:
            messagebox.showerror("Error al guardar venta", str(e))

    
    def abrir_caja_window(self):
        import datetime
        win = tk.Toplevel(self.root)
        win.title("Apertura de Caja")
        ancho = 370
        alto = 540  # Más alto para mostrar todo el contenido y botones
        x = win.winfo_screenwidth() // 2 - ancho // 2
        y = win.winfo_screenheight() // 2 - alto // 2
        win.geometry(f"{ancho}x{alto}+{x}+{y}")
        win.transient(self.root)
        win.grab_set()
        tk.Label(win, text="Usuario apertura:", font=("Arial", 12)).pack(pady=6)

        def _limit_entry(max_len):
            return (win.register(lambda P: len(P) <= max_len), "%P")

        entry_usuario = tk.Entry(
            win,
            font=("Arial", 12),
            validate="key",
            validatecommand=_limit_entry(10),
        )
        entry_usuario.insert(0, self.logged_user or "")
        entry_usuario.pack(pady=2)
        tk.Label(win, text="Fondo inicial:", font=("Arial", 12)).pack(pady=6)
        entry_fondo = tk.Entry(win, font=("Arial", 12))
        entry_fondo.pack(pady=2)
        # Label para mostrar el valor formateado
        label_moneda = tk.Label(win, text="", font=("Arial", 11), fg="#388e3c")
        label_moneda.pack(pady=(0, 4))

        def formatear_moneda(event=None):
            valor = entry_fondo.get().replace(",", ".")
            try:
                if valor:
                    monto = float(valor)
                    label_moneda.config(text=f"$ {monto:,.2f}")
                else:
                    label_moneda.config(text="")
            except Exception:
                label_moneda.config(text="")

        entry_fondo.bind("<KeyRelease>", formatear_moneda)

        hora_apertura = datetime.datetime.now().strftime("%H:%M:%S")
        fecha = datetime.datetime.now().strftime("%Y-%m-%d")
        tk.Label(win, text=f"Fecha: {fecha}", font=("Arial", 11)).pack(pady=4)
        tk.Label(win, text=f"Hora: {hora_apertura}", font=("Arial", 11)).pack(pady=2)
        tk.Label(win, text="Disciplina:", font=("Arial", 12)).pack(pady=6)
        from tkinter import ttk
        conn_disc = get_connection()
        cur_disc = conn_disc.cursor()
        cur_disc.execute("SELECT codigo FROM disciplinas ORDER BY codigo")
        disciplinas = [r[0] for r in cur_disc.fetchall()] or [""]
        conn_disc.close()
        var_disc = tk.StringVar(value=disciplinas[0] if disciplinas else "")
        ttk.Combobox(win, values=disciplinas, textvariable=var_disc, state="readonly", width=14).pack(pady=2)
        tk.Label(win, text="Observaciones:", font=("Arial", 12)).pack(pady=6)
        entry_obs = tk.Text(win, font=("Arial", 12), height=3, width=32)
        entry_obs.pack(pady=2)

        def limitar_texto(widget, max_chars):
            contenido = widget.get("1.0", tk.END)[:-1]
            if len(contenido) > max_chars:
                widget.delete("1.0", tk.END)
                widget.insert("1.0", contenido[:max_chars])

        entry_obs.bind("<KeyRelease>", lambda e: limitar_texto(entry_obs, 30))

        def confirmar():
            usuario = entry_usuario.get().strip()
            fondo = entry_fondo.get().strip().replace(",", ".")
            observaciones = entry_obs.get("1.0", tk.END).strip()
            disciplina = var_disc.get()
            if not usuario or not fondo:
                messagebox.showwarning("Datos incompletos", "Complete usuario y fondo inicial.")
                return
            if len(usuario) > 10:
                messagebox.showwarning("Usuario", "Máximo 10 caracteres.")
                return
            try:
                fondo_val = float(fondo)
            except Exception:
                messagebox.showerror("Error", "El fondo inicial debe ser numérico.")
                return
            if len(observaciones) > 30:
                messagebox.showwarning("Observaciones", "Máximo 30 caracteres.")
                return
            conn = get_connection()
            cursor = conn.cursor()
            # Generar código secuencial por fecha y disciplina
            cursor.execute(
                "SELECT codigo_caja FROM caja_diaria WHERE fecha=? AND disciplina=?",
                (fecha, disciplina),
            )
            existentes = [r[0] for r in cursor.fetchall()]
            sec = 1
            for cod in existentes:
                try:
                    n = int(str(cod).split("-")[0].replace("CA", ""))
                    if n >= sec:
                        sec = n + 1
                except Exception:
                    pass
            codigo_caja = f"CA{sec:02d}-{fecha.replace('-', '')}-{disciplina}"
            cursor.execute(
                "INSERT INTO caja_diaria (codigo_caja, disciplina, fecha, usuario_apertura, hora_apertura, apertura_dt, fondo_inicial, observaciones_apertura, estado) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'abierta')",
                (codigo_caja, disciplina, fecha, usuario, hora_apertura, f"{fecha} {hora_apertura}", fondo_val, observaciones))
            caja_id = cursor.lastrowid
            conn.commit()
            conn.close()
            self.caja_abierta_id = caja_id
            self.actualizar_menu_caja()
            self.menu_view.actualizar_caja_info()
            self.mostrar_pie_caja(self.menu_view)
            win.destroy()
            # Ventana de éxito y botón para ir a stock
            def ir_a_stock():
                self.abrir_stock_window()
                top.destroy()
            top = tk.Toplevel(self.root)
            top.title("Caja abierta")
            ancho, alto = 350, 180
            x = top.winfo_screenwidth() // 2 - ancho // 2
            y = top.winfo_screenheight() // 2 - alto // 2
            top.geometry(f"{ancho}x{alto}+{x}+{y}")
            tk.Label(top, text="¡Caja abierta correctamente!", font=("Arial", 13, "bold"), fg="#388e3c").pack(pady=18)
            btn_stock = tk.Button(top, text="Agregar stock/precios", command=ir_a_stock, bg="#1976d2", fg="white", font=("Arial", 12), width=24)
            btn_stock.pack(pady=8)
            btn_ok = tk.Button(top, text="Cerrar", command=top.destroy, font=("Arial", 12), width=12)
            btn_ok.pack(pady=4)

        btn_confirmar = tk.Button(win, text="Confirmar apertura", command=confirmar, bg="#4CAF50", fg="white", font=("Arial", 12), width=16)
        btn_confirmar.pack(pady=16)
        btn_cancelar = tk.Button(win, text="Cancelar", command=win.destroy, font=("Arial", 12), width=16)
        btn_cancelar.pack(pady=4)

    # Nueva ventana para stock de productos tras abrir caja
    def abrir_stock_window(self):
        from tkinter import ttk
        stock_win = tk.Toplevel(self.root)
        stock_win.title("Agregar stock/precios")
        ancho = 700
        alto = 700  # Aumentar alto para mejor visualización
        x = stock_win.winfo_screenwidth() // 2 - ancho // 2
        y = stock_win.winfo_screenheight() // 2 - alto // 2
        stock_win.geometry(f"{ancho}x{alto}+{x}+{y}")
        stock_win.transient(self.root)
        stock_win.grab_set()
        tk.Label(stock_win, text="Agregar stock/precios", font=("Arial", 15, "bold")).pack(pady=10)
        frame = tk.Frame(stock_win)
        frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        # Encabezados
        headers = ["Producto", "Stock", "Precio", "Ocultar", ""]
        for i, h in enumerate(headers):
            tk.Label(frame, text=h, font=("Arial", 11, "bold")).grid(row=0, column=i, padx=6, pady=4)
        # Obtener productos
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT p.id, p.nombre, p.stock_actual, p.visible, p.precio_venta, c.descripcion as categoria FROM products p LEFT JOIN Categoria_Producto c ON p.categoria_id = c.id ORDER BY c.descripcion, p.nombre"
        )
        productos = cursor.fetchall()
        conn.close()
        entries_stock = {}
        entries_precio = {}
        checks = {}
        last_categoria = None
        row_idx = 1
        for prod in productos:
            pid, nombre, stock, visible, precio, categoria = prod
            if categoria != last_categoria:
                tk.Label(frame, text=f"{categoria if categoria else 'Sin categoría'}", font=("Arial", 11, "bold"), fg="#1976d2").grid(row=row_idx, column=0, columnspan=5, sticky="w", pady=(10,2))
                row_idx += 1
                last_categoria = categoria
            tk.Label(frame, text=nombre, font=("Arial", 11)).grid(row=row_idx, column=0, sticky="w", padx=4)
            var_stock = tk.StringVar(value=str(stock))
            entry_stock = tk.Entry(frame, textvariable=var_stock, width=8, font=("Arial", 11))
            entry_stock.grid(row=row_idx, column=1, padx=4)
            entries_stock[pid] = var_stock
            var_precio = tk.StringVar(value=str(precio))
            entry_precio = tk.Entry(frame, textvariable=var_precio, width=8, font=("Arial", 11))
            entry_precio.grid(row=row_idx, column=2, padx=4)
            entries_precio[pid] = var_precio
            var_chk = tk.BooleanVar(value=bool(visible))
            chk = tk.Checkbutton(frame, variable=var_chk)
            chk.grid(row=row_idx, column=3)
            checks[pid] = var_chk
            row_idx += 1
        # Label info
        label_info = tk.Label(stock_win, text="Si el Stock es 999, no se descuenta al realizar una venta.", font=("Arial", 10), fg="#555")
        label_info.pack(pady=(0, 8))
        # Validación y guardado
        def guardar_stock():
            cambios = []
            for pid in entries_stock:
                try:
                    val = int(entries_stock[pid].get())
                    if val < 1:
                        raise ValueError
                except Exception:
                    messagebox.showerror("Stock", f"Stock inválido para el producto ID {pid}. Debe ser un número mayor a 0.")
                    return
                try:
                    precio_str = entries_precio[pid].get().replace(",", ".")
                    precio_val = float(precio_str)
                    if precio_val <= 0 or precio_val > 999999:
                        raise ValueError
                except Exception:
                    messagebox.showerror("Precio", f"Precio inválido para el producto ID {pid}.")
                    return
                visible = 1 if checks[pid].get() else 0
                cambios.append((val, visible, precio_val, pid))
            conn = get_connection()
            cursor = conn.cursor()
            for val, visible, precio, pid in cambios:
                cursor.execute(
                    "UPDATE products SET stock_actual=?, visible=?, precio_venta=? WHERE id=?",
                    (val, visible, precio, pid),
                )
            conn.commit()
            conn.close()
            messagebox.showinfo("Stock", "Stock y precios actualizados correctamente.")
            stock_win.destroy()
        btn_guardar = tk.Button(stock_win, text="Guardar Cambios", command=guardar_stock, bg="#388e3c", fg="white", font=("Arial", 12), width=18)
        btn_guardar.pack(pady=10)
        btn_cancelar = tk.Button(stock_win, text="Cancelar", command=stock_win.destroy, font=("Arial", 12), width=12)
        btn_cancelar.pack()

    def cerrar_caja_window(self):
        """Abre la vista de detalle/cierre para la caja abierta."""
        caja_id = getattr(self, 'caja_abierta_id', None)
        if not caja_id:
            messagebox.showerror("Cierre de caja", "No hay caja abierta actualmente.")
            return

        # Crear una nueva instancia de CajaListadoView especficamente para cerrar la caja
        try:
            from BuffetApp.caja_listado_view import CajaListadoView
        except Exception:
            from caja_listado_view import CajaListadoView
        self.ocultar_frames()

        # Vista temporal solo para el cierre. Guardarla en self.cajas_view
        # para que los mecanismos de ocultado/restaurado puedan gestionarla correctamente
        self.cajas_view = CajaListadoView(self.root, self.on_caja_cerrada)
        # mostrar detalle directamente
        self.cajas_view.ver_detalle(caja_id)
        self.cajas_view.pack(fill=tk.BOTH, expand=True)

    def vincular_venta_a_caja(self, venta_id):
        caja_id = getattr(self, 'caja_abierta_id', None)
        if not caja_id:
            return
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE ventas SET caja_id=? WHERE id=?", (caja_id, venta_id))
        conn.commit()
        conn.close()
    
    def abrir_caja_dialog(self):
        ahora = datetime.datetime.now()
        fecha = ahora.strftime("%Y-%m-%d")
        hora = ahora.strftime("%H:%M:%S")

        usuario = getattr(self, "usuario_logueado", None) or simpledialog.askstring("Abrir caja", "Usuario:")
        if not usuario: 
            return

        try:
            fondo_inicial = simpledialog.askfloat("Abrir caja", "Fondo inicial (efectivo):", minvalue=0.0)
            if fondo_inicial is None:
                return

            conn = get_connection(); c = conn.cursor()
            # Evitar duplicar caja abierta del mismo día (opcional)
            c.execute("SELECT id FROM caja_diaria WHERE fecha=? AND estado='abierta'", (fecha,))
            existe = c.fetchone()
            if existe:
                if not messagebox.askyesno("Abrir caja", "Ya hay una caja ABIERA hoy. ¿Abrir otra igualmente?"):
                    conn.close(); return

            codigo_caja = f"{usuario}_{fecha.replace('-', '')}_{hora.replace(':', '')}"
            c.execute("""
                INSERT INTO caja_diaria (codigo_caja, fecha, hora_apertura, usuario_apertura, fondo_inicial, estado,
                                        ingresos, retiros, total_ventas, total_efectivo_teorico,
                                        conteo_efectivo_final, diferencia, observaciones_apertura)
                VALUES (?, ?, ?, ?, ?, 'abierta', 0, 0, 0, 0, 0, 0, '')
            """, (codigo_caja, fecha, hora, usuario, float(fondo_inicial)))
            caja_id = c.lastrowid
            conn.commit(); conn.close()
            # Actualizar estado de la app y la UI
            self.caja_abierta_id = caja_id
            self.actualizar_menu_caja()
            if hasattr(self, 'menu_view'):
                try:
                    self.menu_view.actualizar_caja_info()
                    self.mostrar_pie_caja(self.menu_view)
                except Exception:
                    pass
            messagebox.showinfo("Abrir caja", f"Caja abierta correctamente (#{caja_id}).")
            try:
                if getattr(self, 'cajas_view', None):
                    self.cajas_view.cargar_cajas()
            except Exception:
                pass
        except Exception as e:
            messagebox.showerror("Abrir caja", f"No se pudo abrir la caja.\n\nDetalle: {e}")

    def _calc_total_ventas_por_fecha(self, fecha_yyyy_mm_dd):
        conn = get_connection(); c = conn.cursor()
        c.execute("""SELECT COALESCE(SUM(total_ticket),0)
                        FROM tickets
                        WHERE date(fecha_hora)=? AND status!='Anulado'""", (fecha_yyyy_mm_dd,))
        total = c.fetchone()[0] or 0
        conn.close()
        return float(total)               

    def cerrar_caja_dialog(self):
        # Toma la última caja ABIERA
        conn = get_connection(); c = conn.cursor()
        c.execute("""SELECT id, fecha, fondo_inicial, COALESCE(ingresos,0), COALESCE(retiros,0)
                    FROM caja_diaria WHERE estado='abierta'
                    ORDER BY fecha DESC, hora_apertura DESC LIMIT 1""")
        row = c.fetchone()
        if not row:
            conn.close()
            messagebox.showinfo("Cerrar caja", "No hay caja abierta.")
            return

        caja_id, fecha, fondo_inicial, ingresos, retiros = row
        conn.close()

        conteo_final = simpledialog.askfloat("Cerrar caja", "Conteo efectivo final (real):", minvalue=0.0)
        if conteo_final is None:
            return
        obs = simpledialog.askstring("Cerrar caja", "Observaciones de cierre (opcional):") or ""

        total_ventas = self._calc_total_ventas_por_fecha(fecha)
        teorico = float(fondo_inicial) + float(ingresos) - float(retiros) + float(total_ventas)
        diferencia = float(conteo_final) - float(teorico)

        try:
            ahora = datetime.datetime.now().strftime("%H:%M:%S")
            usuario_cierre = getattr(self, "usuario_logueado", "") or ""
            conn = get_connection(); c = conn.cursor()
            c.execute("""
                UPDATE caja_diaria
                SET estado='cerrada',
                    hora_cierre=?,
                    usuario_cierre=?,
                    total_ventas=?,
                    total_efectivo_teorico=?,
                    conteo_efectivo_final=?,
                    diferencia=?,
                    obs_cierre=?
                WHERE id=?
            """, (ahora, usuario_cierre, total_ventas, teorico, conteo_final, diferencia, obs, caja_id))
            conn.commit(); conn.close()
            messagebox.showinfo("Cerrar caja", f"Caja #{caja_id} cerrada.\nTeórico: ${teorico:.2f}\nReal: ${float(conteo_final):.2f}\nDif: ${diferencia:.2f}")
            try:
                self.cajas_view.imprimir_resumen_caja(caja_id)
            except Exception as e:
                messagebox.showerror("Imprimir", f"No se pudo imprimir el resumen.\n\n{e}")
            try:
                self.cajas_view.cargar_cajas()
            except Exception:
                pass
            # Actualizar estado global/UI tras cierre
            try:
                self.on_caja_cerrada()
            except Exception:
                try:
                    self.caja_abierta_id = None
                    self.actualizar_menu_caja()
                    if hasattr(self, 'menu_view'):
                        self.menu_view.actualizar_caja_info()
                        self.mostrar_pie_caja(self.menu_view)
                except Exception:
                    pass
        except Exception as e:
            messagebox.showerror("Cerrar caja", f"No se pudo cerrar la caja.\n\nDetalle: {e}")


# ----------- EJECUCIÓN -----------
if __name__ == "__main__":
    root = tk.Tk()
    app = BarCanchaApp(root)
    root.mainloop()

