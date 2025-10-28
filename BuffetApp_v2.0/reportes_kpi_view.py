import tkinter as tk
from tkinter import ttk, messagebox
from db_utils import get_connection

class ReportesKPIView(tk.Frame):
    """
    Dashboard de KPIs por Caja:
    - Selector de caja
    - KPIs: Total Ventas, Tickets, Ticket Promedio, Ítems Vendidos
    - Ranking de productos (Top 10)
    - Ventas por método de pago
    - Diferencia de cierre (si existen columnas en caja_diaria)
    - Gráfico de barras simple (Top 5 productos)
    """
    def __init__(self, master, *args, **kwargs):
        super().__init__(master, *args, **kwargs)
        self._build_ui()

    def _build_ui(self):
        self.columnconfigure(0, weight=1)
        self.rowconfigure(3, weight=1)

        # Selector de caja
        top = ttk.Frame(self)
        top.grid(row=0, column=0, sticky="ew", padx=10, pady=(10,6))
        ttk.Label(top, text="Caja:").pack(side=tk.LEFT)
        self.cmb_caja = ttk.Combobox(top, state="readonly", width=40)
        self.cmb_caja.pack(side=tk.LEFT, padx=6)
        ttk.Button(top, text="Actualizar", command=self._load_cajas).pack(side=tk.LEFT)
        ttk.Button(top, text="Ver", command=self._load_data).pack(side=tk.LEFT, padx=(8,0))

        # KPIs
        kpis = ttk.Frame(self)
        kpis.grid(row=1, column=0, sticky="ew", padx=10)
        for i in range(4):
            kpis.columnconfigure(i, weight=1)
        self.lbl_total = ttk.Label(kpis, text="Total Ventas: -", font=("Arial", 12, "bold"))
        self.lbl_tickets = ttk.Label(kpis, text="Tickets: -", font=("Arial", 12, "bold"))
        self.lbl_prom = ttk.Label(kpis, text="Ticket Promedio: -", font=("Arial", 12, "bold"))
        self.lbl_items = ttk.Label(kpis, text="Items Vendidos: -", font=("Arial", 12, "bold"))
        self.lbl_total.grid(row=0, column=0, sticky="w", padx=6, pady=6)
        self.lbl_tickets.grid(row=0, column=1, sticky="w", padx=6, pady=6)
        self.lbl_prom.grid(row=0, column=2, sticky="w", padx=6, pady=6)
        self.lbl_items.grid(row=0, column=3, sticky="w", padx=6, pady=6)

    # Dos paneles: izquierda ranking, derecha métodos + diferencia + gráfico de línea por cajas
        mid = ttk.Frame(self)
        mid.grid(row=2, column=0, sticky="nsew", padx=10, pady=6)
        mid.columnconfigure(0, weight=1)
        mid.columnconfigure(1, weight=1)
        mid.rowconfigure(1, weight=1)

        # Ranking productos
        left = ttk.LabelFrame(mid, text="Top productos (cantidad)")
        left.grid(row=0, column=0, rowspan=2, sticky="nsew", padx=(0,6))
        self.tree_rank = ttk.Treeview(left, columns=("producto", "cant"), show="headings", height=12)
        self.tree_rank.heading("producto", text="Producto")
        self.tree_rank.heading("cant", text="Cant.")
        self.tree_rank.column("producto", width=180)
        self.tree_rank.column("cant", width=60)
        y1 = ttk.Scrollbar(left, orient="vertical", command=self.tree_rank.yview)
        self.tree_rank.configure(yscroll=y1.set)
        self.tree_rank.grid(row=0, column=0, sticky="nsew")
        y1.grid(row=0, column=1, sticky="ns")
        left.rowconfigure(0, weight=1)

        # Métodos de pago + diferencia
        right_top = ttk.LabelFrame(mid, text="Métodos de pago")
        right_top.grid(row=0, column=1, sticky="nsew", padx=(6,0))
        self.tree_mp = ttk.Treeview(right_top, columns=("metodo", "total"), show="headings", height=6)
        self.tree_mp.heading("metodo", text="Método")
        self.tree_mp.heading("total", text="Total")
        self.tree_mp.column("metodo", width=150)
        self.tree_mp.column("total", width=100)
        y2 = ttk.Scrollbar(right_top, orient="vertical", command=self.tree_mp.yview)
        self.tree_mp.configure(yscroll=y2.set)
        self.tree_mp.grid(row=0, column=0, sticky="nsew")
        y2.grid(row=0, column=1, sticky="ns")
        right_top.rowconfigure(0, weight=1)

        self.lbl_diff = ttk.Label(right_top, text="Diferencia cierre: -")
        self.lbl_diff.grid(row=1, column=0, sticky="w", padx=4, pady=4)

        # Gráfico de líneas: Totales por caja (X=fecha, Y=total ventas), con filtro de disciplina
        right_bottom = ttk.LabelFrame(mid, text="Totales por caja (línea)")
        right_bottom.grid(row=1, column=1, sticky="nsew", padx=(6,0))
        # Filtro de disciplina para el gráfico
        frame_gf = ttk.Frame(right_bottom)
        frame_gf.pack(fill=tk.X, padx=6, pady=(6,0))
        ttk.Label(frame_gf, text="Disciplina:").pack(side=tk.LEFT)
        self.cmb_disc = ttk.Combobox(frame_gf, state="readonly", width=20)
        self.cmb_disc.pack(side=tk.LEFT, padx=6)
        ttk.Button(frame_gf, text="Ver", command=self._load_line_chart).pack(side=tk.LEFT)
        self.canvas = tk.Canvas(right_bottom, height=220, bg="#fafafa")
        self.canvas.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        self._load_cajas()
        self._load_disciplinas_for_chart()

    def _load_cajas(self):
        try:
            with get_connection() as conn:
                cur = conn.cursor()
                cur.execute("""
                    SELECT id, COALESCE(codigo_caja,'Caja') || ' - ' || COALESCE(fecha,'') || ' (' || COALESCE(disciplina,'') || ')' AS d
                    FROM caja_diaria
                    ORDER BY id DESC
                    LIMIT 200
                """)
                rows = cur.fetchall() or []
        except Exception as e:
            rows = []
        self._cajas = rows
        values = [r[1] for r in rows]
        self.cmb_caja["values"] = values
        if values:
            self.cmb_caja.current(0)
        self._load_data()

    def _get_selected_caja_id(self):
        idx = self.cmb_caja.current()
        if idx is None or idx < 0:
            return None
        try:
            return self._cajas[idx][0]
        except Exception:
            return None

    def _load_data(self):
        caja_id = self._get_selected_caja_id()
        if not caja_id:
            return
        # KPIs
        with get_connection() as conn:
            cur = conn.cursor()
            # Ventas totales y conteos
            cur.execute("SELECT COALESCE(SUM(total_venta),0), COUNT(DISTINCT id) FROM ventas WHERE caja_id=?", (caja_id,))
            total, ventas_count = cur.fetchone()
            cur.execute("SELECT COUNT(*) FROM tickets t JOIN ventas v ON v.id=t.venta_id WHERE v.caja_id=?", (caja_id,))
            tickets_count = cur.fetchone()[0]
            cur.execute("""
                SELECT COALESCE(SUM(vi.cantidad),0)
                FROM venta_items vi
                JOIN tickets t ON t.id=vi.ticket_id
                JOIN ventas v ON v.id=t.venta_id
                WHERE v.caja_id=?
            """, (caja_id,))
            items_count = cur.fetchone()[0]
            prom = (total / ventas_count) if ventas_count else 0
            self.lbl_total.config(text=f"Total Ventas: {total:.2f}")
            self.lbl_tickets.config(text=f"Tickets: {tickets_count}")
            self.lbl_prom.config(text=f"Ticket Promedio: {prom:.2f}")
            self.lbl_items.config(text=f"Items Vendidos: {items_count}")

            # Ranking productos
            cur.execute("""
                SELECT COALESCE(p.nombre,'(sin nombre)'), SUM(vi.cantidad) as cant
                FROM venta_items vi
                JOIN tickets t ON t.id=vi.ticket_id
                JOIN ventas v ON v.id=t.venta_id
                LEFT JOIN products p ON p.id=vi.producto_id
                WHERE v.caja_id=?
                GROUP BY vi.producto_id
                ORDER BY cant DESC, p.nombre ASC
                LIMIT 50
            """, (caja_id,))
            rank_rows = cur.fetchall() or []
            for i in self.tree_rank.get_children():
                self.tree_rank.delete(i)
            for r in rank_rows:
                self.tree_rank.insert("", tk.END, values=r)

            # Métodos de pago
            try:
                cur.execute("""
                    SELECT COALESCE(mp.descripcion,'(sin método)'), COALESCE(SUM(v.total_venta),0)
                    FROM ventas v
                    LEFT JOIN metodos_pago mp ON mp.id=v.metodo_pago_id
                    WHERE v.caja_id=?
                    GROUP BY v.metodo_pago_id
                    ORDER BY 2 DESC
                """, (caja_id,))
                mp_rows = cur.fetchall() or []
            except Exception:
                mp_rows = []
            for i in self.tree_mp.get_children():
                self.tree_mp.delete(i)
            for r in mp_rows:
                self.tree_mp.insert("", tk.END, values=(r[0], f"{(r[1] or 0):.2f}"))

            # Diferencia de cierre (si existe)
            diff_txt = "-"
            try:
                cur.execute("SELECT diferencia, total_efectivo_teorico, conteo_efectivo_final FROM caja_diaria WHERE id=?", (caja_id,))
                row = cur.fetchone()
                if row:
                    dif, teor, contado = row
                    partes = []
                    if dif is not None:
                        partes.append(f"Dif: {dif:.2f}")
                    if teor is not None:
                        partes.append(f"Teórico: {teor:.2f}")
                    if contado is not None:
                        partes.append(f"Contado: {contado:.2f}")
                    if partes:
                        diff_txt = " | ".join(partes)
            except Exception:
                pass
            self.lbl_diff.config(text=f"Diferencia cierre: {diff_txt}")

        # Actualizar gráfico de línea (no depende de caja seleccionada)
        self._load_line_chart()
    def _load_disciplinas_for_chart(self):
        try:
            with get_connection() as conn:
                cur = conn.cursor()
                cur.execute("""
                    SELECT DISTINCT COALESCE(d.codigo, cd.disciplina) as code,
                                    COALESCE(d.descripcion, cd.disciplina) as desc
                    FROM caja_diaria cd
                    LEFT JOIN disciplinas d ON d.codigo = cd.disciplina
                    WHERE cd.disciplina IS NOT NULL AND TRIM(cd.disciplina) <> ''
                    ORDER BY desc
                """)
                rows = cur.fetchall() or []
        except Exception:
            rows = []
        values = ["(Todas)"] + [r[1] for r in rows]
        self._disc_map = {r[1]: r[0] for r in rows}
        try:
            self.cmb_disc["values"] = values
            self.cmb_disc.current(0)
        except Exception:
            pass

    def _load_line_chart(self):
        # Obtener totales por caja (agrupados por fecha) con filtro de disciplina opcional
        disc_desc = None
        try:
            disc_desc = self.cmb_disc.get()
        except Exception:
            pass
        disc_code = None
        if disc_desc and disc_desc != "(Todas)":
            disc_code = self._disc_map.get(disc_desc)
        try:
            with get_connection() as conn:
                cur = conn.cursor()
                sql = (
                    "SELECT fecha, COALESCE(SUM(total_venta),0) as total_dia "
                    "FROM caja_diaria cd "
                    "JOIN ventas v ON v.caja_id = cd.id "
                    "WHERE 1=1 "
                )
                params = []
                if disc_code:
                    sql += " AND cd.disciplina = ?"; params.append(disc_code)
                sql += " GROUP BY fecha ORDER BY fecha"
                cur.execute(sql, params)
                rows = cur.fetchall() or []
        except Exception:
            rows = []
        # Dibujar línea
        self.canvas.delete("all")
        if not rows:
            return
        w = self.canvas.winfo_width() or 400
        h = self.canvas.winfo_height() or 220
        margin_x = 40
        margin_y = 30
        xs = [r[0] for r in rows]
        ys = [float(r[1] or 0) for r in rows]
        maxy = max(ys) or 1
        # Ejes
        self.canvas.create_line(margin_x, h - margin_y, w - margin_x, h - margin_y, fill="#444")
        self.canvas.create_line(margin_x, h - margin_y, margin_x, margin_y, fill="#444")
        # Escala y puntos
        n = len(rows)
        if n == 1:
            step = (w - 2*margin_x) // 2
        else:
            step = (w - 2*margin_x) / (n - 1)
        prev = None
        for i, (xdate, yval) in enumerate(zip(xs, ys)):
            px = margin_x + i * step
            py = h - margin_y - ((h - 2*margin_y) * (yval / maxy))
            r = 3
            self.canvas.create_oval(px - r, py - r, px + r, py + r, fill="#1976d2", outline="")
            if prev:
                self.canvas.create_line(prev[0], prev[1], px, py, fill="#1976d2", width=2)
            prev = (px, py)
            # etiqueta de fecha (cada 5 puntos máx para legibilidad)
            if i % max(1, n // 8) == 0:
                self.canvas.create_text(px, h - margin_y + 12, text=xdate[-5:], anchor="n", font=("Arial", 8))
        # Etiqueta de máximo
        self.canvas.create_text(margin_x - 6, margin_y, text=f"{maxy:.0f}", anchor="e", font=("Arial", 8))
