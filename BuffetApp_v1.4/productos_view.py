import tkinter as tk
from tkinter import messagebox
from db_utils import get_connection
from theme import (
    TITLE_FONT,
    TEXT_FONT,
    apply_button_style,
    apply_treeview_style,
)

class ProductosView(tk.Frame):
    def actualizar_estilos(self, config):
        # Actualiza los estilos de los widgets según la configuración recibida
        self.btn_ancho = config.get("ancho_boton", 20)
        self.btn_alto = config.get("alto_boton", 2)
        self.btn_font = config.get("fuente_boton", "Arial")
        self.color_boton = config.get("color_boton", "#f0f0f0")
        # Si tienes botones personalizados, aquí puedes actualizar su configuración
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
            columns=("id", "codigo", "nombre", "precio", "stock", "categoria", "activo", "visible"),
            show="headings",
            height=10,
            style="App.Treeview",
        )
        self.tree.heading("codigo", text="Código")
        self.tree.heading("nombre", text="Descripción")
        self.tree.heading("precio", text="Precio Venta")
        self.tree.heading("stock", text="Stock")
        self.tree.heading("categoria", text="Categoría")
        self.tree.heading("visible", text="Visible")
        self.tree.column("id", width=0, stretch=False)
        self.tree.column("codigo", width=80)
        self.tree.column("nombre", width=150)
        self.tree.column("precio", width=80)
        self.tree.column("stock", width=80)
        self.tree.column("categoria", width=110)
        self.tree.column("activo", width=0, stretch=False)
        self.tree.column("visible", width=60)
        self.tree.pack(ipadx=10, ipady=5, fill="x", expand=True)
        # Colores por categoría
        # Colores iguales a ventas_view.py
        self.colores_categoria = {
            'Comida': '#FFDD99',
            'Bebida': '#99CCFF',
            'Otros': '#DDFFDD',
            'Sin categoría': '#F4CCCC',
        }
        # Se crearán tags dinámicamente por cada categoría encontrada
        self.tree.bind("<<TreeviewSelect>>", self.on_select)
        self.tree.bind("<Double-1>", self.abrir_edicion_producto)

        self.frame_form = tk.Frame(self)
        self.frame_form.pack(pady=10)
        tk.Label(self.frame_form, text="Código:", font=TEXT_FONT).grid(row=0, column=0, padx=3, pady=3, sticky="e")

        self.entry_codigo = tk.Entry(self.frame_form, width=6, font=TEXT_FONT, state='disabled')
        self.entry_codigo.grid(row=0, column=1, padx=3, pady=3)
        self.entry_codigo.bind("<KeyRelease>", self._codigo_keyrelease)

        tk.Label(self.frame_form, text="Descripción:", font=TEXT_FONT).grid(row=1, column=0, padx=3, pady=3, sticky="e")
        self.entry_nombre = tk.Entry(self.frame_form, width=18, font=TEXT_FONT, state='disabled')
        self.entry_nombre.grid(row=1, column=1, padx=3, pady=3)
        tk.Label(self.frame_form, text="Precio Venta:", font=TEXT_FONT).grid(row=2, column=0, padx=3, pady=3, sticky="e")
        self.entry_precio = tk.Entry(self.frame_form, width=8, font=TEXT_FONT, state='disabled')
        self.entry_precio.grid(row=2, column=1, padx=3, pady=3)
        tk.Label(self.frame_form, text="Stock: ", font=TEXT_FONT).grid(row=3, column=0, padx=3, pady=3, sticky="e")
        self.entry_stock = tk.Entry(self.frame_form, width=8, font=TEXT_FONT, state='disabled')
        self.entry_stock.grid(row=3, column=1, padx=3, pady=3)
        tk.Label(self.frame_form, text="Categoría:", font=TEXT_FONT).grid(row=4, column=0, padx=3, pady=3, sticky="e")
        self.combo_categoria = ttk.Combobox(self.frame_form, state="disabled", width=12, font=TEXT_FONT)
        self.combo_categoria.grid(row=4, column=1, padx=3, pady=3)
        self.var_visible = tk.IntVar()
        self.check_visible = tk.Checkbutton(self.frame_form, text="Visible", variable=self.var_visible, state='disabled', font=TEXT_FONT)
        self.check_visible.grid(row=5, column=1, padx=3, pady=3, sticky="w")

        self.btn_agregar = tk.Button(
            self.frame_form,
            text="Agregar\nNuevo",
            command=self.iniciar_agregar,
        )
        apply_button_style(
            self.btn_agregar,
            style="productos",
            bg="white",
            fg="#388E3C",
            activebackground="#E8F5E9",
            activeforeground="#388E3C",
        )
        self.btn_agregar.grid(row=6, column=0, pady=6, padx=3)
        self.btn_editar = tk.Button(self.frame_form, text="Editar", command=self.abrir_edicion_producto_btn)
        apply_button_style(self.btn_editar, style="productos")

        self.btn_editar.grid(row=6, column=1, pady=6, padx=3)
        self.btn_eliminar = tk.Button(self.frame_form, text="Eliminar", command=self.eliminar_producto)
        apply_button_style(
            self.btn_eliminar,
            style="productos",
            bg="#E53935",
            fg="white",
            activebackground="#B71C1C",
        )
        self.btn_eliminar.grid(row=6, column=2, pady=6, padx=3)

        self.btn_confirmar = tk.Button(self.frame_form, text="Confirmar", command=self.confirmar_accion)
        apply_button_style(
            self.btn_confirmar,
            style="productos",
            bg="#4CAF50",
            fg="white",
            activebackground="#45A049",
        )
        self.btn_cancelar = tk.Button(self.frame_form, text="Cancelar", command=self.cancelar_accion)
        apply_button_style(self.btn_cancelar, style="productos")
        self.btn_confirmar.grid(row=7, column=0, pady=6, padx=3)
        self.btn_cancelar.grid(row=7, column=1, pady=6, padx=3)
        self.btn_confirmar.grid_remove()
        self.btn_cancelar.grid_remove()

        self.producto_seleccionado = None
        self.modo = None # 'editar' o 'agregar'
        self.label_stock_info = tk.Label(self, text="Si el Stock es 999, no se descuenta al realizar una venta.", font=TEXT_FONT, fg="#555")
        self.label_stock_info.pack(pady=(0,8))
        self.cargar_categorias()
        self.cargar_productos()

    def cargar_categorias(self):
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, descripcion FROM Categoria_Producto")
        cats = cursor.fetchall()
        conn.close()
        self.categorias = {str(cid): desc for cid, desc in cats}
        self.combo_categoria['values'] = list(self.categorias.values())

    def cargar_productos(self):
        self.tree.delete(*self.tree.get_children())
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT p.id, p.codigo_producto, p.nombre, p.precio_venta, p.stock_actual, c.descripcion, p.stock_minimo, p.categoria_id, p.visible FROM products p LEFT JOIN Categoria_Producto c ON p.categoria_id = c.id")
        productos = cursor.fetchall()
        conn.close()
        for idx, (pid, codigo, nombre, precio, stock, categoria, activo, categoria_id, visible) in enumerate(productos):
            cat = categoria if categoria else 'Sin categoría'
            color = self.colores_categoria.get(cat, '#EAF1FB')
            tag = f'cat_{cat}'
            if not self.tree.tag_has(tag):
                self.tree.tag_configure(tag, background=color)

            self.tree.insert("", tk.END, values=(pid, (codigo or '').upper(), nombre, precio, stock, categoria, 'Sí' if activo > 0 else 'No', 'Sí' if visible else 'No'), tags=(tag,))

        self.cancelar_accion()

    def on_select(self, event):
        seleccion = self.tree.selection()
        if not seleccion:
            self.producto_seleccionado = None
            self.cancelar_accion()
            return
        item = self.tree.item(seleccion[0])['values']
        self.producto_seleccionado = item[0]
        self.entry_codigo.config(state='disabled')
        self.entry_nombre.config(state='disabled')
        self.entry_precio.config(state='disabled')
        self.entry_stock.config(state='disabled')
        self.combo_categoria.config(state='disabled')
        self.check_visible.config(state='disabled')
        self.entry_codigo.delete(0, tk.END)

        self.entry_codigo.insert(0, str(item[1]).upper())

        self.entry_nombre.delete(0, tk.END)
        self.entry_nombre.insert(0, item[2])
        self.entry_precio.delete(0, tk.END)
        self.entry_precio.insert(0, item[3])
        self.entry_stock.delete(0, tk.END)
        self.entry_stock.insert(0, item[4])
        cat_desc = item[5]
        idx = list(self.categorias.values()).index(cat_desc) if cat_desc in self.categorias.values() else 0
        self.combo_categoria.current(idx)
        self.var_visible.set(1 if item[7] == 'Sí' else 0)
        self.btn_confirmar.grid_remove()
        self.btn_cancelar.grid_remove()
        self.modo = None
        self.btn_agregar.config(state='normal', fg='black')
        self.btn_editar.config(state='normal', fg='black')
        self.btn_eliminar.config(state='normal', fg='black')

    def bloquear_botones_accion(self, modo):
        # Solo deja habilitados Confirmar y Cancelar
        self.btn_agregar.config(state='disabled', fg='gray')
        self.btn_editar.config(state='disabled', fg='gray')
        self.btn_eliminar.config(state='disabled', fg='gray')
        self.btn_confirmar.config(state='normal', fg='black')
        self.btn_cancelar.config(state='normal', fg='black')

    def desbloquear_botones_accion(self):
        self.btn_agregar.config(state='normal', fg='black')
        self.btn_editar.config(state='normal', fg='black')
        self.btn_eliminar.config(state='normal', fg='black')
        self.btn_confirmar.config(state='disabled', fg='gray')
        self.btn_cancelar.config(state='disabled', fg='gray')

    def iniciar_editar(self):
        if not self.producto_seleccionado:
            messagebox.showwarning("Edición", "Seleccione un producto para editar.")
            return
        self.entry_nombre.config(state='normal')
        self.entry_precio.config(state='normal')
        self.entry_stock.config(state='normal')
        self.combo_categoria.config(state='readonly')
        self.check_visible.config(state='normal')
        self.btn_confirmar.grid()
        self.btn_cancelar.grid()
        self.modo = 'editar'
        self.bloquear_botones_accion('editar')
        # Completar campos con valores del producto seleccionado
        seleccion = self.tree.selection()
        if seleccion:
            item = self.tree.item(seleccion[0])['values']
            self.entry_nombre.delete(0, tk.END)
            self.entry_nombre.insert(0, item[1])
            self.entry_precio.delete(0, tk.END)
            self.entry_precio.insert(0, item[2])
            self.entry_stock.delete(0, tk.END)
            self.entry_stock.insert(0, item[3])
            cat_desc = item[4]
            idx = list(self.categorias.values()).index(cat_desc) if cat_desc in self.categorias.values() else 0
            self.combo_categoria.current(idx)
            self.var_visible.set(1 if item[6] == 'Sí' else 0)

    def iniciar_agregar(self):
        self.producto_seleccionado = None
        self.entry_codigo.config(state='normal')
        self.entry_nombre.config(state='normal')
        self.entry_precio.config(state='normal')
        self.entry_stock.config(state='normal')
        self.combo_categoria.config(state='readonly')
        self.check_visible.config(state='normal')
        self.entry_codigo.delete(0, tk.END)
        self.entry_nombre.delete(0, tk.END)
        self.entry_precio.delete(0, tk.END)
        self.entry_stock.delete(0, tk.END)
        self.combo_categoria.set('')
        self.var_visible.set(1)
        self.btn_confirmar.grid()
        self.btn_cancelar.grid()
        self.modo = 'agregar'
        self.bloquear_botones_accion('agregar')

    def _codigo_keyrelease(self, event):
        valor = self.entry_codigo.get().upper()[:4]
        if self.entry_codigo.get() != valor:
            self.entry_codigo.delete(0, tk.END)
            self.entry_codigo.insert(0, valor)

    def cancelar_accion(self):
        self.entry_codigo.config(state='disabled')
        self.entry_nombre.config(state='disabled')
        self.entry_precio.config(state='disabled')
        self.entry_stock.config(state='disabled')
        self.combo_categoria.config(state='disabled')
        self.check_visible.config(state='disabled')
        self.btn_confirmar.grid_remove()
        self.btn_cancelar.grid_remove()
        self.modo = None
        self.producto_seleccionado = None
        self.entry_codigo.delete(0, tk.END)
        self.entry_nombre.delete(0, tk.END)
        self.entry_precio.delete(0, tk.END)
        self.entry_stock.delete(0, tk.END)
        self.combo_categoria.set('')
        self.var_visible.set(1)
        self.desbloquear_botones_accion()

    def confirmar_accion(self):

        codigo = self.entry_codigo.get().strip().upper()
        if len(codigo) > 4:
            messagebox.showwarning("Datos incompletos", "El código debe tener hasta 4 caracteres.")
            return

        nombre = self.entry_nombre.get().strip()
        precio = self.entry_precio.get().strip()
        stock = self.entry_stock.get().strip()
        cat_desc = self.combo_categoria.get().strip()
        visible = self.var_visible.get()
        if not codigo or not nombre or not precio or not stock or not cat_desc:
            messagebox.showwarning("Datos incompletos", "Complete todos los campos.")
            return
        try:
            precio_val = float(precio)
            stock_val = int(stock)
        except Exception:
            messagebox.showerror("Error", "Precio y Stock deben ser valores numéricos.")
            return
        if stock_val > 999:
            messagebox.showerror("Error", "El stock máximo permitido es 999.")
            return
        if precio_val > 999999:
            messagebox.showerror("Error", "El precio máximo permitido es 999999.")
            return
        categoria_id = [k for k, v in self.categorias.items() if v == cat_desc][0]
        conn = get_connection()
        cursor = conn.cursor()
        # Validar que no exista el producto en la misma categoría
        cursor.execute("SELECT COUNT(*) FROM products WHERE nombre=? AND categoria_id=?", (nombre, categoria_id))
        existe = cursor.fetchone()[0]
        if self.modo == 'agregar' and existe:
            conn.close()
            messagebox.showerror("Error", "Ya existe un producto con esa descripción en la misma categoría.")
            return
        if self.modo == 'editar' and existe and nombre != self.tree.item(self.tree.selection()[0])['values'][1]:
            conn.close()
            messagebox.showerror("Error", "Ya existe un producto con esa descripción en la misma categoría.")
            return
        try:
            if self.modo == 'agregar':
                cursor.execute("INSERT INTO products (codigo_producto, nombre, precio_venta, stock_actual, stock_minimo, categoria_id, precio_compra, visible) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                               (codigo, nombre, precio_val, stock_val, 3, int(categoria_id), 0, visible))
                messagebox.showinfo("Producto", "Producto agregado correctamente.")
            elif self.modo == 'editar':
                cursor.execute("UPDATE products SET codigo_producto=?, nombre=?, precio_venta=?, stock_actual=?, categoria_id=?, visible=? WHERE id=?",
                               (codigo, nombre, precio_val, stock_val, int(categoria_id), visible, self.producto_seleccionado))
                messagebox.showinfo("Producto", "Producto editado correctamente.")
            conn.commit()
            conn.close()
            self.cargar_productos()
            self.cancelar_accion()
        except Exception as e:
            conn.close()
            messagebox.showerror("Error", f"No se pudo guardar el producto.\n{e}")

    def eliminar_producto(self):
        if not self.producto_seleccionado:
            messagebox.showwarning("Eliminación", "Seleccione un producto para eliminar.")
            return
        # Confirmación antes de eliminar
        nombre = None
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT nombre FROM products WHERE id=?", (self.producto_seleccionado,))
            row = cursor.fetchone()
            if row:
                nombre = row[0]
            conn.close()
        except Exception:
            pass
        confirmar = messagebox.askyesno("Confirmar eliminación", f"¿Está seguro que desea eliminar el producto '{nombre if nombre else ''}'?")
        if not confirmar:
            return
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("DELETE FROM products WHERE id=?", (self.producto_seleccionado,))
            conn.commit()
            conn.close()
            self.cargar_productos()
            messagebox.showinfo("Producto", "Producto eliminado definitivamente.")
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo eliminar el producto.\n{e}")
        self.cancelar_accion()
        self.bloquear_botones(self.btn_eliminar)

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

    def _abrir_edicion_producto(self, item):
        edit_win = tk.Toplevel(self)
        edit_win.title("Editar Producto")
        edit_win.transient(self)
        edit_win.grab_set()
        # Centrar ventana en pantalla y aumentar altura
        ancho = 350
        alto = 480
        x = self.winfo_screenwidth() // 2 - ancho // 2
        y = self.winfo_screenheight() // 2 - alto // 2
        edit_win.geometry(f"{ancho}x{alto}+{x}+{y}")
        tk.Label(edit_win, text="Código:", font=("Arial", 12)).pack(pady=6)
        entry_codigo = tk.Entry(edit_win, font=("Arial", 12))
        entry_codigo.pack(pady=2)
        entry_codigo.insert(0, item[1])
        tk.Label(edit_win, text="Descripción:", font=("Arial", 12)).pack(pady=6)
        entry_nombre = tk.Entry(edit_win, font=("Arial", 12))
        entry_nombre.pack(pady=2)
        entry_nombre.insert(0, item[2])
        tk.Label(edit_win, text="Precio Venta:", font=("Arial", 12)).pack(pady=6)
        entry_precio = tk.Entry(edit_win, font=("Arial", 12))
        entry_precio.pack(pady=2)
        entry_precio.insert(0, item[3])
        tk.Label(edit_win, text="Stock:", font=("Arial", 12)).pack(pady=6)
        entry_stock = tk.Entry(edit_win, font=("Arial", 12))
        entry_stock.pack(pady=2)
        entry_stock.insert(0, item[4])
        tk.Label(edit_win, text="Categoría:", font=("Arial", 12)).pack(pady=6)
        from tkinter import ttk
        combo_categoria = ttk.Combobox(edit_win, values=list(self.categorias.values()), state="readonly", font=("Arial", 12))
        combo_categoria.pack(pady=2)
        cat_desc = item[5]
        idx = list(self.categorias.values()).index(cat_desc) if cat_desc in self.categorias.values() else 0
        combo_categoria.current(idx)
        var_visible = tk.IntVar(value=1 if item[7] == 'Sí' else 0)
        check_visible = tk.Checkbutton(edit_win, text="Visible", variable=var_visible, font=("Arial", 12))
        check_visible.pack(pady=6)
        frame_btns = tk.Frame(edit_win)
        frame_btns.pack(pady=18)
        def confirmar():
            codigo = entry_codigo.get().strip()
            nombre = entry_nombre.get().strip()
            precio = entry_precio.get().strip()
            stock = entry_stock.get().strip()
            cat_desc_sel = combo_categoria.get().strip()
            visible = var_visible.get()
            if not codigo or not nombre or not precio or not stock or not cat_desc_sel:
                messagebox.showwarning("Datos incompletos", "Complete todos los campos.")
                return
            try:
                precio_val = float(precio)
                stock_val = int(stock)
            except Exception:
                messagebox.showerror("Error", "Precio y Stock deben ser valores numéricos.")
                return
            if stock_val > 999:
                messagebox.showerror("Error", "El stock máximo permitido es 999.")
                return
            if precio_val > 999999:
                messagebox.showerror("Error", "El precio máximo permitido es 999999.")
                return
            categoria_id = [k for k, v in self.categorias.items() if v == cat_desc_sel][0]
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM products WHERE nombre=? AND categoria_id=? AND id<>?", (nombre, categoria_id, item[0]))
            existe = cursor.fetchone()[0]
            if existe:
                conn.close()
                messagebox.showerror("Error", "Ya existe un producto con esa descripción en la misma categoría.")
                return
            try:
                cursor.execute("UPDATE products SET codigo_producto=?, nombre=?, precio_venta=?, stock_actual=?, categoria_id=?, visible=? WHERE id=?",
                               (codigo, nombre, precio_val, stock_val, int(categoria_id), visible, item[0]))
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
