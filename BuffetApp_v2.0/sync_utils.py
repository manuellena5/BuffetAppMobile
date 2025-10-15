"""Sincronización offline: importar datos de otra base (solo cajas/ventas).

Estrategia:
- Usar ATTACH DATABASE para leer desde archivo origen.
- Sincronizar tabla pos por pos_uuid (INSERT OR IGNORE para no duplicar).
- Mapear pos_id/pos_uuid a la base local.
- Importar caja_diaria por caja_uuid (si existe la columna) o por (codigo_caja, fecha, hora_apertura) como fallback débil.
- Importar ventas, tickets y venta_items referenciando IDs re-mapeados.

Se evita sincronizar products y categorías para no pisar catálogos.
"""
from __future__ import annotations

import os
import sqlite3
from typing import Optional
import shutil
import datetime

from db_utils import get_connection
from utils_paths import appdata_dir, DB_PATH


def import_from_db(origen_db_path: str, incluir_historial: bool = True) -> dict:
    """Importa datos desde otra base SQLite sin usar ATTACH.

    Estrategia: copiar el archivo origen a una ruta temporal (para evitar locks), abrir dos conexiones
    (src read-only y dst local), leer filas desde src y escribir en dst con deduplicación.
    """
    if not origen_db_path or not os.path.exists(origen_db_path):
        raise FileNotFoundError("No se encontró la base de datos origen")
    # Evitar importar la misma base en uso
    if os.path.abspath(origen_db_path) == os.path.abspath(DB_PATH):
        raise ValueError("No se puede importar la misma base de datos en uso.")

    resumen = {
        "pos_nuevos": 0,
        "categorias_nuevas": 0,
        "productos_nuevos": 0,
        "cajas_nuevas": 0,
        "ventas_nuevas": 0,
        "tickets_nuevos": 0,
        "items_nuevos": 0,
        # src counts
        "src_pos": 0,
        "src_categorias": 0,
        "src_products": 0,
        "src_cajas": 0,
        "src_ventas": 0,
        "src_tickets": 0,
        "src_items": 0,
    }

    # Copia temporal del origen
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    tmp_dir = os.path.join(appdata_dir(), 'import_tmp')
    os.makedirs(tmp_dir, exist_ok=True)
    tmp_src = os.path.join(tmp_dir, f"import_{ts}.db")
    shutil.copy2(origen_db_path, tmp_src)

    src_conn = None
    dst_conn = None
    # Simple logger a archivo en AppData
    def _log(msg: str):
        try:
            log_dir = appdata_dir()
            with open(os.path.join(log_dir, 'import_logs.txt'), 'a', encoding='utf-8') as lf:
                lf.write(f"{datetime.datetime.now().isoformat()} - {msg}\n")
        except Exception:
            pass
    # Normalizadores de estado
    def _normalize_ticket_status(val):
        try:
            if val is None:
                return 'No impreso'
            s = str(val).strip()
            if s == '':
                return 'No impreso'
            sl = s.lower()
            if sl in ('anulado', 'anulada'):
                return 'Anulado'
            if sl in ('impreso', 'impresa', 'printed'):
                return 'Impreso'
            # Si es numérico y >0, considerar impreso
            if sl.isdigit():
                return 'Impreso' if int(sl) > 0 else 'No impreso'
            # fallback: mantener valor si no es vacío
            return s
        except Exception:
            return 'No impreso'

    def _normalize_venta_status(val):
        try:
            if val is None:
                return 'OK'
            s = str(val).strip()
            if s == '':
                return 'OK'
            return s
        except Exception:
            return 'OK'
    try:
        # Abrir conexiones
        try:
            src_conn = sqlite3.connect(f"file:{tmp_src}?mode=ro", uri=True)
        except Exception:
            src_conn = sqlite3.connect(tmp_src)
        src_conn.row_factory = sqlite3.Row
        src_conn.execute("PRAGMA busy_timeout=5000")

        dst_conn = get_connection()
        dst_conn.execute("PRAGMA busy_timeout=5000")
        dst_cur = dst_conn.cursor()

        src_cur = src_conn.cursor()

        # 1) Importar POS si existe
        try:
            r = src_cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='pos'").fetchone()
            if r:
                rows = src_cur.execute("SELECT pos_uuid, nombre, device_id, hostname, created_at FROM pos").fetchall()
                resumen["src_pos"] = len(rows)
                for row in rows:
                    try:
                        dst_cur.execute(
                            "INSERT OR IGNORE INTO pos (pos_uuid, nombre, device_id, hostname, created_at) VALUES (?, ?, ?, ?, ?)",
                            (row[0], row[1], row[2], row[3], row[4])
                        )
                        if dst_cur.rowcount == 1:
                            resumen["pos_nuevos"] += 1
                    except Exception:
                        pass
        except Exception:
            pass

        # 2) Importar CATEGORÍAS primero
        src_cat_id_to_dst: dict[int,int] = {}
        try:
            r = src_cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='Categoria_Producto'").fetchone()
            if r:
                # Detectar nombre de columna en origen: 'descripcion' o 'nombre'
                cat_cols = {c[1] for c in src_cur.execute("PRAGMA table_info(Categoria_Producto)").fetchall()}
                src_cat_name_col = 'descripcion' if 'descripcion' in cat_cols else ('nombre' if 'nombre' in cat_cols else None)
                if src_cat_name_col:
                    src_cats = src_cur.execute(f"SELECT id, {src_cat_name_col} FROM Categoria_Producto").fetchall()
                    resumen["src_categorias"] = len(src_cats)
                    # Mapa destino por descripcion
                    dst_cats = {}
                    try:
                        for did, ddesc in dst_cur.execute("SELECT id, descripcion FROM Categoria_Producto").fetchall():
                            dst_cats[(ddesc or '').strip().lower()] = int(did)
                    except Exception:
                        dst_cats = {}
                    for sid, sdesc in src_cats:
                        key = (sdesc or '').strip().lower()
                        if not key:
                            continue
                        if key in dst_cats:
                            src_cat_id_to_dst[int(sid)] = dst_cats[key]
                        else:
                            try:
                                dst_cur.execute("INSERT INTO Categoria_Producto (descripcion) VALUES (?)", (sdesc,))
                                new_id = int(dst_cur.lastrowid)
                                dst_cats[key] = new_id
                                src_cat_id_to_dst[int(sid)] = new_id
                                resumen["categorias_nuevas"] += 1
                            except Exception as e:
                                _log(f"Error creando categoria '{sdesc}': {e}")
                                # no asignar
                else:
                    _log("Categoria_Producto sin columna de nombre reconocida (descripcion/nombre)")
        except Exception as e:
            _log(f"Error importando categorias: {e}")

        # 3) Importar/asegurar MÉTODOS DE PAGO antes de ventas/tickets
        mp_desc_to_dst: dict[str,int] = {}
        mp_src_to_dst: dict[int,int] = {}
        try:
            # Index destino actual de métodos de pago por descripción (lower)
            for mid, mdesc in dst_cur.execute("SELECT id, descripcion FROM metodos_pago").fetchall():
                key = (mdesc or '').strip().lower()
                if key:
                    mp_desc_to_dst[key] = int(mid)
            # Traer métodos del origen
            src_mps = src_cur.execute("SELECT id, descripcion FROM metodos_pago").fetchall()
            for sid, sdesc in src_mps:
                k = (sdesc or '').strip().lower()
                if not k:
                    continue
                if k in mp_desc_to_dst:
                    mp_src_to_dst[int(sid)] = mp_desc_to_dst[k]
                else:
                    try:
                        dst_cur.execute("INSERT INTO metodos_pago (descripcion) VALUES (?)", (sdesc,))
                        new_id = int(dst_cur.lastrowid)
                        mp_desc_to_dst[k] = new_id
                        mp_src_to_dst[int(sid)] = new_id
                    except Exception as e:
                        _log(f"Error creando metodo_pago '{sdesc}': {e}")
                        # no mapear
        except Exception as e:
            _log(f"Error importando metodos de pago: {e}")

        # 4) Importar/asegurar PRODUCTOS antes de ventas/tickets
        prod_code_to_local: dict[str,int] = {}
        local_prod_name_to_id: dict[str,int] = {}
        local_prod_to_cat: dict[int, Optional[int]] = {}
        src_prod_map: dict[int,int] = {}
        try:
            # Index destino actual
            for pid, code, nombre, cat_id in dst_cur.execute("SELECT id, codigo_producto, nombre, categoria_id FROM products").fetchall():
                if code:
                    prod_code_to_local[(code or '').strip().lower()] = int(pid)
                local_prod_name_to_id[(nombre or '').strip().lower()] = int(pid)
                local_prod_to_cat[int(pid)] = cat_id
            # Leer productos de origen
            src_products = src_cur.execute("SELECT id, codigo_producto, nombre, precio_compra, precio_venta, stock_actual, stock_minimo, categoria_id, visible, color FROM products").fetchall()
            resumen["src_products"] = len(src_products)
        except Exception as e:
            _log(f"Error preparando índices de productos: {e}")
            src_products = []
        for prow in src_products:
            try:
                (sid, code, nombre, precio_compra, precio_venta, stock_actual, stock_minimo, src_cat_id, visible, color) = prow
                key_code = (code or '').strip().lower()
                key_name = (nombre or '').strip().lower()
                dst_id = None
                if key_code and key_code in prod_code_to_local:
                    dst_id = prod_code_to_local[key_code]
                elif key_name and key_name in local_prod_name_to_id:
                    dst_id = local_prod_name_to_id[key_name]
                if dst_id is None:
                    # Resolver categoría destino
                    dst_cat_id = src_cat_id_to_dst.get(int(src_cat_id)) if src_cat_id is not None else None
                    try:
                        dst_cur.execute(
                            "INSERT INTO products (codigo_producto, nombre, precio_compra, precio_venta, stock_actual, stock_minimo, categoria_id, visible, color) VALUES (?,?,?,?,?,?,?,?,?)",
                            (code, nombre, precio_compra or 0, precio_venta or 0, stock_actual or 0, (stock_minimo or 3), dst_cat_id, (visible if visible is not None else 1), color)
                        )
                        dst_id = int(dst_cur.lastrowid)
                        resumen['productos_nuevos'] += 1
                        # actualizar índices locales
                        if key_code:
                            prod_code_to_local[key_code] = dst_id
                        if key_name:
                            local_prod_name_to_id[key_name] = dst_id
                        local_prod_to_cat[dst_id] = dst_cat_id
                    except Exception as e:
                        _log(f"Error creando producto '{nombre}' (code={code}): {e}")
                        dst_id = None
                if dst_id is not None:
                    src_prod_map[int(sid)] = int(dst_id)
            except Exception as e:
                _log(f"Error procesando producto sid={prow[0]}: {e}")
                pass

    # 5) Importar cajas (caja_diaria)
        # Detectar columnas
        src_cols = {c[1] for c in src_cur.execute("PRAGMA table_info(caja_diaria)").fetchall()}
        tiene_caja_uuid = 'caja_uuid' in src_cols
        tiene_pos_uuid = 'pos_uuid' in src_cols
        # Detectar columnas en destino
        try:
            dst_cols = {c[1] for c in dst_cur.execute("PRAGMA table_info(caja_diaria)").fetchall()}
        except Exception:
            dst_cols = set()
        dst_tiene_caja_uuid = 'caja_uuid' in dst_cols
        dst_tiene_pos_uuid = 'pos_uuid' in dst_cols
        caja_map = {}

        try:
            src_cajas = src_cur.execute("SELECT * FROM caja_diaria").fetchall()
            resumen["src_cajas"] = len(src_cajas)
            _log(f"caja_diaria origen: {len(src_cajas)} filas, cols: {sorted(list(src_cols))}")
        except Exception:
            src_cajas = []

        for r in src_cajas:
            try:
                # helpers
                def getv(name, default=None):
                    try:
                        return r[name]
                    except Exception:
                        return default

                src_id = getv('id')
                values = {
                    'caja_uuid': getv('caja_uuid'),
                    'pos_uuid': getv('pos_uuid'),
                    'codigo_caja': getv('codigo_caja'),
                    'disciplina': getv('disciplina'),
                    'fecha': getv('fecha'),
                    'usuario_apertura': getv('usuario_apertura'),
                    'hora_apertura': getv('hora_apertura'),
                    'fondo_inicial': getv('fondo_inicial', 0),
                    'observaciones_apertura': getv('observaciones_apertura'),
                    'estado': getv('estado'),
                    'hora_cierre': getv('hora_cierre'),
                    'usuario_cierre': getv('usuario_cierre'),
                    'apertura_dt': getv('apertura_dt'),
                    'cierre_dt': getv('cierre_dt'),
                    'total_ventas': getv('total_ventas'),
                    'total_efectivo_teorico': getv('total_efectivo_teorico'),
                    'conteo_efectivo_final': getv('conteo_efectivo_final'),
                    'transferencias_final': getv('transferencias_final'),
                    'ingresos': getv('ingresos'),
                    'retiros': getv('retiros'),
                    'diferencia': getv('diferencia'),
                    'total_tickets': getv('total_tickets'),
                    'obs_cierre': getv('obs_cierre'),
                }

                # Normalización de valores mínimos
                # fecha/hora: si faltan, intentar parsear de apertura_dt (YYYY-MM-DD HH:MM:SS)
                if not values['fecha'] and values['apertura_dt']:
                    try:
                        values['fecha'] = str(values['apertura_dt']).split(' ')[0]
                    except Exception:
                        pass
                if not values['hora_apertura'] and values['apertura_dt']:
                    try:
                        values['hora_apertura'] = str(values['apertura_dt']).split(' ')[1]
                    except Exception:
                        pass
                if not values['hora_apertura']:
                    values['hora_apertura'] = '00:00:00'
                if not values['usuario_apertura']:
                    values['usuario_apertura'] = ''
                # estado: asegurar valor permitido por CHECK
                try:
                    st = (values['estado'] or '').strip().lower()
                    if st not in ('abierta','cerrada'):
                        st = 'abierta'
                    values['estado'] = st
                except Exception:
                    values['estado'] = 'abierta'

                if tiene_caja_uuid and tiene_pos_uuid and dst_tiene_caja_uuid and dst_tiene_pos_uuid and values['caja_uuid']:
                    # Insert por UUID
                    try:
                        dst_cur.execute(
                            """
                            INSERT OR IGNORE INTO caja_diaria (
                                caja_uuid, pos_uuid, codigo_caja, disciplina, fecha, usuario_apertura, hora_apertura,
                                fondo_inicial, observaciones_apertura, estado, hora_cierre, usuario_cierre, apertura_dt, cierre_dt,
                                total_ventas, total_efectivo_teorico, conteo_efectivo_final, transferencias_final, ingresos, retiros,
                                diferencia, total_tickets, obs_cierre
                            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                            """,
                            (
                                values['caja_uuid'], values['pos_uuid'], values['codigo_caja'], values['disciplina'], values['fecha'],
                                values['usuario_apertura'], values['hora_apertura'], values['fondo_inicial'], values['observaciones_apertura'], values['estado'],
                                values['hora_cierre'], values['usuario_cierre'], values['apertura_dt'], values['cierre_dt'], values['total_ventas'],
                                values['total_efectivo_teorico'], values['conteo_efectivo_final'], values['transferencias_final'], values['ingresos'], values['retiros'],
                                values['diferencia'], values['total_tickets'], values['obs_cierre']
                            )
                        )
                        if dst_cur.rowcount == 1:
                            resumen['cajas_nuevas'] += 1
                    except Exception as e:
                        _log(f"Error insert caja UUID {values.get('caja_uuid')}: {e}")
                        pass
                    # Obtener id local por UUID
                    dst_id = None
                    try:
                        dst_id = dst_cur.execute("SELECT id FROM caja_diaria WHERE caja_uuid=?", (values['caja_uuid'],)).fetchone()
                        dst_id = dst_id[0] if dst_id else None
                    except Exception:
                        dst_id = None
                else:
                    # Fallback: dedupe por (codigo_caja, fecha, hora_apertura)
                    try:
                        exists = dst_cur.execute(
                            "SELECT id FROM caja_diaria WHERE codigo_caja=? AND fecha=? AND hora_apertura=? LIMIT 1",
                            (values['codigo_caja'], values['fecha'], values['hora_apertura'])
                        ).fetchone()
                        if not exists:
                            dst_cur.execute(
                                """
                                INSERT INTO caja_diaria (
                                    codigo_caja, disciplina, fecha, usuario_apertura, hora_apertura,
                                    fondo_inicial, observaciones_apertura, estado, hora_cierre, usuario_cierre, apertura_dt, cierre_dt,
                                    total_ventas, total_efectivo_teorico, conteo_efectivo_final, transferencias_final, ingresos, retiros,
                                    diferencia, total_tickets, obs_cierre
                                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                                """,
                                (
                                    values['codigo_caja'], values['disciplina'], values['fecha'], values['usuario_apertura'], values['hora_apertura'],
                                    values['fondo_inicial'], values['observaciones_apertura'], values['estado'], values['hora_cierre'], values['usuario_cierre'], values['apertura_dt'], values['cierre_dt'],
                                    values['total_ventas'], values['total_efectivo_teorico'], values['conteo_efectivo_final'], values['transferencias_final'], values['ingresos'], values['retiros'],
                                    values['diferencia'], values['total_tickets'], values['obs_cierre']
                                )
                            )
                            resumen['cajas_nuevas'] += 1
                            dst_id = int(dst_cur.lastrowid)
                        else:
                            dst_id = int(exists[0])
                    except Exception as e:
                        _log(f"Error insert caja triple {values.get('codigo_caja')} {values.get('fecha')} {values.get('hora_apertura')}: {e}")
                        pass
                    # Obtener id local por triple clave
                    dst_id = None
                    try:
                        dst_id = dst_cur.execute(
                            "SELECT id FROM caja_diaria WHERE codigo_caja=? AND fecha=? AND hora_apertura=? LIMIT 1",
                            (values['codigo_caja'], values['fecha'], values['hora_apertura'])
                        ).fetchone()
                        dst_id = dst_id[0] if dst_id else None
                    except Exception:
                        dst_id = None

                if src_id is not None and dst_id is not None:
                    caja_map[int(src_id)] = int(dst_id)
            except Exception as e:
                _log(f"Error procesando caja src_id={getv('id')}: {e}")
                pass

        if incluir_historial:
            # Ya hicimos categorías y productos arriba, tenemos src_prod_map y local_prod_to_cat disponibles

            # 6) Importar ventas
            venta_map = {}
            try:
                # Traer metodo_pago_id si existe en origen
                src_cols_v = {c[1] for c in src_cur.execute("PRAGMA table_info(ventas)").fetchall()}
                if 'metodo_pago_id' in src_cols_v:
                    src_ventas = src_cur.execute("SELECT id, fecha_hora, total_venta, status, activo, caja_id, metodo_pago_id FROM ventas").fetchall()
                else:
                    src_ventas = src_cur.execute("SELECT id, fecha_hora, total_venta, status, activo, caja_id, NULL as metodo_pago_id FROM ventas").fetchall()
                resumen["src_ventas"] = len(src_ventas)
            except Exception:
                src_ventas = []
            for v in src_ventas:
                try:
                    sid, fecha_hora, total_venta, status, activo, src_caja_id, src_mp_id = v
                    dst_caja_id = caja_map.get(int(src_caja_id))
                    if not dst_caja_id:
                        continue
                    # Normalizar status venta
                    status = _normalize_venta_status(status)
                    # Mapear método de pago si está
                    metodo_pago_id = None
                    if src_mp_id is not None and 'mp_src_to_dst' in locals():
                        metodo_pago_id = mp_src_to_dst.get(int(src_mp_id))
                    # buscar existente
                    row = dst_cur.execute(
                        "SELECT id FROM ventas WHERE fecha_hora=? AND ABS(total_venta-?)<0.0001 AND caja_id=? LIMIT 1",
                        (fecha_hora, total_venta, dst_caja_id)
                    ).fetchone()
                    if row:
                        dst_id = int(row[0])
                        # Completar datos faltantes si corresponde
                        try:
                            cur_row = dst_cur.execute("SELECT status, metodo_pago_id FROM ventas WHERE id=?", (dst_id,)).fetchone()
                            cur_status = cur_row[0] if cur_row else None
                            cur_mp = cur_row[1] if cur_row else None
                            # Setear método de pago si está vacío en destino y tenemos uno válido
                            if cur_mp is None and metodo_pago_id is not None:
                                dst_cur.execute("UPDATE ventas SET metodo_pago_id=? WHERE id=?", (metodo_pago_id, dst_id))
                            # Normalizar status si está vacío en destino
                            if (cur_status is None or str(cur_status).strip() == '') and status:
                                dst_cur.execute("UPDATE ventas SET status=? WHERE id=?", (status, dst_id))
                        except Exception as e:
                            _log(f"Warning: no se pudo actualizar venta existente id={dst_id}: {e}")
                    else:
                        if metodo_pago_id is not None:
                            dst_cur.execute(
                                "INSERT INTO ventas (fecha_hora, total_venta, status, activo, metodo_pago_id, caja_id) VALUES (?,?,?,?,?,?)",
                                (fecha_hora, total_venta, status, activo, metodo_pago_id, dst_caja_id)
                            )
                        else:
                            dst_cur.execute(
                                "INSERT INTO ventas (fecha_hora, total_venta, status, activo, metodo_pago_id, caja_id) VALUES (?,?,?,?,NULL,?)",
                                (fecha_hora, total_venta, status, activo, dst_caja_id)
                            )
                        dst_id = int(dst_cur.lastrowid)
                        resumen['ventas_nuevas'] += 1
                    venta_map[int(sid)] = dst_id
                except Exception as e:
                    _log(f"Error insert venta sid={sid}: {e}")
                    pass

            # 7) Importar tickets
            ticket_map = {}
            try:
                src_tickets = src_cur.execute("SELECT id, venta_id, producto_id, fecha_hora, status, total_ticket, identificador_ticket FROM tickets").fetchall()
                resumen["src_tickets"] = len(src_tickets)
            except Exception:
                src_tickets = []
            for t in src_tickets:
                try:
                    sid, src_venta_id, src_prod_id, fecha_hora, status, total_ticket, ident = t
                    dst_venta_id = venta_map.get(int(src_venta_id))
                    if not dst_venta_id:
                        continue
                    # Normalizar status ticket
                    status = _normalize_ticket_status(status)
                    dst_prod_id = None
                    dst_cat_id = None
                    if src_prod_id is not None and 'src_prod_map' in locals():
                        dst_prod_id = src_prod_map.get(int(src_prod_id))
                        if dst_prod_id is not None:
                            # Si el producto local no tiene categoría, dejar NULL (no 0)
                            dst_cat_id = local_prod_to_cat.get(dst_prod_id)
                            if not dst_cat_id:
                                dst_cat_id = None
                            else:
                                # Validar que la categoría existe en la tabla local; si no, dejar NULL
                                try:
                                    exists = dst_cur.execute("SELECT 1 FROM Categoria_Producto WHERE id=?", (dst_cat_id,)).fetchone()
                                    if not exists:
                                        dst_cat_id = None
                                except Exception:
                                    dst_cat_id = None
                    # dedupe por identificador + fecha_hora
                    row = dst_cur.execute(
                        "SELECT id FROM tickets WHERE identificador_ticket=? AND fecha_hora=? LIMIT 1",
                        (ident, fecha_hora)
                    ).fetchone()
                    if row:
                        dst_id = int(row[0])
                        # Si ya existía, intentar actualizar status si está vacío o 'No impreso' y en origen viene algo
                        try:
                            cur_row = dst_cur.execute("SELECT status FROM tickets WHERE id=?", (dst_id,)).fetchone()
                            cur_status = cur_row[0] if cur_row else None
                            if (cur_status is None or str(cur_status).strip() in ('', 'No impreso')) and (status and str(status).strip() != ''):
                                dst_cur.execute("UPDATE tickets SET status=? WHERE id=?", (status, dst_id))
                        except Exception as e:
                            _log(f"Warning: no se pudo actualizar ticket existente id={dst_id}: {e}")
                    else:
                        dst_cur.execute(
                            "INSERT INTO tickets (venta_id, categoria_id, producto_id, fecha_hora, status, total_ticket, identificador_ticket) VALUES (?,?,?,?,?,?,?)",
                            (dst_venta_id, dst_cat_id, dst_prod_id, fecha_hora, status, total_ticket, ident)
                        )
                        dst_id = int(dst_cur.lastrowid)
                        resumen['tickets_nuevos'] += 1
                    ticket_map[int(sid)] = dst_id
                except Exception as e:
                    try:
                        _log(
                            f"Error insert ticket sid={sid}: {e} | venta_id_dst={locals().get('dst_venta_id')} "
                            f"prod_id_dst={locals().get('dst_prod_id')} cat_id_dst={locals().get('dst_cat_id')} ident={locals().get('ident')} fecha={locals().get('fecha_hora')}"
                        )
                    except Exception:
                        _log(f"Error insert ticket sid={sid}: {e}")
                    pass

            # 6) Importar items
            try:
                src_items = src_cur.execute("SELECT ticket_id, producto_id, cantidad, precio_unitario, subtotal FROM venta_items").fetchall()
                resumen["src_items"] = len(src_items)
            except Exception:
                src_items = []
            for it in src_items:
                try:
                    src_ticket_id, src_prod_id, cantidad, precio_unitario, subtotal = it
                    dst_ticket_id = ticket_map.get(int(src_ticket_id))
                    if not dst_ticket_id:
                        continue
                    dst_prod_id = None
                    if src_prod_id is not None and 'src_prod_map' in locals():
                        dst_prod_id = src_prod_map.get(int(src_prod_id))
                    # dedupe: comparar por valores
                    row = None
                    try:
                        if dst_prod_id is not None:
                            row = dst_cur.execute(
                                """
                                SELECT 1 FROM venta_items 
                                 WHERE ticket_id=? AND cantidad=? 
                                   AND ABS(precio_unitario-?)<0.0001 AND ABS(subtotal-?)<0.0001
                                   AND producto_id=?
                                 LIMIT 1
                                """,
                                (dst_ticket_id, cantidad, precio_unitario, subtotal, dst_prod_id)
                            ).fetchone()
                        else:
                            row = dst_cur.execute(
                                """
                                SELECT 1 FROM venta_items 
                                 WHERE ticket_id=? AND cantidad=? 
                                   AND ABS(precio_unitario-?)<0.0001 AND ABS(subtotal-?)<0.0001
                                 LIMIT 1
                                """,
                                (dst_ticket_id, cantidad, precio_unitario, subtotal)
                            ).fetchone()
                    except Exception:
                        row = None
                    if row:
                        continue
                    dst_cur.execute(
                        "INSERT INTO venta_items (ticket_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (?,?,?,?,?)",
                        (dst_ticket_id, dst_prod_id, cantidad, precio_unitario, subtotal)
                    )
                    resumen['items_nuevos'] += 1
                except Exception as e:
                    _log(f"Error insert item ticket_id={src_ticket_id}: {e}")
                    pass

        # commit final
        dst_conn.commit()
    finally:
        # limpiar
        try:
            if src_conn:
                src_conn.close()
        except Exception:
            pass
        try:
            if dst_conn:
                dst_conn.close()
        except Exception:
            pass
        try:
            if os.path.exists(tmp_src):
                os.remove(tmp_src)
        except Exception:
            pass

    return resumen
