import tkinter as tk
from tkinter import messagebox
from db_utils import get_connection
from theme import FONT_FAMILY, CART

# Utilidad para cargar productos

def cargar_productos():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT p.id, p.nombre, p.precio_venta, p.stock_actual, p.visible, p.codigo_producto
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
    def __init__(self, master, cobrar_callback, imprimir_ticket_callback, *args, **kwargs):
        super().__init__(master, *args, **kwargs)
        self.cobrar_callback = cobrar_callback
        self.imprimir_ticket_callback = imprimir_ticket_callback
        self.productos = cargar_productos()
        self.stock_dict = {prod[0]: prod[3] for prod in self.productos}
        self.carrito = []  # [id, nombre, precio, cantidad]
        self.imprimir_ticket_var = tk.BooleanVar(value=True)
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
        # Botón para recargar productos (solo redibuja las tarjetas)
        top_actions = tk.Frame(self.left_container, bg="#F8FAFC")
        top_actions.pack(fill="x", padx=8, pady=(8,4))
        btn_reload = tk.Button(top_actions, text="Actualizar productos", command=self.recargar_productos, bg="#E5E7EB", font=(FONT_FAMILY, 10))
        btn_reload.pack(side="left")
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
        # El panel_productos contiene el top_actions; solo eliminar tarjetas existentes debajo
        # Borrar todo menos el primer hijo (top_actions)
        children = self.panel_productos.winfo_children()
        for w in children[1:]:
            w.destroy()
        card_width = 260
        card_height = 110
        self.botones_funcion = []
        max_cols = 3
        # dibujar todos los productos; el canvas proveerá scroll si no entran
        for idx, prod in enumerate(self.productos):
            prod_id, nombre, precio, stock, _, _ = prod
            tecla = f"F{idx+1}"
            fila = idx // max_cols
            col = idx % max_cols
            card = tk.Frame(self.panel_productos, bg="#FFFFFF", bd=2, relief="groove", width=card_width, height=card_height)
            card.grid(row=fila, column=col, padx=8, pady=10, sticky="nsew")
            card.grid_propagate(False)
            name_lbl = tk.Label(card, text=nombre, font=(FONT_FAMILY, 16, "bold"), bg="#FFFFFF", anchor="w")
            name_lbl.pack(side="top", anchor="w", padx=16, pady=(10,0))
            price_lbl = tk.Label(card, text=f"$ {precio:,.0f}", font=(FONT_FAMILY, 14), fg="#059669", bg="#FFFFFF")
            price_lbl.pack(side="top", anchor="w", padx=16)
            display_stock = '∞' if self.stock_dict.get(prod_id, 0) == 999 else self.stock_dict.get(prod_id, 0)
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
                card.bind('<Button-1>', _on_click)
            except Exception:
                pass
            for w in (name_lbl, price_lbl, stock_lbl, tecla_lbl,):
                try:
                    w.unbind('<Enter>')
                    w.unbind('<Leave>')
                except Exception:
                    pass
                try:
                    w.bind('<Button-1>', lambda e, p=prod, widget=card: _on_click(e, p, widget))
                except Exception:
                    pass
            # Guardar referencia por si se quiere usar más adelante
            self.botones_funcion.append(lambda e=None, p=prod: self._agregar_al_carrito(p))

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
        # stock==999 significa stock infinito
        if stock_val != 999 and stock_val == 0:
            messagebox.showwarning("Sin stock", f"No hay stock disponible para {prod[1]}")
            return
        existente = next((item for item in self.carrito if item[0] == prod_id), None)
        if existente:
            # permitir cuando stock sea infinito o haya al menos 1 unidad disponible
            if stock_val == 999 or stock_val > 0:
                existente[3] += 1
            else:
                messagebox.showwarning("Stock insuficiente", f"No hay más stock disponible para {prod[1]}")
                return
        else:
            self.carrito.append([prod[0], prod[1], prod[2], 1])  # id, nombre, precio, cantidad
        # sólo decrementar si no es infinito
        if stock_val != 999:
            self.stock_dict[prod_id] -= 1
            # Si justo quedó en 5, avisar
            if self.stock_dict[prod_id] == 5:
                messagebox.showwarning("Stock bajo", f"Solo quedan 5 unidades de {prod[1]}")
        self._draw_productos()
        self._actualizar_carrito()

    def _sumar_item(self, idx):
        prod_id = self.carrito[idx][0]
        stock_val = self._get_stock(prod_id)
        if stock_val == 999 or (isinstance(stock_val, int) and stock_val > 0):
            # aumentar cantidad en carrito
            self.carrito[idx][3] += 1
            # decrementar stock real salvo si es infinito (999)
            if stock_val != 999:
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
        # devolver stock sólo si no es infinito
        if self.stock_dict.get(prod_id, 0) != 999:
            self.stock_dict[prod_id] += 1
        if self.carrito[idx][3] == 0:
            self.carrito.pop(idx)
        self._draw_productos()
        self._actualizar_carrito()

    def _cancelar(self):
        # Devolver stock de los productos en el carrito
        for item in self.carrito:
            prod_id, _, _, cantidad = item
            if self.stock_dict.get(prod_id, 0) != 999:
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
                    for t in result['tickets']:
                        # llamar al método estático para imprimir cada ticket
                        try:
                            self.imprimir_ticket_por_item_win32_static(fecha, t.get('producto_nombre'), ticket_id=t.get('ticket_id'), identificador_ticket=t.get('identificador'), codigo_caja=t.get('codigo_caja'))
                        except Exception:
                            # fallback: intentar el callback genérico si existe
                            try:
                                self.imprimir_ticket_callback(self.carrito)
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
