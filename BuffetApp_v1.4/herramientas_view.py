import tkinter as tk
from tkinter import messagebox

# HerramientasView centraliza la gestión de backups y el test de impresora
class HerramientasView:
    def __init__(self, parent):
        self.parent = parent

    def abrir_backup_window(self, root):
        backup_win = tk.Toplevel(root)
        backup_win.title("Gestión de Backups")
        backup_win.geometry("600x400")

        btn_backup = tk.Button(backup_win, text="Realizar Backup Manual", command=lambda: self.backup_to_drive(refresh_list=True, parent=backup_win))
        btn_backup.pack(pady=10)

        lbl = tk.Label(backup_win, text="Backups disponibles en Google Drive:")
        lbl.pack()
        listbox = tk.Listbox(backup_win, width=80)
        listbox.pack(pady=10, fill=tk.BOTH, expand=True)

        btn_restore = tk.Button(backup_win, text="Restaurar Backup Seleccionado", command=lambda: self.restore_from_drive(listbox, parent=backup_win))
        btn_restore.pack(pady=10)

        self.cargar_lista_backups(listbox, parent=backup_win)

    def cargar_lista_backups(self, listbox, parent=None):
        try:
            from pydrive.auth import GoogleAuth
            from pydrive.drive import GoogleDrive
        except ImportError:
            messagebox.showerror("Error", "PyDrive no está instalado. Ejecuta 'pip install pydrive' en la terminal.")
            return
        import os
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
        import os
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
            import datetime
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

    def restore_from_drive(self, listbox, parent=None):
        import os
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
        import win32print
        import win32ui
        try:
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
