import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from db_utils import get_connection
from theme import apply_treeview_style, format_currency
# Permitir import tanto como paquete (BuffetApp.*) como módulo suelto (tests)
try:
    from .caja_operaciones import DetalleCajaFrame  # type: ignore
except Exception:  # ImportError cuando no se carga como paquete
    from caja_operaciones import DetalleCajaFrame  # type: ignore
import csv
import os


class CajaListadoView(tk.Frame):
	"""Full CajaListadoView: muestra listado con columnas, botones y export.

	Columnas incluyen tickets_anulados y diferencia. Export incluye esas columnas.
	"""

	# Note: 'id' is kept as the internal iid for selection but removed from visible columns
	COLUMNS = [
		('codigo', 'Código'),
		('fecha', 'Fecha'),
		('usuario', 'Usuario Apertura'),
		('fondo_inicial', 'Fondo Inicial'),
		('total_ventas', 'Total Ventas'),
		('ventas_efectivo', 'Ventas Efectivo'),
		('transferencias_final', 'Transferencias'),
		('ingresos', 'Ingresos'),
		('retiros', 'Retiros'),
		('conteo_efectivo_final', 'Conteo Efectivo Final'),
		('diferencia', 'Diferencia'),
		('total_tickets', 'Tickets'),
		('tickets_anulados', 'Tickets Anulados'),
		('estado', 'Estado'),
	]

	def __init__(self, parent, on_caja_cerrada=None):
		super().__init__(parent)
		self.on_caja_cerrada = on_caja_cerrada
		self._detalle_frame = None
		self._filter_date = None  # fecha seleccionada para filtrar (str 'YYYY-MM-DD') o None para todas
		self.var_fecha = tk.StringVar()
		self.combo_fecha = None

		# Top: botones
		self.btn_frame = tk.Frame(self)
		self.btn_frame.pack(side=tk.TOP, fill=tk.X, padx=6, pady=6)
		tk.Button(self.btn_frame, text='Ver detalle', command=self._btn_ver_detalle).pack(side=tk.LEFT, padx=4)
		tk.Button(self.btn_frame, text='Refrescar', command=self._refresh_list).pack(side=tk.LEFT, padx=4)
		# Export buttons removed per UX request

		# Filtro por fecha (Combobox, mismo estilo que historial) al lado de los botones
		tk.Label(self.btn_frame, text='Filtrar por fecha:', font=("Arial", 11)).pack(side=tk.LEFT, padx=(12, 4))
		self.actualizar_fechas_combo()
		self.var_fecha.trace_add('write', self._on_fecha_cambiada)

		# Treeview
		cols = [c[0] for c in self.COLUMNS]
		headings = [c[1] for c in self.COLUMNS]
		style = apply_treeview_style()
		self.tree = ttk.Treeview(self, columns=cols, show='headings', selectmode='browse', style='App.Treeview')
		for cid, head in zip(cols, headings):
			self.tree.heading(cid, text=head)
			self.tree.column(cid, width=110, anchor='w')
		# highlight tag for open boxes
		try:
			self.tree.tag_configure('abierta', background='#FFF59D')
		except Exception:
			pass

		self.vsb = ttk.Scrollbar(self, orient='vertical', command=self.tree.yview)
		self.hsb = ttk.Scrollbar(self, orient='horizontal', command=self.tree.xview)
		self.tree.configure(yscroll=self.vsb.set, xscroll=self.hsb.set)
		self.tree.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
		self.vsb.pack(side=tk.RIGHT, fill=tk.Y)
		self.hsb.pack(side=tk.BOTTOM, fill=tk.X)

		self.tree.bind('<Double-1>', lambda e: self._btn_ver_detalle())

		# Cargar listado inicial
		self.cargar_cajas()

	def _refresh_list(self):
		"""Recarga las fechas y el listado aplicando el filtro actual."""
		self.actualizar_fechas_combo()
		self.cargar_cajas()

	def cargar_cajas(self):
		# limpia
		for it in self.tree.get_children():
			self.tree.delete(it)

		with get_connection() as conn:
			cur = conn.cursor()
			# Base query
			query = (
				"SELECT cd.id, cd.codigo_caja, cd.fecha, cd.usuario_apertura, COALESCE(cd.fondo_inicial,0),"
				" (SELECT COALESCE(SUM(t.total_ticket),0) FROM tickets t JOIN ventas v ON v.id=t.venta_id WHERE v.caja_id=cd.id AND t.status!='Anulado') as total_ventas,"
				# Ventas en efectivo: siempre por método de pago efectivo
				" (SELECT COALESCE(SUM(t.total_ticket),0) FROM tickets t JOIN ventas v ON v.id=t.venta_id LEFT JOIN metodos_pago mp ON mp.id=v.metodo_pago_id WHERE v.caja_id=cd.id AND t.status!='Anulado' AND (LOWER(mp.descripcion) LIKE 'efectivo%' OR LOWER(mp.descripcion)='efectivo')) as ventas_efectivo,"
				# Transferencias: si la caja está abierta, suma en vivo; si no, usa valor final o suma en vivo
				" CASE WHEN LOWER(COALESCE(cd.estado,''))='abierta' THEN ("
				"   SELECT COALESCE(SUM(t.total_ticket),0)"
				"     FROM tickets t"
				"     JOIN ventas v ON v.id=t.venta_id"
				"     LEFT JOIN metodos_pago mp ON mp.id=v.metodo_pago_id"
				"    WHERE v.caja_id=cd.id AND t.status!='Anulado' AND LOWER(mp.descripcion) LIKE 'transfer%'"
				")"
				" ELSE COALESCE(cd.transferencias_final, ("
				"   SELECT COALESCE(SUM(t.total_ticket),0)"
				"     FROM tickets t"
				"     JOIN ventas v ON v.id=t.venta_id"
				"     LEFT JOIN metodos_pago mp ON mp.id=v.metodo_pago_id"
				"    WHERE v.caja_id=cd.id AND t.status!='Anulado' AND LOWER(mp.descripcion) LIKE 'transfer%')) END AS transferencias_final,"
				" (SELECT COALESCE(SUM(m.monto),0) FROM caja_movimiento m WHERE m.caja_id=cd.id AND m.tipo='INGRESO') as ingresos,"
				" (SELECT COALESCE(SUM(m.monto),0) FROM caja_movimiento m WHERE m.caja_id=cd.id AND m.tipo='RETIRO') as retiros,"
				" COALESCE(cd.conteo_efectivo_final,0),"
				" COALESCE(cd.diferencia,0),"
				" (SELECT COUNT(*) FROM tickets t JOIN ventas v ON v.id=t.venta_id WHERE v.caja_id=cd.id AND t.status!='Anulado') as total_tickets,"
				" (SELECT COUNT(*) FROM tickets t JOIN ventas v ON v.id=t.venta_id WHERE v.caja_id=cd.id AND t.status='Anulado') as tickets_anulados,"
				" COALESCE(cd.estado, '')"
				" FROM caja_diaria cd"
			)
			params = []
			if self._filter_date:
				query += " WHERE cd.fecha = ? ORDER BY cd.fecha DESC, cd.codigo_caja DESC"
				params.append(self._filter_date)
			else:
				query += " ORDER BY cd.fecha DESC LIMIT 200"
			cur.execute(query, params)
			rows = cur.fetchall()

			for row in rows:
				(cid, codigo, fecha, usuario, fondo_inicial, total_ventas, ventas_efectivo,  transfer, ingresos, retiros, conteo_final, diferencia_db,total_tickets, tickets_anulados, estado) = row

				# Si diferencia guardada es NULL => calcular por la fórmula del negocio
				if diferencia_db is None:
					try:
						# Nueva lógica: real = conteo_final + transferencias
						real = float(conteo_final or 0) + float(transfer or 0)
						# teor = fondo_inicial + total_ventas + ingresos - retiros
						teor = float(fondo_inicial or 0) + float(total_ventas or 0) + float(ingresos or 0) - float(retiros or 0)
						diferencia = real - teor
					except Exception:
						diferencia = 0
				else:
					diferencia = diferencia_db or 0

				# Build visible values (omit internal id, append estado)
				values = [codigo, fecha, usuario, fondo_inicial, total_ventas, ventas_efectivo,  transfer, ingresos, retiros, conteo_final, diferencia,total_tickets, tickets_anulados, estado]
				tags = ()
				if str(estado).lower() == 'abierta':
					tags = ('abierta',)
				self.tree.insert('', 'end', iid=str(cid), values=values, tags=tags)

		# Pedir al controlador que refresque el pie global si este frame está contenido en la app principal
		try:
			if hasattr(self.master, 'mostrar_pie_caja'):
				self.master.mostrar_pie_caja(self)
		except Exception:
			pass

	def actualizar_fechas_combo(self):
		"""Carga/actualiza el combobox de fechas (DISTINCT fecha de caja_diaria)."""
		try:
			fechas = []
			with get_connection() as conn:
				cur = conn.cursor()
				cur.execute("SELECT DISTINCT fecha FROM caja_diaria ORDER BY fecha DESC LIMIT 365")
				fechas = [str(row[0]) for row in cur.fetchall() if row and row[0]]
			valores = ["Mostrar todo"] + fechas
			if self.combo_fecha:
				self.combo_fecha['values'] = valores
				# Mantener selección si existe, sino fallback a índice 0
				actual = self.var_fecha.get()
				if actual not in valores:
					self.combo_fecha.current(0)
			else:
				self.combo_fecha = ttk.Combobox(
					self.btn_frame,
					textvariable=self.var_fecha,
					values=valores,
					state="readonly",
					width=20,
				)
				self.combo_fecha.pack(side=tk.LEFT, padx=4)
				self.combo_fecha.current(0)
		except Exception:
			pass

	def _on_fecha_cambiada(self, *args):
		"""Actualiza el filtro interno y recarga el listado al cambiar la fecha."""
		try:
			valor = self.var_fecha.get()
			if not valor or valor == "Mostrar todo":
				self._filter_date = None
			else:
				self._filter_date = valor
			self.cargar_cajas()
		except Exception:
			pass


	def _selected_caja_id(self):
		sel = self.tree.selection()
		if not sel:
			return None
		return int(sel[0])

	def _btn_ver_detalle(self):
		cid = self._selected_caja_id()
		if not cid:
			messagebox.showwarning('Detalle', 'Seleccione una caja en la lista')
			return
		self.ver_detalle(cid)

	def _hide_list_widgets(self):
		"""Oculta los widgets del listado para mostrar el detalle."""
		try:
			self.btn_frame.pack_forget()
		except Exception:
			pass
		try:
			self.hsb.pack_forget()
		except Exception:
			pass
		try:
			self.vsb.pack_forget()
		except Exception:
			pass
		try:
			self.tree.pack_forget()
		except Exception:
			pass

	def _show_list_widgets(self):
		"""Vuelve a mostrar los widgets del listado."""
		try:
			self.btn_frame.pack(side=tk.TOP, fill=tk.X, padx=6, pady=6)
		except Exception:
			pass
		try:
			self.tree.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
		except Exception:
			pass
		try:
			self.vsb.pack(side=tk.RIGHT, fill=tk.Y)
		except Exception:
			pass
		try:
			self.hsb.pack(side=tk.BOTTOM, fill=tk.X)
		except Exception:
			pass

	def ver_detalle(self, caja_id=None):
		if caja_id is None:
			return
		# cerrar detalle previo
		self.cerrar_detalle()
		try:
			# ocultar listado y mostrar solo el detalle
			self._hide_list_widgets()
			self._detalle_frame = DetalleCajaFrame(self, caja_id, on_close=self._on_close_wrapper)
			self._detalle_frame.pack(fill='both', expand=True)
		except Exception as e:
			messagebox.showerror('Detalle', f'Error al abrir detalle: {e}')

	def cerrar_detalle(self):
		if self._detalle_frame:
			try:
				self._detalle_frame.destroy()
			except Exception:
				pass
			self._detalle_frame = None
		# restaurar listado cuando se cierra el detalle
		self._show_list_widgets()
		self._show_list_widgets()

	def _on_close_wrapper(self, *args, **kwargs):
		if callable(self.on_caja_cerrada):
			try:
				self.on_caja_cerrada(*args, **kwargs)
			except TypeError:
				self.on_caja_cerrada()
		# Cerrar la vista de detalle y restaurar el listado
		self.cerrar_detalle()
		# Si la caja fue cerrada (callback puede pasar True), refrescar el listado
		try:
			cerrada = False
			if args and isinstance(args[0], bool):
				cerrada = args[0]
			elif isinstance(kwargs.get('cerrada'), bool):
				cerrada = kwargs['cerrada']
			if cerrada:
				self.actualizar_fechas_combo()
				self.cargar_cajas()
		except Exception:
			pass

	# def export_csv(self):
	# 	# Export functions removed: export_csv and export_excel