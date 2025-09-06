import tkinter as tk


class MenuView(tk.Frame):
    """Vista principal con acciones relacionadas a la caja."""

    def __init__(self, master, get_caja_info, on_cerrar_caja, on_ver_cierre, on_abrir_caja):#, on_ingreso, on_retiro):
        super().__init__(master)
        self.get_caja_info = get_caja_info
        self.on_cerrar_caja = on_cerrar_caja
        self.on_ver_cierre = on_ver_cierre
        self.on_abrir_caja = on_abrir_caja
        # self.on_ingreso = on_ingreso
        # self.on_retiro = on_retiro

        self.label_bienvenida = tk.Label(self, text="Bienvenido al sistema de ventas", font=("Arial", 20))
        self.label_bienvenida.pack(pady=40)

        self.btn_abrir = tk.Button(self, text="Abrir caja", width=20, command=self.on_abrir_caja)
        self.btn_abrir.pack(pady=5)

        self.btn_cerrar = tk.Button(self, text="Cerrar caja", width=20, command=self.on_cerrar_caja)
        self.btn_cerrar.pack(pady=5)

        # Botón de informe del día oculto

        # self.btn_ingreso = tk.Button(self, text="Informar ingreso", width=20, command=self.on_ingreso, state=tk.DISABLED)
        # self.btn_ingreso.pack(pady=5)

        # self.btn_retiro = tk.Button(self, text="Informar retiro", width=20, command=self.on_retiro, state=tk.DISABLED)
        # self.btn_retiro.pack(pady=5)

    def actualizar_caja_info(self):
        """Actualiza el mensaje y los botones según el estado de la caja."""
        info = self.get_caja_info()
        if info:
            self.label_bienvenida.config(
                text=f"Caja {info['codigo']} ({info['disciplina']}) abierta por {info['usuario_apertura']}\nApertura: {info['hora_apertura']} - Fondo $ {info['fondo_inicial']}"
            )
            self.btn_abrir.config(state=tk.DISABLED)
            self.btn_cerrar.config(state=tk.NORMAL)
            # self.btn_ingreso.config(state=(tk.DISABLED if info.get('tiene_ingreso') else tk.NORMAL))
            # self.btn_retiro.config(state=(tk.DISABLED if info.get('tiene_retiro') else tk.NORMAL))




        else:
            self.label_bienvenida.config(text="No hay caja abierta")
            self.btn_abrir.config(state=tk.NORMAL)
            self.btn_cerrar.config(state=tk.DISABLED)
            # self.btn_ingreso.config(state=tk.DISABLED)
            # self.btn_retiro.config(state=tk.DISABLED)
