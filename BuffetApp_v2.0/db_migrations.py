"""Funciones de migración reutilizables para BuffetApp."""
import sqlite3
import shutil
import datetime
import os
from .utils_paths import DB_PATH, appdata_dir

BACKUP_DIR = os.path.join(appdata_dir(), 'backup')
os.makedirs(BACKUP_DIR, exist_ok=True)


def backup_db(db_path: str = None) -> str:
    db_path = db_path or DB_PATH
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    dst = os.path.join(BACKUP_DIR, f'barcancha_{ts}.db')
    # Prefer sqlite online backup API for a consistent copy while DB may be in use
    try:
        src_conn = sqlite3.connect(db_path)
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
    except Exception:
        # fallback to filesystem copy
        shutil.copy2(db_path, dst)
    return dst


def add_ventas_efectivo_column_with_backup(db_path: str = None) -> str:
    """Hace backup y añade la columna ventas_efectivo si no existe.

    Devuelve la ruta del backup realizado.
    """
    db_path = db_path or DB_PATH
    backup_path = backup_db(db_path)

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("PRAGMA table_info(caja_diaria)")
    cols = [r[1] for r in c.fetchall()]
    if 'ventas_efectivo' in cols:
        conn.close()
        return backup_path

    c.execute('ALTER TABLE caja_diaria ADD COLUMN ventas_efectivo REAL DEFAULT 0')
    conn.commit()

    # popular
    c.execute('SELECT id FROM caja_diaria')
    cajas = [r[0] for r in c.fetchall()]
    for cid in cajas:
        c.execute(
            "SELECT COALESCE(SUM(t.total_ticket),0) FROM tickets t JOIN ventas v ON v.id=t.venta_id JOIN metodos_pago mp ON mp.id=v.metodo_pago_id WHERE v.caja_id=? AND t.status!='Anulado' AND mp.descripcion='Efectivo'",
            (cid,)
        )
        val = c.fetchone()[0] or 0
        c.execute('UPDATE caja_diaria SET ventas_efectivo=? WHERE id=?', (val, cid))
    conn.commit()

    # índices
    try:
        c.execute('CREATE INDEX IF NOT EXISTS idx_ventas_caja ON ventas(caja_id)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_tickets_venta ON tickets(venta_id)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_metodo_pago ON ventas(metodo_pago_id)')
        conn.commit()
    except Exception:
        pass

    conn.close()
    return backup_path
