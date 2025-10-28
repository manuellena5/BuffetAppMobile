import tkinter as tk
from tkinter import messagebox
from db_utils import get_connection
from theme import FONT_FAMILY, CART
try:
    from theme import SALES_GRID as _SALES_GRID
except Exception:
    _SALES_GRID = None

# Utilidad para cargar productos

def cargar_productos():
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute('''
            SELECT p.id, p.nombre, p.precio_venta, p.stock_actual, p.visible, p.codigo_producto,
                   COALESCE(p.contabiliza_stock,1) AS contabiliza_stock,
                   CAST(COALESCE(p.orden_visual, p.id) AS INTEGER) AS orden_visual
            FROM products p
            WHERE p.visible = 1
            ORDER BY CAST(COALESCE(p.orden_visual, p.id) AS INTEGER)
        ''')
    except Exception:
        cursor.execute('''
            SELECT p.id, p.nombre, p.precio_venta, p.stock_actual, p.visible, p.codigo_producto,
                   1 as contabiliza_stock, p.id as orden_visual
            FROM products p
            WHERE p.visible = 1
            ORDER BY p.id
        ''')
    productos = cursor.fetchall()
    conn.close()
    return productos

def cargar_metodos_pago():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT id, descripcion FROM metodos_pago ORDER BY id")
    rows = cur.fetchall()
    conn.close()
    return rows

class VentasViewNew(tk.Frame):
    def __init__(self, master, cobrar_callback, imprimir_ticket_callback, on_tickets_impresos=None, *args, **kwargs):
        # Extraer controller de kwargs antes de inicializar tk.Frame para evitar pasar una opción desconocida
        self.controller = kwargs.pop('controller', None)
        super().__init__(master, *args, **kwargs)
        self.cobrar_callback = cobrar_callback
        self.imprimir_ticket_callback = imprimir_ticket_callback
        self.on_tickets_impresos = on_tickets_impresos
        # Controller opcional para abrir vistas externas (menú principal, tickets, stock, etc.) ya extraído arriba
        self.productos = cargar_productos()
        self.stock_dict = {prod[0]: prod[3] for prod in self.productos}
        self.carrito = []  # [id, nombre, precio, cantidad]
        self.imprimir_ticket_var = tk.BooleanVar(value=True)
        self.modo_orden = tk.BooleanVar(value=False)
        self.productos_ordenados = None  # lista temporal cuando se activa Ordenar
        self._build_layout()
        self._draw_productos()
        self._draw_carrito()
        self._bind_shortcuts()

    def _build_layout(self):
        self.config(bg="#F3F4F6")
        self.grid_columnconfigure(0, weight=3)
        self.grid_columnconfigure(1, weight=2)
        self.grid_rowconfigure(0, weight=1)
        # Contenedor izquierdo: acciones arriba (pack) y panel de productos abajo (grid internamente)
        self.left_container = tk.Frame(self, bg="#F8FAFC")
        self.left_container.grid(row=0, column=0, sticky="nsew", padx=(16,8), pady=16)
        # Barra de acciones superior (orden requerido)
        top_actions = tk.Frame(self.left_container, bg="#F8FAFC")
        top_actions.pack(fill="x", padx=8, pady=(8,4))
        # Menú principal
        tk.Button(top_actions, text="Menú principal", command=lambda: getattr(self.controller, 'mostrar_menu_principal', lambda: None)(), bg="#E5E7EB", font=(FONT_FAMILY, 10)).pack(side="left")
        # Actualizar
        btn_reload = tk.Button(top_actions, text="Actualizar", command=self.recargar_productos, bg="#E5E7EB", font=(FONT_FAMILY, 10))
        btn_reload.pack(side="left", padx=(8,0))
        
        def _toggle_modo_orden():
            # Activar/desactivar modo ordenar. Al guardar, persistimos orden en DB.
            if not self.modo_orden.get():
                self.productos_ordenados = list(self.productos)
                self.modo_orden.set(True)
                try:
                    self._btn_orden.configure(text="Guardar orden")
                except Exception:
                    pass
                self._draw_productos()
            else:
                # Guardar orden en DB y salir
                try:
                    if isinstance(self.productos_ordenados, list) and self.productos_ordenados:
                        self._guardar_orden_db(self.productos_ordenados)
                except Exception:
                    pass
                self.productos_ordenados = None
                self.modo_orden.set(False)
                try:
                    self._btn_orden.configure(text="Ordenar productos")
                except Exception:
                    pass
                self.recargar_productos()
        btn_orden = tk.Button(top_actions, text="Ordenar productos", command=_toggle_modo_orden, bg="#E5E7EB", font=(FONT_FAMILY, 10))
        btn_orden.pack(side="left", padx=8)
        self._btn_orden = btn_orden

        # Productos | Stock/Precios (modal)
        tk.Button(
            top_actions,
            text="Productos | Stock/Precios",
            command=lambda: getattr(self.controller, 'abrir_stock_window', lambda: None)(),
            bg="#E5E7EB", font=(FONT_FAMILY, 10)
        ).pack(side="left", padx=8)

        # Tickets (caja actual)
        tk.Button(top_actions, text="Tickets", command=lambda: getattr(self.controller, 'mostrar_tickets_hoy', lambda: None)(), bg="#E5E7EB", font=(FONT_FAMILY, 10)).pack(side="left", padx=8)

        # Cerrar caja
        tk.Button(top_actions, text="Cerrar caja", command=lambda: getattr(self.controller, 'cerrar_caja_window', lambda: None)(), bg="#E5E7EB", font=(FONT_FAMILY, 10)).pack(side="left", padx=8)
        # Panel productos con scrollbar (canvas + frame interno)
        canvas_frame = tk.Frame(self.left_container, bg="#F8FAFC")
        canvas_frame.pack(fill="both", expand=True)
        self.panel_canvas = tk.Canvas(canvas_frame, bg="#F8FAFC", highlightthickness=0)
        vscroll = tk.Scrollbar(canvas_frame, orient=tk.VERTICAL, command=self.panel_canvas.yview)
        self.panel_canvas.configure(yscrollcommand=vscroll.set)
        vscroll.pack(side="right", fill="y")
        self.panel_canvas.pack(side="left", fill="both", expand=True)
        # frame interno donde dibujaremos las tarjetas
        self.panel_productos = tk.Frame(self.panel_canvas, bg="#F8FAFC")
        self.panel_canvas.create_window((0, 0), window=self.panel_productos, anchor="nw")
        # actualizar scrollregion cuando cambie el frame
        def _on_frame_config(event):
            self.panel_canvas.configure(scrollregion=self.panel_canvas.bbox("all"))
        self.panel_productos.bind('<Configure>', _on_frame_config)
        # permitir scroll con rueda del mouse
        def _on_mousewheel(event):
            # cross-platform delta normalization
            delta = 0
            try:
                if event.delta:
                    delta = -1 if event.delta > 0 else 1
            except Exception:
                if event.num == 4:
                    delta = -1
                elif event.num == 5:
                    delta = 1
            self.panel_canvas.yview_scroll(delta, "units")
        # vincular al canvas para capturar eventos mientras el mouse esté sobre la zona
        self.panel_canvas.bind_all('<MouseWheel>', _on_mousewheel)
        self.panel_canvas.bind_all('<Button-4>', _on_mousewheel)
        self.panel_canvas.bind_all('<Button-5>', _on_mousewheel)
        # Panel carrito
        self.panel_carrito = tk.Frame(self, bg="#FFFFFF", bd=1, relief="solid")
        self.panel_carrito.grid(row=0, column=1, sticky="nsew", padx=(8,16), pady=16)

    def _draw_productos(self):
        # Limpiar todas las tarjetas actuales antes de redibujar
        for w in self.panel_productos.winfo_children():
            try:
                w.destroy()
            except Exception:
                pass
        # Medidas y espaciados (configurables desde theme.SALES_GRID)
        if _SALES_GRID and isinstance(_SALES_GRID, dict):
            self.card_width = int(_SALES_GRID.get('card_width', 260))
            self.card_height = int(_SALES_GRID.get('card_height', 110))
            self.card_padx = int(_SALES_GRID.get('card_padx', 8))
            self.card_pady = int(_SALES_GRID.get('card_pady', 10))
            self.max_cols = int(_SALES_GRID.get('columns', 3))
        else:
            self.card_width = 260
            self.card_height = 110
            self.card_padx = 8
            self.card_pady = 10
            self.max_cols = 3
        self.botones_funcion = []
        self._cards = []
        # Igualar ancho al original (card_width) para las 3 columnas, sin expansión extra
        min_col_w = self.card_width + self.card_padx * 2
        for c in range(self.max_cols):
            # uniform mantiene las 3 columnas con el mismo ancho base; weight=0 evita que se expandan
            self.panel_productos.grid_columnconfigure(c, weight=0, uniform='prod', minsize=min_col_w)

        # Fuente de productos: en modo ordenar usar lista temporal
        productos_src = self.productos_ordenados if (self.modo_orden.get() and isinstance(self.productos_ordenados, list)) else self.productos
        # dibujar todos los productos; el canvas proveerá scroll si no entran
        for idx, prod in enumerate(productos_src):
            # Manejar filas con/sin columna contabiliza_stock
            try:
                prod_id, nombre, precio, stock, _visible, _codigo, contabiliza, orden_visual = prod
            except Exception:
                prod_id, nombre, precio, stock, _visible, _codigo = prod
                contabiliza = 1
                orden_visual = idx + 1
            tecla = f"F{idx+1}"
            fila = idx // self.max_cols
            col = idx % self.max_cols
            card = tk.Frame(self.panel_productos, bg="#FFFFFF", bd=2, relief="groove", width=self.card_width, height=self.card_height)
            card.grid(row=fila, column=col, padx=self.card_padx, pady=self.card_pady, sticky="nsew")
            card.grid_propagate(False)
            name_lbl = tk.Label(
                card,
                text=nombre,
                font=(FONT_FAMILY, 16, "bold"),
                bg="#FFFFFF",
                anchor="w",
                justify="left"
            )
            name_lbl.pack(side="top", anchor="w", padx=16, pady=(10,0))
            price_lbl = tk.Label(card, text=f"$ {precio:,.0f}", font=(FONT_FAMILY, 14), fg="#059669", bg="#FFFFFF")
            price_lbl.pack(side="top", anchor="w", padx=16)
            # Mostrar stock sólo si contabiliza_stock=1
            stock_lbl = None
            try:
                mostrar_stock = int(contabiliza) == 1
            except Exception:
                mostrar_stock = True
            if mostrar_stock:
                display_stock = self.stock_dict.get(prod_id, 0)
                stock_lbl = tk.Label(card, text=f"Stock: {display_stock}", font=(FONT_FAMILY, 11), fg="#475569", bg="#FFFFFF")
                stock_lbl.pack(side="top", anchor="w", padx=16)
            # (El botón "Agregar" fue removido; la tarjeta es clicable)
            tecla_lbl = tk.Label(card, text=tecla, font=(FONT_FAMILY,10), fg="#475569", bg="#FFFFFF")
            tecla_lbl.pack(side="right", padx=8, pady=10)
            # Estilizar la tarjeta para que parezca un botón
            try:
                card.config(relief='raised', bd=2, highlightthickness=0, cursor='hand2')
            except Exception:
                pass

            # Animación visual: cambio de fondo al hover y al click
            def _on_click(e, p=prod, widget=card):
                try:
                    # Animación simple al click (cambiar fondo y restaurar después)
                    orig = getattr(widget, '_orig_bg', widget.cget('bg'))
                    widget.config(bg='#E6EEF8')
                    self.after(120, lambda w=widget, o=orig: (w.config(bg=o) if (hasattr(w, 'winfo_exists') and w.winfo_exists()) else None))
                except Exception:
                    pass
                # Agregar producto
                try:
                    self._agregar_al_carrito(p)
                except Exception:
                    pass

            # Bind only click on the card and its children. Removed Enter/Leave hover handlers to avoid resizes/flicker.
            try:
                card.unbind('<Enter>')
                card.unbind('<Leave>')
            except Exception:
                pass
            try:
                if not self.modo_orden.get():
                    card.bind('<Button-1>', _on_click)
            except Exception:
                pass
            bindables = [name_lbl, price_lbl, tecla_lbl]
            if stock_lbl is not None:
                bindables.insert(2, stock_lbl)
            for w in bindables:
                try:
                    w.unbind('<Enter>')
                    w.unbind('<Leave>')
                except Exception:
                    pass
                try:
                    if not self.modo_orden.get():
                        w.bind('<Button-1>', lambda e, p=prod, widget=card: _on_click(e, p, widget))
                except Exception:
                    pass
            # Controles de orden en modo ordenar
            if self.modo_orden.get():
                ctrl = tk.Frame(card, bg="#FFFFFF")
                ctrl.pack(side="bottom", fill="x", padx=12, pady=6)
                # ← mueve a la izquierda (índice-1), → mueve a la derecha (índice+1)
                btn_up = tk.Button(ctrl, text="←", width=3, command=lambda i=idx: self._mover_por_indice(i, -1))
                btn_dn = tk.Button(ctrl, text="→", width=3, command=lambda i=idx: self._mover_por_indice(i, 1))
                btn_up.pack(side="left", padx=2)
                btn_dn.pack(side="left", padx=2)
                # Deshabilitar flechas inválidas (al inicio/fin)
                try:
                    total_items = len(productos_src)
                    if idx == 0:
                        btn_up.configure(state='disabled')
                    if idx == total_items - 1:
                        btn_dn.configure(state='disabled')
                except Exception:
                    pass

            # Guardar referencia por si se quiere usar más adelante
            self.botones_funcion.append(lambda e=None, p=prod: self._agregar_al_carrito(p))
            card._idx = idx
            self._cards.append(card)

    def _mover_por_indice(self, idx_from, delta):
        """En modo ordenar, mover producto en memoria y redibujar."""
        if not self.modo_orden.get() or not isinstance(self.productos_ordenados, list):
            return
        total = len(self.productos_ordenados)
        if total <= 1:
            return
        idx_to = idx_from + delta
        if idx_to < 0 or idx_to >= total:
            return
        try:
            self.productos_ordenados[idx_from], self.productos_ordenados[idx_to] = (
                self.productos_ordenados[idx_to], self.productos_ordenados[idx_from]
            )
            self._draw_productos()
        except Exception:
            pass

    def _guardar_orden_db(self, productos_ordenados):
        """Persistir el orden actual a orden_visual (1..N)."""
        try:
            conn = get_connection()
            cur = conn.cursor()
            cur.execute("UPDATE products SET orden_visual = id WHERE orden_visual IS NULL")
            pos = 1
            for prod in productos_ordenados:
                try:
                    pid = int(prod[0])
                    cur.execute("UPDATE products SET orden_visual=? WHERE id=?", (pos, pid))
                    pos += 1
                except Exception:
                    pass
            conn.commit()
            conn.close()
        except Exception:
            try:
                conn.close()
            except Exception:
                pass

    def _swap_productos_db(self, id1, orden1, id2, orden2):
        try:
            conn = get_connection()
            cur = conn.cursor()
            cur.execute("UPDATE products SET orden_visual = id WHERE orden_visual IS NULL")
            cur.execute("UPDATE products SET orden_visual=? WHERE id=?", (orden2, id1))
            cur.execute("UPDATE products SET orden_visual=? WHERE id=?", (orden1, id2))
            conn.commit()
            conn.close()
        except Exception:
            try:
                conn.close()
            except Exception:
                pass

    def _mover_producto(self, prod_id, orden_actual, delta):
        """Mueve el producto cambiando su orden_visual en +delta y ajusta colisión con el que ocupa esa posición."""
        try:
            conn = get_connection()
            cur = conn.cursor()
            # asegurar que todos tengan orden inicial
            cur.execute("UPDATE products SET orden_visual = id WHERE orden_visual IS NULL")
            nuevo = max(1, int(orden_actual) + int(delta))
            # encontrar si hay otro con ese orden
            cur.execute("SELECT id, orden_visual FROM products WHERE orden_visual=? AND id<>? ORDER BY id LIMIT 1", (nuevo, prod_id))
            other = cur.fetchone()
            # actualizar el actual al nuevo
            cur.execute("UPDATE products SET orden_visual=? WHERE id=?", (nuevo, prod_id))
            # si hay colisión, empujar al otro en sentido opuesto (simple swap)
            if other:
                cur.execute("UPDATE products SET orden_visual=? WHERE id=?", (orden_actual, other[0]))
            conn.commit()
            conn.close()
        except Exception:
            try:
                conn.close()
            except Exception:
                pass

    def recargar_productos(self):
        """Recargar listado de productos desde la DB y redibujar únicamente las tarjetas."""
        self.productos = cargar_productos()
        # actualizar stock dict con los nuevos valores (mantener existencias en cache si no hay valor)
        new_stock = {prod[0]: prod[3] for prod in self.productos}
        for pid, s in new_stock.items():
            self.stock_dict[pid] = s
        self._draw_productos()

    def _draw_carrito(self):
        # Limpiar y construir la vista del carrito
        for widget in self.panel_carrito.winfo_children():
            widget.destroy()
        tk.Label(self.panel_carrito, text="Carrito", font=(FONT_FAMILY, 16, "bold"), bg="#FFFFFF").pack(anchor="w", padx=12, pady=(8,0))

        # Contenedor que agrupa el encabezado (fixed) y el area scrollable (canvas)
        list_wrap = tk.Frame(self.panel_carrito, bg="#FFFFFF")
        list_wrap.pack(fill="both", expand=True, padx=12, pady=(8,0))

        # Encabezados alineados con columnas (usamos grid dentro de list_wrap)
        header = tk.Frame(list_wrap, bg="#FFFFFF")
        header.grid(row=0, column=0, columnspan=3, sticky="we")
        header.grid_columnconfigure(0, weight=1)
        # dar un espacio fijo a la columna de cantidad para centrar el encabezado
        header.grid_columnconfigure(1, weight=0, minsize=320)
        header.grid_columnconfigure(2, weight=0)
        tk.Label(header, text="Ítem", font=(FONT_FAMILY, 11, "bold"), bg="#FFFFFF", anchor="w").grid(row=0, column=0, sticky="w", padx=8)
        # Centrar 'Cant.' sobre la columna de cantidad
        tk.Label(header, text="Cant.", font=(FONT_FAMILY, 11, "bold"), bg="#FFFFFF").grid(row=0, column=1)
        tk.Label(header, text="Subtotal", font=(FONT_FAMILY, 11, "bold"), bg="#FFFFFF").grid(row=0, column=2, sticky="e", padx=8)

        # Area scrollable para items: canvas con frame interno y scrollbar vertical.
        items_canvas = tk.Canvas(list_wrap, bg="#FFFFFF", highlightthickness=0, height=240)
        items_vscroll = tk.Scrollbar(list_wrap, orient=tk.VERTICAL, command=items_canvas.yview)
        items_canvas.configure(yscrollcommand=items_vscroll.set)
        list_wrap.grid_rowconfigure(1, weight=1)
        list_wrap.grid_columnconfigure(0, weight=1)
        items_canvas.grid(row=1, column=0, sticky="nsew")
        items_vscroll.grid(row=1, column=2, sticky="ns")
        self.items_frame = tk.Frame(items_canvas, bg="#FFFFFF")
        items_window = items_canvas.create_window((0, 0), window=self.items_frame, anchor="nw")

        def _on_canvas_config(e):
            try:
                items_canvas.itemconfig(items_window, width=e.width)
            except Exception:
                pass

        items_canvas.bind('<Configure>', _on_canvas_config)

        def _on_items_config(event):
            try:
                items_canvas.configure(scrollregion=items_canvas.bbox("all"))
            except Exception:
                pass

        self.items_frame.bind('<Configure>', _on_items_config)

        def _on_items_mousewheel(event):
            delta = 0
            try:
                if event.delta:
                    delta = -1 if event.delta > 0 else 1
            except Exception:
                if getattr(event, 'num', None) == 4:
                    delta = -1
                elif getattr(event, 'num', None) == 5:
                    delta = 1
            items_canvas.yview_scroll(delta, "units")

        items_canvas.bind('<Enter>', lambda e: items_canvas.bind_all('<MouseWheel>', _on_items_mousewheel))
        items_canvas.bind('<Leave>', lambda e: items_canvas.unbind_all('<MouseWheel>'))

        # Colocar Total, checkbox y botones en la parte inferior del panel de carrito
        self.label_total = tk.Label(self.panel_carrito, text="Total: $0", font=CART['total_font'], bg="#FFFFFF", fg="#1E293B")
        self.label_total.pack(side="bottom", anchor="e", padx=12, pady=(8,12))

        chk = tk.Checkbutton(self.panel_carrito, text="Imprimir ticket al cobrar", variable=self.imprimir_ticket_var, bg="#FFFFFF", font=(FONT_FAMILY, 10))
        chk.pack(side="bottom", anchor="w", padx=12, pady=(0,8))

        acciones = tk.Frame(self.panel_carrito, bg="#FFFFFF")
        acciones.pack(side="bottom", fill="x", padx=12, pady=(0,12))

        cobrar_box = tk.Frame(acciones, bg="#FFFFFF")
        cobrar_box.pack(side="left", padx=(0,8))
        btn_cobrar = tk.Button(cobrar_box, text="Cobrar", command=self._cobrar, bg="#10B981", fg="#fff", font=CART['button_font'], padx=CART['button_padx'], pady=CART['button_pady'])
        btn_cobrar.pack()
        tk.Label(cobrar_box, text="Ctrl+Enter", font=(FONT_FAMILY, 10), bg="#FFFFFF", fg="#1E293B").pack()

        cancelar_box = tk.Frame(acciones, bg="#FFFFFF")
        cancelar_box.pack(side="right")
        btn_cancelar = tk.Button(cancelar_box, text="Cancelar", command=self._cancelar, bg="#F43F5E", fg="#fff", font=CART['button_font'], padx=CART['button_padx'], pady=CART['button_pady'])
        btn_cancelar.pack()
        tk.Label(cancelar_box, text="Ctrl+<-", font=(FONT_FAMILY, 10), bg="#FFFFFF", fg="#1E293B").pack()

        # Finalmente actualizar la lista de items
        self._actualizar_carrito()

    def _actualizar_carrito(self):
        for widget in self.items_frame.winfo_children():
            widget.destroy()
        self.total = 0
        for idx, item in enumerate(self.carrito):
            prod_id, nombre, precio, cantidad = item
            subtotal = cantidad * precio
            self.total += subtotal
            # Usar grid para asegurar alineación: nombre | qty controls | subtotal
            row = tk.Frame(self.items_frame, bg="#F8FAFC" if idx%2==0 else "#FFFFFF")
            row.pack(fill="x")
            row.grid_columnconfigure(0, weight=1)
            row.grid_columnconfigure(1, weight=0)
            row.grid_columnconfigure(2, weight=0)
            # Nombre a la izquierda y expandible
            lbl_name = tk.Label(row, text=nombre, font=CART['item_font'], bg=row['bg'], anchor="w")
            lbl_name.grid(row=0, column=0, sticky="we", padx=8)
            # Contenedor de cantidad y botones (columna 1)
            qty_frame = tk.Frame(row, bg=row['bg'])
            qty_frame.grid(row=0, column=1, sticky="e", padx=8)
            # Quiet +/- buttons: flat, no border, background matches row to avoid gray fill
            tk.Button(qty_frame, text="-", command=lambda i=idx: self._restar_item(i), width=3, font=CART['qty_button_font'], relief='flat', bd=0, highlightthickness=0, bg=row['bg'], activebackground=row['bg']).pack(side="left", padx=1, pady=1)
            tk.Label(qty_frame, text=str(cantidad), width=4, anchor="center", bg=row['bg'], font=CART['qty_button_font']).pack(side="left", padx=2)
            tk.Button(qty_frame, text="+", command=lambda i=idx: self._sumar_item(i), width=3, font=CART['qty_button_font'], relief='flat', bd=0, highlightthickness=0, bg=row['bg'], activebackground=row['bg']).pack(side="left", padx=1, pady=1)
            # Subtotal a la derecha (columna 2)
            lbl_sub = tk.Label(row, text=f"$ {subtotal:,.0f}", font=CART['subtotal_font'], bg=row['bg'], anchor="e", width=12)
            lbl_sub.grid(row=0, column=2, sticky="e", padx=8)
        self.label_total.config(text=f"Total: $ {self.total:,.0f}")

    def _get_stock(self, prod_id):
        """Return stock as int or 999 for infinite; safe-cast values from stock_dict."""
        val = self.stock_dict.get(prod_id, 0)
        try:
            intval = int(val)
            return intval
        except Exception:
            # if not castable, return as-is
            return val

    def _agregar_al_carrito(self, prod):
        prod_id = prod[0]
        stock_val = self.stock_dict.get(prod_id, 0)
        # Si el producto no contabiliza stock, permitir agregar siempre (no chequear existencia)
        # Necesitamos conocer contabiliza_stock del producto actual
        try:
            contabiliza = int(prod[6])
        except Exception:
            contabiliza = 1
        if contabiliza == 1 and stock_val == 0:
            messagebox.showwarning("Sin stock", f"No hay stock disponible para {prod[1]}")
            return
        existente = next((item for item in self.carrito if item[0] == prod_id), None)
        if existente:
            # permitir cuando no contabiliza o haya al menos 1 unidad disponible
            if contabiliza == 0 or stock_val > 0:
                existente[3] += 1
            else:
                messagebox.showwarning("Stock insuficiente", f"No hay más stock disponible para {prod[1]}")
                return
        else:
            self.carrito.append([prod[0], prod[1], prod[2], 1])  # id, nombre, precio, cantidad
        # sólo decrementar si contabiliza
        if contabiliza == 1:
            self.stock_dict[prod_id] -= 1
            # Si justo quedó en 5, avisar
            if self.stock_dict[prod_id] == 5:
                messagebox.showwarning("Stock bajo", f"Solo quedan 5 unidades de {prod[1]}")
        self._draw_productos()
        self._actualizar_carrito()

    def _sumar_item(self, idx):
        prod_id = self.carrito[idx][0]
        stock_val = self._get_stock(prod_id)
        # Si no contabiliza, permitir sumar sin chequear stock; si contabiliza, requerir stock > 0
        contabiliza = 1
        try:
            # buscar el producto actual
            prod = next((p for p in self.productos if p[0] == prod_id), None)
            if prod is not None:
                contabiliza = int(prod[6])
        except Exception:
            contabiliza = 1
        if contabiliza == 0 or (isinstance(stock_val, int) and stock_val > 0):
            # aumentar cantidad en carrito
            self.carrito[idx][3] += 1
            # decrementar stock real sólo si contabiliza
            if contabiliza == 1:
                self.stock_dict[prod_id] -= 1
                if self.stock_dict[prod_id] == 5:
                    messagebox.showwarning("Stock bajo", f"Solo quedan 5 unidades de {self.carrito[idx][1]}")
            self._draw_productos()
            self._actualizar_carrito()
        else:
            messagebox.showwarning("Stock insuficiente", "No hay más stock disponible para este producto.")

    def _restar_item(self, idx):
        prod_id = self.carrito[idx][0]
        self.carrito[idx][3] -= 1
    # devolver stock sólo si contabiliza
        try:
            prod = next((p for p in self.productos if p[0] == prod_id), None)
            contabiliza = int(prod[6]) if prod is not None else 1
        except Exception:
            contabiliza = 1
        if contabiliza == 1:
            self.stock_dict[prod_id] += 1
        if self.carrito[idx][3] == 0:
            self.carrito.pop(idx)
        self._draw_productos()
        self._actualizar_carrito()

    def _cancelar(self):
        # Devolver stock de los productos en el carrito
        for item in self.carrito:
            prod_id, _, _, cantidad = item
            try:
                prod = next((p for p in self.productos if p[0] == prod_id), None)
                contabiliza = int(prod[6]) if prod is not None else 1
            except Exception:
                contabiliza = 1
            if contabiliza == 1:
                self.stock_dict[prod_id] += cantidad
        self.carrito.clear()
        self._draw_productos()
        self._actualizar_carrito()

    def _cobrar(self):
        if not self.carrito:
            messagebox.showwarning("Carrito vacío", "Agregue productos antes de cobrar.")
            return
        # Ventana flotante para método de pago: cargar desde DB
        metodos = cargar_metodos_pago()
        if not metodos:
            messagebox.showerror("Métodos de pago", "No hay métodos de pago configurados en la base de datos.\nConfigure al menos uno en la tabla metodos_pago.")
            return
        # Usar el diálogo centralizado que devuelve el id del método seleccionado.
        from metodo_pago_dialog import MetodoPagoDialog
        dlg = MetodoPagoDialog(self)
        metodo = dlg.result
        if not metodo:
            return
        # Guardar venta en la base de datos y obtener info de tickets
        result = self.cobrar_callback(self.carrito, metodo)
        # Si la callback devolvió info y el checkbox está activo, imprimir por item
        if self.imprimir_ticket_var.get():
            try:
                if result and isinstance(result, dict) and 'tickets' in result:
                    fecha = __import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    _printed_ids = []
                    for t in result['tickets']:
                        # llamar al método estático para imprimir cada ticket
                        try:
                            ok = self.imprimir_ticket_por_item_win32_static(
                                fecha,
                                t.get('producto_nombre'),
                                ticket_id=t.get('ticket_id'),
                                identificador_ticket=t.get('identificador'),
                                codigo_caja=t.get('codigo_caja')
                            )
                            if ok and t.get('ticket_id'):
                                _printed_ids.append(t.get('ticket_id'))
                        except Exception:
                            # fallback: intentar el callback genérico si existe
                            try:
                                self.imprimir_ticket_callback(self.carrito)
                            except Exception:
                                pass
                    # Marcar como Impreso los tickets que salieron correctamente
                    try:
                        if _printed_ids and callable(self.on_tickets_impresos):
                            self.on_tickets_impresos(_printed_ids)
                    except Exception:
                        pass
                else:
                    # si no se devolvió info, llamar al callback genérico
                    try:
                        self.imprimir_ticket_callback(self.carrito)
                    except Exception:
                        pass
            except Exception:
                pass
        self.carrito.clear()
        self._draw_productos()
        self._actualizar_carrito()

    @staticmethod
    def imprimir_ticket_por_item_win32_static(fecha, nombre_item, ticket_id=None, identificador_ticket=None, codigo_caja=None, disciplina=None):
        """Ported static printer from previous ventas_view implementation."""
        try:
            import win32print, win32ui, win32con
        except Exception:
            try:
                messagebox.showerror("Ticket", "No está disponible la librería de impresión en este sistema.")
            except Exception:
                pass
            return False

        # Resolver impresora seleccionada o predeterminada
        try:
            from app_config import get_printer_name
            sel = get_printer_name()
            printer_name = sel if sel else win32print.GetDefaultPrinter()
        except Exception:
            try:
                printer_name = win32print.GetDefaultPrinter()
            except Exception:
                printer_name = ''
        try:
            hPrinter = win32print.OpenPrinter(printer_name)
            info = win32print.GetPrinter(hPrinter, 2)
            status = info['Status']
            PRINTER_STATUS_OFFLINE = 0x00000080
            PRINTER_STATUS_ERROR = 0x00000002
            PRINTER_STATUS_NOT_AVAILABLE = 0x00001000
            if status & (PRINTER_STATUS_OFFLINE | PRINTER_STATUS_ERROR | PRINTER_STATUS_NOT_AVAILABLE):
                win32print.ClosePrinter(hPrinter)
                try:
                    messagebox.showerror("Ticket", f"La impresora '{printer_name}' está offline / error / no disponible")
                except Exception:
                    pass
                return False
            win32print.ClosePrinter(hPrinter)
        except Exception:
            try:
                messagebox.showerror("Ticket", f"No se pudo conectar con la impresora: {printer_name}")
            except Exception:
                pass
            return False

        pdc = None
        try:
            pdc = win32ui.CreateDC()
            pdc.CreatePrinterDC(printer_name)
            pdc.StartDoc(f"Ticket {nombre_item}")
            pdc.StartPage()

            ANCHO_PX     = 520
            TOP_MARGIN   = 0
            GAP          = 2

            TITLE_H      = 40
            META_H       = 24
            ITEM_BOX_H   = 76

            def center_text(text):
                w, _ = pdc.GetTextExtent(text)
                return max(0, (ANCHO_PX - w) // 2)

            font_title   = win32ui.CreateFont({"name": "Arial", "height": TITLE_H, "weight": 700, "charset": win32con.ANSI_CHARSET})
            font_meta    = win32ui.CreateFont({"name": "Arial", "height": META_H,   "weight": 400, "charset": win32con.ANSI_CHARSET})

            y = TOP_MARGIN
            pdc.SelectObject(font_title)
            pdc.TextOut(center_text("BUFFET"), y, "BUFFET")
            y += TITLE_H + GAP

            pdc.SelectObject(font_meta)
            if identificador_ticket:
                pdc.TextOut(center_text(f"Nº {identificador_ticket}"), y, f"Nº {identificador_ticket}")
                y += META_H + GAP

            pdc.TextOut(center_text(f"{fecha}"), y, f"{fecha}")
            y += META_H + GAP

            if codigo_caja:
                pdc.TextOut(center_text(f"Caja {codigo_caja}"), y, f"Caja {codigo_caja}")
                y += META_H + GAP

            texto_item = str(nombre_item).upper()

            tam = 86
            while True:
                font_item_big = win32ui.CreateFont({"name": "Arial", "height": tam, "weight": 700, "charset": win32con.ANSI_CHARSET})
                pdc.SelectObject(font_item_big)
                w, h = pdc.GetTextExtent(texto_item)
                if (w <= ANCHO_PX - 8) and (h <= ITEM_BOX_H - 4) and tam >= 36:
                    break
                tam -= 4
                if tam < 36:
                    break

            pdc.SelectObject(font_item_big)
            x = center_text(texto_item)
            y_item = y + max(0, (ITEM_BOX_H - pdc.GetTextExtent(texto_item)[1]) // 2)
            pdc.TextOut(x, y_item, texto_item)

            y += ITEM_BOX_H

            pdc.EndPage()
            pdc.EndDoc()
            try:
                messagebox.showinfo("Ticket", f"Ticket enviado a la impresora: {printer_name}")
            except Exception:
                pass
            return True
        except Exception:
            try:
                messagebox.showerror("Ticket", f"No se pudo imprimir en: {printer_name}")
            except Exception:
                pass
            return False
        finally:
            if pdc:
                try:
                    pdc.DeleteDC()
                except Exception:
                    pass

    def _bind_shortcuts(self):
        for idx in range(min(12, len(self.productos))):
            self.master.bind(f'<F{idx+1}>', lambda e, i=idx: self._agregar_al_carrito(self.productos[i]))
        self.master.bind('<Control-Return>', lambda e: self._cobrar())
        self.master.bind('<Control-BackSpace>', lambda e: self._cancelar())
