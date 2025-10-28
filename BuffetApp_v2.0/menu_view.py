import tkinter as tk


class MenuView(tk.Frame):
    """Vista principal en 2 columnas con botones uniformes y emojis."""

    def __init__(self, master, get_caja_info, on_cerrar_caja, on_ver_cierre, on_abrir_caja, controller=None):
        super().__init__(master)
        self.get_caja_info = get_caja_info
        self.on_cerrar_caja = on_cerrar_caja
        self.on_ver_cierre = on_ver_cierre
        self.on_abrir_caja = on_abrir_caja
        self.controller = controller  # para mostrar_ventas / historial / productos / listado

        # Encabezado (sin emoji para compatibilidad)
        self.label_bienvenida = tk.Label(self, text="Bienvenido al sistema de ventas", font=("Arial", 22, 'bold'))
        self.label_bienvenida.grid(row=0, column=0, columnspan=2, pady=(16, 12), sticky='n')

        # Estilo uniforme
        self.btn_font = ("Segoe UI", 16, 'bold')
        self.btn_width_chars = 22  # mismo ancho para todos los botones

        def make_card_button(parent, emoji: str, title: str, cmd, bg="#ffffff", fg="#111", hover_bg="#f0f0f0"):
            # Tarjeta con borde sutil
            frame = tk.Frame(parent, bd=1, relief='solid', bg=bg, highlightthickness=0)
            btn = tk.Button(
                frame,
                text=f"{emoji}  {title}",
                font=self.btn_font,
                command=cmd,
                bd=0,
                bg=bg,
                fg=fg,
                activebackground=hover_bg,
                relief='flat',
                padx=18, pady=14,
                width=self.btn_width_chars
            )
            btn.pack(anchor='center', padx=10, pady=10)

            # Hover
            def on_enter(_):
                frame.configure(bg=hover_bg); btn.configure(bg=hover_bg)
            def on_leave(_):
                frame.configure(bg=bg); btn.configure(bg=bg)
            frame.bind('<Enter>', on_enter); frame.bind('<Leave>', on_leave)
            btn.bind('<Enter>', on_enter); btn.bind('<Leave>', on_leave)
            return frame, btn

        # Layout 2 columnas
        grid = tk.Frame(self)
        grid.grid(row=1, column=0, columnspan=2, sticky='nsew', padx=12, pady=6)
        self.grid_columnconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)
        grid.grid_columnconfigure(0, weight=1)
        grid.grid_columnconfigure(1, weight=1)

        # Columna izquierda: VENTAS / TICKETS (hoy) / PRODUCTOS
        left = tk.Frame(grid)
        left.grid(row=0, column=0, sticky='n', padx=(0, 8))
        card_ventas, self.btn_ventas = make_card_button(left, "🧾", "VENTAS", self._on_ventas)
        card_ventas.grid(row=0, column=0, sticky='n', pady=(0, 8))
        card_tickets, self.btn_tickets = make_card_button(left, "🎟️", "TICKETS", self._on_tickets_hoy)
        card_tickets.grid(row=1, column=0, sticky='n', pady=(0, 8))
        card_productos, self.btn_productos = make_card_button(left, "🧃", "PRODUCTOS", self._on_productos)
        card_productos.grid(row=2, column=0, sticky='n', pady=(0, 8))

        # Columna derecha: ABRIR CAJA / CERRAR CAJA / CONFIGURACION
        right = tk.Frame(grid)
        right.grid(row=0, column=1, sticky='n', padx=(8, 0))
        card_abrir, self.btn_abrir = make_card_button(right, "📥", "ABRIR CAJA", self.on_abrir_caja)
        card_abrir.grid(row=0, column=0, sticky='n', pady=(0, 8))
        card_cerrar, self.btn_cerrar = make_card_button(right, "📤", "CERRAR CAJA", self.on_cerrar_caja)
        card_cerrar.grid(row=1, column=0, sticky='n', pady=(0, 8))
        card_config, self.btn_config = make_card_button(right, "⚙️", "CONFIGURACION", self._on_configuracion)
        card_config.grid(row=2, column=0, sticky='n')

        # Estado inicial de botones
        self.actualizar_caja_info()

    # Acciones
    def _on_ventas(self):
        if self.controller and hasattr(self.controller, 'mostrar_ventas'):
            self.controller.mostrar_ventas()

    def _on_tickets_hoy(self):
        if self.controller and hasattr(self.controller, 'mostrar_tickets_hoy'):
            self.controller.mostrar_tickets_hoy()

    def _on_productos(self):
        if self.controller and hasattr(self.controller, 'mostrar_productos'):
            self.controller.mostrar_productos()

    # Se elimina botón Reportes de la vista principal

    def _on_configuracion(self):
        if self.controller and hasattr(self.controller, 'mostrar_configuracion'):
            self.controller.mostrar_configuracion()

    def actualizar_caja_info(self):
        """Actualiza encabezado y habilita/deshabilita acciones según estado de caja."""
        info = self.get_caja_info()
        if info:
            self.label_bienvenida.config(
                text=f"Caja {info['codigo']} ({info['disciplina']}) abierta  •  Apertura {info['hora_apertura']}  •  Fondo $ {info['fondo_inicial']}"
            )
            try:
                self.btn_abrir.config(state=tk.DISABLED)
                self.btn_cerrar.config(state=tk.NORMAL)
                self.btn_ventas.config(state=tk.NORMAL)
            except Exception:
                pass
        else:
            self.label_bienvenida.config(text="No hay caja abierta")
            try:
                self.btn_abrir.config(state=tk.NORMAL)
                self.btn_cerrar.config(state=tk.DISABLED)
                self.btn_ventas.config(state=tk.DISABLED)
            except Exception:
                pass
