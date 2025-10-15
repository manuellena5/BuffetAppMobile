import os
import sqlite3
import shutil
import datetime
import tkinter as tk
from tkinter import messagebox
from theme import themed_button, apply_button_style, COLORS


# HerramientasView centraliza la gestión de backups y el test de impresora
class HerramientasView:
    def __init__(self, parent):
        self.parent = parent

    def abrir_backup_window(self, root):
        backup_win = tk.Toplevel(root)
        backup_win.title("Gestión de Backups")
        backup_win.geometry("600x400")

        # Local backup button (writes to %LOCALAPPDATA%\BuffetApp\backup)
        btn_local = themed_button(backup_win, text="Realizar Backup Local (AppData)", command=lambda: self.backup_local(parent=backup_win))
        apply_button_style(btn_local)
        btn_local.pack(pady=6)

        btn_backup = themed_button(backup_win, text="Realizar Backup Manual (Drive)", command=lambda: self.backup_to_drive(refresh_list=True, parent=backup_win))
        apply_button_style(btn_backup)
        btn_backup.pack(pady=6)

        lbl = tk.Label(backup_win, text="Backups disponibles en Google Drive:")
        lbl.pack()
        listbox = tk.Listbox(backup_win, width=80)
        listbox.pack(pady=10, fill=tk.BOTH, expand=True)

        btn_restore = tk.Button(backup_win, text="Restaurar Backup Seleccionado", command=lambda: self.restore_from_drive(listbox, parent=backup_win))
        btn_restore.pack(pady=10)

        # try to populate both drive list and local list
        self.cargar_lista_backups(listbox, parent=backup_win)
        try:
            # also populate local backups into the same listbox (top of list)
            from utils_paths import appdata_dir
            bdir = os.path.join(appdata_dir(), 'backup')
            if os.path.exists(bdir):
                for fn in sorted(os.listdir(bdir), reverse=True):
                    listbox.insert(0, fn)
        except Exception:
            pass

    def cargar_lista_backups(self, listbox, parent=None):
        try:
            from pydrive.auth import GoogleAuth
            from pydrive.drive import GoogleDrive
        except ImportError:
            # silently ignore PyDrive absence; the UI still shows local backups
            return
        try:
            gauth = GoogleAuth()
            gauth.LocalWebserverAuth()
            drive = GoogleDrive(gauth)
            folder_name = "BuffetApp_Backups"
            folder_id = None
            file_list = drive.ListFile({'q': f"title='{folder_name}' and mimeType='application/vnd.google-apps.folder' and trashed=false"}).GetList()
            if file_list:
                folder_id = file_list[0]['id']
            else:
                folder_metadata = {'title': folder_name, 'mimeType': 'application/vnd.google-apps.folder'}
                folder = drive.CreateFile(folder_metadata)
                folder.Upload()
                folder_id = folder['id']
            query = f"'{folder_id}' in parents and trashed=false"
            backups = drive.ListFile({'q': query}).GetList()
            listbox.delete(0, tk.END)
            for f in sorted(backups, key=lambda x: x['title'], reverse=True):
                listbox.insert(tk.END, f["title"])
            listbox.folder_id = folder_id
            listbox.drive = drive
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo cargar la lista de backups.\n\nDetalle: {e}")

    def backup_to_drive(self, refresh_list=False, parent=None):
        try:
            from pydrive.auth import GoogleAuth
            from pydrive.drive import GoogleDrive
        except ImportError:
            messagebox.showerror("Error", "PyDrive no está instalado. Ejecuta 'pip install pydrive' en la terminal.")
            return
        db_path = os.path.join(os.path.dirname(__file__), "barcancha.db")
        if not os.path.exists(db_path):
            messagebox.showerror("Error", "No se encontró el archivo de base de datos barcancha.db.")
            return
        try:
            gauth = GoogleAuth()
            gauth.LocalWebserverAuth()
            drive = GoogleDrive(gauth)
            folder_name = "BuffetApp_Backups"
            folder_id = None
            file_list = drive.ListFile({'q': f"title='{folder_name}' and mimeType='application/vnd.google-apps.folder' and trashed=false"}).GetList()
            if file_list:
                folder_id = file_list[0]['id']
            else:
                folder_metadata = {'title': folder_name, 'mimeType': 'application/vnd.google-apps.folder'}
                folder = drive.CreateFile(folder_metadata)
                folder.Upload()
                folder_id = folder['id']
            fecha = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
            file_drive = drive.CreateFile({'title': f'barcancha_backup_{fecha}.db', 'parents': [{'id': folder_id}]})
            file_drive.SetContentFile(db_path)
            file_drive.Upload()
            messagebox.showinfo("Backup", f"Backup subido a Google Drive como barcancha_backup_{fecha}.db en la carpeta {folder_name}")
            if refresh_list and parent:
                for widget in parent.winfo_children():
                    if isinstance(widget, tk.Listbox):
                        self.cargar_lista_backups(widget, parent=parent)
        except Exception as e:
            messagebox.showerror("Error de backup", f"No se pudo subir el backup a Google Drive.\n\nDetalle: {e}")

    def backup_local(self, parent=None):
        """Create a local backup under %LOCALAPPDATA%\BuffetApp\backup using db_migrations.backup_db() if available, otherwise fallback inline."""
        try:
            try:
                from db_migrations import backup_db
            except Exception:
                backup_db = None

            def _refresh_listbox(parent_win):
                if not parent_win:
                    return
                for w in parent_win.winfo_children():
                    if isinstance(w, tk.Listbox):
                        try:
                            w.delete(0, tk.END)
                            from utils_paths import appdata_dir
                            bdir = os.path.join(appdata_dir(), 'backup')
                            if os.path.exists(bdir):
                                for fn in sorted(os.listdir(bdir), reverse=True):
                                    w.insert(tk.END, fn)
                        except Exception:
                            pass

            if callable(backup_db):
                path = backup_db()
                try:
                    from utils_paths import appdata_dir
                    log_path = os.path.join(appdata_dir(), 'backup_logs.txt')
                    with open(log_path, 'a', encoding='utf-8') as lf:
                        lf.write(f"{datetime.datetime.now().isoformat()} - manual backup created: {path}\n")
                except Exception:
                    pass
                messagebox.showinfo('Backup local', f'Backup creado: {path}')
                _refresh_listbox(parent)
                return

            # Fallback inline: use DB_PATH and sqlite online backup API
            from utils_paths import DB_PATH, appdata_dir
            ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
            bdir = os.path.join(appdata_dir(), 'backup')
            os.makedirs(bdir, exist_ok=True)
            dst = os.path.join(bdir, f'barcancha_{ts}.db')
            try:
                src_conn = sqlite3.connect(DB_PATH)
                dest_conn = sqlite3.connect(dst)
                with dest_conn:
                    src_conn.backup(dest_conn)
                try:
                    dest_conn.close()
                except Exception:
                    pass
                try:
                    src_conn.close()
                except Exception:
                    pass
                # log & notify
                try:
                    log_path = os.path.join(appdata_dir(), 'backup_logs.txt')
                    with open(log_path, 'a', encoding='utf-8') as lf:
                        lf.write(f"{datetime.datetime.now().isoformat()} - inline backup created: {dst}\n")
                except Exception:
                    pass
                messagebox.showinfo('Backup local', f'Backup creado: {dst}')
                _refresh_listbox(parent)
                return
            except Exception as e:
                # fallback to file copy
                try:
                    shutil.copy2(DB_PATH, dst)
                    try:
                        log_path = os.path.join(appdata_dir(), 'backup_logs.txt')
                        with open(log_path, 'a', encoding='utf-8') as lf:
                            lf.write(f"{datetime.datetime.now().isoformat()} - inline backup copied: {dst}\n")
                    except Exception:
                        pass
                    messagebox.showinfo('Backup local', f'Backup creado (copiado): {dst}')
                    _refresh_listbox(parent)
                    return
                except Exception as e2:
                    try:
                        log_path = os.path.join(appdata_dir(), 'backup_logs.txt')
                        with open(log_path, 'a', encoding='utf-8') as lf:
                            lf.write(f"{datetime.datetime.now().isoformat()} - manual backup failed: {e2}\n")
                    except Exception:
                        pass
                    messagebox.showerror('Backup local', f'Error creando backup local: {e2}')
                    return
        except Exception as e:
            messagebox.showerror('Backup local', f'Error inesperado: {e}')

    def restore_from_drive(self, listbox, parent=None):
        sel = listbox.curselection()
        if not sel:
            messagebox.showwarning("Restaurar", "Selecciona un backup de la lista.")
            return
        filename = listbox.get(sel[0])
        confirm = messagebox.askyesno("Confirmar restauración", f"¿Seguro que quieres restaurar el backup '{filename}'?\nEsto reemplazará la base de datos local y no se puede deshacer.")
        if not confirm:
            return
        try:
            drive = listbox.drive
            folder_id = listbox.folder_id
            query = f"title='{filename}' and '{folder_id}' in parents and trashed=false"
            files = drive.ListFile({'q': query}).GetList()
            if not files:
                messagebox.showerror("Restaurar", "No se encontró el archivo en Drive.")
                return
            file_drive = files[0]
            db_path = os.path.join(os.path.dirname(__file__), "barcancha.db")
            file_drive.GetContentFile(db_path)
            messagebox.showinfo("Restaurar", f"Backup restaurado correctamente desde Google Drive: {filename}\n\nLa base de datos local ha sido reemplazada.")
        except Exception as e:
            messagebox.showerror("Error de restauración", f"No se pudo restaurar el backup.\n\nDetalle: {e}")

    def test_impresora(self):
            try:
                import win32print
                import win32ui
                printer_name = win32print.GetDefaultPrinter()
                try:
                    hPrinter = win32print.OpenPrinter(printer_name)
                    printer_info = win32print.GetPrinter(hPrinter, 2)
                    status = printer_info['Status']
                    PRINTER_STATUS_OFFLINE = 0x00000080
                    PRINTER_STATUS_ERROR = 0x00000002
                    PRINTER_STATUS_NOT_AVAILABLE = 0x00001000
                    if status & PRINTER_STATUS_OFFLINE or status & PRINTER_STATUS_ERROR or status & PRINTER_STATUS_NOT_AVAILABLE:
                        win32print.ClosePrinter(hPrinter)
                        messagebox.showerror("Estado de impresora", f"La impresora '{printer_name}' está offline, en error o no disponible.\n\nVerifica la conexión y el estado.")
                        return
                    win32print.ClosePrinter(hPrinter)
                except Exception as e:
                    messagebox.showerror("Estado de impresora", f"No se pudo obtener el estado de la impresora: {printer_name}\n\nDetalle: {e}")
                    return
                pdc = None
                try:
                    pdc = win32ui.CreateDC()
                    pdc.CreatePrinterDC(printer_name)
                    pdc.StartDoc("Test Impresora")
                    pdc.StartPage()
                    y = 100
                    pdc.TextOut(200, y, "TEST IMPRESORA")
                    y += 50
                    pdc.TextOut(200, y, "Si ves esto, la impresora funciona.")
                    pdc.EndPage()
                    pdc.EndDoc()
                    messagebox.showinfo("Test Impresora", f"Se envió una página de prueba a: {printer_name}")
                except Exception as e:
                    messagebox.showerror("Error de impresión", f"No se pudo imprimir en la impresora: {printer_name}\n\nVerifica que esté conectada y encendida.\n\nDetalle: {e}")
                finally:
                    if pdc:
                        try:
                            pdc.DeleteDC()
                        except Exception:
                            pass
            except Exception as e:
                messagebox.showerror("Error de impresión", f"No se pudo obtener la impresora predeterminada.\n\nDetalle: {e}")
    