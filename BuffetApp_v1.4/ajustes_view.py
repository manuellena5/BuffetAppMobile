import tkinter as tk
from tkinter import colorchooser, messagebox
from db_utils import get_connection
import os

class AjustesView(tk.Frame):
    def __init__(self, master, app):
        super().__init__(master)
        self.app = app
        self.ventas_view = app.ventas_view
        self.label = tk.Label(self, text="Ajustes de Productos", font=("Arial", 18))
        self.label.pack(pady=10)

        # Ancho y alto de botones
        frame_size = tk.Frame(self)
        frame_size.pack(pady=5)
        tk.Label(frame_size, text="Ancho botón:").grid(row=0, column=0)
        self.var_ancho = tk.IntVar(value=self.ventas_view.btn_ancho if hasattr(self.ventas_view, 'btn_ancho') else 16)
        tk.Entry(frame_size, textvariable=self.var_ancho, width=5).grid(row=0, column=1)
        tk.Label(frame_size, text="Alto botón:").grid(row=0, column=2)
        self.var_alto = tk.IntVar(value=self.ventas_view.btn_alto if hasattr(self.ventas_view, 'btn_alto') else 2)
        tk.Entry(frame_size, textvariable=self.var_alto, width=5).grid(row=0, column=3)

        # Colores por producto
        frame_color = tk.Frame(self)
        frame_color.pack(pady=10)
        productos = self.obtener_productos()
        self.color_vars = {}
        for producto in productos:
            pid, nombre = producto
            var = tk.StringVar(value=self.obtener_color_producto(pid))
            self.color_vars[pid] = var
            row = tk.Frame(frame_color)
            row.pack(fill="x", pady=2)
            tk.Label(row, text=nombre, width=18).pack(side=tk.LEFT)
            tk.Entry(row, textvariable=var, width=10).pack(side=tk.LEFT)
            tk.Button(row, text="Elegir color", command=lambda v=var: self.elegir_color(v)).pack(side=tk.LEFT)

        # Botón guardar
        tk.Button(self, text="Guardar ajustes", font=("Arial", 12), command=self.guardar_ajustes).pack(pady=15)
        # Botón restaurar valores de fábrica
        tk.Button(self, text="Restaurar valores de fábrica", font=("Arial", 12), fg="red", command=self.restaurar_fabrica).pack(pady=5)

        # Botón Salir en la esquina inferior derecha
        try:
            from tkinter import PhotoImage
            icon_path = os.path.join(os.path.dirname(__file__), "icon_salir.png")
            self.icon_salir = PhotoImage(file=icon_path)
        except Exception:
            self.icon_salir = None
        self.boton_salir = tk.Button(self, text="Salir", image=self.icon_salir, compound=tk.LEFT if self.icon_salir else None, command=self.master.quit)
        self.boton_salir.place(relx=1.0, rely=1.0, anchor="se", x=-10, y=-10)

    def obtener_productos(self):
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, nombre FROM products WHERE visible=1 ORDER BY nombre")
        productos = cursor.fetchall()
        conn.close()
        return productos

    def obtener_color_producto(self, producto_id):
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT color FROM products WHERE id=?", (producto_id,))
        row = cursor.fetchone()
        conn.close()
        return row[0] if row and row[0] else ""

    def elegir_color(self, var):
        color = colorchooser.askcolor()[1]
        if color:
            var.set(color)

    def guardar_ajustes(self):
        ancho = self.var_ancho.get()
        alto = self.var_alto.get()
        if ancho <= 0 or alto <= 0:
            messagebox.showerror("Valor inválido", "El ancho y el alto del botón deben ser mayores a cero.")
            return
        nueva_config = {
            "ancho_boton": ancho,
            "alto_boton": alto,
            "color_boton": "#f0f0f0"
        }
        # Guardar colores en DB
        conn = get_connection()
        cursor = conn.cursor()
        for pid, var in self.color_vars.items():
            color = var.get()
            cursor.execute("UPDATE products SET color=? WHERE id=?", (color, pid))
        conn.commit()
        conn.close()
        self.app.actualizar_configuracion(nueva_config)
        messagebox.showinfo("Ajustes", "Ajustes guardados correctamente. La aplicación se reiniciará para aplicar los cambios.")
        self.app.root.destroy()
        import sys
        os.execl(sys.executable, sys.executable, *sys.argv)

    def restaurar_fabrica(self):
        config_path = os.path.join(os.path.dirname(__file__), "config.json")
        respuesta = messagebox.askyesno("Restaurar valores de fábrica", "¿Está seguro que desea restaurar la configuración inicial? Se perderán los cambios realizados.")
        if respuesta:
            if os.path.exists(config_path):
                os.remove(config_path)
            messagebox.showinfo("Restaurar", "La aplicación se reiniciará con los valores de fábrica.")
            self.app.root.destroy()
            import sys
            os.execl(sys.executable, sys.executable, *sys.argv)

