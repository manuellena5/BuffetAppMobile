import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import csv
import datetime as dt
from db_utils import get_connection

class ReportesTabularView(tk.Frame):
    """
    Explorador de ventas con filtros + tabla + exportación CSV (compatible Excel).
    Filtros: fecha desde/hasta, disciplina, método de pago, estado ticket, producto contiene.
    Resultados: una fila por ítem de venta.
    """
    def __init__(self, master, *args, **kwargs):
        super().__init__(master, *args, **kwargs)
        self._build_ui()

    def _build_ui(self):
        self.columnconfigure(0, weight=1)
        # Filtros (top)
        filtros = ttk.LabelFrame(self, text="Filtros")
        filtros.grid(row=0, column=0, sticky="nsew", padx=10, pady=(10, 6))
        for i in range(8):
            filtros.columnconfigure(i, weight=1)

        # Fecha desde / hasta (YYYY-MM-DD)
        ttk.Label(filtros, text="Fecha desde").grid(row=0, column=0, sticky="w", padx=4, pady=4)
        self.var_fdesde = tk.StringVar(value=(dt.date.today().strftime("%Y-%m-01")))
        ttk.Entry(filtros, textvariable=self.var_fdesde, width=12).grid(row=1, column=0, sticky="w", padx=4)

        ttk.Label(filtros, text="Fecha hasta").grid(row=0, column=1, sticky="w", padx=4, pady=4)
        self.var_fhasta = tk.StringVar(value=(dt.date.today().strftime("%Y-%m-%d")))
        ttk.Entry(filtros, textvariable=self.var_fhasta, width=12).grid(row=1, column=1, sticky="w", padx=4)

        # Disciplina
        ttk.Label(filtros, text="Disciplina").grid(row=0, column=2, sticky="w", padx=4, pady=4)
        self.cmb_disc = ttk.Combobox(filtros, state="readonly")
        self.cmb_disc.grid(row=1, column=2, sticky="we", padx=4)
        self._cargar_disciplinas()

        # Método de pago
        ttk.Label(filtros, text="Método de pago").grid(row=0, column=3, sticky="w", padx=4, pady=4)
        self.cmb_mp = ttk.Combobox(filtros, state="readonly")
        self.cmb_mp.grid(row=1, column=3, sticky="we", padx=4)
        self._cargar_metodos_pago()

        # Estado ticket
        ttk.Label(filtros, text="Estado ticket").grid(row=0, column=4, sticky="w", padx=4, pady=4)
        self.cmb_estado = ttk.Combobox(filtros, state="readonly", values=["(Todos)", "No impreso", "Impreso", "Anulado"])
        self.cmb_estado.current(0)
        self.cmb_estado.grid(row=1, column=4, sticky="we", padx=4)

        # Producto (contiene)
        ttk.Label(filtros, text="Producto contiene").grid(row=0, column=5, sticky="w", padx=4, pady=4)
        self.var_prod = tk.StringVar()
        ttk.Entry(filtros, textvariable=self.var_prod).grid(row=1, column=5, sticky="we", padx=4)

        # Botones
        btns = tk.Frame(filtros)
        btns.grid(row=1, column=7, sticky="e", padx=4)
        ttk.Button(btns, text="Buscar", command=self.buscar).pack(side=tk.LEFT, padx=(0,6))
        ttk.Button(btns, text="Exportar CSV", command=self.exportar_csv).pack(side=tk.LEFT)

        # Tabla
        self.tree = ttk.Treeview(self, columns=(
            "fecha", "caja", "venta_id", "ticket_id", "producto", "cantidad", "precio", "subtotal", "metodo_pago"
        ), show="headings", height=18)
        headers = [
            ("fecha", "Fecha/Hora"), ("caja", "Caja"), ("venta_id", "Venta"), ("ticket_id", "Ticket"),
            ("producto", "Producto"), ("cantidad", "Cant."), ("precio", "Precio"), ("subtotal", "Subtotal"), ("metodo_pago", "Método Pago")
        ]
        for k, txt in headers:
            self.tree.heading(k, text=txt)
            self.tree.column(k, width=110 if k in ("fecha", "producto") else 80, anchor="w")
        vsb = ttk.Scrollbar(self, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscroll=vsb.set)
        self.tree.grid(row=1, column=0, sticky="nsew", padx=(10,0), pady=(0,10))
        vsb.grid(row=1, column=0, sticky="nse", padx=(0,10), pady=(0,10))
        self.rowconfigure(1, weight=1)

    def _cargar_disciplinas(self):
        try:
            with get_connection() as conn:
                cur = conn.cursor()
                cur.execute("SELECT codigo, COALESCE(descripcion, codigo) FROM disciplinas ORDER BY 2")
                rows = cur.fetchall() or []
        except Exception:
            rows = []
        values = ["(Todas)"] + [r[1] for r in rows]
        self.cmb_disc["values"] = values
        self.cmb_disc.current(0)
        self._disc_map = {r[1]: r[0] for r in rows}

    def _cargar_metodos_pago(self):
        try:
            with get_connection() as conn:
                cur = conn.cursor()
                cur.execute("SELECT id, descripcion FROM metodos_pago ORDER BY 2")
                rows = cur.fetchall() or []
        except Exception:
            rows = []
        values = ["(Todos)"] + [r[1] for r in rows]
        self.cmb_mp["values"] = values
        self.cmb_mp.current(0)
        self._mp_map = {r[1]: r[0] for r in rows}

    def buscar(self):
        # Construir SQL con filtros opcionales
        fdesde = self.var_fdesde.get().strip()
        fhasta = self.var_fhasta.get().strip()
        prod_like = self.var_prod.get().strip()
        disc_desc = self.cmb_disc.get().strip()
        mp_desc = self.cmb_mp.get().strip()
        estado = self.cmb_estado.get().strip()

        sql = (
            "SELECT v.fecha_hora, cd.codigo_caja, v.id, t.id, p.nombre, vi.cantidad, vi.precio_unitario, vi.subtotal, mp.descripcion "
            "FROM venta_items vi "
            "JOIN tickets t ON t.id = vi.ticket_id "
            "JOIN ventas v ON v.id = t.venta_id "
            "LEFT JOIN products p ON p.id = vi.producto_id "
            "LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id "
            "LEFT JOIN caja_diaria cd ON cd.id = v.caja_id "
            "LEFT JOIN disciplinas d ON d.codigo = cd.disciplina "
            "WHERE 1=1 "
        )
        params = []
        # Rango de fechas
        if fdesde:
            sql += " AND date(v.fecha_hora) >= ?"; params.append(fdesde)
        if fhasta:
            sql += " AND date(v.fecha_hora) <= ?"; params.append(fhasta)
        # Disciplina
        if disc_desc and disc_desc != "(Todas)":
            disc_code = self._disc_map.get(disc_desc)
            if disc_code:
                sql += " AND cd.disciplina = ?"; params.append(disc_code)
        # Método de pago
        if mp_desc and mp_desc != "(Todos)":
            mp_id = self._mp_map.get(mp_desc)
            if mp_id:
                sql += " AND v.metodo_pago_id = ?"; params.append(mp_id)
        # Estado ticket
        if estado and estado != "(Todos)":
            sql += " AND t.status = ?"; params.append(estado)
        # Producto contiene
        if prod_like:
            sql += " AND p.nombre LIKE ?"; params.append(f"%{prod_like}%")
        # Orden
        sql += " ORDER BY v.fecha_hora DESC, v.id DESC, t.id DESC"

        try:
            with get_connection() as conn:
                cur = conn.cursor()
                cur.execute(sql, params)
                rows = cur.fetchall() or []
        except Exception as e:
            messagebox.showerror("Reportes", f"Error consultando datos.\n{e}")
            return

        # Volcar a la tabla
        for i in self.tree.get_children():
            self.tree.delete(i)
        for r in rows:
            # Ajustes de formato simples
            fecha = r[0]
            caja = r[1] or ""
            venta_id = r[2]; ticket_id = r[3]
            prod = r[4] or ""
            cant = r[5] or 0
            precio = r[6] or 0
            subtotal = r[7] or 0
            mp = r[8] or ""
            self.tree.insert("", tk.END, values=(fecha, caja, venta_id, ticket_id, prod, cant, precio, subtotal, mp))

    def exportar_csv(self):
        if not self.tree.get_children():
            messagebox.showwarning("Exportar", "No hay datos para exportar.")
            return
        path = filedialog.asksaveasfilename(
            title="Guardar como", defaultextension=".csv",
            filetypes=(("CSV", "*.csv"), ("Todos", "*.*"))
        )
        if not path:
            return
        try:
            with open(path, "w", newline="", encoding="utf-8") as f:
                w = csv.writer(f, delimiter=';')
                w.writerow(["Fecha/Hora", "Caja", "Venta", "Ticket", "Producto", "Cantidad", "Precio", "Subtotal", "Método Pago"])
                for iid in self.tree.get_children():
                    w.writerow(self.tree.item(iid, "values"))
            messagebox.showinfo("Exportar", "Exportación completada.")
        except Exception as e:
            messagebox.showerror("Exportar", f"No se pudo exportar el archivo.\n{e}")
