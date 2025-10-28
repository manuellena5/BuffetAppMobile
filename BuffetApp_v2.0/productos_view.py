import tkinter as tk
from tkinter import messagebox
from db_utils import get_connection, generate_unique_product_code
from theme import (
    TITLE_FONT,
    TEXT_FONT,
    apply_button_style,
    apply_treeview_style,
)


class ProductosView(tk.Frame):
    def actualizar_estilos(self, config):
        self.btn_ancho = config.get("ancho_boton", 20)
        self.btn_alto = config.get("alto_boton", 2)
        self.btn_font = config.get("fuente_boton", "Arial")
        self.color_boton = config.get("color_boton", "#f0f0f0")

    def __init__(self, master):
        super().__init__(master)
        self.master = master
        self.label = tk.Label(self, text="Gestión de Productos", font=TITLE_FONT)
        self.label.pack(pady=10)

        from tkinter import ttk
        style = apply_treeview_style()
        style.map("App.Treeview", background=[('selected', '#CCE5FF')])
        style.layout("App.Treeview", [
            ('Treeview.field', {'sticky': 'nswe', 'border': '1', 'children': [
                ('Treeview.padding', {'sticky': 'nswe', 'children': [
                    ('Treeview.treearea', {'sticky': 'nswe'})
                ]})
            ]})
        ])

        self.frame_tabla = tk.Frame(self)
        self.frame_tabla.pack(pady=10, padx=60, fill="x")
        self.tree = ttk.Treeview(
            self.frame_tabla,
            columns=("id", "codigo", "nombre", "precio", "precio_compra", "stock", "categoria", "visible"),
            show="headings",
            height=12,
            style="App.Treeview",
        )
        self.tree.heading("codigo", text="Código")
        self.tree.heading("nombre", text="Descripción")
        self.tree.heading("precio", text="Precio Venta")
        self.tree.heading("precio_compra", text="Precio Compra")
        self.tree.heading("stock", text="Stock")
        self.tree.heading("categoria", text="Categoría")
        self.tree.heading("visible", text="Visible")
        self.tree.column("id", width=0, stretch=False)
        self.tree.column("codigo", width=80)
        self.tree.column("nombre", width=180)
        self.tree.column("precio", width=90)
        self.tree.column("precio_compra", width=110)
        self.tree.column("stock", width=80)
        self.tree.column("categoria", width=110)
        self.tree.column("visible", width=60)
        self.tree.pack(ipadx=10, ipady=10, fill="x", expand=True)

        self.colores_categoria = {
            'Comida': '#FFDD99',
            'Bebida': '#99CCFF',
            'Otros': '#DDFFDD',
            'Sin categoría': '#F4CCCC',
        }

        self.tree.bind("<<TreeviewSelect>>", self.on_select)
        self.tree.bind("<Double-1>", self.abrir_edicion_producto)

        self.frame_form = tk.Frame(self)
        self.frame_form.pack(pady=10)
        self.btn_agregar = tk.Button(self.frame_form, text="Agregar\nNuevo", command=self.iniciar_agregar)
        apply_button_style(self.btn_agregar, style="productos")
        apply_button_style(self.btn_agregar, style="success")
        self.btn_agregar.grid(row=0, column=0, pady=6, padx=3)
        self.btn_editar = tk.Button(self.frame_form, text="Editar", command=self.abrir_edicion_producto_btn)
        apply_button_style(self.btn_editar, style="productos")
        apply_button_style(self.btn_editar, style="primary")
        self.btn_editar.grid(row=0, column=1, pady=6, padx=3)

        self.producto_seleccionado = None
        self.btn_editar.config(state='disabled')
        self.label_stock_info = tk.Label(self, text="Solo se descuenta stock si 'Contabilizar stock' está activado.", font=TEXT_FONT, fg="#555")
        self.label_stock_info.pack(pady=(0, 8))

        self.cargar_categorias()
        self.cargar_productos()

    def cargar_categorias(self):
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, descripcion FROM Categoria_Producto")
        cats = cursor.fetchall()
        conn.close()
        self.categorias = {str(cid): desc for cid, desc in cats}

    def cargar_productos(self):
        self.tree.delete(*self.tree.get_children())
        conn = get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute("""
                SELECT p.id,
                       p.codigo_producto,
                       p.nombre,
                       p.precio_venta,
                       COALESCE(p.precio_compra, p.precio_venta) AS precio_compra,
                       p.stock_actual,
                       c.descripcion,
                       p.visible,
                       COALESCE(p.contabiliza_stock,1) AS contabiliza_stock,
                       CAST(COALESCE(p.orden_visual, p.id) AS INTEGER) AS orden_visual
                FROM products p
                LEFT JOIN Categoria_Producto c ON p.categoria_id = c.id
                ORDER BY CAST(COALESCE(p.orden_visual, p.id) AS INTEGER)
            """)
        except Exception:
            cursor.execute("""
                SELECT p.id, p.codigo_producto, p.nombre, p.precio_venta,
                       p.precio_venta AS precio_compra, p.stock_actual, c.descripcion,
                       p.visible, 1 AS contabiliza_stock, p.id AS orden_visual
                FROM products p
                LEFT JOIN Categoria_Producto c ON p.categoria_id = c.id
                ORDER BY p.id
            """)
        productos = cursor.fetchall()
        conn.close()
        for pid, codigo, nombre, precio, precio_compra, stock, categoria, visible, contabiliza, _ov in productos:
            cat = categoria if categoria else 'Sin categoría'
            color = self.colores_categoria.get(cat, '#EAF1FB')
            tag = f'cat_{cat}'
            if not self.tree.tag_has(tag):
                self.tree.tag_configure(tag, background=color)
            extra = ' (No cont.)' if int(contabiliza or 1) == 0 else ''
            nombre_txt = (nombre or '') + extra
            vis_txt = 'Sí' if int(visible or 0) > 0 else 'No'
            self.tree.insert("", tk.END, values=(pid, (codigo or '').upper(), nombre_txt, precio, precio_compra, stock, categoria, vis_txt), tags=(tag,))

        self.producto_seleccionado = None
        self.btn_editar.config(state='disabled')

    def on_select(self, event):
        seleccion = self.tree.selection()
        if not seleccion:
            self.producto_seleccionado = None
            self.btn_editar.config(state='disabled')
            return
        item = self.tree.item(seleccion[0])['values']
        self.producto_seleccionado = item[0]
        self.btn_editar.config(state='normal')

    def iniciar_agregar(self):
        self._abrir_agregar_producto()

    def abrir_edicion_producto(self, event=None):
        seleccion = self.tree.selection()
        if not seleccion:
            messagebox.showwarning("Edición", "Seleccione un producto para editar.")
            return
        item = self.tree.item(seleccion[0])['values']
        self._abrir_edicion_producto(item)

    def abrir_edicion_producto_btn(self):
        seleccion = self.tree.selection()
        if not seleccion:
            messagebox.showwarning("Edición", "Seleccione un producto para editar.")
            return
        item = self.tree.item(seleccion[0])['values']
        self._abrir_edicion_producto(item)

    def cancelar_accion(self):
        self.producto_seleccionado = None
        self.btn_editar.config(state='disabled')

    def _abrir_agregar_producto(self):
        add_win = tk.Toplevel(self)
        add_win.title("Agregar Producto")
        add_win.transient(self)
        add_win.grab_set()
        ancho = 360
        alto = 600
        x = self.winfo_screenwidth() // 2 - ancho // 2
        y = self.winfo_screenheight() // 2 - alto // 2
        add_win.geometry(f"{ancho}x{alto}+{x}+{y}")

        tk.Label(add_win, text="Descripción:", font=("Arial", 12)).pack(pady=6)
        entry_nombre = tk.Entry(add_win, font=("Arial", 12))
        entry_nombre.pack(pady=2)

        tk.Label(add_win, text="Precio Venta:", font=("Arial", 12)).pack(pady=6)
        entry_precio = tk.Entry(add_win, font=("Arial", 12))
        entry_precio.pack(pady=2)

        tk.Label(add_win, text="Precio Compra:", font=("Arial", 12)).pack(pady=6)
        entry_precio_compra = tk.Entry(add_win, font=("Arial", 12))
        entry_precio_compra.pack(pady=2)

        tk.Label(add_win, text="Categoría:", font=("Arial", 12)).pack(pady=6)
        from tkinter import ttk
        combo_categoria = ttk.Combobox(add_win, values=list(self.categorias.values()), state="readonly", font=("Arial", 12))
        combo_categoria.pack(pady=2)
        combo_categoria.set('')

        var_visible = tk.IntVar(value=1)
        var_contab = tk.IntVar(value=1)
        check_visible = tk.Checkbutton(add_win, text="Visible", variable=var_visible, font=("Arial", 12))
        check_visible.pack(pady=6)

        check_contab = tk.Checkbutton(add_win, text="Contabilizar stock", variable=var_contab, font=("Arial", 12))
        check_contab.pack(pady=6)

        tk.Label(add_win, text="Stock:", font=("Arial", 12)).pack(pady=6)
        entry_stock = tk.Entry(add_win, font=("Arial", 12))
        entry_stock.pack(pady=2)

        def _toggle_stock_state():
            if var_contab.get() == 1:
                entry_stock.config(state='normal')
            else:
                entry_stock.delete(0, tk.END)
                entry_stock.insert(0, '0')
                entry_stock.config(state='disabled')

        check_contab.configure(command=_toggle_stock_state)
        _toggle_stock_state()

        frame_btns = tk.Frame(add_win)
        frame_btns.pack(pady=18)

        def confirmar():
            nombre = entry_nombre.get().strip()
            precio = entry_precio.get().strip()
            precio_compra = entry_precio_compra.get().strip()
            stock = entry_stock.get().strip()
            cat_desc_sel = combo_categoria.get().strip()
            visible = var_visible.get()
            if not nombre or not precio or not cat_desc_sel:
                messagebox.showwarning("Datos incompletos", "Complete los campos obligatorios.")
                return
            conn = get_connection()
            cursor = conn.cursor()
            codigo = generate_unique_product_code(nombre)
            try:
                precio_val = float(precio)
            except Exception:
                messagebox.showerror("Error", "Precio Venta debe ser numérico.")
                return
            try:
                precio_compra_val = float(precio_compra) if precio_compra else float(precio_val)
            except Exception:
                messagebox.showerror("Error", "Precio Compra debe ser numérico.")
                return
            if int(var_contab.get()) == 1:
                try:
                    stock_val = int(stock)
                except Exception:
                    messagebox.showerror("Error", "Stock debe ser entero.")
                    return
            else:
                stock_val = 0
            if stock_val > 999:
                messagebox.showerror("Error", "El stock máximo permitido es 999.")
                return
            if precio_val > 999999:
                messagebox.showerror("Error", "El precio máximo permitido es 999999.")
                return
            categoria_id = None
            try:
                categoria_id = [k for k, v in self.categorias.items() if v == cat_desc_sel][0]
            except Exception:
                categoria_id = None
            cursor.execute("SELECT COUNT(*) FROM products WHERE nombre=? AND categoria_id=?", (nombre, categoria_id))
            if cursor.fetchone()[0]:
                conn.close()
                messagebox.showerror("Error", "Ya existe un producto con esa descripción en la misma categoría.")
                return
            try:
                cursor.execute("SELECT COALESCE(MAX(CAST(orden_visual AS INTEGER)), 0) FROM products")
                try:
                    next_order = int((cursor.fetchone() or [0])[0]) + 1
                except Exception:
                    next_order = 1
                cursor.execute(
                    """
                    INSERT INTO products (
                        codigo_producto, nombre, precio_venta, stock_actual, stock_minimo,
                        categoria_id, precio_compra, visible, contabiliza_stock, orden_visual
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        codigo, nombre, float(precio_val), int(stock_val), 3,
                        (int(categoria_id) if categoria_id is not None else None),
                        float(precio_compra_val), int(visible), int(var_contab.get()), int(next_order)
                    )
                )
                conn.commit()
                conn.close()
                self.cargar_productos()
                add_win.destroy()
                messagebox.showinfo("Producto", "Producto agregado correctamente.")
            except Exception as e:
                conn.close()
                messagebox.showerror("Error", f"No se pudo guardar el producto.\n{e}")

        def cancelar():
            add_win.destroy()

        btn_confirmar = tk.Button(frame_btns, text="Confirmar", command=confirmar, bg="#4CAF50", fg="white", font=("Arial", 12), width=10)
        btn_confirmar.pack(side=tk.LEFT, padx=8)
        btn_cancelar = tk.Button(frame_btns, text="Cancelar", command=cancelar, font=("Arial", 12), width=10)
        btn_cancelar.pack(side=tk.LEFT, padx=8)

    def _abrir_edicion_producto(self, item):
        edit_win = tk.Toplevel(self)
        edit_win.title("Editar Producto")
        edit_win.transient(self)
        edit_win.grab_set()
        ancho = 360
        alto = 620
        x = self.winfo_screenwidth() // 2 - ancho // 2
        y = self.winfo_screenheight() // 2 - alto // 2
        edit_win.geometry(f"{ancho}x{alto}+{x}+{y}")

        # Cargar datos actuales desde DB por id
        pid = int(item[0])
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT codigo_producto, nombre, precio_venta, COALESCE(precio_compra, precio_venta) AS precio_compra,
                   stock_actual, categoria_id, visible, COALESCE(contabiliza_stock,1)
            FROM products WHERE id=?
        """, (pid,))
        row = cur.fetchone()
        conn.close()
        if not row:
            messagebox.showerror("Edición", "No se pudo cargar el producto.")
            return
        codigo_actual, nombre_actual, precio_venta_actual, precio_compra_actual, stock_actual, categoria_id_actual, visible_actual, contab_actual = row

        tk.Label(edit_win, text="Descripción:", font=("Arial", 12)).pack(pady=6)
        entry_nombre = tk.Entry(edit_win, font=("Arial", 12))
        entry_nombre.pack(pady=2)
        entry_nombre.insert(0, nombre_actual)

        tk.Label(edit_win, text="Precio Venta:", font=("Arial", 12)).pack(pady=6)
        entry_precio = tk.Entry(edit_win, font=("Arial", 12))
        entry_precio.pack(pady=2)
        entry_precio.insert(0, str(precio_venta_actual))

        tk.Label(edit_win, text="Precio Compra:", font=("Arial", 12)).pack(pady=6)
        entry_precio_compra = tk.Entry(edit_win, font=("Arial", 12))
        entry_precio_compra.pack(pady=2)
        entry_precio_compra.insert(0, str(precio_compra_actual))

        tk.Label(edit_win, text="Categoría:", font=("Arial", 12)).pack(pady=6)
        from tkinter import ttk
        combo_categoria = ttk.Combobox(edit_win, values=list(self.categorias.values()), state="readonly", font=("Arial", 12))
        combo_categoria.pack(pady=2)
        try:
            cat_desc = next((v for k, v in self.categorias.items() if int(k) == int(categoria_id_actual)), '')
            if cat_desc and cat_desc in self.categorias.values():
                combo_categoria.current(list(self.categorias.values()).index(cat_desc))
            else:
                combo_categoria.set('')
        except Exception:
            combo_categoria.set('')

        var_visible = tk.IntVar(value=1 if int(visible_actual or 0) > 0 else 0)
        var_contab = tk.IntVar(value=int(contab_actual or 1))

        check_visible = tk.Checkbutton(edit_win, text="Visible", variable=var_visible, font=("Arial", 12))
        check_visible.pack(pady=6)

        check_contab = tk.Checkbutton(edit_win, text="Contabilizar stock", variable=var_contab, font=("Arial", 12))
        check_contab.pack(pady=6)

        tk.Label(edit_win, text="Stock:", font=("Arial", 12)).pack(pady=6)
        entry_stock = tk.Entry(edit_win, font=("Arial", 12))
        entry_stock.pack(pady=2)
        entry_stock.insert(0, str(stock_actual))

        def _toggle_stock_state_edit():
            if var_contab.get() == 1:
                entry_stock.config(state='normal')
            else:
                entry_stock.delete(0, tk.END)
                entry_stock.insert(0, '0')
                entry_stock.config(state='disabled')

        check_contab.configure(command=_toggle_stock_state_edit)
        _toggle_stock_state_edit()

        frame_btns = tk.Frame(edit_win)
        frame_btns.pack(pady=18)

        def confirmar():
            nombre = entry_nombre.get().strip()
            precio = entry_precio.get().strip()
            precio_compra = entry_precio_compra.get().strip()
            stock = entry_stock.get().strip()
            cat_desc_sel = combo_categoria.get().strip()
            visible = var_visible.get()
            if not nombre or not precio:
                messagebox.showwarning("Datos incompletos", "Complete los campos obligatorios.")
                return
            conn = get_connection()
            cursor = conn.cursor()
            try:
                precio_val = float(precio)
                precio_compra_val = float(precio_compra) if precio_compra else float(precio_val)
            except Exception:
                messagebox.showerror("Error", "Los precios deben ser numéricos.")
                return
            if int(var_contab.get()) == 1:
                try:
                    stock_val = int(stock)
                except Exception:
                    messagebox.showerror("Error", "Stock debe ser entero.")
                    return
            else:
                stock_val = 0
            if stock_val > 999:
                messagebox.showerror("Error", "El stock máximo permitido es 999.")
                return
            if precio_val > 999999:
                messagebox.showerror("Error", "El precio máximo permitido es 999999.")
                return
            categoria_id = None
            try:
                categoria_id = [k for k, v in self.categorias.items() if v == cat_desc_sel][0]
            except Exception:
                categoria_id = None
            cursor.execute("SELECT COUNT(*) FROM products WHERE nombre=? AND categoria_id=? AND id<>?", (nombre, categoria_id, pid))
            if cursor.fetchone()[0]:
                conn.close()
                messagebox.showerror("Error", "Ya existe un producto con esa descripción en la misma categoría.")
                return
            try:
                # Generar código si está vacío
                code_to_set = None
                try:
                    cursor.execute("SELECT codigo_producto FROM products WHERE id=?", (pid,))
                    rcode = cursor.fetchone()
                    current_code = (rcode[0] if rcode else None)
                    if not current_code or not str(current_code).strip():
                        code_to_set = generate_unique_product_code(nombre)
                except Exception:
                    code_to_set = None

                if code_to_set:
                    cursor.execute(
                        "UPDATE products SET codigo_producto=?, nombre=?, precio_venta=?, precio_compra=?, stock_actual=?, categoria_id=?, visible=?, contabiliza_stock=? WHERE id=?",
                        (code_to_set, nombre, float(precio_val), float(precio_compra_val), int(stock_val), (int(categoria_id) if categoria_id is not None else None), int(visible), int(var_contab.get()), pid)
                    )
                else:
                    cursor.execute(
                        "UPDATE products SET nombre=?, precio_venta=?, precio_compra=?, stock_actual=?, categoria_id=?, visible=?, contabiliza_stock=? WHERE id=?",
                        (nombre, float(precio_val), float(precio_compra_val), int(stock_val), (int(categoria_id) if categoria_id is not None else None), int(visible), int(var_contab.get()), pid)
                    )
                conn.commit()
                conn.close()
                self.cargar_productos()
                edit_win.destroy()
                messagebox.showinfo("Producto", "Producto editado correctamente.")
            except Exception as e:
                conn.close()
                messagebox.showerror("Error", f"No se pudo guardar el producto.\n{e}")

        def cancelar():
            edit_win.destroy()

        btn_confirmar = tk.Button(frame_btns, text="Confirmar", command=confirmar, bg="#4CAF50", fg="white", font=("Arial", 12), width=10)
        btn_confirmar.pack(side=tk.LEFT, padx=8)
        btn_cancelar = tk.Button(frame_btns, text="Cancelar", command=cancelar, font=("Arial", 12), width=10)
        btn_cancelar.pack(side=tk.LEFT, padx=8)
