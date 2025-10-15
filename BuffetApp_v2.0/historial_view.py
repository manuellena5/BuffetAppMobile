import tkinter as tk
from tkinter import messagebox
from tkinter import ttk
from init_db import log_error
from db_utils import get_connection

class HistorialView(tk.Frame):
    def __init__(self, master):
        super().__init__(master)
        self.label_historial = tk.Label(self, text="Historial de Ventas", font=("Arial", 18))
        self.label_historial.pack(pady=10)
        # Filtros debajo del título
        self.frame_filtro_fecha = tk.Frame(self)
        self.frame_filtro_fecha.pack(fill=tk.X, pady=(0,8))
        tk.Label(self.frame_filtro_fecha, text="Filtrar por fecha:", font=("Arial", 11)).pack(side=tk.LEFT, padx=5)
        self.var_fecha = tk.StringVar()
        self.combo_fecha = None
        self.actualizar_fechas_combo()
        tk.Label(self.frame_filtro_fecha, text="Caja:", font=("Arial", 11)).pack(side=tk.LEFT, padx=5)
        self.var_caja = tk.StringVar()
        self.combo_caja = None
        self.cajas_rows = []
        self.actualizar_cajas_combo()
        self.var_fecha.trace_add('write', self._on_fecha_cambiada)
        self.var_caja.trace_add('write', self.on_filtro_cambiado)
        self.var_ocultar_anulados = tk.BooleanVar(value=False)
        self.chk_ocultar = tk.Checkbutton(self.frame_filtro_fecha, text="Ocultar anulados", variable=self.var_ocultar_anulados, command=self.on_filtro_cambiado)
        self.chk_ocultar.pack(side=tk.LEFT, padx=5)

        from theme import apply_treeview_style, FONTS
        style = apply_treeview_style()
        # asegúrate de usar el style namespaced 'App.Treeview' para este Treeview
        style.configure('App.Treeview', font=FONTS['normal'])
        style.configure('App.Treeview.Heading', font=FONTS['bold'])
        # Contenedor principal del listado (árbol + scrollbar) para permitir expansión
        self.content_frame = tk.Frame(self)
        self.content_frame.pack(fill=tk.BOTH, expand=True, padx=0, pady=(4, 4))
        self.tree = ttk.Treeview(
            self.content_frame,
            columns=("fecha_hora", "item", "total", "categoria", "status", "codigo_caja", "identificador", "metodo_pago"),
            show="headings",
            style='App.Treeview',
        )
        self.tree.heading("fecha_hora", text="Fecha")
        self.tree.heading("item", text="Item")
        self.tree.heading("total", text="Monto Total")
        self.tree.heading("categoria", text="Categoria")
        self.tree.heading("status", text="Estado")
        self.tree.heading("codigo_caja", text="Caja")
        self.tree.heading("identificador", text="Identificador")
        self.tree.heading("metodo_pago", text="Método de Pago")
        self.tree.column("fecha_hora", width=120)
        self.tree.column("item", width=100)
        self.tree.column("total", width=100, anchor=tk.E)
        self.tree.column("categoria", width=75)
        self.tree.column("status", width=75)
        self.tree.column("codigo_caja", width=140)
        self.tree.column("identificador", width=125)
        self.tree.column("metodo_pago", width=120)
        self.scrollbar = ttk.Scrollbar(self.content_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=self.scrollbar.set)
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.scrollbar.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 8))

        # Acciones horizontales (reutilizamos el nombre del frame para compatibilidad externa)
        self.frame_botones_tabla = tk.Frame(self)
        self.frame_botones_tabla.pack(fill=tk.X, pady=(0, 6))
        self.btn_reimprimir = tk.Button(self.frame_botones_tabla, text="Reimprimir Ticket", font=("Arial", 10), command=self.reimprimir_ticket_seleccionado)
        self.btn_reimprimir.pack(side=tk.LEFT, padx=4)
        self.btn_actualizar = tk.Button(
            self.frame_botones_tabla,
            text="Actualizar",
            font=("Arial", 10),
            command=lambda: self.cargar_historial(
                self.var_fecha.get() if self.var_fecha.get() != "Mostrar todo" else None,
                self.cajas_rows[self.combo_caja.current()-1][0]
                if self.combo_caja and self.combo_caja.current() > 0 and self.combo_caja.current()-1 < len(self.cajas_rows)
                else None,
                1,
            ),
        )
        self.btn_actualizar.pack(side=tk.LEFT, padx=4)
        self.btn_exportar = tk.Button(self.frame_botones_tabla, text="Exportar a Excel", font=("Arial", 10), command=self.exportar_excel)
        self.btn_exportar.pack(side=tk.LEFT, padx=4)
        self.btn_anular = tk.Button(self.frame_botones_tabla, text="Anular Ticket", font=("Arial", 10), command=self.anular_ticket)
        self.btn_anular.pack(side=tk.LEFT, padx=4)

        # Paginación
        self.frame_paginacion = tk.Frame(self)
        self.frame_paginacion.pack(pady=(0, 6))
        self.btn_prev = tk.Button(self.frame_paginacion, text="<", width=3, command=self.previa, state=tk.DISABLED)
        self.btn_prev.pack(side=tk.LEFT, padx=6)
        self.lbl_pagina = tk.Label(self.frame_paginacion, text="1 de 1")
        self.lbl_pagina.pack(side=tk.LEFT, padx=6)
        self.btn_next = tk.Button(self.frame_paginacion, text=">", width=3, command=self.siguiente, state=tk.DISABLED)
        self.btn_next.pack(side=tk.LEFT, padx=6)
        self.filas_por_pagina = 33
        self.pagina_actual = 1
        self.total_paginas = 1
        self.historial_rows = []
        self.filtro_fecha = None
        self.filtro_caja = None


        # (Removido) Botón Salir local para no interferir con el layout ni duplicar controles

        # cargar historial filtrando por la caja seleccionada por defecto
        self.on_filtro_cambiado()

    def actualizar_fechas_combo(self):
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT DISTINCT substr(fecha_hora, 1, 10) FROM ventas ORDER BY fecha_hora DESC")
        fechas = [row[0] for row in cursor.fetchall()]
        conn.close()
        fechas_combo = ["Mostrar todo"] + fechas
        if self.combo_fecha:
            self.combo_fecha['values'] = fechas_combo
        else:
            self.combo_fecha = ttk.Combobox(
                self.frame_filtro_fecha,
                textvariable=self.var_fecha,
                values=fechas_combo,
                state="readonly",
                width=20,
            )
            self.combo_fecha.pack(side=tk.LEFT, padx=5)
            self.combo_fecha.current(0)

    def actualizar_cajas_combo(self):
        conn = get_connection()
        cursor = conn.cursor()
        fecha = self.var_fecha.get()
        if fecha and fecha != "Mostrar todo":
            cursor.execute(
                "SELECT id, codigo_caja, estado FROM caja_diaria WHERE fecha=? ORDER BY hora_apertura",
                (fecha,),
            )
        else:
            cursor.execute(
                "SELECT id, codigo_caja, estado FROM caja_diaria ORDER BY fecha DESC, hora_apertura DESC",
            )
        self.cajas_rows = cursor.fetchall()
        conn.close()
        cajas_combo = ["Todas"] + [
            f"{row[1]} (abierta)" if row[2] == 'abierta' else row[1] for row in self.cajas_rows
        ]
        if self.combo_caja:
            self.combo_caja['values'] = cajas_combo
        else:
            self.combo_caja = ttk.Combobox(
                self.frame_filtro_fecha,
                textvariable=self.var_caja,
                values=cajas_combo,
                state="readonly",
                width=25,
            )
            self.combo_caja.pack(side=tk.LEFT, padx=5)
        self.combo_caja.current(0)

    def _on_fecha_cambiada(self, *args):
        self.actualizar_cajas_combo()
        self.on_filtro_cambiado()


    def on_filtro_cambiado(self, *args):
        fecha = self.var_fecha.get()
        if fecha == "Mostrar todo" or not fecha:
            fecha = None
        caja_id = None
        if self.combo_caja:
            idx = self.combo_caja.current()
            if idx > 0 and idx - 1 < len(self.cajas_rows):
                caja_id = self.cajas_rows[idx - 1][0]
        self.cargar_historial(fecha, caja_id, 1)

    def cargar_historial(self, fecha_filtrada=None, caja_filtrada=None, pagina=1):
        try:
            # Refresh caja combo to reflect current caja states (may have changed elsewhere)
            try:
                self.actualizar_cajas_combo()
            except Exception:
                pass
            self.filtro_fecha = fecha_filtrada
            self.filtro_caja = caja_filtrada
            conn = get_connection()
            cursor = conn.cursor()

            base_query = """
                FROM venta_items vi
                LEFT JOIN tickets t ON vi.ticket_id = t.id
                LEFT JOIN ventas v ON t.venta_id = v.id
                LEFT JOIN products p ON vi.producto_id = p.id
                LEFT JOIN Categoria_Producto c ON t.categoria_id = c.id
                LEFT JOIN caja_diaria cd ON v.caja_id = cd.id
                LEFT JOIN metodos_pago mp ON v.metodo_pago_id = mp.id
            """

            filtros = []
            params = []
            if fecha_filtrada:
                filtros.append("substr(v.fecha_hora, 1, 10) = ?")
                params.append(fecha_filtrada)
            if caja_filtrada:
                filtros.append("v.caja_id = ?")
                params.append(caja_filtrada)
            if self.var_ocultar_anulados.get():
                filtros.append("t.status != 'Anulado'")

            where_clause = ""
            if filtros:
                where_clause = " WHERE " + " AND ".join(filtros)

            count_query = "SELECT COUNT(*) " + base_query + where_clause
            cursor.execute(count_query, params)
            total_rows = cursor.fetchone()[0]
            self.total_paginas = max(1, (total_rows + self.filas_por_pagina - 1) // self.filas_por_pagina)

            offset = (pagina - 1) * self.filas_por_pagina
            select_query = (
                "SELECT v.fecha_hora, t.identificador_ticket, p.nombre, vi.cantidad, vi.subtotal, "
                "c.descripcion, t.status, cd.codigo_caja, cd.disciplina, t.id, v.id, mp.descripcion as metodo_pago "
                + base_query + where_clause +
                " ORDER BY v.fecha_hora DESC, v.id, t.categoria_id LIMIT ? OFFSET ?"
            )
            cursor.execute(select_query, params + [self.filas_por_pagina, offset])
            rows = cursor.fetchall()
            conn.close()

            self.historial_rows = rows
            self.pagina_actual = pagina
            self.mostrar_pagina()
        except Exception as e:
            import datetime, traceback
            fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            tb = traceback.extract_tb(e.__traceback__)
            linea = tb[-1].lineno if tb else 'N/A'
            modulo = tb[-1].filename if tb else 'HistorialView.cargar_historial'
            mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
            try:
                log_error(fecha_hora, modulo, mensaje)
            except Exception:
                pass
            messagebox.showerror("Error de historial", "No se pudo cargar el historial por un error del sistema.")

    def mostrar_pagina(self):
        self.tree.delete(*self.tree.get_children())
        rows = self.historial_rows
        last_caja = None
        color1 = '#F5F5F5'
        color2 = "#D2ECFF"
        current_color = color1
        for row in rows:
            (
                fecha_hora,
                identificador,
                nombre,
                cantidad,
                subtotal,
                categoria,
                status,
                codigo_caja,
                disciplina,
                ticket_id,
                venta_id,
                metodo_pago
            ) = row
            if codigo_caja != last_caja:
                current_color = color2 if current_color == color1 else color1
                last_caja = codigo_caja
            try:
                monto_str = f"$ {int(round(float(subtotal))):,}".replace(",", ".")
            except Exception:
                monto_str = f"$ {subtotal}"
            bg = '#D3D3D3' if str(status).lower() == 'anulado' else current_color
            self.tree.insert(
                "",
                tk.END,
                values=(
                    fecha_hora,
                    nombre,
                    monto_str,
                    categoria,
                    status,
                    codigo_caja,
                    identificador,
                    metodo_pago or ""
                ),
                tags=(str(ticket_id),),
            )
            self.tree.tag_configure(str(ticket_id), background=bg)

        self.lbl_pagina.config(text=f"{self.pagina_actual} de {self.total_paginas}")
        self.btn_prev.config(state=(tk.NORMAL if self.pagina_actual > 1 else tk.DISABLED))
        self.btn_next.config(state=(tk.NORMAL if self.pagina_actual < self.total_paginas else tk.DISABLED))

    def previa(self):
        if self.pagina_actual > 1:
            nueva = self.pagina_actual - 1
            self.cargar_historial(self.filtro_fecha, self.filtro_caja, nueva)

    def siguiente(self):
        if self.pagina_actual < self.total_paginas:
            nueva = self.pagina_actual + 1
            self.cargar_historial(self.filtro_fecha, self.filtro_caja, nueva)

    def exportar_excel(self):
        try:
            import pandas as pd
        except ImportError:
            messagebox.showwarning(
                "Exportar",
                "La exportación a Excel requiere 'pandas' (no incluido en la versión ligera).\n"
                "Opciones:\n"
                " 1) Instalar: pip install pandas (y volver a generar el exe si querés redistribuir).\n"
                " 2) Usar copiar datos: se generará un TSV provisional en el portapapeles."
            )
            try:
                # Fallback: copiar al portapapeles datos visibles (solo página actual) en formato tabulado
                filas = []
                for item in self.tree.get_children():
                    vals = self.tree.item(item, 'values')
                    filas.append('\t'.join(str(v) for v in vals))
                if filas:
                    self.root.clipboard_clear()
                    self.root.clipboard_append('\n'.join(filas))
                    messagebox.showinfo("Exportar", "Datos de la página actual copiados al portapapeles (TSV).")
            except Exception:
                pass
            return
        import os
        import datetime
        # Exportar todos los datos aplicando los filtros actuales
        try:
            conn = get_connection()
            cursor = conn.cursor()
            query = """
                SELECT v.fecha_hora, t.identificador_ticket, p.nombre, vi.cantidad, vi.subtotal,
                       c.descripcion, t.status, cd.codigo_caja, cd.disciplina, mp.descripcion as metodo_pago
                FROM venta_items vi
                LEFT JOIN tickets t ON vi.ticket_id = t.id
                LEFT JOIN ventas v ON t.venta_id = v.id
                LEFT JOIN products p ON vi.producto_id = p.id
                LEFT JOIN Categoria_Producto c ON t.categoria_id = c.id
                LEFT JOIN caja_diaria cd ON v.caja_id = cd.id
                LEFT JOIN metodos_pago mp ON v.metodo_pago_id = mp.id
            """
            filtros = []
            params = []
            if self.filtro_fecha:
                filtros.append("substr(v.fecha_hora, 1, 10) = ?")
                params.append(self.filtro_fecha)
            if self.filtro_caja:
                filtros.append("v.caja_id = ?")
                params.append(self.filtro_caja)
            if self.var_ocultar_anulados.get():
                filtros.append("t.status != 'Anulado'")
            if filtros:
                query += " WHERE " + " AND ".join(filtros)
            query += " ORDER BY v.fecha_hora DESC, v.id, t.categoria_id"
            cursor.execute(query, params)
            rows = cursor.fetchall()
            conn.close()
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo obtener el historial completo.\n\nDetalle: {e}")
            return
        df = pd.DataFrame([
            {
                "Fecha": r[0],
                "Item": r[2],
                "Monto Total": r[4],
                "Categoria": r[5],
                "Estado": r[6],
                "Caja (código)": r[7],
                "Identificador": r[1],
                "Método de Pago": r[9],
                "Cantidad": r[3],
                "Disciplina": r[8],
            }
            for r in rows
        ])
        fecha = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        # Carpeta Descargas del usuario
        from pathlib import Path
        downloads = str(Path.home() / "Downloads")
        filename = os.path.join(downloads, f"historial_ventas_{fecha}.xlsx")
        try:
            df.to_excel(filename, index=False)
            messagebox.showinfo("Exportar a Excel", f"Historial exportado correctamente a:\n{filename}")
            try:
                os.startfile(filename)
            except Exception:
                pass
        except Exception as e:
            messagebox.showerror("Error de exportación", f"No se pudo exportar el historial a Excel.\n\nDetalle: {e}")

    def reimprimir_ticket_seleccionado(self):
        seleccion = self.tree.selection()
        if not seleccion:
            messagebox.showinfo("Reimpresión", "Seleccione un ticket para reimprimir.")
            return
        ticket_id = int(self.tree.item(seleccion[0], "tags")[0])
        self.reimprimir_ticket(ticket_id)


    def reimprimir_ticket(self, ticket_id):
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT v.fecha_hora, t.status, t.identificador_ticket, c.descripcion, cd.codigo_caja, cd.disciplina FROM tickets t LEFT JOIN ventas v ON t.venta_id = v.id LEFT JOIN Categoria_Producto c ON t.categoria_id = c.id LEFT JOIN caja_diaria cd ON v.caja_id = cd.id WHERE t.id=?", (ticket_id,))
            ticket = cursor.fetchone()
            if not ticket:
                messagebox.showerror("Reimpresión", "No se encontró el ticket.")
                conn.close()
                return
            fecha_hora, status, identificador_ticket, categoria, codigo_caja, disciplina = ticket
            if status == 'Impreso':
                if not messagebox.askyesno("Reimpresión", "El ticket ya fue impreso. ¿Desea reimprimir de todos modos?"):
                    conn.close()
                    return
            # Obtener items
            cursor.execute("SELECT cantidad, producto_id FROM venta_items WHERE ticket_id=?", (ticket_id,))
            items = cursor.fetchall()
            productos = []
            for cantidad, producto_id in items:
                cursor.execute("SELECT nombre FROM products WHERE id=?", (producto_id,))
                nombre = cursor.fetchone()[0]
                productos.append((cantidad, nombre, categoria))
            from ventas_view_new import VentasViewNew
            exito = True
            for cantidad, nombre, _ in productos:
                for _ in range(cantidad):
                    ok = VentasViewNew.imprimir_ticket_por_item_win32_static(
                        fecha_hora,
                        nombre,
                        ticket_id,
                        identificador_ticket,
                        codigo_caja,
                        disciplina,
                    )
                    if not ok:
                        exito = False
            nuevo_status = 'Impreso' if exito else 'No impreso'
            cursor.execute("UPDATE tickets SET status=? WHERE id=?", (nuevo_status, ticket_id))
            conn.commit()
            conn.close()
            messagebox.showinfo("Reimpresión", f"Ticket {'impreso' if exito else 'NO impreso'}.")
            self.cargar_historial(self.filtro_fecha, self.filtro_caja, self.pagina_actual)
        except Exception as e:
            import datetime, traceback
            fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            tb = traceback.extract_tb(e.__traceback__)
            linea = tb[-1].lineno if tb else 'N/A'
            modulo = tb[-1].filename if tb else 'HistorialView.reimprimir_ticket'
            mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
            try:
                log_error(fecha_hora, modulo, mensaje)
            except Exception:
                pass
            messagebox.showerror("Error de reimpresión", "No se pudo reimprimir el ticket por un error del sistema.")

    def anular_ticket(self):
        seleccion = self.tree.selection()
        if not seleccion:
            messagebox.showinfo("Anular Ticket", "Seleccione un ticket para anular.")
            return
        ticket_id = int(self.tree.item(seleccion[0], "tags")[0])
        if not messagebox.askyesno("Anular Ticket", "¿Confirma que desea anular el ticket seleccionado?"):
            return
        try:
            conn = get_connection()
            cursor = conn.cursor()
            # Marcar ticket como anulado
            cursor.execute("UPDATE tickets SET status='Anulado' WHERE id=?", (ticket_id,))
            # Devolver el stock de los productos asociados
            cursor.execute("SELECT producto_id, cantidad FROM venta_items WHERE ticket_id=?", (ticket_id,))
            items = cursor.fetchall()
            for prod_id, cantidad in items:
                cursor.execute("SELECT stock_actual FROM products WHERE id=?", (prod_id,))
                stock_actual = cursor.fetchone()[0]
                if stock_actual != 999:
                    nuevo_stock = stock_actual + cantidad
                    cursor.execute("UPDATE products SET stock_actual=? WHERE id=?", (nuevo_stock, prod_id))
            conn.commit()
            conn.close()
            self.cargar_historial(self.filtro_fecha, self.filtro_caja, self.pagina_actual)
            messagebox.showinfo("Anular Ticket", "Ticket anulado y stock actualizado.")
        except Exception as e:
            import datetime, traceback
            fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            tb = traceback.extract_tb(e.__traceback__)
            linea = tb[-1].lineno if tb else 'N/A'
            modulo = tb[-1].filename if tb else 'HistorialView.anular_ticket'
            mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
            try:
                log_error(fecha_hora, modulo, mensaje)
            except Exception:
                pass
            messagebox.showerror("Anular Ticket", "No se pudo anular el ticket por un error del sistema.")

    def on_tree_double_click(self, event):
        item = self.tree.identify_row(event.y)
        col = self.tree.identify_column(event.x)
        if not item or col != '#4':
            return
        ticket_id = int(self.tree.item(item, "tags")[0])
        self.reimprimir_ticket(ticket_id)

    def editar_venta(self):
        seleccion = self.tree.selection()
        if not seleccion:
            messagebox.showinfo("Editar Ticket", "Seleccione un ticket para editar.")
            return
        try:
            ticket_id = int(self.tree.item(seleccion[0], "tags")[0])
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT v.fecha_hora, t.total_ticket, c.descripcion FROM tickets t LEFT JOIN ventas v ON t.venta_id = v.id LEFT JOIN Categoria_Producto c ON t.categoria_id = c.id WHERE t.id=?", (ticket_id,))
            ticket = cursor.fetchone()
            conn.close()
            edit_win = tk.Toplevel(self)
            edit_win.title("Editar Ticket")
            tk.Label(edit_win, text=f"ID Ticket: {ticket_id}", font=("Arial", 12)).pack(pady=5)
            tk.Label(edit_win, text="Fecha y Hora:", font=("Arial", 12)).pack()
            entry_fecha = tk.Entry(edit_win, font=("Arial", 12))
            entry_fecha.pack()
            entry_fecha.insert(0, ticket[0])
            tk.Label(edit_win, text="Total Ticket:", font=("Arial", 12)).pack()
            entry_total = tk.Entry(edit_win, font=("Arial", 12))
            entry_total.pack()
            entry_total.insert(0, ticket[1])
            tk.Label(edit_win, text=f"Categoría: {ticket[2]}", font=("Arial", 12)).pack(pady=5)
            def guardar_edicion():
                try:
                    nueva_fecha = entry_fecha.get()
                    nuevo_total = entry_total.get()
                    conn = get_connection()
                    cursor = conn.cursor()
                    cursor.execute("UPDATE tickets SET fecha_hora=?, total_ticket=? WHERE id=?", (nueva_fecha, nuevo_total, ticket_id))
                    conn.commit()
                    conn.close()
                    edit_win.destroy()
                    self.cargar_historial(self.filtro_fecha, self.filtro_caja, self.pagina_actual)
                    messagebox.showinfo("Editar Ticket", "Ticket actualizado correctamente.")
                except Exception as e:
                    import datetime, traceback
                    fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    tb = traceback.extract_tb(e.__traceback__)
                    linea = tb[-1].lineno if tb else 'N/A'
                    modulo = tb[-1].filename if tb else 'HistorialView.guardar_edicion'
                    mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
                    try:
                        log_error(fecha_hora, modulo, mensaje)
                    except Exception:
                        pass
                    messagebox.showerror("Error de edición", "No se pudo editar el ticket por un error del sistema.")
            tk.Button(edit_win, text="Guardar", font=("Arial", 12), command=guardar_edicion).pack(pady=10)
        except Exception as e:
            import datetime, traceback
            fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            tb = traceback.extract_tb(e.__traceback__)
            linea = tb[-1].lineno if tb else 'N/A'
            modulo = tb[-1].filename if tb else 'HistorialView.editar_venta'
            mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
            try:
                log_error(fecha_hora, modulo, mensaje)
            except Exception:
                pass
            messagebox.showerror("Error de edición", "No se pudo abrir la edición por un error del sistema.")

    def eliminar_venta(self):
        seleccion = self.tree.selection()
        if not seleccion:
            messagebox.showinfo("Eliminar Ticket", "Seleccione un ticket para eliminar.")
            return
        try:
            ticket_id = int(self.tree.item(seleccion[0], "tags")[0])
            confirmar = messagebox.askyesno("Confirmar eliminación", "¿Está seguro que desea eliminar el ticket seleccionado?")
            if not confirmar:
                return
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("DELETE FROM venta_items WHERE ticket_id=?", (ticket_id,))
            cursor.execute("DELETE FROM tickets WHERE id=?", (ticket_id,))
            conn.commit()
            conn.close()
            self.cargar_historial(self.filtro_fecha, self.filtro_caja, self.pagina_actual)
        except Exception as e:
            import datetime, traceback
            fecha_hora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            tb = traceback.extract_tb(e.__traceback__)
            linea = tb[-1].lineno if tb else 'N/A'
            modulo = tb[-1].filename if tb else 'HistorialView.eliminar_venta'
            mensaje = f"{type(e).__name__}: {e} (Línea {linea})"
            try:
                log_error(fecha_hora, modulo, mensaje)
            except Exception:
                pass
            messagebox.showerror("Error de eliminación", "No se pudo eliminar el ticket por un error del sistema.")
