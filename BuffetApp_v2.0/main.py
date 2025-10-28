import tkinter as tk
import datetime
from tkinter import simpledialog, messagebox

# Núcleo ligero importado al inicio; vistas pesadas se importan lazy dentro de métodos
from init_db import init_db, log_error
from app_config import get_config
from utils_paths import CONFIG_PATH, DB_PATH, resource_path
from db_utils import get_connection
import sqlite3
import uuid
from db_utils import get_current_pos_uuid



# ----------- INTERFAZ PRINCIPAL -----------
class BarCanchaApp:
    def imprimir_ticket(self, carrito):
        # TODO: Implementar lógica real de impresión de ticket si es necesario
        print("[DEBUG] imprimir_ticket llamado con carrito:", carrito)
        # Aquí puedes llamar a la lógica de impresión real si existe

    def marcar_tickets_impresos(self, ticket_ids):
        """Marca como 'Impreso' los tickets indicados.
        Acepta lista de IDs (int) y realiza un UPDATE en bloque.
        """
        try:
            if not ticket_ids:
                return
            ids = [int(x) for x in ticket_ids if str(x).isdigit()]
            if not ids:
                return
            placeholders = ",".join(["?"] * len(ids))
            with get_connection() as conn:
                cur = conn.cursor()
                cur.execute(f"UPDATE tickets SET status='Impreso' WHERE id IN ({placeholders})", ids)
                conn.commit()
        except Exception as e:
            # No bloquear el flujo por errores de marcado; loguear si hay logger
            try:
                fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                log_error(fecha_hora, 'marcar_tickets_impresos', f'Error: {e}')
            except Exception:
                pass

    def __init__(self, root):
        import json, os, threading
        self.root = root
        # Confirmación al cerrar la aplicación desde la 'X'
        try:
            self.root.protocol("WM_DELETE_WINDOW", self._confirm_exit)
        except Exception:
            pass
        try:
            from theme import APP_VERSION
            self.root.title(f"Sistema de Ventas - Bar de Cancha - {APP_VERSION}")
        except Exception:
            self.root.title("Sistema de Ventas - Bar de Cancha")
        # Establecer icono de la aplicación
        # Intentar varios iconos empaquetados
        try:
            # Preferir .ico (más liviano en arranque) y fallback a PNGs
            ico = resource_path("app.ico")
            if os.path.exists(ico):
                try:
                    self.root.iconbitmap(ico)
                except Exception:
                    pass
            if not os.path.exists(ico):
                for candidate in [
                    "cdm_mitre_white_app_256.png",
                    "cdm_mitre_white_app_2048.png",
                    "icon_salir.png"
                ]:
                    icon_path = resource_path(candidate)
                    if os.path.exists(icon_path):
                        self.root.iconphoto(True, tk.PhotoImage(file=icon_path))
                        break
        except Exception as e:
            print(f"No se pudo cargar un icono: {e}")

        # Inicializar DB y migraciones de POS/Settings (idempotente)
        # Si la DB ya existe, correr en segundo plano para no bloquear el arranque
        try:
            if not os.path.exists(DB_PATH):
                init_db()
            else:
                threading.Thread(target=init_db, daemon=True).start()
        except Exception:
            pass

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

        # Menú Principal (botón/entrada simple)
        self.menu_bar.add_command(label="Menú Principal", command=self.mostrar_menu_principal, state=tk.DISABLED)

        # Ventas
        self.menu_bar.add_command(label="Ventas", command=self.mostrar_ventas, state=tk.DISABLED)

        # Tickets (muestra tickets de la caja actual)
        self.menu_bar.add_command(label="Tickets", command=self.mostrar_tickets_hoy, state=tk.DISABLED)

        # Cajas -> Abrir / Cerrar / Listado
        self.caja_menu = tk.Menu(self.menu_bar, tearoff=0)
        self.caja_menu.add_command(label="Abrir Caja", command=self.abrir_caja_window)
        self.caja_menu.add_command(label="Cerrar Caja", command=self.cerrar_caja_window, state=tk.DISABLED)
        self.caja_menu.add_separator()
        self.caja_menu.add_command(label="Listado de Cajas", command=self.mostrar_cajas)
        self.menu_bar.add_cascade(label="Cajas", menu=self.caja_menu)

        # Reportes -> Historial de ventas
        self.reportes_menu = tk.Menu(self.menu_bar, tearoff=0)
        self.reportes_menu.add_command(label="Historial de ventas", command=self.mostrar_historial, state=tk.DISABLED)
        # Dashboard de Caja
        self.reportes_menu.add_command(label="Dashboard de Caja", command=self.mostrar_reportes_kpi, state=tk.DISABLED)
        self.menu_bar.add_cascade(label="Reportes", menu=self.reportes_menu)

        # Productos
        self.menu_bar.add_command(label="Productos", command=self.mostrar_productos, state=tk.DISABLED)

        # Configuración -> subitems
        from herramientas_view import HerramientasView  # mantener import, instanciar lazy
        self.herramientas_view = None
        def _hv():
            if self.herramientas_view is None:
                self.herramientas_view = HerramientasView(self)
            return self.herramientas_view

        self.configuracion_menu = tk.Menu(self.menu_bar, tearoff=0)
        self.configuracion_menu.add_command(label="Config. Impresora", command=lambda: _hv().abrir_impresora_window(self.root), state=tk.DISABLED)
        self.configuracion_menu.add_command(label="Backups y Sincronización", command=lambda: _hv().abrir_backup_window(self.root), state=tk.DISABLED)
        # Punto de venta
        self.pos_menu = tk.Menu(self.configuracion_menu, tearoff=0)
        self.pos_menu.add_command(label="Gestionar Punto de Venta", command=lambda: _hv().abrir_pos_window(self.root))
        self.configuracion_menu.add_cascade(label="Punto de venta", menu=self.pos_menu)
        # Usuarios dentro de Configuración
        self.configuracion_menu.add_command(label="Usuarios", command=self.mostrar_usuarios)
        self.menu_bar.add_cascade(label="Configuracion", menu=self.configuracion_menu)

        # Sesion -> Cerrar sesión
        self.sesion_menu = tk.Menu(self.menu_bar, tearoff=0)
        self.sesion_menu.add_command(label="Cerrar sesión", command=self.cerrar_sesion)
        self.menu_bar.add_cascade(label="Sesion", menu=self.sesion_menu)

        self.logged_user = None
        self.logged_role = None

        # Crear MenuView de forma perezosa luego del login para acelerar arranque
        self.menu_view = None

        # Vistas cargadas a demanda
        self.ventas_view = None
        self.historial_view = None
        self.cajas_view = None
        self.informe_view = None
        self.ajustes_view = None
        self.productos_view = None

        self.caja_abierta_id = None

        self.ocultar_frames()
        # Import tardío para reducir costo inicial
        from login_view import LoginView  # noqa: E402 (import tardío intencional)
        self.login_view = LoginView(self.root, self.on_login)
        self.login_view.pack(fill=tk.BOTH, expand=True)


    def _confirm_exit(self):
        """Pregunta confirmación antes de cerrar la aplicación."""
        try:
            if messagebox.askyesno("Salir", "¿Realmente desea cerrar la aplicación?"):
                self.root.destroy()
        except Exception:
            # Fallback: cerrar
            try:
                self.root.destroy()
            except Exception:
                pass


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
        # Historial es ahora un submenu dentro de Reportes
        try:
            self.reportes_menu.entryconfig("Historial de ventas", state=tk.NORMAL)
            self.reportes_menu.entryconfig("Dashboard de Caja", state=tk.NORMAL)
        except Exception:
            # mantenemos compatibilidad si no existe
            try:
                self.menu_bar.entryconfig("Historial ventas", state=tk.NORMAL)
            except Exception:
                pass
        self.menu_bar.entryconfig("Productos", state=tk.NORMAL)
        # Configuración (antes herramientas) -> habilitar subitems
        try:
            self.configuracion_menu.entryconfig("Config. Impresora", state=tk.NORMAL)
            self.configuracion_menu.entryconfig("Backups y Sincronización", state=tk.NORMAL)
        except Exception:
            pass
        # Usuarios: visibilidad se ajusta post-login según rol


    def actualizar_menu_caja(self):
        info = self.get_caja_info()
        abierta = bool(info)
        self.caja_menu.entryconfig("Abrir Caja",  state=(tk.DISABLED if abierta else tk.NORMAL))
        self.caja_menu.entryconfig("Cerrar Caja", state=(tk.NORMAL if abierta else tk.DISABLED))
        # Las operaciones de Ingreso/Retiro se gestionan desde Detalle/Cierre de Caja
        # por lo que ya no existen entradas dedicadas en este menú.
        self.menu_bar.entryconfig("Ventas", state=(tk.NORMAL if abierta else tk.DISABLED))
        # Tickets debe estar habilitado solo con caja abierta
        try:
            self.menu_bar.entryconfig("Tickets", state=(tk.NORMAL if abierta else tk.DISABLED))
        except Exception:
            pass
        # Reportes: permitir siempre Dashboard e Historial en el menú
        try:
            self.reportes_menu.entryconfig("Dashboard de Caja", state=tk.NORMAL)
        except Exception:
            pass

    # --- Reportes ---
    def mostrar_reportes_kpi(self):
        try:
            from reportes_kpi_view import ReportesKPIView
        except Exception as e:
            messagebox.showerror("Reportes", f"No se pudo abrir el Dashboard.\n{e}")
            return
        self.ocultar_frames()
        self.reportes_kpi_view = ReportesKPIView(self.root)
        self.reportes_kpi_view.pack(fill=tk.BOTH, expand=True)

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
        # if not self.informe_view:
        #     from informe_dia_view import InformeDiaView
        #     self.informe_view = InformeDiaView(self.root)
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
            # Siempre insertamos un nuevo movimiento; los triggers (init_db) actualizan caja_diaria
            try:
                cur.execute(
                    "INSERT INTO caja_movimiento (caja_id, tipo, monto, observacion) VALUES (?, ?, ?, ?)",
                    (caja_id, tipo.upper(), monto, obs)
                )
            except sqlite3.IntegrityError as e:
                conn.rollback(); conn.close()
                messagebox.showerror(
                    "Base de datos",
                    "No se pudo guardar el movimiento.\n\nTu base tiene una restricción única en (caja_id, tipo). Para permitir múltiples ingresos/retiros por caja, hay que quitarla."
                )
                return
            except Exception as e:
                conn.rollback(); conn.close()
                messagebox.showerror("Error", f"No se pudo guardar el movimiento: {e}")
                return
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

    
    def on_login(self, usuario, rol, disciplina=None):
        self.logged_user = usuario
        self.logged_role = rol
        # Si no se recibió disciplina, abrir modal para forzar la selección
        if not disciplina:
            disciplina = self._elegir_disciplina_modal()
        # Guardar disciplina seleccionada
        try:
            self.disciplina_actual = disciplina
        except Exception:
            self.disciplina_actual = None
        self.login_view.pack_forget()
        # Mostrar la barra de menú una vez autenticado el usuario
        self.root.config(menu=self.menu_bar)
        self.habilitar_menu()
        # Ajustar menú según rol
        try:
            if str(rol).lower() == 'administrador':
                self.menu_bar.entryconfig('Usuarios', state=tk.NORMAL)
            else:
                self.menu_bar.entryconfig('Usuarios', state=tk.DISABLED)
        except Exception:
            pass
        # Mostrar disciplina en el título si corresponde
        try:
            if disciplina:
                desc = None
                try:
                    with get_connection() as _conn:
                        _cur = _conn.cursor()
                        _cur.execute("SELECT descripcion FROM disciplinas WHERE codigo=?", (disciplina,))
                        rowd = _cur.fetchone()
                        desc = rowd[0] if rowd else None
                except Exception:
                    desc = None
                suffix = desc or disciplina
                if suffix:
                    self.root.title(f"Sistema de Ventas - Bar de Cancha - Disciplina: {suffix}")
        except Exception:
            pass

        conn = get_connection()
        cursor = conn.cursor()
        # Búsqueda básica para la lógica existente (pares id,codigo)
        cursor.execute("SELECT id, codigo_caja FROM caja_diaria WHERE estado='abierta'")
        rows = cursor.fetchall()
        # Búsqueda extendida con disciplina para admins
        try:
            cursor.execute(
                """
                SELECT cd.id, cd.codigo_caja, cd.disciplina, COALESCE(d.descripcion, cd.disciplina) AS disciplina_desc
                  FROM caja_diaria cd
                  LEFT JOIN disciplinas d ON d.codigo = cd.disciplina
                 WHERE cd.estado='abierta'
                """
            )
            rows_full = cursor.fetchall()
        except Exception:
            rows_full = []
        conn.close()

        # Regla: si inicia como Cajero y hay una o más cajas abiertas, NO permitir abrir otra;
        # pedir autenticación de Administrador para cerrar la(s) abierta(s)
        if str(rol).lower() == 'cajero' and rows:
            self.caja_abierta_id = None
            try:
                self._pedir_admin_para_cerrar_caja(rows)
            except Exception:
                # Si el flujo falla, informar y continuar sin caja abierta
                messagebox.showwarning("Caja", "Hay cajas abiertas. Un administrador debe cerrarlas para continuar.")
        else:
            # Si es administrador y hay exactamente una caja abierta con distinta disciplina a la seleccionada, avisar y redirigir a cierre
            try:
                if rows_full and len(rows_full) == 1 and str(rol).lower() == 'administrador':
                    caja_id, cod_caja, caja_disc, caja_disc_desc = rows_full[0]
                    if disciplina and caja_disc and str(caja_disc) != str(disciplina):
                        # Cambiar a la disciplina de la caja abierta y actualizar título
                        self.disciplina_actual = caja_disc
                        try:
                            suffix = caja_disc_desc or caja_disc
                            if suffix:
                                self.root.title(f"Sistema de Ventas - Bar de Cancha - Disciplina: {suffix}")
                        except Exception:
                            pass
                        # Setear caja abierta actual
                        self.caja_abierta_id = caja_id
                        # Modal informativa con acción de cierre
                        win = tk.Toplevel(self.root)
                        win.title("Caja abierta en otra disciplina")
                        win.transient(self.root)
                        win.grab_set()
                        # Centrar ventana en pantalla
                        try:
                            ancho, alto = 540, 260
                            sw = self.root.winfo_screenwidth(); sh = self.root.winfo_screenheight()
                            x = (sw - ancho) // 2; y = (sh - alto) // 2
                            win.geometry(f"{ancho}x{alto}+{x}+{y}")
                        except Exception:
                            pass
                        msg = (
                            "Se encontró una caja abierta en otra disciplina.\n\n"
                            f"Disciplina de la caja abierta: {caja_disc_desc or caja_disc}.\n\n"
                            "Se iniciará la sesión con esa disciplina.\n\n"
                            "Para continuar, cierre la caja abierta."
                        )
                        tk.Label(win, text=msg, font=("Arial", 11), justify="left", padx=12, pady=12).pack()
                        def _go_close():
                            try:
                                win.grab_release()
                            except Exception:
                                pass
                            win.destroy()
                            # Abrir ventana de Cerrar caja
                            self.cerrar_caja_window()
                        tk.Button(win, text="Cerrar caja", command=_go_close, width=16).pack(pady=(0,12))
                        # No continuar mostrando menú principal aquí; el flujo va a cierre
                        self.actualizar_menu_caja()
                        return
            except Exception:
                pass
            # Flujo estándar si no aplica la condición especial de admin
            if not rows:
                messagebox.showinfo("Caja", "No hay caja abierta. Abra una caja desde el menú Caja para habilitar ventas.")
                self.caja_abierta_id = None
            elif len(rows) == 1:
                self.caja_abierta_id = rows[0][0]
            else:
                self.resolver_cajas_abiertas(rows)

        self.actualizar_menu_caja()
        self.mostrar_menu_principal()

    def _elegir_disciplina_modal(self):
        # Cargar disciplinas
        try:
            with get_connection() as conn:
                cur = conn.cursor()
                cur.execute("SELECT codigo, COALESCE(descripcion, codigo) as desc FROM disciplinas ORDER BY desc, codigo")
                rows = cur.fetchall() or []
        except Exception:
            rows = []
        # Si no hay disciplinas, fallback
        if not rows:
            return 'BAR'
        # Construir modal bloqueante
        win = tk.Toplevel(self.root)
        win.title("Seleccione disciplina")
        win.transient(self.root)
        win.grab_set()
        try:
            win.protocol("WM_DELETE_WINDOW", lambda: None)  # Evitar cerrar sin seleccionar
        except Exception:
            pass
        # Hacer la ventana más alta para que no se oculte el botón Aceptar (y achicar 25% respecto a la versión previa)
        ancho, alto = 540, 450
        x = self.root.winfo_screenwidth() // 2 - ancho // 2
        y = self.root.winfo_screenheight() // 2 - alto // 2
        win.geometry(f"{ancho}x{alto}+{x}+{y}")
        try:
            win.minsize(480, 420)
        except Exception:
            pass
        tk.Label(win, text="Debe elegir una disciplina para continuar.", font=("Arial", 12)).pack(pady=(14, 8))
        map_desc_to_code = {str(d or c): str(c) for c, d in rows}
        descs = list(map_desc_to_code.keys())
        # Radio buttons de disciplinas (por defecto "BAR" si existe)
        # Buscar una opción cuyo código o descripción sea "BAR"
        default_desc = None
        for c, d in rows:
            c_str = str(c or '').strip()
            d_str = str(d or c).strip()
            if c_str.upper() == 'BAR' or d_str.upper() == 'BAR':
                default_desc = d_str
                break
        if not default_desc and descs:
            default_desc = descs[0]
        var_desc = tk.StringVar(value=default_desc or '')
        radios_container = tk.Frame(win)
        radios_container.pack(pady=6)
        try:
            for desc in descs:
                tk.Radiobutton(radios_container, text=desc, variable=var_desc, value=desc, anchor='w', padx=8).pack(fill='x', anchor='w')
        except Exception:
            pass
        seleccionado = {'code': None}
        def confirmar():
            d = (var_desc.get() or '').strip()
            code = map_desc_to_code.get(d)
            if not code:
                messagebox.showwarning('Disciplina', 'Seleccione una disciplina.'); return
            seleccionado['code'] = code
            try:
                win.grab_release()
            except Exception:
                pass
            win.destroy()
        tk.Button(win, text="Aceptar", command=confirmar, bg="#1976d2", fg="white", width=12).pack(pady=12)
        self.root.wait_window(win)
        # Si por alguna razón no se seleccionó, forzar primera
        return seleccionado['code'] or map_desc_to_code.get(descs[0]) or 'BAR'

    def cerrar_sesion(self):
        """Cierra la sesión actual y vuelve a la pantalla de login"""
        try:
            # Limpiar estado de usuario y caja
            self.logged_user = None
            self.logged_role = None
            try:
                self.disciplina_actual = None
            except Exception:
                pass
            self.caja_abierta_id = None
            # Ocultar todas las vistas y quitar menú
            self.ocultar_frames()
            try:
                self.root.config(menu=None)
            except Exception:
                pass
            try:
                # Fallback adicional para asegurar que la barra desaparezca en Windows
                self.root['menu'] = None
            except Exception:
                pass
            try:
                # Algunos entornos requieren cadena vacía en lugar de None
                self.root.config(menu='')
            except Exception:
                pass
            try:
                self.root['menu'] = ''
            except Exception:
                pass
            # Volver a mostrar login
            try:
                self.login_view.destroy()
            except Exception:
                pass
            from login_view import LoginView
            self.login_view = LoginView(self.root, self.on_login)
            self.login_view.pack(fill=tk.BOTH, expand=True)
            # Restaurar título básico (sin disciplina)
            try:
                from theme import APP_VERSION
                self.root.title(f"Sistema de Ventas - Bar de Cancha - {APP_VERSION}")
            except Exception:
                try:
                    self.root.title("Sistema de Ventas - Bar de Cancha")
                except Exception:
                    pass
        except Exception as e:
            messagebox.showerror("Sesión", f"No se pudo cerrar sesión. {e}")

    def _pedir_admin_para_cerrar_caja(self, open_rows):
        """Muestra un modal para autenticación de administrador y, si es correcta,
        abre la vista de cierre para la(s) caja(s) abierta(s).

        open_rows: lista de (id, codigo_caja) para cajas con estado='abierta'
        """
        win = tk.Toplevel(self.root)
        win.title("Cierre requerido por Administrador")
        ancho, alto = 420, 220
        x = self.root.winfo_screenwidth() // 2 - ancho // 2
        y = self.root.winfo_screenheight() // 2 - alto // 2
        win.geometry(f"{ancho}x{alto}+{x}+{y}")
        win.transient(self.root)
        win.grab_set()

        tk.Label(win, text="Hay cajas abiertas. Se requiere un Administrador para cerrarlas.", font=("Arial", 11)).pack(pady=(12, 8))
        form = tk.Frame(win)
        form.pack(pady=6)
        tk.Label(form, text="Usuario admin:").grid(row=0, column=0, sticky='w')
        entry_user = tk.Entry(form)
        entry_user.grid(row=1, column=0, pady=(0,8))
        tk.Label(form, text="Contraseña:").grid(row=2, column=0, sticky='w')
        entry_pass = tk.Entry(form, show='*')
        entry_pass.grid(row=3, column=0)

        btns = tk.Frame(win)
        btns.pack(pady=10)

        def autenticar_y_abrir():
            usuario_admin = entry_user.get().strip()
            pass_admin = entry_pass.get().strip()
            if not usuario_admin or not pass_admin:
                messagebox.showwarning('Administrador', 'Ingrese usuario y contraseña.'); return
            # validar credenciales con rol Administrador
            try:
                conn = get_connection(); cur = conn.cursor()
                cur.execute("SELECT rol FROM usuarios WHERE usuario=? AND password=?", (usuario_admin, pass_admin))
                row = cur.fetchone(); conn.close()
            except Exception as e:
                messagebox.showerror('Administrador', f'Error de base de datos: {e}'); return
            if not row or str(row[0]).lower() != 'administrador':
                messagebox.showerror('Administrador', 'Credenciales inválidas o sin rol Administrador.'); return
            # Autenticación OK: abrir UI de cierre con usuario del sistema = admin temporal
            win.destroy()
            # Guardar sesión original del cajero
            orig_user = self.logged_user; orig_role = self.logged_role
            try:
                # Elevar temporalmente a admin para que el cierre registre usuario_cierre correcto
                self.logged_user = usuario_admin
                self.logged_role = 'Administrador'
                # Si hay una sola caja abierta, abrir su detalle directamente; si hay varias, resolver selección
                if len(open_rows) == 1:
                    self.abrir_cierre_para_caja(open_rows[0][0], restore_session=(orig_user, orig_role))
                else:
                    # mostrar selector; al finalizar (on_close) restaurar sesión
                    self._abrir_selector_cajas_para_admin(open_rows, restore_session=(orig_user, orig_role))
            except Exception:
                # ante cualquier problema, restaurar sesión original
                self.logged_user = orig_user; self.logged_role = orig_role

        tk.Button(btns, text="Autenticar y cerrar", command=autenticar_y_abrir, bg="#1976d2", fg="white").pack(side=tk.LEFT, padx=6)
        tk.Button(btns, text="Cancelar", command=win.destroy).pack(side=tk.LEFT, padx=6)

    def _abrir_selector_cajas_para_admin(self, rows, restore_session=None):
        """Permite al admin seleccionar una de las cajas abiertas para ver/cerrar su detalle."""
        # Reutilizar la ventana existente de resolución pero forzando el flujo a abrir detalle en lugar de "usar caja"
        sel_win = tk.Toplevel(self.root)
        sel_win.title("Cajas abiertas")
        tk.Label(sel_win, text="Seleccione la caja a cerrar:" ).pack(padx=10, pady=5)
        lista = tk.Listbox(sel_win, width=48)
        lista.pack(padx=10, pady=5)
        for cid, codigo in rows:
            lista.insert(tk.END, f"{codigo} (id {cid})")

        def abrir_detalle():
            sel = lista.curselection()
            if not sel:
                messagebox.showwarning("Caja", "Debe seleccionar una caja.")
                return
            caja_id = rows[sel[0]][0]
            sel_win.destroy()
            self.abrir_cierre_para_caja(caja_id, restore_session=restore_session)

        tk.Button(sel_win, text="Abrir detalle", command=abrir_detalle).pack(pady=10)
        sel_win.grab_set()
        self.root.wait_window(sel_win)

    def abrir_cierre_para_caja(self, caja_id, restore_session=None):
        """Abre la vista de detalle/cierre para la caja indicada.
        Si restore_session es una tupla (user, role), se restaurará al cerrar la caja o al volver de la vista.
        """
        try:
            from caja_listado_view import CajaListadoView
        except Exception:
            from caja_listado_view import CajaListadoView
        self.ocultar_frames()
        # Vista temporal para el cierre
        self.cajas_view = CajaListadoView(self.root, self.on_caja_cerrada)
        # Propagar usuario/rol actuales (admin temporal)
        try:
            self.cajas_view.logged_user = getattr(self, 'logged_user', None)
            self.cajas_view.logged_role = getattr(self, 'logged_role', None)
        except Exception:
            pass
        # Envolver callback para restaurar sesión si corresponde
        if restore_session is not None:
            orig_user, orig_role = restore_session
            def _restore_and_callback(*args, **kwargs):
                try:
                    self.logged_user = orig_user
                    self.logged_role = orig_role
                except Exception:
                    pass
                try:
                    self.on_caja_cerrada(*args, **kwargs)
                except Exception:
                    pass
            try:
                self.cajas_view.on_caja_cerrada = _restore_and_callback
            except Exception:
                pass
        # Mostrar detalle directamente
        try:
            self.cajas_view.ver_detalle(caja_id)
        except Exception:
            pass
        self.cajas_view.pack(fill=tk.BOTH, expand=True)

    # abrir_backup_confirm eliminado: backup se gestiona desde Herramientas → Backups y Sincronización

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
        if getattr(self, 'menu_view', None):
            try:
                self.menu_view.pack_forget()
            except Exception:
                pass
        if self.ventas_view:
            self.ventas_view.pack_forget()
        if self.historial_view:
            self.historial_view.pack_forget()
        # Ocultar vista de tickets de caja actual si existe
        if getattr(self, 'tickets_caja_view', None):
            try:
                self.tickets_caja_view.pack_forget()
            except Exception:
                pass
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
        # Ocultar reportes si están visibles
        if getattr(self, 'reportes_kpi_view', None):
            try:
                self.reportes_kpi_view.pack_forget()
            except Exception:
                pass
        if getattr(self, 'reportes_tabular_view', None):
            try:
                self.reportes_tabular_view.pack_forget()
            except Exception:
                pass
        # Asegurar ocultar Usuarios para evitar superposición de pantallas
        if getattr(self, 'usuarios_view', None):
            try:
                self.usuarios_view.pack_forget()
            except Exception:
                pass
        if self.ajustes_view:
            try:
                self.ajustes_view.pack_forget()
            except Exception:
                pass

    def refrescar_ventas_productos(self):
        try:
            if getattr(self, 'ventas_view', None) and hasattr(self.ventas_view, 'recargar_productos'):
                self.ventas_view.recargar_productos()
        except Exception:
            pass

    def mostrar_cajas(self):
        if not self.cajas_view:
            from caja_listado_view import CajaListadoView  # lazy import
            self.cajas_view = CajaListadoView(self.root, self.on_caja_cerrada)
            try:
                self.cajas_view.logged_user = getattr(self, 'logged_user', None)
                self.cajas_view.logged_role = getattr(self, 'logged_role', None)
            except Exception:
                pass
        self.ocultar_frames()
        self.cajas_view.pack(fill=tk.BOTH, expand=True)
        self.mostrar_pie_caja(self.cajas_view)  # si tenés este pie en otras vistas

    def mostrar_menu_principal(self):
        # Crear MenuView solo cuando sea necesario (post-login)
        if self.menu_view is None:
            from menu_view import MenuView  # import tardío
            self.menu_view = MenuView(
                self.root,
                get_caja_info=self.get_caja_info,
                on_cerrar_caja=self.cerrar_caja_window,
                on_ver_cierre=self.ver_cierre_caja,
                on_abrir_caja=self.abrir_caja_window,
                controller=self,
            )
        self.ocultar_frames()
        try:
            self.menu_view.actualizar_caja_info()
        except Exception:
            pass
        self.menu_view.pack(fill=tk.BOTH, expand=True)
        self.mostrar_pie_caja(self.menu_view)

    def mostrar_usuarios(self):
        # Solo admin
        if str(getattr(self, 'logged_role', '')).lower() != 'administrador':
            messagebox.showwarning('Usuarios', 'No tiene permisos para acceder a Usuarios.')
            return
        try:
            self.ocultar_frames()
            from usuarios_view import UsuariosView
            self.usuarios_view = getattr(self, 'usuarios_view', None)
            if self.usuarios_view is None:
                self.usuarios_view = UsuariosView(self.root)
            self.usuarios_view.pack(fill=tk.BOTH, expand=True)
        except Exception as e:
            messagebox.showerror('Usuarios', f'No se pudo abrir Usuarios.\n{e}')

    def mostrar_pie_caja(self, parent):
        # Elimina barras previas si existen
        for widget in getattr(parent, '_pie_caja_widgets', []):
            widget.destroy()
        info = self.get_caja_info()
        if info:
            # Calcular ventas actuales de la caja abierta
            total_ventas = 0
            try:
                with get_connection() as conn:
                    cur = conn.cursor()
                    cur.execute(
                        """
                        SELECT COALESCE(SUM(t.total_ticket),0)
                          FROM tickets t JOIN ventas v ON v.id=t.venta_id
                         WHERE v.caja_id=? AND t.status!='Anulado'
                        """,
                        (getattr(self, 'caja_abierta_id', None),)
                    )
                    total_ventas = cur.fetchone()[0] or 0
            except Exception:
                total_ventas = 0
            try:
                from theme import format_currency
                ventas_txt = format_currency(total_ventas)
            except Exception:
                ventas_txt = f"$ {total_ventas:,.2f}"
            texto = f"🟢 Caja {info['codigo']} abierta - Apertura: {info['hora_apertura']}  •  Ventas al momento: {ventas_txt}"
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
            ancho, alto = 540, 600
            x = self.root.winfo_screenwidth() // 2 - ancho // 2
            y = self.root.winfo_screenheight() // 2 - alto // 2
            self.root.geometry(f"{ancho}x{alto}+{x}+{y}")
            return
        if not self.ventas_view:
            from ventas_view_new import VentasViewNew  # lazy import
            self.ventas_view = VentasViewNew(
                self.root,
                cobrar_callback=self.on_cobrar,
                imprimir_ticket_callback=self.imprimir_ticket,
                on_tickets_impresos=self.marcar_tickets_impresos,
                controller=self
            )
        # Siempre refrescar productos/stock/precios al entrar a Ventas
        try:
            if hasattr(self.ventas_view, 'recargar_productos'):
                self.ventas_view.recargar_productos()
        except Exception:
            pass
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
                   cd.usuario_apertura, cd.fecha, cd.hora_apertura, cd.fondo_inicial, cd.estado, COALESCE(cd.descripcion_evento, '')
              FROM caja_diaria cd
              LEFT JOIN disciplinas d ON d.codigo = cd.disciplina
             WHERE cd.id=?
            """,
            (caja_id,),
        )
        info = cursor.fetchone()
        if info:
            codigo_caja, disciplina, usuario_apertura, fecha, hora_apertura, fondo_inicial, estado, descripcion_evento = info
        else:
            codigo_caja = disciplina = usuario_apertura = fecha = hora_apertura = estado = ''
            fondo_inicial = 0
            descripcion_evento = ''

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
            'descripcion_evento': descripcion_evento,
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
            from historial_view import HistorialView  # lazy import
            self.historial_view = HistorialView(self.root)
            try:
                self.historial_view.logged_user = getattr(self, 'logged_user', None)
                self.historial_view.logged_role = getattr(self, 'logged_role', None)
            except Exception:
                pass
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

    def mostrar_tickets_hoy(self):
        # Mostrar la nueva vista filtrada sólo por la caja abierta
        caja_id = getattr(self, 'caja_abierta_id', None)
        if not caja_id:
            try:
                messagebox.showinfo("Tickets", "No hay caja abierta.")
            except Exception:
                pass
            return
        try:
            from TicketCajaActual_view import TicketCajaActualView
        except Exception:
            from TicketCajaActual_view import TicketCajaActualView
        self.ocultar_frames()
        self.tickets_caja_view = TicketCajaActualView(self.root, controller=self)
        self.tickets_caja_view.pack(fill=tk.BOTH, expand=True)
        self.mostrar_pie_caja(self.tickets_caja_view)

    def mostrar_reportes(self):
        # Ventana temporal de Reportes (placeholder con accesos)
        win = tk.Toplevel(self.root)
        win.title("Reportes")
        ancho, alto = 520, 420
        x = self.root.winfo_screenwidth() // 2 - ancho // 2
        y = self.root.winfo_screenheight() // 2 - alto // 2
        win.geometry(f"{ancho}x{alto}+{x}+{y}")
        tk.Label(win, text="Reportes", font=("Arial", 16, "bold")).pack(pady=12)
        tk.Label(win, text="Próximamente: filtros por rango de fechas, disciplina, método de pago, categoría y producto.", wraplength=480, justify="left").pack(pady=(0,10))
        frame = tk.Frame(win)
        frame.pack(pady=8)
        tk.Button(frame, text="Ventas por fecha", width=22, state=tk.DISABLED).grid(row=0, column=0, padx=6, pady=6)
        tk.Button(frame, text="Por disciplina", width=22, state=tk.DISABLED).grid(row=0, column=1, padx=6, pady=6)
        tk.Button(frame, text="Por producto", width=22, state=tk.DISABLED).grid(row=1, column=0, padx=6, pady=6)
        tk.Button(frame, text="Exportar (CSV/Excel)", width=22, state=tk.DISABLED).grid(row=1, column=1, padx=6, pady=6)
        tk.Button(win, text="Cerrar", command=win.destroy, width=14).pack(pady=10)

    def mostrar_configuracion(self):
        # Ventana con accesos a impresora, backups/sync y POS
        win = tk.Toplevel(self.root)
        win.title("Configuración")
        ancho, alto = 520, 360
        x = self.root.winfo_screenwidth() // 2 - ancho // 2
        y = self.root.winfo_screenheight() // 2 - alto // 2
        win.geometry(f"{ancho}x{alto}+{x}+{y}")
        tk.Label(win, text="Configuración", font=("Arial", 16, "bold")).pack(pady=12)
        btns = tk.Frame(win)
        btns.pack(pady=8)
        # Obtener herramientas view (crear si no existe)
        try:
            if getattr(self, 'herramientas_view', None) is None:
                from herramientas_view import HerramientasView
                self.herramientas_view = HerramientasView(self)
            hv = self.herramientas_view
        except Exception:
            hv = None
        tk.Button(btns, text="Config. Impresora", width=24, command=(lambda: hv.abrir_impresora_window(self.root) if hv else None)).grid(row=0, column=0, padx=6, pady=6)
        tk.Button(btns, text="Backups y Sincronización", width=24, command=(lambda: hv.abrir_backup_window(self.root) if hv else None)).grid(row=0, column=1, padx=6, pady=6)
        tk.Button(btns, text="Punto de Venta", width=24, command=(lambda: hv.abrir_pos_window(self.root) if hv else None)).grid(row=1, column=0, padx=6, pady=6)
        # Usuarios solo visible para admin
        if str(getattr(self, 'logged_role', '')).lower() == 'administrador':
            tk.Button(btns, text="Usuarios", width=24, command=self.mostrar_usuarios).grid(row=1, column=1, padx=6, pady=6)
        tk.Button(win, text="Cerrar", command=win.destroy, width=14).pack(pady=10)

    def mostrar_productos(self):
        self.ocultar_frames()
        if not self.productos_view:
            from productos_view import ProductosView  # lazy import
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
            # Obtener datos necesarios de products: codigo_producto, categoria_id, stock_actual, contabiliza_stock
            try:
                cursor.execute(
                    f"SELECT id, codigo_producto, categoria_id, stock_actual, COALESCE(contabiliza_stock,1) FROM products WHERE id IN ({','.join('?' for _ in prod_ids)})",
                    prod_ids,
                )
                prod_rows = cursor.fetchall()
                prod_info = {r[0]: {'codigo': r[1], 'categoria': r[2], 'stock': r[3], 'contabiliza': int(r[4])} for r in prod_rows}
            except Exception:
                cursor.execute(
                    f"SELECT id, codigo_producto, categoria_id, stock_actual FROM products WHERE id IN ({','.join('?' for _ in prod_ids)})",
                    prod_ids,
                )
                prod_rows = cursor.fetchall()
                prod_info = {r[0]: {'codigo': r[1], 'categoria': r[2], 'stock': r[3], 'contabiliza': 1} for r in prod_rows}

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
                        # Actualizar stock sólo si contabiliza_stock=1
                        try:
                            if int(info.get('contabiliza', 1)) == 1:
                                cursor.execute("UPDATE products SET stock_actual = stock_actual - 1 WHERE id = ?", (prod_id,))
                                stock_actual = (stock_actual - 1) if stock_actual is not None else stock_actual
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
            # Refrescar pie global con ventas al momento
            try:
                # Actualizar pie en la vista actual si existe
                current_parent = None
                if self.ventas_view and self.ventas_view.winfo_manager():
                    current_parent = self.ventas_view
                elif self.menu_view and self.menu_view.winfo_manager():
                    current_parent = self.menu_view
                elif self.cajas_view and self.cajas_view.winfo_manager():
                    current_parent = self.cajas_view
                if current_parent is not None:
                    self.mostrar_pie_caja(current_parent)
            except Exception:
                pass
            return {'venta_id': venta_id, 'tickets': tickets_info}
        except Exception as e:
            messagebox.showerror("Error al guardar venta", str(e))

    
    def abrir_caja_window(self):
        import datetime
        from tkinter import ttk
        # Si es cajero y ya hay una caja abierta en el sistema, forzar flujo de admin
        try:
            if str(getattr(self, 'logged_role', '')).lower() == 'cajero':
                with get_connection() as _conn:
                    _cur = _conn.cursor()
                    _cur.execute("SELECT id, codigo_caja FROM caja_diaria WHERE estado='abierta'")
                    _rows = _cur.fetchall()
                if _rows:
                    messagebox.showwarning('Caja', 'Ya existe una caja abierta. Un administrador debe cerrarla para abrir una nueva.')
                    try:
                        self._pedir_admin_para_cerrar_caja(_rows)
                    except Exception:
                        pass
                    return
        except Exception:
            pass
        win = tk.Toplevel(self.root)
        win.title("Apertura de Caja")
        ancho = 370
        alto = 620  # Más alto para mostrar todo el contenido y botones
        x = win.winfo_screenwidth() // 2 - ancho // 2
        y = win.winfo_screenheight() // 2 - alto // 2
        win.geometry(f"{ancho}x{alto}+{x}+{y}")
        win.transient(self.root)
        win.grab_set()
        tk.Label(win, text="Cajero apertura:", font=("Arial", 12)).pack(pady=6)

        def _limit_entry(max_len):
            return (win.register(lambda P: len(P) <= max_len), "%P")

        entry_usuario = tk.Entry(
            win,
            font=("Arial", 12),
            validate="key",
            validatecommand=_limit_entry(10),
        )
        # Este campo representa el nombre de la persona que oficia de cajero al abrir
        # No se autocompleta con el usuario del sistema para permitir ingresar el nombre del cajero humano.
        entry_usuario.insert(0, "")
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
        # La disciplina se tomará del login (self.disciplina_actual); no se muestra selector aquí
        # Selector de Punto de venta
        tk.Label(win, text="Punto de venta:", font=("Arial", 12)).pack(pady=6)
        try:
            conn_cj = get_connection(); cur_cj = conn_cj.cursor()
            cur_cj.execute("SELECT id, descripcion, prefijo, predeterminada FROM pos_cajas WHERE activo=1 ORDER BY id")
            _pos_cajas_rows = cur_cj.fetchall() or []
            conn_cj.close()
        except Exception:
            _pos_cajas_rows = []
        caja_items = [f"{d} ({p})" for (_id, d, p, _pred) in _pos_cajas_rows] or ["Caja1 (Caj01)"]
        default_idx = 0
        for idx, (_id, _d, _p, _pred) in enumerate(_pos_cajas_rows):
            if int(_pred or 0) == 1:
                default_idx = idx; break
        var_caja_tpl = tk.StringVar(value=(caja_items[default_idx] if caja_items else ""))
        ttk.Combobox(win, values=caja_items, textvariable=var_caja_tpl, state="readonly", width=18).pack(pady=2)
        # Descripción del evento (nuevo campo)
        tk.Label(win, text="Descripción del evento:", font=("Arial", 12)).pack(pady=(8,4))
        entry_evento = tk.Entry(win, font=("Arial", 12))
        entry_evento.pack(pady=(0, 6))
        # Limitar a 100 caracteres
        def _limit_evento(P):
            return len(P) <= 100
        entry_evento.configure(validate="key", validatecommand=(win.register(_limit_evento), "%P"))

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
            cajero_apertura = entry_usuario.get().strip()
            usuario_apertura = (self.logged_user or "")
            fondo = entry_fondo.get().strip().replace(",", ".")
            observaciones = entry_obs.get("1.0", tk.END).strip()
            descripcion_evento = entry_evento.get().strip()
            # Disciplina definida por el login
            disciplina = getattr(self, 'disciplina_actual', None)
            if not disciplina:
                # Fallback: primer código o 'BAR'
                try:
                    cur_tmp = get_connection().cursor()
                    cur_tmp.execute("SELECT codigo FROM disciplinas ORDER BY codigo LIMIT 1")
                    rowd = cur_tmp.fetchone()
                    disciplina = rowd[0] if rowd and rowd[0] else 'BAR'
                except Exception:
                    disciplina = 'BAR'
            # Resolver plantilla de caja
            try:
                sel_txt = var_caja_tpl.get()
                sel_idx = caja_items.index(sel_txt)
            except Exception:
                sel_idx = default_idx
            sel_row = _pos_cajas_rows[sel_idx] if _pos_cajas_rows else (None, 'Caja1', 'Caj01', 1)
            pos_caja_id = sel_row[0]
            caja_prefijo = sel_row[2]
            if not cajero_apertura or not fondo:
                messagebox.showwarning("Datos incompletos", "Complete el Cajero de apertura y el fondo inicial.")
                return
            if len(cajero_apertura) > 10:
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
            if len(descripcion_evento) > 100:
                messagebox.showwarning("Descripción del evento", "Máximo 100 caracteres.")
                return
            conn = get_connection()
            cursor = conn.cursor()
            # Generar código por prefijo + fecha + disciplina con sufijo incremental
            base_code = f"{caja_prefijo}-{fecha.replace('-', '')}-{disciplina}"
            cursor.execute(
                "SELECT codigo_caja FROM caja_diaria WHERE fecha=? AND disciplina=? AND (caja_prefijo=? OR codigo_caja LIKE ?)",
                (fecha, disciplina, caja_prefijo, base_code + '%')
            )
            existentes = [r[0] for r in cursor.fetchall()] or []
            import re as _re
            used = set()
            for cod in existentes:
                if cod == base_code:
                    used.add(1)
                else:
                    m = _re.match(_re.escape(base_code) + r"-(\d+)$", str(cod))
                    if m:
                        try:
                            used.add(int(m.group(1)))
                        except Exception:
                            pass
            codigo_caja = base_code if not used else f"{base_code}-{max(used)+1}"
            # Generar identificadores
            caja_uuid = str(uuid.uuid4())
            pos_uuid = get_current_pos_uuid()
            # Intentar insertar con pos_uuid y caja_uuid si las columnas existen (migración las crea)
            try:
                cursor.execute(
                    "INSERT INTO caja_diaria (codigo_caja, disciplina, fecha, usuario_apertura, cajero_apertura, hora_apertura, apertura_dt, fondo_inicial, descripcion_evento, observaciones_apertura, estado, pos_uuid, caja_uuid, pos_caja_id, caja_prefijo) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'abierta', ?, ?, ?, ?)",
                    (codigo_caja, disciplina, fecha, usuario_apertura, cajero_apertura, hora_apertura, f"{fecha} {hora_apertura}", fondo_val, descripcion_evento, observaciones, pos_uuid, caja_uuid, pos_caja_id, caja_prefijo)
                )
            except Exception:
                # Fallback: columnas no existen en bases viejas
                try:
                    cursor.execute(
                        "ALTER TABLE caja_diaria ADD COLUMN descripcion_evento TEXT"
                    )
                except Exception:
                    pass
                # Intentar agregar cajero_apertura si existe; si no, omitir y luego actualizar
                try:
                    cursor.execute(
                        "INSERT INTO caja_diaria (codigo_caja, disciplina, fecha, usuario_apertura, cajero_apertura, hora_apertura, apertura_dt, fondo_inicial, descripcion_evento, observaciones_apertura, estado) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'abierta')",
                        (codigo_caja, disciplina, fecha, usuario_apertura, cajero_apertura, hora_apertura, f"{fecha} {hora_apertura}", fondo_val, descripcion_evento, observaciones)
                    )
                except Exception:
                    cursor.execute(
                        "INSERT INTO caja_diaria (codigo_caja, disciplina, fecha, usuario_apertura, hora_apertura, apertura_dt, fondo_inicial, descripcion_evento, observaciones_apertura, estado) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'abierta')",
                        (codigo_caja, disciplina, fecha, usuario_apertura, hora_apertura, f"{fecha} {hora_apertura}", fondo_val, descripcion_evento, observaciones)
                    )
            caja_id = cursor.lastrowid
            conn.commit()
            conn.close()
            self.caja_abierta_id = caja_id
            self.actualizar_menu_caja()
            self.menu_view.actualizar_caja_info()
            self.mostrar_pie_caja(self.menu_view)
            win.destroy()
            # Ir a Ventas y abrir la ventana de stock/precios en modo modal
            try:
                self.mostrar_ventas()
            except Exception:
                pass
            self.abrir_stock_window()

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
        header = tk.Frame(stock_win)
        header.pack(fill=tk.X, pady=10)
        tk.Label(header, text="Agregar stock/precios", font=("Arial", 15, "bold")).pack(side=tk.LEFT, padx=(0,8))
        
        def _refrescar_grid():
            # Limpiar filas anteriores (mantener encabezados en row 0)
            for w in frame.grid_slaves():
                info = w.grid_info()
                try:
                    if int(info.get('row', 0)) > 0:
                        w.destroy()
                except Exception:
                    pass
            # Obtener productos nuevamente
            conn = get_connection(); cursor = conn.cursor()
            try:
                cursor.execute(
                    "SELECT p.id, p.nombre, p.stock_actual, p.visible, p.precio_venta, COALESCE(p.contabiliza_stock,1), c.descripcion as categoria FROM products p LEFT JOIN Categoria_Producto c ON p.categoria_id = c.id ORDER BY c.descripcion, p.nombre"
                )
            except Exception:
                cursor.execute(
                    "SELECT p.id, p.nombre, p.stock_actual, p.visible, p.precio_venta, 1 as contabiliza_stock, c.descripcion as categoria FROM products p LEFT JOIN Categoria_Producto c ON p.categoria_id = c.id ORDER BY c.descripcion, p.nombre"
                )
            productos2 = cursor.fetchall(); conn.close()
            nonlocal_entries_stock.clear(); nonlocal_entries_precio.clear(); nonlocal_checks.clear(); nonlocal_checks_contab.clear()
            last_categoria = None; row_idx = 1
            for prod in productos2:
                pid, nombre, stock, visible, precio, contabiliza, categoria = prod
                if categoria != last_categoria:
                    tk.Label(frame, text=f"{categoria if categoria else 'Sin categoría'}", font=("Arial", 11, "bold"), fg="#1976d2").grid(row=row_idx, column=0, columnspan=6, sticky="w", pady=(10,2))
                    row_idx += 1
                    last_categoria = categoria
                tk.Label(frame, text=nombre, font=("Arial", 11)).grid(row=row_idx, column=0, sticky="w", padx=4)
                var_stock = tk.StringVar(value=str(stock))
                entry_stock = tk.Entry(frame, textvariable=var_stock, width=8, font=("Arial", 11))
                entry_stock.grid(row=row_idx, column=1, padx=4)
                nonlocal_entries_stock[pid] = var_stock
                var_precio = tk.StringVar(value=str(precio))
                entry_precio = tk.Entry(frame, textvariable=var_precio, width=8, font=("Arial", 11))
                entry_precio.grid(row=row_idx, column=2, padx=4)
                nonlocal_entries_precio[pid] = var_precio
                # Ocultar: True => oculto (visible=0). Usar checkbox sencillo.
                var_ocultar = tk.BooleanVar(value=(not bool(visible)))
                tk.Checkbutton(frame, variable=var_ocultar).grid(row=row_idx, column=3)
                nonlocal_checks[pid] = var_ocultar
                var_ct = tk.BooleanVar(value=bool(contabiliza))
                # Toggle habilitación del campo Stock según "Contabilizar Stock"
                def _make_toggle(e_widget, v_stock, v_ct):
                    def _t():
                        try:
                            if v_ct.get():
                                e_widget.config(state='normal')
                            else:
                                v_stock.set('0')
                                e_widget.config(state='disabled')
                        except Exception:
                            pass
                    return _t
                ct_btn = tk.Checkbutton(frame, variable=var_ct, command=_make_toggle(entry_stock, var_stock, var_ct))
                ct_btn.grid(row=row_idx, column=4)
                # Estado inicial del stock según contabiliza
                try:
                    if not bool(contabiliza):
                        var_stock.set('0'); entry_stock.config(state='disabled')
                except Exception:
                    pass
                nonlocal_checks_contab[pid] = var_ct
                row_idx += 1

        def _abrir_alta_desde_stock():
            # Abrir el modal de alta reutilizando ProductosView, y refrescar la grilla al guardar
            try:
                from productos_view import ProductosView
                # Crear un frame no visible dentro de esta ventana como master del modal
                pv_hidden = ProductosView(stock_win)
                try:
                    pv_hidden.pack_forget()
                except Exception:
                    pass
                # Reemplazar su método cargar_productos para que refresque esta grilla cuando el alta confirme
                pv_hidden.cargar_productos = lambda: _refrescar_grid()
                pv_hidden._abrir_agregar_producto()
            except Exception as e:
                messagebox.showerror("Productos", f"No se pudo abrir el alta de productos.\n{e}")
        btn_nuevo = tk.Button(header, text="Agregar producto nuevo", command=_abrir_alta_desde_stock, bg="#1976d2", fg="white", font=("Arial", 11))
        # Dejar un margen entre el botón y el borde derecho
        btn_nuevo.pack(side=tk.RIGHT, padx=(0, 14))
        frame = tk.Frame(stock_win)
        frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        # Encabezados
        headers = ["Producto", "Stock", "Precio Venta", "Ocultar", "Contabilizar Stock", ""]
        for i, h in enumerate(headers):
            tk.Label(frame, text=h, font=("Arial", 11, "bold")).grid(row=0, column=i, padx=6, pady=4)

        # Estructuras mutables que usaremos en refrescos
        nonlocal_entries_stock = {}
        nonlocal_entries_precio = {}
        nonlocal_checks = {}
        nonlocal_checks_contab = {}
        entries_stock = nonlocal_entries_stock
        entries_precio = nonlocal_entries_precio
        checks = nonlocal_checks
        checks_contab = nonlocal_checks_contab

        # Primera carga
        _refrescar_grid()
        # Label info
        label_info = tk.Label(stock_win, text="Se descuenta stock sólo si 'Contabilizar Stock' está activado.", font=("Arial", 10), fg="#555")
        label_info.pack(pady=(0, 8))
        # Validación y guardado
        def guardar_stock():
            cambios = []
            for pid in entries_stock:
                try:
                    val = int(entries_stock[pid].get())
                    if val < 0:
                        raise ValueError
                except Exception:
                    messagebox.showerror("Stock", f"Stock inválido para el producto ID {pid}. Debe ser un número >= 0.")
                    return
                try:
                    precio_str = entries_precio[pid].get().replace(",", ".")
                    precio_val = float(precio_str)
                    if precio_val < 0 or precio_val > 999999:
                        raise ValueError
                except Exception:
                    messagebox.showerror("Precio", f"Precio inválido para el producto ID {pid}.")
                    return
                contab = 1 if checks_contab[pid].get() else 0
                # Si no contabiliza, el stock debe guardarse como 0
                val_to_save = 0 if contab == 0 else val
                # visible = 0 si "ocultar" está activo; 1 si no
                visible_final = 0 if checks[pid].get() else 1
                cambios.append((val_to_save, visible_final, precio_val, contab, pid))
            conn = get_connection()
            cursor = conn.cursor()
            for val, visible, precio, contab, pid in cambios:
                try:
                    cursor.execute(
                        "UPDATE products SET stock_actual=?, visible=?, precio_venta=?, contabiliza_stock=? WHERE id=?",
                        (val, visible, precio, contab, pid),
                    )
                except Exception:
                    cursor.execute(
                        "UPDATE products SET stock_actual=?, visible=?, precio_venta=? WHERE id=?",
                        (val, visible, precio, pid),
                    )
            conn.commit()
            conn.close()
            messagebox.showinfo("Stock", "Stock y precios actualizados correctamente.")
            try:
                stock_win.grab_release()
            except Exception:
                pass
            stock_win.destroy()
            # Refrescar productos en Ventas si está abierta
            try:
                self.refrescar_ventas_productos()
            except Exception:
                pass
        btn_guardar = tk.Button(stock_win, text="Guardar Cambios", command=guardar_stock, bg="#388e3c", fg="white", font=("Arial", 12), width=18)
        btn_guardar.pack(pady=10)
        def cancelar_stock():
            try:
                stock_win.grab_release()
            except Exception:
                pass
            stock_win.destroy()
            try:
                self.refrescar_ventas_productos()
            except Exception:
                pass
        btn_cancelar = tk.Button(stock_win, text="Cancelar", command=cancelar_stock, font=("Arial", 12), width=12)
        # Dejar margen inferior para que no quede pegado al borde
        btn_cancelar.pack(pady=(0, 14))

    def cerrar_caja_window(self):
        """Abre la vista de detalle/cierre para la caja abierta."""
        caja_id = getattr(self, 'caja_abierta_id', None)
        if not caja_id:
            messagebox.showerror("Cierre de caja", "No hay caja abierta actualmente.")
            return

        # Crear una nueva instancia de CajaListadoView especficamente para cerrar la caja
        try:
            from caja_listado_view import CajaListadoView
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

            # Usar caja predeterminada y generar código con prefijo
            try:
                c.execute("SELECT id, prefijo FROM pos_cajas WHERE predeterminada=1 AND activo=1 ORDER BY id LIMIT 1")
                rowp = c.fetchone()
                pos_caja_id, caja_prefijo = (rowp[0], rowp[1]) if rowp else (None, 'Caj01')
            except Exception:
                pos_caja_id, caja_prefijo = (None, 'Caj01')
            # Disciplina por defecto tomando la elegida en sesión si existe
            disciplina = getattr(self, 'disciplina_actual', None) or 'BAR'
            try:
                if not disciplina:
                    c.execute("SELECT codigo FROM disciplinas ORDER BY codigo LIMIT 1")
                    rowd = c.fetchone()
                    if rowd and rowd[0]:
                        disciplina = rowd[0]
            except Exception:
                pass
            base_code = f"{caja_prefijo}-{fecha.replace('-', '')}-{disciplina}"
            c.execute(
                "SELECT codigo_caja FROM caja_diaria WHERE fecha=? AND disciplina=? AND (caja_prefijo=? OR codigo_caja LIKE ?)",
                (fecha, disciplina, caja_prefijo, base_code + '%')
            )
            existentes = [r[0] for r in c.fetchall()] or []
            import re as _re2
            used = set()
            for cod in existentes:
                if cod == base_code:
                    used.add(1)
                else:
                    m = _re2.match(_re2.escape(base_code) + r"-(\d+)$", str(cod))
                    if m:
                        try:
                            used.add(int(m.group(1)))
                        except Exception:
                            pass
            codigo_caja = base_code if not used else f"{base_code}-{max(used)+1}"
            caja_uuid = str(uuid.uuid4())
            pos_uuid = get_current_pos_uuid()
            try:
                c.execute(
                    """
                    INSERT INTO caja_diaria (codigo_caja, fecha, hora_apertura, usuario_apertura, fondo_inicial, estado,
                                            ingresos, retiros, total_ventas, total_efectivo_teorico,
                                            conteo_efectivo_final, diferencia, observaciones_apertura, pos_uuid, caja_uuid, pos_caja_id, caja_prefijo, disciplina)
                    VALUES (?, ?, ?, ?, ?, 'abierta', 0, 0, 0, 0, 0, 0, '', ?, ?, ?, ?, ?)
                """,
                    (codigo_caja, fecha, hora, usuario, float(fondo_inicial), pos_uuid, caja_uuid, pos_caja_id, caja_prefijo, disciplina)
                )
            except Exception:
                c.execute(
                    """
                    INSERT INTO caja_diaria (codigo_caja, fecha, hora_apertura, usuario_apertura, fondo_inicial, estado,
                                            ingresos, retiros, total_ventas, total_efectivo_teorico,
                                            conteo_efectivo_final, diferencia, observaciones_apertura)
                    VALUES (?, ?, ?, ?, ?, 'abierta', 0, 0, 0, 0, 0, 0, '')
                """,
                    (codigo_caja, fecha, hora, usuario, float(fondo_inicial))
                )
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
            usuario_cierre = getattr(self, 'logged_user', None) or getattr(self, "usuario_logueado", "") or ""
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

