import tkinter as tk
from tkinter import ttk, messagebox
from db_utils import get_connection
from theme import TITLE_FONT, apply_treeview_style, themed_button, apply_button_style


class UsuariosView(tk.Frame):
    """ABM simple de usuarios (solo para administrador) con layout centrado y tabla compacta."""

    def __init__(self, master):
        super().__init__(master)

        # Layout del frame principal con grid para centrar contenido
        self.columnconfigure(0, weight=1)
        self.columnconfigure(1, weight=0)
        self.columnconfigure(2, weight=1)
        self.rowconfigure(0, weight=0)
        self.rowconfigure(1, weight=1)
        self.rowconfigure(2, weight=0)

        # Título centrado
        tk.Label(self, text="Gestión de Usuarios", font=TITLE_FONT).grid(row=0, column=1, pady=(14, 6))

        # Contenedor centrado
        center = tk.Frame(self)
        center.grid(row=1, column=1, sticky="n")

        # Estilo Treeview
        style = apply_treeview_style()
        style.map("App.Treeview", background=[('selected', '#CCE5FF')])

        frame_tabla = tk.Frame(center)
        frame_tabla.pack(pady=8, padx=20)
        cols = ("usuario", "rol")
        self.tree = ttk.Treeview(frame_tabla, columns=cols, show='headings', height=10, style="App.Treeview")
        self.tree.heading("usuario", text="Usuario")
        self.tree.heading("rol", text="Rol")
        self.tree.column("usuario", width=220, anchor="w")
        self.tree.column("rol", width=140, anchor="center")
        vsb = ttk.Scrollbar(frame_tabla, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        vsb.grid(row=0, column=1, sticky="ns")
        frame_tabla.columnconfigure(0, weight=1)
        frame_tabla.rowconfigure(0, weight=1)
        self.tree.bind('<<TreeviewSelect>>', lambda e: self._on_select())

        # Botonera
        btns = tk.Frame(center)
        btns.pack(pady=8)
        self.btn_add = themed_button(btns, text="Agregar", command=self._agregar)
        try:
            apply_button_style(self.btn_add, bg="#166534", fg="white", width=12)
        except Exception:
            apply_button_style(self.btn_add, width=12)
        self.btn_add.pack(side=tk.LEFT, padx=4)
        self.btn_edit = themed_button(btns, text="Editar", command=self._editar)
        apply_button_style(self.btn_edit, width=10)
        self.btn_edit.pack(side=tk.LEFT, padx=4)
        self.btn_del = themed_button(btns, text="Eliminar", command=self._eliminar)
        try:
            apply_button_style(self.btn_del, bg="#F43F5E", fg="white", width=10)
        except Exception:
            apply_button_style(self.btn_del, width=10)
        self.btn_del.pack(side=tk.LEFT, padx=4)
        self.btn_edit.config(state=tk.DISABLED)
        self.btn_del.config(state=tk.DISABLED)

        self._load()

    def _ensure_schema(self, cur):
        try:
            cur.execute("PRAGMA table_info(usuarios)")
            cols = [r[1] for r in cur.fetchall()]
            if 'activo' not in cols:
                try:
                    cur.execute("ALTER TABLE usuarios ADD COLUMN activo INTEGER NOT NULL DEFAULT 1")
                except Exception:
                    pass
        except Exception:
            pass

    def _load(self):
        self.tree.delete(*self.tree.get_children())
        with get_connection() as conn:
            cur = conn.cursor()
            self._ensure_schema(cur)
            cur.execute("SELECT usuario, rol FROM usuarios WHERE COALESCE(activo,1)=1 ORDER BY usuario")
            for usuario, rol in cur.fetchall():
                self.tree.insert('', 'end', values=(usuario, rol))

    def _on_select(self):
        sel = self.tree.selection()
        state = tk.NORMAL if sel else tk.DISABLED
        self.btn_edit.config(state=state)
        self.btn_del.config(state=state)

    def _agregar(self):
        self._open_form()

    def _editar(self):
        sel = self.tree.selection()
        if not sel:
            return
        values = self.tree.item(sel[0], 'values')
        self._open_form(usuario=values[0], rol=values[1])

    def _eliminar(self):
        sel = self.tree.selection()
        if not sel:
            return
        usuario = self.tree.item(sel[0], 'values')[0]
        if str(usuario).strip().lower() in ("admin", "cajero"):
            messagebox.showwarning("Usuarios", "No se pueden eliminar los usuarios 'admin' y 'cajero'.")
            return
        if not messagebox.askyesno(
            "Eliminar",
            f"¿Dar de baja (inactivar) al usuario '{usuario}'?\nLa eliminación es lógica (activo=0)."
        ):
            return
        with get_connection() as conn:
            cur = conn.cursor()
            self._ensure_schema(cur)
            # No dejar sin administradores activos
            try:
                cur.execute("SELECT COUNT(*) FROM usuarios WHERE rol='administrador' AND COALESCE(activo,1)=1")
                cnt_admin = (cur.fetchone() or [0])[0]
                if cnt_admin <= 1:
                    cur.execute("SELECT rol FROM usuarios WHERE usuario=?", (usuario,))
                    r = cur.fetchone()
                    if r and str(r[0]).lower() == 'administrador':
                        messagebox.showwarning("Usuarios", "No se puede eliminar el último administrador.")
                        return
            except Exception:
                pass
            cur.execute("UPDATE usuarios SET activo=0 WHERE usuario=?", (usuario,))
            conn.commit()
        self._load()

    def _open_form(self, usuario=None, rol='cajero'):
        win = tk.Toplevel(self)
        win.title("Usuario")
        win.transient(self)
        win.grab_set()
        ancho, alto = 360, 260
        x = win.winfo_screenwidth() // 2 - ancho // 2
        y = win.winfo_screenheight() // 2 - alto // 2
        win.geometry(f"{ancho}x{alto}+{x}+{y}")

        tk.Label(win, text="Usuario:", font=("Arial", 12)).pack(pady=(10, 4))
        entry_user = tk.Entry(win, font=("Arial", 12))
        entry_user.pack(pady=(0, 6))
        if usuario:
            entry_user.insert(0, usuario)
            entry_user.config(state='disabled')

        tk.Label(win, text="Rol:", font=("Arial", 12)).pack(pady=(4, 4))
        combo_rol = ttk.Combobox(win, values=["administrador", "cajero"], state='readonly', font=("Arial", 12))
        combo_rol.pack(pady=(0, 6))
        combo_rol.set(rol if rol in ("administrador", "cajero") else "cajero")

        tk.Label(win, text="Contraseña:" + (" (dejar vacío para no cambiar)" if usuario else ""), font=("Arial", 12)).pack(pady=(4, 4))
        entry_pass = tk.Entry(win, font=("Arial", 12), show='*')
        entry_pass.pack(pady=(0, 10))

        def guardar():
            u = (entry_user.get() or '').strip()
            r = combo_rol.get().strip()
            p = (entry_pass.get() or '').strip()
            if not u or not r:
                messagebox.showwarning("Usuarios", "Complete usuario y rol.")
                return
            with get_connection() as conn:
                cur = conn.cursor()
                self._ensure_schema(cur)
                if usuario is None:
                    if not p:
                        messagebox.showwarning("Usuarios", "Ingrese una contraseña.")
                        return
                    try:
                        cur.execute("INSERT INTO usuarios (usuario, password, rol, activo) VALUES (?, ?, ?, 1)", (u, p, r))
                        conn.commit()
                    except Exception as e:
                        messagebox.showerror("Usuarios", f"No se pudo crear el usuario.\n{e}")
                        return
                else:
                    try:
                        if p:
                            cur.execute("UPDATE usuarios SET password=?, rol=? WHERE usuario=?", (p, r, u))
                        else:
                            cur.execute("UPDATE usuarios SET rol=? WHERE usuario=?", (r, u))
                        conn.commit()
                    except Exception as e:
                        messagebox.showerror("Usuarios", f"No se pudo actualizar el usuario.\n{e}")
                        return
            self._load()
            win.destroy()

        tk.Button(win, text="Guardar", command=guardar, bg="#166534", fg="white", width=12).pack(pady=6)
        tk.Button(win, text="Cancelar", command=win.destroy, width=12).pack(pady=2)
