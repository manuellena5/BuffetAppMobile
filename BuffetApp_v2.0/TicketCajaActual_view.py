import tkinter as tk
from tkinter import ttk, messagebox
from db_utils import get_connection
from init_db import log_error

class TicketCajaActualView(tk.Frame):
    def __init__(self, master, controller=None):
        super().__init__(master)
        self.controller = controller
        self._build_ui()
        self._load_productos_lista()
        self._load_data()

    def _build_ui(self):
        tk.Label(self, text="Tickets de la caja actual", font=("Arial", 18)).pack(pady=(10,6))
        # Barra superior: Ventas | filtro producto (Listbox) | filtro estado | Anular | Reimprimir | Actualizar
        top = tk.Frame(self)
        top.pack(fill=tk.X, padx=8, pady=(0,8))
        # Ir a Ventas (volver)
        tk.Button(top, text="Ir a Ventas", command=self._volver).pack(side=tk.LEFT, padx=(0,8))
        # Filtro producto (Combobox desplegable)
        prod_frame = tk.Frame(top)
        prod_frame.pack(side=tk.LEFT, padx=(0,10))
        tk.Label(prod_frame, text="Producto:", font=("Arial", 10)).pack(anchor="w")
        self.var_producto = tk.StringVar(value="(Todos)")
        self.cmb_productos = ttk.Combobox(prod_frame, textvariable=self.var_producto, state='readonly', width=30)
        self.cmb_productos.pack()
        self.cmb_productos.bind('<<ComboboxSelected>>', lambda e: self._load_data())
        # Filtro estado
        state_frame = tk.Frame(top)
        state_frame.pack(side=tk.LEFT, padx=(10,10))
        tk.Label(state_frame, text="Estado:", font=("Arial", 10)).pack(anchor="w")
        self.var_estado = tk.StringVar(value="Todos")
        self.cmb_estado = ttk.Combobox(state_frame, textvariable=self.var_estado, state='readonly', width=14,
                                       values=["Todos", "Impreso", "No impreso", "Anulado"])
        self.cmb_estado.pack()
        self.cmb_estado.bind('<<ComboboxSelected>>', lambda e: self._load_data())
        # Botones de acciones
        tk.Button(top, text="Anular ticket", command=self._anular_sel).pack(side=tk.LEFT, padx=6)
        tk.Button(top, text="Reimprimir ticket", command=self._reimprimir_sel).pack(side=tk.LEFT, padx=6)
        tk.Button(top, text="Actualizar", command=self._load_data).pack(side=tk.LEFT, padx=6)
        # Tree
        content = tk.Frame(self)
        content.pack(fill=tk.BOTH, expand=True, padx=8, pady=(0,6))
        self.tree = ttk.Treeview(
            content,
            columns=("fecha_hora","item","total","categoria","status","codigo_caja","identificador","metodo_pago"),
            show='headings'
        )
        self.tree.heading("fecha_hora", text="Fecha")
        self.tree.heading("item", text="Item")
        self.tree.heading("total", text="Monto Total")
        self.tree.heading("categoria", text="Categoria")
        self.tree.heading("status", text="Estado")
        self.tree.heading("codigo_caja", text="Caja")
        self.tree.heading("identificador", text="Identificador")
        self.tree.heading("metodo_pago", text="Método de Pago")
        self.tree.column("fecha_hora", width=120)
        self.tree.column("item", width=140)
        self.tree.column("total", width=100, anchor=tk.E)
        self.tree.column("categoria", width=80)
        self.tree.column("status", width=90)
        self.tree.column("codigo_caja", width=140)
        self.tree.column("identificador", width=120)
        self.tree.column("metodo_pago", width=120)
        scr = ttk.Scrollbar(content, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scr.set)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scr.pack(side=tk.LEFT, fill=tk.Y)
    # Sin botonera inferior; todo queda arriba

    def _get_caja_abierta_id(self):
        try:
            if self.controller and hasattr(self.controller, 'caja_abierta_id'):
                return getattr(self.controller, 'caja_abierta_id')
            conn = get_connection(); cur = conn.cursor()
            cur.execute("SELECT id FROM caja_diaria WHERE estado='abierta' ORDER BY fecha DESC, hora_apertura DESC LIMIT 1")
            row = cur.fetchone(); conn.close()
            return row[0] if row else None
        except Exception:
            try:
                conn.close()
            except Exception:
                pass
            return None

    def _load_productos_lista(self):
        try:
            caja_id = self._get_caja_abierta_id()
            if not caja_id:
                # limpiar combobox
                try:
                    self.cmb_productos['values'] = []
                    self.var_producto.set("")
                except Exception:
                    pass
                return
            conn = get_connection(); cur = conn.cursor()
            cur.execute(
                """
                SELECT DISTINCT p.nombre
                  FROM venta_items vi
                  JOIN tickets t ON t.id = vi.ticket_id
                  JOIN ventas v ON v.id = t.venta_id
                  JOIN products p ON p.id = vi.producto_id
                 WHERE v.caja_id=?
                 ORDER BY p.nombre
                """,
                (caja_id,)
            )
            rows = [r[0] for r in cur.fetchall()]; conn.close()
            # Poblar combobox con opción (Todos) al inicio
            vals = ["(Todos)"] + rows
            try:
                self.cmb_productos['values'] = vals
                self.var_producto.set("(Todos)")
            except Exception:
                pass
        except Exception:
            try:
                conn.close()
            except Exception:
                pass

    def _load_data(self):
        caja_id = self._get_caja_abierta_id()
        if not caja_id:
            messagebox.showinfo("Tickets", "No hay caja abierta.")
            self.tree.delete(*self.tree.get_children())
            return
        # Producto seleccionado en Combobox ("(Todos)" = sin filtro)
        prod_f = ''
        try:
            val = (self.var_producto.get() or '').strip()
            if val and val != "(Todos)":
                prod_f = val
        except Exception:
            prod_f = ''
        est = self.var_estado.get()
        try:
            conn = get_connection(); cur = conn.cursor()
            base = (
                "FROM venta_items vi "
                "LEFT JOIN tickets t ON vi.ticket_id = t.id "
                "LEFT JOIN ventas v ON t.venta_id = v.id "
                "LEFT JOIN products p ON vi.producto_id = p.id "
                "LEFT JOIN Categoria_Producto c ON t.categoria_id = c.id "
                "LEFT JOIN caja_diaria cd ON v.caja_id = cd.id "
                "LEFT JOIN metodos_pago mp ON v.metodo_pago_id = mp.id "
                "WHERE v.caja_id = ? "
            )
            params = [caja_id]
            if prod_f:
                base += "AND p.nombre = ? "
                params.append(prod_f)
            if est and est != 'Todos':
                base += "AND t.status = ? "
                params.append(est)
            sel = (
                "SELECT v.fecha_hora, p.nombre, vi.subtotal, c.descripcion, t.status, cd.codigo_caja, t.identificador_ticket, mp.descripcion "
                + base + " ORDER BY v.fecha_hora DESC, v.id, t.categoria_id"
            )
            cur.execute(sel, params)
            rows = cur.fetchall(); conn.close()
            self._fill_tree(rows)
        except Exception as e:
            import datetime, traceback
            fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            tb = traceback.extract_tb(e.__traceback__)
            linea = tb[-1].lineno if tb else 'N/A'
            modulo = tb[-1].filename if tb else 'TicketCajaActualView._load_data'
            mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
            try:
                log_error(fecha_hora, modulo, mensaje)
            except Exception:
                pass
            messagebox.showerror("Error", "No se pudo cargar los tickets de la caja actual.")

    def _fill_tree(self, rows):
        self.tree.delete(*self.tree.get_children())
        for r in rows:
            fecha_hora, nombre, subtotal, categoria, status, codigo_caja, identificador, mp = r
            try:
                monto_str = f"$ {int(round(float(subtotal))):,}".replace(",", ".")
            except Exception:
                monto_str = f"$ {subtotal}"
            bg = '#D3D3D3' if str(status).lower() == 'anulado' else ''
            iid = self.tree.insert('', tk.END, values=(fecha_hora, nombre, monto_str, categoria, status, codigo_caja, identificador, mp or '' ))
            if bg:
                self.tree.item(iid, tags=('anul',))
                self.tree.tag_configure('anul', background=bg)

    def _get_selected_ticket_id(self):
        sel = self.tree.selection()
        if not sel:
            return None
        # recuperar ticket_id por identificador
        ident = self.tree.item(sel[0], 'values')[6]
        try:
            conn = get_connection(); cur = conn.cursor()
            cur.execute("SELECT id FROM tickets WHERE identificador_ticket=?", (ident,))
            row = cur.fetchone(); conn.close()
            return row[0] if row else None
        except Exception:
            try:
                conn.close()
            except Exception:
                pass
            return None

    def _reimprimir_sel(self):
        tid = self._get_selected_ticket_id()
        if not tid:
            messagebox.showinfo("Reimpresión", "Seleccione un ticket para reimprimir.")
            return
        self._reimprimir(tid)

    def _reimprimir(self, ticket_id):
        try:
            conn = get_connection(); cur = conn.cursor()
            cur.execute("SELECT v.fecha_hora, t.status, t.identificador_ticket, c.descripcion, cd.codigo_caja, cd.disciplina FROM tickets t LEFT JOIN ventas v ON t.venta_id = v.id LEFT JOIN Categoria_Producto c ON t.categoria_id = c.id LEFT JOIN caja_diaria cd ON v.caja_id = cd.id WHERE t.id=?", (ticket_id,))
            ticket = cur.fetchone()
            if not ticket:
                messagebox.showerror("Reimpresión", "No se encontró el ticket."); conn.close(); return
            fecha_hora, status, identificador_ticket, categoria, codigo_caja, disciplina = ticket
            if status == 'Impreso':
                if not messagebox.askyesno("Reimpresión", "El ticket ya fue impreso. ¿Desea reimprimir de todos modos?"):
                    conn.close(); return
            # Items
            cur.execute("SELECT cantidad, producto_id FROM venta_items WHERE ticket_id=?", (ticket_id,))
            items = cur.fetchall()
            from ventas_view_new import VentasViewNew
            exito = True
            for cantidad, producto_id in items:
                cur.execute("SELECT nombre FROM products WHERE id=?", (producto_id,))
                nombre = cur.fetchone()[0]
                for _ in range(cantidad):
                    ok = VentasViewNew.imprimir_ticket_por_item_win32_static(
                        fecha_hora, nombre, ticket_id, identificador_ticket, codigo_caja, disciplina
                    )
                    if not ok:
                        exito = False
            nuevo_status = 'Impreso' if exito else 'No impreso'
            cur.execute("UPDATE tickets SET status=? WHERE id=?", (nuevo_status, ticket_id))
            conn.commit(); conn.close()
            messagebox.showinfo("Reimpresión", f"Ticket {'impreso' if exito else 'NO impreso'}.")
            self._load_data()
        except Exception as e:
            import datetime, traceback
            fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            tb = traceback.extract_tb(e.__traceback__)
            linea = tb[-1].lineno if tb else 'N/A'
            modulo = tb[-1].filename if tb else 'TicketCajaActualView._reimprimir'
            mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
            try:
                log_error(fecha_hora, modulo, mensaje)
            except Exception:
                pass
            messagebox.showerror("Error de reimpresión", "No se pudo reimprimir por un error del sistema.")

    def _anular_sel(self):
        tid = self._get_selected_ticket_id()
        if not tid:
            messagebox.showinfo("Anular Ticket", "Seleccione un ticket para anular.")
            return
        if not messagebox.askyesno("Anular Ticket", "¿Confirma que desea anular el ticket seleccionado?"):
            return
        try:
            conn = get_connection(); cur = conn.cursor()
            cur.execute("UPDATE tickets SET status='Anulado' WHERE id=?", (tid,))
            # Devolver stock de productos si contabiliza_stock=1
            cur.execute("SELECT producto_id, cantidad FROM venta_items WHERE ticket_id=?", (tid,))
            items = cur.fetchall()
            for prod_id, cantidad in items:
                try:
                    cur.execute("SELECT COALESCE(contabiliza_stock,1) FROM products WHERE id=?", (prod_id,))
                    row = cur.fetchone(); contabiliza = int(row[0]) if row and row[0] is not None else 1
                except Exception:
                    contabiliza = 1
                if contabiliza == 1:
                    cur.execute("UPDATE products SET stock_actual = COALESCE(stock_actual,0) + ? WHERE id=?", (cantidad, prod_id))
            conn.commit(); conn.close()
            self._load_data()
            messagebox.showinfo("Anular Ticket", "Ticket anulado y stock actualizado.")
        except Exception as e:
            import datetime, traceback
            fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            tb = traceback.extract_tb(e.__traceback__)
            linea = tb[-1].lineno if tb else 'N/A'
            modulo = tb[-1].filename if tb else 'TicketCajaActualView._anular_sel'
            mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
            try:
                log_error(fecha_hora, modulo, mensaje)
            except Exception:
                pass
            messagebox.showerror("Anular Ticket", "No se pudo anular el ticket.")

    def _volver(self):
        if self.controller and hasattr(self.controller, 'mostrar_ventas'):
            self.controller.mostrar_ventas()
        else:
            try:
                self.pack_forget()
            except Exception:
                pass
