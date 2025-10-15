import tkinter as tk
from tkinter import messagebox
from db_utils import get_connection
from theme import LOGIN, COLORS


class LoginView(tk.Frame):
    def __init__(self, master, on_login):
        super().__init__(master, bg=COLORS['background'])
        self.on_login = on_login
        # layout responsive: un frame central con padding amplio
        container = tk.Frame(self, bg=COLORS['background'])
        container.place(relx=0.5, rely=0.5, anchor='center')

        title = tk.Label(container, text="BUFFET - Ingreso", font=LOGIN['title_font'], bg=COLORS['background'], fg=COLORS['text'])
        title.pack(pady=(0, LOGIN['padding_y']))

        form = tk.Frame(container, bg=COLORS['background'])
        form.pack()

        tk.Label(form, text="Usuario:", font=LOGIN['label_font'], bg=COLORS['background'], fg=COLORS['text']).grid(row=0, column=0, sticky='w', pady=6)
        self.entry_usuario = tk.Entry(form, font=LOGIN['entry_font'], width=LOGIN['width'])
        self.entry_usuario.grid(row=1, column=0, pady=(0,12))

        tk.Label(form, text="Contraseña:", font=LOGIN['label_font'], bg=COLORS['background'], fg=COLORS['text']).grid(row=2, column=0, sticky='w', pady=6)
        self.entry_password = tk.Entry(form, font=LOGIN['entry_font'], show="*", width=LOGIN['width'])
        self.entry_password.grid(row=3, column=0, pady=(0,12))

        self.var_rol = tk.StringVar()
        self.label_rol = tk.Label(form, text="", font=(LOGIN['label_font'][0], max(LOGIN['label_font'][1]-2, 10)), fg=COLORS['text_secondary'], bg=COLORS['background'])
        self.label_rol.grid(row=4, column=0, pady=(0,8))

        btn = tk.Button(container, text="Ingresar", command=self.login, bg='#10B981', fg='white', font=LOGIN['button_font'], padx=20, pady=10)
        btn.pack(pady=(4,0))

        self.entry_usuario.bind('<Return>', lambda e: self.entry_password.focus())
        self.entry_password.bind('<Return>', lambda e: btn.invoke())

    def login(self):
        usuario = self.entry_usuario.get().strip()
        password = self.entry_password.get().strip()
        if not usuario or not password:
            messagebox.showwarning("Login", "Ingrese usuario y contraseña.")
            return
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT rol FROM usuarios WHERE usuario=? AND password= ?", (usuario, password))
        row = cursor.fetchone()
        conn.close()
        if row:
            rol = row[0]
            self.label_rol.config(text=f"Rol: {rol}")
            try:
                self.on_login(usuario, rol)
            except Exception:
                pass
        else:
            messagebox.showerror("Login", "Usuario o contraseña incorrectos.")
            self.label_rol.config(text="")
