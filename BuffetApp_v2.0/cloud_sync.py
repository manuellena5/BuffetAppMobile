import os
import json
import sqlite3
import uuid as _uuid
from datetime import datetime
from typing import Dict, Any, List, Tuple

import requests

from db_utils import get_connection

# Config desde app_config (si está disponible) o variables de entorno como fallback
try:
    from app_config import get_supabase_url, get_supabase_anon_key
except Exception:
    def get_supabase_url():
        return None
    def get_supabase_anon_key():
        return None

_URL_FROM_CFG = (get_supabase_url() or "").strip()
_KEY_FROM_CFG = (get_supabase_anon_key() or "").strip()

SUPABASE_URL = (_URL_FROM_CFG or os.getenv("SUPABASE_URL", "")).rstrip("/")
SUPABASE_REST = f"{SUPABASE_URL}/rest/v1" if SUPABASE_URL else ""
SUPABASE_ANON_KEY = _KEY_FROM_CFG or os.getenv("SUPABASE_ANON_KEY", "")

HEADERS = {
    "apikey": SUPABASE_ANON_KEY,
    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation,resolution=merge-duplicates",
}


def is_configured() -> bool:
    return bool(SUPABASE_REST and SUPABASE_ANON_KEY)


def _ensure_sync_columns(conn: sqlite3.Connection) -> None:
    cur = conn.cursor()
    try:
        cur.execute("PRAGMA table_info(caja_diaria)")
        cols = [r[1] for r in cur.fetchall()]
        if 'nube_enviado' not in cols:
            try:
                cur.execute("ALTER TABLE caja_diaria ADD COLUMN nube_enviado INTEGER DEFAULT 0")
            except Exception:
                pass
        if 'nube_uuid' not in cols:
            try:
                cur.execute("ALTER TABLE caja_diaria ADD COLUMN nube_uuid TEXT")
            except Exception:
                pass
        if 'enviado_nube_ts' not in cols:
            try:
                cur.execute("ALTER TABLE caja_diaria ADD COLUMN enviado_nube_ts TEXT")
            except Exception:
                pass
        conn.commit()
    except Exception:
        pass


def _post(table: str, rows: List[Dict[str, Any]]) -> Any:
    url = f"{SUPABASE_REST}/{table}"
    data = json.dumps(rows, ensure_ascii=False).encode("utf-8")
    r = requests.post(url, headers=HEADERS, data=data, timeout=20)
    if r.status_code >= 300:
        raise RuntimeError(f"POST {table} {r.status_code}: {r.text}")
    try:
        return r.json()
    except Exception:
        return None


def _coalesce_dt(date_str: str, time_str: str) -> str:
    if date_str and time_str:
        return f"{date_str} {time_str}"
    return date_str or ""


def _build_payload(caja_id: int) -> Tuple[Dict[str, Any], List[Dict[str, Any]], str, Dict[str, Dict[str, Any]], int, str]:
    """Devuelve (cabecera, items, uuid_usado) para la caja indicada."""
    with get_connection() as conn:
        _ensure_sync_columns(conn)
        cur = conn.cursor()
        # Caja
        cur.execute(
            """
            SELECT id, COALESCE(nube_uuid,''), codigo_caja, fecha, hora_apertura, hora_cierre,
                   usuario_apertura, usuario_cierre, cajero_apertura, cajero_cierre,
                   fondo_inicial, total_ventas, total_efectivo_teorico,
                   conteo_efectivo_final, transferencias_final, ingresos, retiros,
                   diferencia, total_tickets, observaciones_apertura, obs_cierre, descripcion_evento, disciplina
              FROM caja_diaria WHERE id=?
            """,
            (caja_id,),
        )
        row = cur.fetchone()
        if not row:
            raise ValueError("Caja no encontrada")
        (
            _id, nube_uuid, codigo_caja, fecha, hora_ap, hora_ci,
            usuario_aper, usuario_cie, cajero_aper, cajero_cie,
            fondo_inicial, total_ventas, total_teorico,
            conteo_final, transf_final, ingresos, retiros,
            diferencia, total_tickets, obs_ap, obs_cierre, descripcion_evento, disciplina
        ) = row
        uuid_final = nube_uuid or str(_uuid.uuid4())

        # Fechas completas
        fecha_apertura = _coalesce_dt(fecha, hora_ap)
        fecha_cierre = _coalesce_dt(fecha, hora_ci)

        # Fallbacks de totales si están en NULL
        def _nz(val, default=0.0):
            try:
                return float(val if val is not None else default)
            except Exception:
                return default

        # Items de la caja (detalle)
        cur.execute(
            """
            SELECT t.id as ticket_id,
                   t.fecha_hora as fecha,
                   p.id as producto_id,
                   p.nombre as producto_nombre,
                   p.codigo_producto as producto_codigo,
                   c.descripcion as categoria,
                   vi.cantidad,
                   vi.precio_unitario,
                   (vi.cantidad * vi.precio_unitario) as total,
                   mp.descripcion as metodo_pago
              FROM venta_items vi
              JOIN tickets t ON t.id = vi.ticket_id
              JOIN ventas v ON v.id = t.venta_id
              LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
              JOIN products p ON p.id = vi.producto_id
              LEFT JOIN Categoria_Producto c ON c.id = p.categoria_id
             WHERE v.caja_id = ? AND (t.status IS NULL OR t.status!='Anulado')
            """,
            (caja_id,),
        )
        items_rows = cur.fetchall() or []

        # Preparar set de productos necesarios para validar en nube (por código y nombre)
        productos_necesarios: Dict[str, Dict[str, Any]] = {}
        # clave por codigo; para códigos vacíos, omitimos
        for (
            ticket_id, fecha_t, producto_id, producto_nombre, producto_codigo,
            categoria, cantidad, precio_unitario, total, metodo_pago
        ) in items_rows:
            if producto_codigo:
                key = str(producto_codigo).strip().upper()
                if key not in productos_necesarios:
                    productos_necesarios[key] = {
                        "codigo_producto": key,
                        "nombre": producto_nombre,
                        "precio_venta": float(precio_unitario or 0),
                    }

        cabecera = {
            "uuid": uuid_final,
            "caja_local_id": _id,
            "codigo_caja": codigo_caja,
            "fecha_apertura": fecha_apertura or None,
            "fecha_cierre": fecha_cierre or None,
            "usuario_apertura": usuario_aper,
            "usuario_cierre": usuario_cie,
            "cajero_apertura": cajero_aper,
            "cajero_cierre": cajero_cie,
            "fondo_inicial": _nz(fondo_inicial),
            "total_ventas": _nz(total_ventas),
            "total_efectivo_teorico": _nz(total_teorico),
            "conteo_efectivo_final": _nz(conteo_final),
            "transferencias_final": _nz(transf_final),
            "ingresos": _nz(ingresos),
            "retiros": _nz(retiros),
            "diferencia": _nz(diferencia),
            "total_tickets": int(total_tickets or 0),
            "observaciones_apertura": obs_ap,
            "obs_cierre": obs_cierre,
            "descripcion_evento": descripcion_evento,
            "disciplina": disciplina,
            # Los siguientes campos se pueden completar en servidor
            # "dispositivo": hostname,
            # "enviado_en": now ts
        }

        detalle: List[Dict[str, Any]] = []
        tickets_set = set()
        for (
            ticket_id, fecha_t, producto_id, producto_nombre, producto_codigo, categoria,
            cantidad, precio_unitario, total, metodo_pago
        ) in items_rows:
            if ticket_id is not None:
                tickets_set.add(int(ticket_id))
            detalle.append({
                "caja_uuid": uuid_final,
                "ticket_id": int(ticket_id) if ticket_id is not None else None,
                "fecha": fecha_t,
                "producto_id": int(producto_id) if producto_id is not None else None,
                "producto_nombre": producto_nombre,
                "categoria": categoria,
                "cantidad": int(cantidad or 0),
                "precio_unitario": float(precio_unitario or 0),
                "total": float(total or 0),
                "metodo_pago": metodo_pago,
            })
        tickets_subidos = len(tickets_set)
        return cabecera, detalle, uuid_final, productos_necesarios, tickets_subidos, (codigo_caja or "")


def _fetch_existing_product_codes(codes: List[str]) -> set:
    if not codes:
        return set()
    found = set()
    # Particionar para no exceder límites de URL
    bs = 100
    for i in range(0, len(codes), bs):
        chunk = codes[i:i+bs]
        # Construir filtro in.("A","B")
        values = ",".join([f'"{c}"' for c in chunk])
        url = f"{SUPABASE_REST}/products?select=codigo_producto&codigo_producto=in.({values})"
        r = requests.get(url, headers=HEADERS, timeout=20)
        if r.status_code >= 300:
            raise RuntimeError(f"GET products {r.status_code}: {r.text}")
        arr = r.json() if r.text else []
        for row in arr:
            cp = (row.get("codigo_producto") or "").strip().upper()
            if cp:
                found.add(cp)
    return found


def _ensure_remote_products(productos_necesarios: Dict[str, Dict[str, Any]]) -> int:
    """Asegura que los productos por codigo existan en Supabase. Devuelve cantidad insertada."""
    if not productos_necesarios:
        return 0
    codes = list(productos_necesarios.keys())
    existentes = _fetch_existing_product_codes(codes)
    faltantes = [productos_necesarios[c] for c in codes if c not in existentes]
    if not faltantes:
        return 0
    # Insertar en lotes
    inserted = 0
    bs = 200
    for i in range(0, len(faltantes), bs):
        chunk = faltantes[i:i+bs]
        try:
            _post("products", chunk)
            inserted += len(chunk)
        except Exception as e:
            # Continuar con los siguientes; reportar parcial
            raise
    return inserted


def sync_caja(caja_id: int) -> Dict[str, Any]:
    if not is_configured():
        raise RuntimeError("Supabase no configurado (SUPABASE_URL / SUPABASE_ANON_KEY)")
    cab, items, uuid_final, productos_necesarios, tickets_subidos, codigo_caja = _build_payload(caja_id)
    # Asegurar catálogo de productos
    new_products = 0
    try:
        new_products = _ensure_remote_products(productos_necesarios)
    except Exception as e:
        # No abortar el envío de caja por productos faltantes; continuar y reflejar error en resultado
        productos_error = str(e)
    else:
        productos_error = None
    # Enviar primero cabecera, luego items
    _post("cajas", [cab])
    if items:
        # enviar en lotes para limitar tamaño
        bs = 500
        for i in range(0, len(items), bs):
            _post("caja_items", items[i:i+bs])
    # Marcar como sincronizada
    with get_connection() as conn:
        _ensure_sync_columns(conn)
        cur = conn.cursor()
        cur.execute(
            "UPDATE caja_diaria SET nube_enviado=1, nube_uuid=?, enviado_nube_ts=? WHERE id=?",
            (uuid_final, datetime.now().strftime('%Y-%m-%d %H:%M:%S'), caja_id)
        )
        conn.commit()
    res = {
        "caja_id": caja_id,
        "uuid": uuid_final,
        "items_subidos": len(items),
        "tickets_subidos": tickets_subidos,
        "codigo_caja": codigo_caja,
        "new_products": new_products,
    }
    if productos_error:
        res["productos_error"] = productos_error
    return res


def sync_pendientes(limit: int = 20) -> List[Dict[str, Any]]:
    if not is_configured():
        raise RuntimeError("Supabase no configurado")
    resultados: List[Dict[str, Any]] = []
    with get_connection() as conn:
        _ensure_sync_columns(conn)
        cur = conn.cursor()
        cur.execute(
            "SELECT id FROM caja_diaria WHERE estado='cerrada' AND COALESCE(nube_enviado,0)=0 ORDER BY id DESC LIMIT ?",
            (limit,)
        )
        ids = [r[0] for r in cur.fetchall()] or []
    for caja_id in ids:
        try:
            r = sync_caja(caja_id)
            r["ok"] = True
            resultados.append(r)
        except Exception as e:
            resultados.append({"caja_id": caja_id, "ok": False, "error": str(e)})
    return resultados
