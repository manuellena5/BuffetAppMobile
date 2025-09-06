import tkinter as tk
from tkinter import messagebox
from db_utils import get_connection

class LoginView(tk.Frame):
    def __init__(self, master, on_login):
        super().__init__(master)
        self.on_login = on_login
        self.pack(fill=tk.BOTH, expand=True)
        tk.Label(self, text="Login", font=("Arial", 18)).pack(pady=18)
        tk.Label(self, text="Usuario:", font=("Arial", 12)).pack(pady=4)
        self.entry_usuario = tk.Entry(self, font=("Arial", 12))
        self.entry_usuario.pack(pady=2)
        tk.Label(self, text="Contraseña:", font=("Arial", 12)).pack(pady=4)
        self.entry_password = tk.Entry(self, font=("Arial", 12), show="*")
        self.entry_password.pack(pady=2)
        self.var_rol = tk.StringVar()
        self.label_rol = tk.Label(self, text="", font=("Arial", 11), fg="#555")
        self.label_rol.pack(pady=2)
        btn_login = tk.Button(self, text="Ingresar", command=self.login, font=("Arial", 12), width=12, bg="#4CAF50", fg="white")
        btn_login.pack(pady=12)
        self.entry_usuario.bind('<Return>', lambda e: self.entry_password.focus())
        self.entry_password.bind('<Return>', lambda e: btn_login.invoke())

    def login(self):
        usuario = self.entry_usuario.get().strip()
        password = self.entry_password.get().strip()
        if not usuario or not password:
            messagebox.showwarning("Login", "Ingrese usuario y contraseña.")
            return
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT rol FROM usuarios WHERE usuario=? AND password=?", (usuario, password))
        row = cursor.fetchone()
        conn.close()
        if row:
            rol = row[0]
            self.label_rol.config(text=f"Rol: {rol}")
            self.on_login(usuario, rol)
        else:
            messagebox.showerror("Login", "Usuario o contraseña incorrectos.")
            self.label_rol.config(text="")
