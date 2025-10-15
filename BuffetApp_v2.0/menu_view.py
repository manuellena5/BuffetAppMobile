import tkinter as tk


class MenuView(tk.Frame):
    """Vista principal con acciones en una cuadrícula de botones grandes."""

    def __init__(self, master, get_caja_info, on_cerrar_caja, on_ver_cierre, on_abrir_caja, controller=None):
        super().__init__(master)
        self.get_caja_info = get_caja_info
        self.on_cerrar_caja = on_cerrar_caja
        self.on_ver_cierre = on_ver_cierre
        self.on_abrir_caja = on_abrir_caja
        # controller: referencia al objeto BarCanchaApp para llamadas directas (mostrar_ventas, etc.)
        self.controller = controller

        # Welcome label (aumentado para accesibilidad)
        self.label_bienvenida = tk.Label(self, text="Bienvenido al sistema de ventas", font=("Arial", 24))
        self.label_bienvenida.grid(row=0, column=0, columnspan=3, pady=(20, 30))

        # Reduce button font by 3 points for requested sizing
        btn_font = ("Arial", 15, 'bold')
        btn_cfg = {'font': btn_font, 'width': 18, 'height': 4}

        # Grid of main actions: 3 columns x 2 rows
        self.btn_abrir = tk.Button(self, text="ABRIR CAJA", command=self.on_abrir_caja, **btn_cfg)
        self.btn_abrir.grid(row=1, column=0, padx=12, pady=12, sticky='nsew')

        self.btn_cerrar = tk.Button(self, text="CERRAR CAJA", command=self.on_cerrar_caja, **btn_cfg)
        self.btn_cerrar.grid(row=1, column=1, padx=12, pady=12, sticky='nsew')

        self.btn_ventas = tk.Button(self, text="VENTAS", command=self._on_ventas, **btn_cfg)
        self.btn_ventas.grid(row=1, column=2, padx=12, pady=12, sticky='nsew')

        self.btn_listado = tk.Button(self, text="LISTADO DE CAJAS", command=self._on_listado_cajas, **btn_cfg)
        self.btn_listado.grid(row=2, column=0, padx=12, pady=12, sticky='nsew')

        self.btn_productos = tk.Button(self, text="PRODUCTOS", command=self._on_productos, **btn_cfg)
        self.btn_productos.grid(row=2, column=1, padx=12, pady=12, sticky='nsew')

        self.btn_historial = tk.Button(self, text="HISTORIAL", command=self._on_historial, **btn_cfg)
        self.btn_historial.grid(row=2, column=2, padx=12, pady=12, sticky='nsew')

        # Make columns expand evenly
        for c in range(3):
            self.grid_columnconfigure(c, weight=1)

    def _on_ventas(self):
        # Only allow ventas if there's a controller or we fallback to no-op
        if self.controller and hasattr(self.controller, 'mostrar_ventas'):
            self.controller.mostrar_ventas()
        else:
            # try to call via master callbacks if available
            try:
                if hasattr(self, 'on_ver_cierre'):
                    # fallback to show ventas via controller elsewhere
                    pass
            except Exception:
                pass

    def _on_listado_cajas(self):
        if self.controller and hasattr(self.controller, 'mostrar_listado_cajas'):
            self.controller.mostrar_listado_cajas()

    def _on_productos(self):
        if self.controller and hasattr(self.controller, 'mostrar_productos'):
            self.controller.mostrar_productos()

    def _on_historial(self):
        if self.controller and hasattr(self.controller, 'mostrar_historial'):
            self.controller.mostrar_historial()

    def actualizar_caja_info(self):
        """Actualiza el mensaje y activa/desactiva botones según el estado de la caja."""
        info = self.get_caja_info()
        if info:
            self.label_bienvenida.config(
                text=f"Caja {info['codigo']} ({info['disciplina']}) abierta por {info['usuario_apertura']}\nApertura: {info['hora_apertura']} - Fondo $ {info['fondo_inicial']}"
            )
            self.btn_abrir.config(state=tk.DISABLED)
            self.btn_cerrar.config(state=tk.NORMAL)
            self.btn_ventas.config(state=tk.NORMAL)
        else:
            self.label_bienvenida.config(text="No hay caja abierta")
            self.btn_abrir.config(state=tk.NORMAL)
            self.btn_cerrar.config(state=tk.DISABLED)
            self.btn_ventas.config(state=tk.DISABLED)
