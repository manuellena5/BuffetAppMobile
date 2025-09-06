import tkinter as tk
from tkinter import simpledialog
from db_utils import get_connection


class MetodoPagoDialog(simpledialog.Dialog):
    """Diálogo simple que carga los métodos de pago desde la tabla `metodos_pago`.

    Resultado (`self.result`) será el id (int) del método seleccionado o None si se canceló.
    Soporta atajos: Enter = confirmar, Esc = cancelar, '1' = Efectivo, '2' = Transferencia.
    """

    def __init__(self, parent, title="Seleccionar método de pago"):
        self.selected_id = None
        super().__init__(parent, title)

    def body(self, master):
        tk.Label(master, text="Seleccione el método de pago:", font=("Arial", 12)).pack(pady=(8, 4))

        conn = get_connection()
        cur = conn.cursor()
        cur.execute("SELECT id, descripcion FROM metodos_pago ORDER BY id")
        self.metodos = cur.fetchall()
        conn.close()

        if not self.metodos:
            tk.Label(master, text="No hay métodos configurados.", font=("Arial", 11)).pack(pady=8)
            return None

        self.var = tk.IntVar(value=self.metodos[0][0])
        for mid, desc in self.metodos:
            tk.Radiobutton(master, text=desc, variable=self.var, value=mid, font=("Arial", 11), anchor='w', justify='left').pack(fill='x', anchor='w', padx=12)

        # Leyenda de atajos para el usuario
        tk.Label(master, text="1 = Efectivo, 2 = Transferencia · Enter = Aceptar · Esc = Cancelar", font=("Arial", 9), fg="#444").pack(pady=(6,4))

        # Bindings locales dentro del diálogo; los handlers retornan 'break'
        # para evitar que la tecla se propague al contenedor padre y active
        # atajos globales (p. ej. agregar items o salir de la pantalla de ventas).
        def _on_return(event):
            try:
                self.ok()
            except Exception:
                pass
            return "break"

        def _on_escape(event):
            try:
                self.cancel()
            except Exception:
                pass
            return "break"

        def _on_control_return(event):
            # si presionan Ctrl+Enter, tratamos como Enter y no propagamos
            try:
                self.ok()
            except Exception:
                pass
            return "break"

        def _on_key_local(event):
            # manejar '1' y '2' y evitar propagación
            try:
                self._on_key(event)
            except Exception:
                pass
            return "break"

        self.bind('<Return>', _on_return)
        self.bind('<Escape>', _on_escape)
        self.bind('<Control-Return>', _on_control_return)
        self.bind('<Key>', _on_key_local)

        return None

    def _on_key(self, event):
        # Mapear '1' a Efectivo y '2' a Transferencia si existen
        if not event.char:
            return
        ch = event.char
        if ch == '1':
            for mid, desc in self.metodos:
                if desc and desc.strip().lower().startswith('efect'):
                    self.var.set(mid)
                    break
        elif ch == '2':
            for mid, desc in self.metodos:
                if desc and 'transfer' in desc.strip().lower():
                    self.var.set(mid)
                    break

    def apply(self):
        try:
            self.selected_id = int(self.var.get())
        except Exception:
            self.selected_id = None
        self.result = self.selected_id
