import os
import sqlite3
import shutil
import datetime
import tkinter as tk
from tkinter import messagebox
from theme import themed_button, apply_button_style, COLORS, format_currency
from tkinter import filedialog
from tkinter import ttk
from db_utils import get_connection
from app_config import (
    get_device_id, get_device_name, set_device_name, set_device_id,
    get_printer_name, set_printer_name,
)
from sync_utils import import_from_db
from utils_paths import DB_PATH, appdata_dir
# Importación opcional de sincronización en la nube
try:
    from cloud_sync import is_configured as cloud_is_configured, sync_pendientes as cloud_sync_pendientes
except Exception:
    def cloud_is_configured():
        return False
    def cloud_sync_pendientes(limit: int = 20):
        raise RuntimeError("Sincronización en la nube no disponible")


# HerramientasView centraliza la gestión de backups y el test de impresora
class HerramientasView:
    def __init__(self, parent):
        self.parent = parent
        # Sin Google Drive: todo lo relacionado fue removido.
        self._printers_cached = []

    def abrir_backup_window(self, root):
        backup_win = tk.Toplevel(root)
        backup_win.title("Gestión de Backups")
        # Centrar y hacer modal
        try:
            backup_win.update_idletasks()
            w, h = 980, 620
            sw, sh = backup_win.winfo_screenwidth(), backup_win.winfo_screenheight()
            x = max(0, (sw // 2) - (w // 2))
            y = max(0, (sh // 2) - (h // 2))
            backup_win.geometry(f"{w}x{h}+{x}+{y}")
        except Exception:
            backup_win.geometry("980x620")
        backup_win.transient(root)
        backup_win.grab_set()

        # Sección: Identificador de dispositivo (POS local) - solo lectura
        frm_pos = tk.LabelFrame(backup_win, text="Punto de Venta (este dispositivo)")
        frm_pos.pack(fill=tk.X, padx=8, pady=8)
        tk.Label(frm_pos, text="Nombre:").grid(row=0, column=0, sticky="w", padx=6, pady=4)
        tk.Entry(frm_pos, state="readonly", readonlybackground="#f7f7f7", width=28,
                 textvariable=tk.StringVar(value=get_device_name())).grid(row=0, column=1, sticky="w", padx=6, pady=4)
        tk.Label(frm_pos, text="ID (UUID):").grid(row=1, column=0, sticky="w", padx=6, pady=4)
        tk.Entry(frm_pos, state="readonly", readonlybackground="#f7f7f7", width=36,
                 textvariable=tk.StringVar(value=get_device_id())).grid(row=1, column=1, sticky="w", padx=6, pady=4)

        # Separador
        tk.Label(backup_win, text="").pack()

        # Botones de backup/exportación
        btn_local = themed_button(backup_win, text="Realizar Backup Local (AppData)", command=lambda: self.backup_local(parent=backup_win))
        apply_button_style(btn_local)
        btn_local.pack(pady=6)

        btn_export = themed_button(backup_win, text="Exportar backup a archivo…", command=lambda: self.export_backup_file(parent=backup_win))
        apply_button_style(btn_export)
        btn_export.pack(pady=6)

        # Importar/Restaurar acciones
        def _importar_db():
            try:
                from utils_paths import appdata_dir
                initial_dir = os.path.join(appdata_dir(), 'import_tmp')
            except Exception:
                initial_dir = None
            path = filedialog.askopenfilename(
                title="Seleccionar base de datos a importar",
                filetypes=[("SQLite DB", "*.db"), ("Todos", "*.*")],
                initialdir=(initial_dir if initial_dir and os.path.exists(initial_dir) else None)
            )
            if not path:
                return
            try:
                res = import_from_db(path, incluir_historial=True)
                messagebox.showinfo(
                    "Importación",
                    (
                        "Importación completada.\n"
                        f"POS nuevos: {res.get('pos_nuevos')}\n"
                        f"Categorías nuevas: {res.get('categorias_nuevas')} (origen: {res.get('src_categorias')})\n"
                        f"Productos nuevos: {res.get('productos_nuevos')} (origen: {res.get('src_products')})\n"
                        f"Cajas nuevas: {res.get('cajas_nuevas')} (origen: {res.get('src_cajas')})\n"
                        f"Ventas: {res.get('ventas_nuevas')} (origen: {res.get('src_ventas')})\n"
                        f"Tickets: {res.get('tickets_nuevos')} (origen: {res.get('src_tickets')})\n"
                        f"Items: {res.get('items_nuevos')} (origen: {res.get('src_items')})"
                    )
                )
            except Exception as e:
                messagebox.showerror("Importación", f"Error al importar: {e}")

        btns_sync = tk.Frame(backup_win)
        btns_sync.pack(pady=6)
        btn_import = themed_button(btns_sync, text="Importar desde .db (Sincronizar)", command=_importar_db)
        apply_button_style(btn_import)
        btn_import.pack(side=tk.LEFT, padx=6)

        # Restaurar BD (botón rojo)
        def _restore_db():
            self.restore_database_from_file(parent=backup_win)
        btn_restore = themed_button(btns_sync, text="Restaurar BD desde archivo…", command=_restore_db)
        try:
            apply_button_style(btn_restore, bg=COLORS.get('error', '#F43F5E'), fg='white')
        except Exception:
            apply_button_style(btn_restore)
        btn_restore.pack(side=tk.LEFT, padx=6)

        # Botón de sincronización con la nube (Supabase)
        def _sync_cloud_now():
            # Abre la nueva ventana de sincronización (listado + acciones)
            try:
                if not cloud_is_configured():
                    messagebox.showwarning(
                        "Sincronización",
                        "Supabase no está configurado. Configurá SUPABASE_URL y SUPABASE_ANON_KEY en el entorno o ajustes."
                    )
                    return
                self.abrir_sync_window(backup_win)
            except Exception as e:
                messagebox.showerror("Sincronización", f"Error al abrir la ventana de sincronización: {e}")

        btn_sync = themed_button(btns_sync, text="Sincronizar datos con la nube", command=_sync_cloud_now)
        apply_button_style(btn_sync)
        btn_sync.pack(side=tk.LEFT, padx=6)

        # Lista local de backups (debajo de las acciones)
        tk.Label(backup_win, text="Backups locales (AppData/Local/BuffetApp/backup):").pack(pady=(6,0))
        list_frame = tk.Frame(backup_win)
        list_frame.pack(fill=tk.BOTH, expand=True, padx=6, pady=4)
        scrollbar = tk.Scrollbar(list_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        listbox = tk.Listbox(list_frame, width=110, height=12, yscrollcommand=scrollbar.set)
        listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.config(command=listbox.yview)
        try:
            bdir = os.path.join(appdata_dir(), 'backup')
            if os.path.exists(bdir):
                files = sorted(os.listdir(bdir), reverse=True)
                for fn in files:
                    listbox.insert(0, fn)
        except Exception:
            pass

    def abrir_sync_window(self, root):
        """Ventana para listar últimas 20 cajas y sincronizar pendientes, validando estado en la nube."""
        win = tk.Toplevel(root)
        win.title("Sincronización con la nube")
        try:
            win.update_idletasks()
            w, h = 1280, 680
            sw, sh = win.winfo_screenwidth(), win.winfo_screenheight()
            x = max(0, (sw // 2) - (w // 2))
            y = max(0, (sh // 2) - (h // 2))
            win.geometry(f"{w}x{h}+{x}+{y}")
        except Exception:
            win.geometry("1280x680")
        win.transient(root)
        win.grab_set()
        try:
            win.minsize(1100, 560)
        except Exception:
            pass

        # Tabla de cajas
        cols = ("Código", "Evento", "Apertura", "Cierre", "Tickets", "Ventas", "Local", "Nube")
        tree = ttk.Treeview(win, columns=cols, show="headings", height=18)
        for c in cols:
            tree.heading(c, text=c)
        tree.column("Código", width=110, anchor="w")
        tree.column("Evento", width=220, anchor="w")
        tree.column("Apertura", width=180, anchor="w")
        tree.column("Cierre", width=180, anchor="w")
        tree.column("Tickets", width=80, anchor="e")
        tree.column("Ventas", width=100, anchor="e")
        tree.column("Local", width=70, anchor="center")
        tree.column("Nube", width=70, anchor="center")

        vsb = ttk.Scrollbar(win, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=vsb.set)
        tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(8,0), pady=8)
        vsb.pack(side=tk.RIGHT, fill=tk.Y, padx=(0,8), pady=8)

        # Tag para filas sincronizadas en nube
        tree.tag_configure("synced", background="#E7F6EC", foreground="#166534")  # verde suave

        data_rows = []  # para reuso en sincronización

        def _load_rows():
            # Limpiar
            for iid in tree.get_children():
                tree.delete(iid)
            data_rows.clear()
            # Leer últimas 20 cajas locales
            try:
                with get_connection() as conn:
                    cur = conn.cursor()
                    cur.execute(
                        """
                        SELECT id, codigo_caja, descripcion_evento, fecha, hora_apertura, hora_cierre,
                               COALESCE(total_tickets,0), COALESCE(total_ventas,0),
                               COALESCE(nube_enviado,0), COALESCE(nube_uuid,'')
                          FROM caja_diaria
                         ORDER BY id DESC
                         LIMIT 20
                        """
                    )
                    rows = cur.fetchall() or []
            except Exception as e:
                messagebox.showerror("Sincronización", f"No se pudieron leer las cajas locales: {e}")
                rows = []

            # Consultar Supabase por los UUID disponibles
            uuid_map = {}
            uuids = []
            for r in rows:
                # Columna 9 = nube_uuid (según SELECT)
                val = r[9]
                s = str(val if val is not None else "").strip()
                if s:
                    uuids.append(s)
            remote_uuids = set()
            if uuids:
                try:
                    from cloud_sync import SUPABASE_REST, HEADERS  # usar mismas credenciales
                    import requests
                    # Particionar en grupos para URL IN
                    bs = 100
                    for i in range(0, len(uuids), bs):
                        chunk = uuids[i:i+bs]
                        values = ",".join([f'"{u}"' for u in chunk])
                        url = f"{SUPABASE_REST}/cajas?select=uuid&uuid=in.({values})"
                        r = requests.get(url, headers=HEADERS, timeout=20)
                        if r.status_code < 300 and r.text:
                            for row in r.json():
                                u = (row.get("uuid") or "").strip()
                                if u:
                                    remote_uuids.add(u)
                except Exception:
                    # Si falla la consulta remota, dejamos Nube en base a local
                    remote_uuids = set()

            # Poblar tabla
            for rid, cod, evento, fch, ha, hc, tickets, ventas, local_sync, nube_uuid in rows:
                ap = f"{fch or ''} {ha or ''}".strip()
                ci = f"{fch or ''} {hc or ''}".strip()
                nube_ok = (str(nube_uuid).strip() in remote_uuids) if (str(nube_uuid).strip()) else False
                vals = (cod or "", evento or "", ap, ci, int(tickets or 0), f"{float(ventas or 0):.2f}", "Sí" if local_sync else "No", "Sí" if nube_ok else "No")
                tag = ("synced",) if nube_ok else ()
                tree.insert("", tk.END, iid=str(rid), values=vals, tags=tag)
                data_rows.append({
                    "id": int(rid),
                    "codigo": cod or "",
                    "evento": evento or "",
                    "local_sync": bool(local_sync),
                    "nube_uuid": (nube_uuid or "").strip(),
                    "nube_ok": bool(nube_ok),
                })

        _load_rows()

        # Acciones
        btns = tk.Frame(win)
        btns.pack(fill=tk.X, padx=8, pady=(0,8))

        def _sync_pending():
            # Determinar pendientes (Nube == No)
            pendientes = [d for d in data_rows if not d["nube_ok"]]
            if not pendientes:
                messagebox.showinfo("Sincronización", "No hay pendientes para sincronizar.")
                return
            # Confirmar lista de cajas a sincronizar
            resumen = "\n".join([f"- Caja {d['id']} ({d['codigo']})" for d in pendientes])
            if not messagebox.askyesno("Confirmar", f"Se sincronizarán {len(pendientes)} cajas:\n\n{resumen}\n\n¿Continuar?"):
                return
            # Modal de progreso
            progress = tk.Toplevel(win)
            progress.title("Sincronizando…")
            progress.transient(win)
            progress.grab_set()
            lbl = tk.Label(progress, text="Sincronizando cajas…")
            lbl.pack(padx=16, pady=(14, 6))
            pbar = ttk.Progressbar(progress, mode="determinate", length=360, maximum=len(pendientes))
            pbar.pack(padx=16, pady=(0, 14))
            ok_cnt = 0; err_cnt = 0
            errores = []
            try:
                from cloud_sync import sync_caja
                for idx, d in enumerate(pendientes, start=1):
                    try:
                        lbl.configure(text=f"Sincronizando caja {d['id']} ({d['codigo']})…")
                        progress.update_idletasks()
                        r = sync_caja(d["id"])
                        ok_cnt += 1
                    except Exception as e:
                        err_cnt += 1
                        errores.append(f"Caja {d['id']}: {e}")
                    finally:
                        pbar['value'] = idx
                        try:
                            progress.update_idletasks()
                        except Exception:
                            pass
            finally:
                try:
                    progress.destroy()
                except Exception:
                    pass
            # Resultado
            if err_cnt:
                message = f"Sincronización finalizada. OK: {ok_cnt} | Errores: {err_cnt}\n\n" + "\n".join(errores[:10])
                messagebox.showwarning("Sincronización", message)
            else:
                messagebox.showinfo("Sincronización", f"Sincronización completada. OK: {ok_cnt}")
            # Refrescar tabla
            _load_rows()

        tk.Button(btns, text="Sincronizar pendientes", command=_sync_pending, bg="#166534", fg="white").pack(side=tk.LEFT, padx=4)
        tk.Button(btns, text="Cerrar", command=win.destroy).pack(side=tk.LEFT, padx=4)

    def abrir_impresora_window(self, root):
        """Ventana de configuración de impresora: elegir y probar."""
        win = tk.Toplevel(root)
        win.title("Config. Impresora")
        try:
            win.update_idletasks()
            w, h = 1000, 420
            sw, sh = win.winfo_screenwidth(), win.winfo_screenheight()
            x = max(0, (sw // 2) - (w // 2))
            y = max(0, (sh // 2) - (h // 2))
            win.geometry(f"{w}x{h}+{x}+{y}")
        except Exception:
            win.geometry("1000x420")
        win.transient(root)
        win.grab_set()

        frm_prn = tk.LabelFrame(win, text="Impresora del sistema")
        frm_prn.pack(fill=tk.X, padx=12, pady=12)
        tk.Label(frm_prn, text="Seleccionar impresora:").grid(row=0, column=0, sticky="w", padx=6, pady=6)
        self.var_printer = tk.StringVar(value=get_printer_name() or "")
        self.combo_printers = ttk.Combobox(frm_prn, textvariable=self.var_printer, state="readonly", width=60)
        self.combo_printers.grid(row=0, column=1, sticky="we", padx=6, pady=6)
        frm_prn.columnconfigure(1, weight=1)
        self.combo_printers.bind('<<ComboboxSelected>>', self._on_printer_selected)
        ttk.Button(frm_prn, text="Actualizar lista", command=self._refresh_printers).grid(row=0, column=2, sticky="w", padx=6, pady=6)
        ttk.Button(frm_prn, text="Guardar selección", command=self._save_printer).grid(row=0, column=3, sticky="w", padx=6, pady=6)
        ttk.Button(frm_prn, text="Usar predeterminada", command=self._clear_printer).grid(row=0, column=4, sticky="w", padx=6, pady=6)

        # Info de impresora actual y predeterminada
        info_frame = tk.Frame(win)
        info_frame.pack(fill=tk.X, padx=12, pady=(4, 10))
        self.var_printer_info = tk.StringVar(value="")
        lbl_info = tk.Label(info_frame, textvariable=self.var_printer_info, anchor="w", justify="left")
        lbl_info.pack(fill=tk.X)

        # Acción de prueba
        btns = tk.Frame(win)
        btns.pack(fill=tk.X, padx=12, pady=8)
        ttk.Button(btns, text="Test Ticket de Venta", command=self.test_ticket_venta).pack(side=tk.LEFT, padx=(0,8))
        ttk.Button(btns, text="Test Cierre de Caja", command=self.test_ticket_cierre).pack(side=tk.LEFT)

        # Inicial
        self._refresh_printers()
        self._update_printer_info()

    def abrir_pos_window(self, root):
        """Ventana para ver datos del POS y gestionar cajas predeterminadas."""
        win = tk.Toplevel(root)
        win.title("Punto de Venta")
        # Agrandar y centrar ventana
        try:
            win.update_idletasks()
            w, h = 880, 560
            sw, sh = win.winfo_screenwidth(), win.winfo_screenheight()
            x = max(0, (sw // 2) - (w // 2))
            y = max(0, (sh // 2) - (h // 2))
            win.geometry(f"{w}x{h}+{x}+{y}")
        except Exception:
            win.geometry("880x560")

        # Datos del dispositivo (solo lectura)
        frm_dev = tk.LabelFrame(win, text="Dispositivo")
        frm_dev.pack(fill=tk.X, padx=8, pady=8)
        tk.Label(frm_dev, text="Nombre del dispositivo:").grid(row=0, column=0, sticky="w", padx=6, pady=4)
        tk.Entry(frm_dev, state="readonly", width=42, readonlybackground="#f7f7f7",
                 textvariable=tk.StringVar(value=get_device_name())).grid(row=0, column=1, sticky="w", padx=6, pady=4)
    # Oculto: ID (UUID) del dispositivo (se solicitó no mostrarlo en Punto de Venta)
    # tk.Label(frm_dev, text="ID (UUID):").grid(row=1, column=0, sticky="w", padx=6, pady=4)
    # tk.Entry(frm_dev, state="readonly", width=42, readonlybackground="#f7f7f7",
    #          textvariable=tk.StringVar(value=get_device_id())).grid(row=1, column=1, sticky="w", padx=6, pady=4)

        # Listado de cajas (plantillas)
        frm_cajas = tk.LabelFrame(win, text="Cajas disponibles")
        frm_cajas.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)
        columns = ("Descripción", "Prefijo", "Predeterminada", "Estado")
        tree = ttk.Treeview(frm_cajas, columns=columns, show="headings", height=8)
        # Encabezados y tamaños de columnas
        for c in columns:
            tree.heading(c, text=c)
            if c == "Descripción":
                tree.column(c, width=300, anchor="w")
            elif c == "Prefijo":
                tree.column(c, width=120, anchor="w")
            elif c == "Predeterminada":
                tree.column(c, width=140, anchor="center")
            else:  # Estado
                tree.column(c, width=100, anchor="center")

        # Scrollbar vertical
        vsb = ttk.Scrollbar(frm_cajas, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=vsb.set)
        tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        vsb.pack(side=tk.RIGHT, fill=tk.Y)
        # Cargar listado inicial
        def _refresh_tree():
            try:
                for iid in tree.get_children():
                    tree.delete(iid)
                conn = get_connection(); cur = conn.cursor()
                cur.execute("SELECT id, descripcion, prefijo, predeterminada, activo FROM pos_cajas ORDER BY id")
                for rid, desc, pref, pred, activo in cur.fetchall():
                    tree.insert("", tk.END, iid=str(rid), values=(desc, pref, "Sí" if pred else "No", "Activa" if activo else "Inactiva"))
                conn.close()
            except Exception:
                pass
        _refresh_tree()

        # Acción: marcar predeterminada
        btns = tk.Frame(win)
        btns.pack(fill=tk.X, padx=8, pady=6)
        def set_default():
            sel = tree.selection()
            if not sel:
                messagebox.showwarning("Punto de Venta", "Seleccioná una caja para establecer como predeterminada.")
                return
            caja_id = int(sel[0])
            vals_sel = tree.item(sel[0], 'values')
            # Si está inactiva, ofrecer reactivarla
            if len(vals_sel) >= 4 and vals_sel[3] == "Inactiva":
                if not messagebox.askyesno("Punto de Venta", "La caja seleccionada está inactiva. ¿Querés reactivarla y establecerla como predeterminada?"):
                    return
                reactivate = True
            else:
                reactivate = False
            try:
                conn = get_connection(); cur = conn.cursor()
                # Dejar solo una predeterminada
                cur.execute("UPDATE pos_cajas SET predeterminada=CASE WHEN id=? THEN 1 ELSE 0 END", (caja_id,))
                if reactivate:
                    cur.execute("UPDATE pos_cajas SET activo=1 WHERE id=?", (caja_id,))
                conn.commit(); conn.close()
                # Refrescar listado
                _refresh_tree()
                messagebox.showinfo("Punto de Venta", "Caja predeterminada actualizada.")
            except Exception as e:
                messagebox.showerror("Punto de Venta", f"No se pudo actualizar: {e}")

        btn_def = themed_button(btns, text="Establecer como predeterminada", command=set_default)
        apply_button_style(btn_def)
        btn_def.pack(side=tk.LEFT, padx=4)

        # Helpers
        # Nota: _refresh_tree inicial ya definido arriba y reutilizado más abajo

        def _open_modal(title, initial=None):
            top = tk.Toplevel(win)
            top.title(title)
            top.transient(win)
            top.grab_set()
            top.geometry("380x220+{}+{}".format(win.winfo_rootx()+60, win.winfo_rooty()+60))
            tk.Label(top, text="Descripción:").grid(row=0, column=0, sticky="w", padx=8, pady=8)
            var_desc = tk.StringVar(value=(initial.get('descripcion') if initial else ""))
            tk.Entry(top, textvariable=var_desc, width=28).grid(row=0, column=1, padx=8, pady=8)
            tk.Label(top, text="Prefijo:").grid(row=1, column=0, sticky="w", padx=8, pady=8)
            var_pref = tk.StringVar(value=(initial.get('prefijo') if initial else ""))
            tk.Entry(top, textvariable=var_pref, width=16).grid(row=1, column=1, padx=8, pady=8, sticky='w')
            # Checkbox para predeterminada solo en edición
            var_pred = tk.BooleanVar(value=bool(initial.get('predeterminada')) if initial else False)
            if initial is not None:
                tk.Checkbutton(top, text="Predeterminada", variable=var_pred).grid(row=2, column=1, padx=8, pady=4, sticky='w')
            btn_bar = tk.Frame(top)
            btn_bar.grid(row=3, column=0, columnspan=2, pady=12)
            def _ok():
                desc = var_desc.get().strip()
                pref = var_pref.get().strip()
                if not desc:
                    messagebox.showwarning("Cajas", "La descripción no puede estar vacía.")
                    return
                if not pref:
                    messagebox.showwarning("Cajas", "El prefijo no puede estar vacío.")
                    return
                try:
                    conn = get_connection(); cur = conn.cursor()
                    if initial is None:
                        # Alta
                        cur.execute("INSERT INTO pos_cajas (descripcion, prefijo, predeterminada, activo) VALUES (?, ?, 0, 1)", (desc, pref))
                    else:
                        # Edición
                        rid = initial['id']
                        cur.execute("UPDATE pos_cajas SET descripcion=?, prefijo=? WHERE id=?", (desc, pref, rid))
                        if var_pred.get():
                            cur.execute("UPDATE pos_cajas SET predeterminada=CASE WHEN id=? THEN 1 ELSE 0 END", (rid,))
                    conn.commit(); conn.close()
                    _refresh_tree()
                    top.destroy()
                except sqlite3.IntegrityError:
                    messagebox.showerror("Cajas", "Prefijo duplicado. Debe ser único.")
                except Exception as e:
                    messagebox.showerror("Cajas", f"No se pudo guardar: {e}")
            def _cancel():
                top.destroy()
            tk.Button(btn_bar, text="Guardar", command=_ok, width=12, bg="#15803D", fg="white").pack(side=tk.LEFT, padx=6)
            tk.Button(btn_bar, text="Cancelar", command=_cancel, width=12).pack(side=tk.LEFT, padx=6)

        def add_box():
            _open_modal("Nueva Caja")

        def edit_box(event=None):
            sel = tree.selection()
            if not sel:
                return
            iid = sel[0]
            vals = tree.item(iid, 'values')
            initial = {'id': int(iid), 'descripcion': vals[0], 'prefijo': vals[1], 'predeterminada': 1 if vals[2] == 'Sí' else 0}
            _open_modal("Editar Caja", initial=initial)

        def delete_box():
            sel = tree.selection()
            if not sel:
                messagebox.showwarning("Cajas", "Seleccioná una caja para eliminar.")
                return
            iid = int(sel[0])
            # Confirmación
            if not messagebox.askyesno("Eliminar", "¿Dar de baja esta caja?\nNo se borrará, solo quedará inactiva."):
                return
            try:
                conn = get_connection(); cur = conn.cursor()
                # Si es predeterminada, dar de baja y asegurar otra por defecto
                cur.execute("SELECT predeterminada FROM pos_cajas WHERE id=?", (iid,))
                pred = (cur.fetchone() or [0])[0]
                cur.execute("UPDATE pos_cajas SET activo=0, predeterminada=0 WHERE id=?", (iid,))
                if pred:
                    # elegir otra como predeterminada si no hay
                    cur.execute("SELECT COUNT(*) FROM pos_cajas WHERE activo=1 AND predeterminada=1")
                    if (cur.fetchone() or [0])[0] == 0:
                        cur.execute("UPDATE pos_cajas SET predeterminada=1 WHERE id=(SELECT id FROM pos_cajas WHERE activo=1 ORDER BY id LIMIT 1)")
                conn.commit(); conn.close()
                _refresh_tree()
            except Exception as e:
                messagebox.showerror("Cajas", f"No se pudo eliminar: {e}")

        def activate_box():
            sel = tree.selection()
            if not sel:
                messagebox.showwarning("Cajas", "Seleccioná una caja inactiva para reactivar.")
                return
            iid = int(sel[0])
            try:
                conn = get_connection(); cur = conn.cursor()
                cur.execute("UPDATE pos_cajas SET activo=1 WHERE id=?", (iid,))
                conn.commit(); conn.close()
                _refresh_tree()
            except Exception as e:
                messagebox.showerror("Cajas", f"No se pudo reactivar: {e}")

        # Botonera ABM
        btn_add = themed_button(btns, text="Agregar", command=add_box)
        try:
            apply_button_style(btn_add, bg=COLORS.get('success', '#166534'), fg='white')
        except Exception:
            apply_button_style(btn_add)
        btn_add.pack(side=tk.LEFT, padx=4)
        btn_edit = themed_button(btns, text="Editar", command=edit_box)
        apply_button_style(btn_edit)
        btn_edit.pack(side=tk.LEFT, padx=4)
        btn_del = themed_button(btns, text="Eliminar", command=delete_box)
        try:
            apply_button_style(btn_del, bg=COLORS.get('error', '#F43F5E'), fg='white')
        except Exception:
            apply_button_style(btn_del)
        btn_del.pack(side=tk.LEFT, padx=4)

        btn_act = themed_button(btns, text="Reactivar", command=activate_box)
        apply_button_style(btn_act)
        btn_act.pack(side=tk.LEFT, padx=4)

        # Doble click para editar
        tree.bind('<Double-1>', edit_box)

    def backup_local(self, parent=None):
        """Create a local backup under %LOCALAPPDATA%\BuffetApp\backup using db_migrations.backup_db() if available, otherwise fallback inline."""
        try:
            try:
                from db_migrations import backup_db
            except Exception:
                backup_db = None

            def _refresh_listbox(parent_win):
                if not parent_win:
                    return
                for w in parent_win.winfo_children():
                    if isinstance(w, tk.Listbox):
                        try:
                            w.delete(0, tk.END)
                            from utils_paths import appdata_dir
                            bdir = os.path.join(appdata_dir(), 'backup')
                            if os.path.exists(bdir):
                                for fn in sorted(os.listdir(bdir), reverse=True):
                                    w.insert(tk.END, fn)
                        except Exception:
                            pass

            if callable(backup_db):
                path = backup_db()
                try:
                    from utils_paths import appdata_dir
                    log_path = os.path.join(appdata_dir(), 'backup_logs.txt')
                    with open(log_path, 'a', encoding='utf-8') as lf:
                        lf.write(f"{datetime.datetime.now().isoformat()} - manual backup created: {path}\n")
                except Exception:
                    pass
                messagebox.showinfo('Backup local', f'Backup creado: {path}')
                _refresh_listbox(parent)
                return

            # Fallback inline: use DB_PATH and sqlite online backup API
            from utils_paths import DB_PATH, appdata_dir
            ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
            bdir = os.path.join(appdata_dir(), 'backup')
            os.makedirs(bdir, exist_ok=True)
            dst = os.path.join(bdir, f'barcancha_{ts}.db')
            try:
                src_conn = sqlite3.connect(DB_PATH)
                dest_conn = sqlite3.connect(dst)
                with dest_conn:
                    src_conn.backup(dest_conn)
                try:
                    dest_conn.close()
                except Exception:
                    pass
                try:
                    src_conn.close()
                except Exception:
                    pass
                # log & notify
                try:
                    log_path = os.path.join(appdata_dir(), 'backup_logs.txt')
                    with open(log_path, 'a', encoding='utf-8') as lf:
                        lf.write(f"{datetime.datetime.now().isoformat()} - inline backup created: {dst}\n")
                except Exception:
                    pass
                messagebox.showinfo('Backup local', f'Backup creado: {dst}')
                _refresh_listbox(parent)
                return
            except Exception as e:
                # fallback to file copy
                try:
                    shutil.copy2(DB_PATH, dst)
                    try:
                        log_path = os.path.join(appdata_dir(), 'backup_logs.txt')
                        with open(log_path, 'a', encoding='utf-8') as lf:
                            lf.write(f"{datetime.datetime.now().isoformat()} - inline backup copied: {dst}\n")
                    except Exception:
                        pass
                    messagebox.showinfo('Backup local', f'Backup creado (copiado): {dst}')
                    _refresh_listbox(parent)
                    return
                except Exception as e2:
                    try:
                        log_path = os.path.join(appdata_dir(), 'backup_logs.txt')
                        with open(log_path, 'a', encoding='utf-8') as lf:
                            lf.write(f"{datetime.datetime.now().isoformat()} - manual backup failed: {e2}\n")
                    except Exception:
                        pass
                    messagebox.showerror('Backup local', f'Error creando backup local: {e2}')
                    return
        except Exception as e:
            messagebox.showerror('Backup local', f'Error inesperado: {e}')

    def export_backup_file(self, parent=None):
        """Genera un backup y permite guardarlo en una ruta elegida por el usuario (copiar a pendrive, etc.)."""
        try:
            # Primero crear backup local y obtener ruta
            backup_path = None
            try:
                from db_migrations import backup_db
                backup_path = backup_db()
            except Exception:
                # Fallback: copiar DB_PATH a un archivo temporal en backup dir
                ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
                bdir = os.path.join(appdata_dir(), 'backup')
                os.makedirs(bdir, exist_ok=True)
                backup_path = os.path.join(bdir, f'barcancha_{ts}.db')
                shutil.copy2(DB_PATH, backup_path)

            # Preguntar dónde guardar
            default_name = os.path.basename(backup_path)
            dest = filedialog.asksaveasfilename(title='Guardar backup como…', defaultextension='.db', initialfile=default_name, filetypes=[('SQLite DB', '*.db'), ('Todos', '*.*')])
            if not dest:
                return
            shutil.copy2(backup_path, dest)
            messagebox.showinfo('Exportar backup', f'Se guardó el backup en:\n{dest}')
        except Exception as e:
            messagebox.showerror('Exportar backup', f'No se pudo exportar el backup: {e}')

    def restore_database_from_file(self, parent=None):
        """Restaura la base de datos desde un archivo .db seleccionado por el usuario.
        Hace un backup local antes de sobrescribir DB_PATH.
        """
        try:
            src = filedialog.askopenfilename(title='Seleccionar archivo .db para restaurar', filetypes=[('SQLite DB', '*.db'), ('Todos', '*.*')])
            if not src:
                return
            if not messagebox.askyesno('Restaurar BD', 'Esta acción reemplazará la base de datos actual por el archivo seleccionado.\nSe hará un backup automático antes de continuar.\n\n¿Confirmás la restauración?'):
                return
            # Backup previo
            try:
                self.backup_local(parent=None)
            except Exception:
                pass
            # Intentar copiar sobre DB_PATH
            try:
                # Cerrar conexiones conocidas: no tenemos un pool global, confiamos en GC
                shutil.copy2(src, DB_PATH)
                messagebox.showinfo('Restaurar BD', 'Restauración completada. Reiniciá la aplicación para aplicar los cambios.')
            except Exception as e:
                messagebox.showerror('Restaurar BD', f'No se pudo restaurar la base de datos.\nDetalle: {e}\n\nCerrá la app e intentá nuevamente.')
        except Exception as e:
            messagebox.showerror('Restaurar BD', f'Error inesperado: {e}')

    # Funcionalidad de Google Drive eliminada por pedido del usuario.

    def _resolve_printer_name(self) -> str:
        """Devuelve la impresora a usar: seleccionada en config o la predeterminada del sistema."""
        try:
            sel = get_printer_name()
            if sel:
                return sel
        except Exception:
            pass
        try:
            import win32print
            return win32print.GetDefaultPrinter()
        except Exception:
            # Fallback: cadena vacía provocará error manejado más abajo
            return ""

    def _refresh_printers(self):
        try:
            import win32print
            flags = 2  # PRINTER_ENUM_LOCAL
            self._printers_cached = [name for (flags, desc, name, comment) in win32print.EnumPrinters(flags)]
        except Exception:
            self._printers_cached = []
        vals = [p for p in self._printers_cached]
        if not vals:
            vals = []
        self.combo_printers['values'] = vals
        # Selección actual si existe
        cur = get_printer_name()
        if cur and cur in vals:
            self.combo_printers.set(cur)
        elif cur:
            # mantener texto aunque no esté en la lista (impresora desconectada)
            self.combo_printers.set(cur)
        else:
            try:
                import win32print
                self.combo_printers.set(win32print.GetDefaultPrinter())
            except Exception:
                self.combo_printers.set("")
        # Actualizar info
        self._update_printer_info()

    def _save_printer(self):
        name = (self.var_printer.get() or "").strip()
        if not name:
            messagebox.showinfo("Impresora", "No hay selección. Se usará la predeterminada del sistema.")
            set_printer_name(None)
            return
        set_printer_name(name)
        messagebox.showinfo("Impresora", f"Impresora guardada: {name}")
        self._update_printer_info()

    def _clear_printer(self):
        set_printer_name(None)
        self._refresh_printers()
        messagebox.showinfo("Impresora", "Se usará la impresora predeterminada de Windows.")
        self._update_printer_info()

    def _update_printer_info(self):
        """Actualiza label con impresora seleccionada y predeterminada de Windows."""
        try:
            sel = get_printer_name()
        except Exception:
            sel = None
        try:
            import win32print
            default = win32print.GetDefaultPrinter()
        except Exception:
            default = "(No disponible)"
        # Estado
        status_txt = "Desconocido"
        try:
            name_for_status = sel or default
            if name_for_status:
                ok, stat = self._get_printer_status(name_for_status)
                status_txt = ("Online" if ok else "Offline/Error") + (f" ({stat})" if stat else "")
        except Exception:
            pass
        texto = ""
        if sel:
            texto += f"Seleccionada: {sel}\n"
        else:
            texto += "Seleccionada: (Usando predeterminada del sistema)\n"
        texto += f"Predeterminada de Windows: {default}\n"
        texto += f"Estado actual: {status_txt}"
        try:
            self.var_printer_info.set(texto)
        except Exception:
            pass

    def _get_printer_status(self, printer_name: str):
        try:
            import win32print
            hPrinter = win32print.OpenPrinter(printer_name)
            try:
                info = win32print.GetPrinter(hPrinter, 2)
                status = info.get('Status', 0)
                PRINTER_STATUS_OFFLINE = 0x00000080
                PRINTER_STATUS_ERROR = 0x00000002
                PRINTER_STATUS_NOT_AVAILABLE = 0x00001000
                ok = not (status & (PRINTER_STATUS_OFFLINE | PRINTER_STATUS_ERROR | PRINTER_STATUS_NOT_AVAILABLE))
                return ok, status
            finally:
                try:
                    win32print.ClosePrinter(hPrinter)
                except Exception:
                    pass
        except Exception:
            return False, None

    def _on_printer_selected(self, event=None):
        # Refrescar texto con selección actual del combo (sin requerir guardar)
        try:
            self._update_printer_info()
        except Exception:
            pass

    def test_impresora(self):
            try:
                import win32print, win32ui, win32con
                printer_name = self._resolve_printer_name()
                # Estado
                ok, _ = self._get_printer_status(printer_name)
                if not ok:
                    messagebox.showerror("Estado de impresora", f"La impresora '{printer_name}' está offline, en error o no disponible.\n\nVerifica la conexión y el estado.")
                    return
                # 1) Ticket de venta de ejemplo (similar a Ventas)
                pdc = None
                try:
                    pdc = win32ui.CreateDC()
                    pdc.CreatePrinterDC(printer_name)
                    pdc.StartDoc("Test - Ticket de Venta")
                    pdc.StartPage()
                    ANCHO_PX = 520
                    GAP = 2
                    TITLE_H = 40
                    META_H = 24
                    ITEM_BOX_H = 76
                    def center_x(text):
                        w, _ = pdc.GetTextExtent(text)
                        return max(0, (ANCHO_PX - w) // 2)
                    font_title = win32ui.CreateFont({"name": "Arial", "height": TITLE_H, "weight": 700, "charset": win32con.ANSI_CHARSET})
                    font_meta  = win32ui.CreateFont({"name": "Arial", "height": META_H,   "weight": 400, "charset": win32con.ANSI_CHARSET})
                    y = 0
                    pdc.SelectObject(font_title)
                    pdc.TextOut(center_x("BUFFET"), y, "BUFFET"); y += TITLE_H + GAP
                    pdc.SelectObject(font_meta)
                    pdc.TextOut(center_x("Nº 0001-000123"), y, "Nº 0001-000123"); y += META_H + GAP
                    from datetime import datetime
                    fh = datetime.now().strftime("%Y-%m-%d %H:%M")
                    pdc.TextOut(center_x(fh), y, fh); y += META_H + GAP
                    pdc.TextOut(center_x("Caja A01"), y, "Caja A01"); y += META_H + GAP
                    # Item grande
                    item_text = "HAMBURGUESA"
                    tam = 86
                    while True:
                        font_item_big = win32ui.CreateFont({"name": "Arial", "height": tam, "weight": 700, "charset": win32con.ANSI_CHARSET})
                        pdc.SelectObject(font_item_big)
                        w, h = pdc.GetTextExtent(item_text)
                        if (w <= ANCHO_PX - 8) and (h <= ITEM_BOX_H - 4) and tam >= 36:
                            break
                        tam -= 4
                        if tam < 36:
                            break
                    pdc.SelectObject(font_item_big)
                    y_item = y + max(0, (ITEM_BOX_H - pdc.GetTextExtent(item_text)[1]) // 2)
                    pdc.TextOut(center_x(item_text), y_item, item_text)
                    pdc.EndPage(); pdc.EndDoc()
                finally:
                    if pdc:
                        try:
                            pdc.DeleteDC()
                        except Exception:
                            pass
                messagebox.showinfo("Test Impresora", f"Se envió el ticket de venta de prueba a: {printer_name}")
            except Exception as e:
                messagebox.showerror("Error de impresión", f"No se pudo realizar la prueba de impresión.\n\nDetalle: {e}")

    def test_ticket_venta(self):
        """Imprime un ticket de venta de ejemplo con el layout utilizado en ventas."""
        self.test_impresora()

    def test_ticket_cierre(self):
        """Imprime un ticket de cierre de caja de ejemplo en modo RAW (ESC/POS) con el mismo layout que el cierre real."""
        try:
            import win32print, win32ui, win32con
            printer_name = self._resolve_printer_name()
            ok, _ = self._get_printer_status(printer_name)
            if not ok:
                messagebox.showerror("Estado de impresora", f"La impresora '{printer_name}' está offline, en error o no disponible.\n\nVerifica la conexión y el estado.")
                return
            import datetime as _dt
            # Construir texto usando el mismo patrón que caja_operaciones._imprimir_ticket
            W = 40  # ancho fijo del ticket
            now = _dt.datetime.now()
            fecha = now.strftime("%Y-%m-%d")
            hora = now.strftime("%H:%M")
            # Valores de ejemplo (alineados a la lógica real)
            codigo_caja = "A01"
            usuario_apertura = "cajero"
            usuario_cierre = "cajero"
            disciplina = "General"
            fondo_inicial = 2000
            conteo_final = 7950
            transferencias = 4345
            ingresos = 500
            retiros = 200
            total_general = 12345
            diferencia = conteo_final + transferencias - (fondo_inicial + total_general + ingresos - retiros)
            ticket_lines = []
            ticket_lines.append("=" * W)
            ticket_lines.append("CIERRE DE CAJA".center(W))
            ticket_lines.append("=" * W)
            ticket_lines.append(f"Codigo caja: {codigo_caja}")
            ticket_lines.append(f"Fecha apertura: {fecha} {hora}")
            ticket_lines.append(f"Usuario apertura: {usuario_apertura}")
            ticket_lines.append(f"Disciplina: {disciplina}")
            ticket_lines.append(f"Fecha cierre: {fecha} {hora}")
            ticket_lines.append(f"Usuario cierre: {usuario_cierre}")
            ticket_lines.append("-" * W)
            ticket_lines.append("TOTALES POR MEDIO DE PAGO")
            ticket_lines.append("-" * W)
            # ejemplos de medios de pago
            ticket_lines.append(f"Efectivo: {format_currency(total_general - transferencias)}")
            ticket_lines.append(f"Transferencia: {format_currency(transferencias)}")
            ticket_lines.append("-" * W)
            ticket_lines.append(f"TOTAL: {format_currency(total_general)}")
            ticket_lines.append("-" * W)
            ticket_lines.append(f"Fondo inicial: {format_currency(fondo_inicial)}")
            ticket_lines.append(f"Conteo final: {format_currency(conteo_final)}")
            ticket_lines.append(f"Transferencias: {format_currency(transferencias)}")
            ticket_lines.append(f"Ingresos: {format_currency(ingresos)}")
            ticket_lines.append(f"Retiros: {format_currency(-abs(float(retiros)))}")
            ticket_lines.append(f"Diferencia: {format_currency(diferencia, include_sign=True)}")
            ticket_lines.append(f"Tickets anulados: 2")
            ticket_lines.append("=" * W)
            ticket_lines.append("ITEMS VENDIDOS:")
            ticket_lines.append("(Producto x Cant) = Monto Total")
            ticket_lines.append("-" * W)
            ticket_lines.append(f"(Hamburguesa x 3) = {format_currency(4500)}")
            ticket_lines.append(f"(Gaseosa x 5) = {format_currency(3500)}")
            ticket_lines.append(f"(Papas x 2) = {format_currency(1200)}")
            text = "\n".join(ticket_lines) + "\n\n"
            # Detectar impresoras tipo PDF (usar GDI para que abra el diálogo y renderice texto correctamente)
            is_pdf = False
            try:
                h = win32print.OpenPrinter(printer_name)
                try:
                    info = win32print.GetPrinter(h, 2)
                    driver = (info.get('pDriverName') or info.get('DriverName') or "").lower()
                    is_pdf = ('pdf' in printer_name.lower()) or ('pdf' in driver)
                finally:
                    win32print.ClosePrinter(h)
            except Exception:
                is_pdf = ('pdf' in printer_name.lower())

            if is_pdf:
                # GDI: imprimir líneas monoespaciadas para respetar layout 40 columnas
                pdc = None
                try:
                    pdc = win32ui.CreateDC()
                    pdc.CreatePrinterDC(printer_name)
                    pdc.StartDoc("Test - Cierre de Caja")
                    pdc.StartPage()
                    # Monoespaciada para 40-col
                    font = win32ui.CreateFont({"name": "Courier New", "height": 24, "weight": 400, "charset": win32con.ANSI_CHARSET})
                    pdc.SelectObject(font)
                    x = 40  # margen izquierdo
                    y = 60
                    line_h = 28
                    for line in ticket_lines:
                        pdc.TextOut(x, y, line)
                        y += line_h
                    pdc.EndPage(); pdc.EndDoc()
                    messagebox.showinfo("Test Impresora", f"Se envió el ticket de cierre de prueba a: {printer_name}")
                except Exception as e:
                    messagebox.showerror("Test Impresora", f"Error al imprimir ticket de cierre (GDI): {e}")
                finally:
                    if pdc:
                        try:
                            pdc.DeleteDC()
                        except Exception:
                            pass
            else:
                # RAW para POS/ESC-POS
                try:
                    data = text.encode('cp437', errors='replace')
                except Exception:
                    data = text.encode('cp1252', errors='replace')
                try:
                    hPrinter = win32print.OpenPrinter(printer_name)
                    try:
                        win32print.StartDocPrinter(hPrinter, 1, ("Test - Cierre de Caja", None, "RAW"))
                        win32print.StartPagePrinter(hPrinter)
                        win32print.WritePrinter(hPrinter, data)
                        # corte parcial
                        win32print.WritePrinter(hPrinter, b"\x1dV\x00")
                        win32print.EndPagePrinter(hPrinter)
                        win32print.EndDocPrinter(hPrinter)
                    finally:
                        win32print.ClosePrinter(hPrinter)
                    messagebox.showinfo("Test Impresora", f"Se envió el ticket de cierre de prueba a: {printer_name}")
                except Exception as e:
                    messagebox.showerror("Test Impresora", f"Error al imprimir ticket de cierre (RAW): {e}")
        except Exception as e:
            messagebox.showerror("Error de impresión", f"No se pudo realizar la prueba de cierre.\n\nDetalle: {e}")
    