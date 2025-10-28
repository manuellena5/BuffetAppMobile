import sqlite3
from utils_paths import DB_PATH
import re
import unicodedata


def get_connection():
    """Return a SQLite connection with foreign keys enabled."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def get_setting(key: str) -> str | None:
    try:
        conn = get_connection(); cur = conn.cursor()
        cur.execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        cur.execute("SELECT value FROM settings WHERE key=?", (key,))
        row = cur.fetchone()
        conn.close()
        return row[0] if row else None
    except Exception:
        try:
            conn.close()
        except Exception:
            pass
        return None


def get_current_pos_uuid() -> str | None:
    return get_setting('device_pos_uuid')


def _normalize_text(txt: str) -> str:
    if not isinstance(txt, str):
        return ""
    # Quitar acentos y no alfanuméricos, mantener letras/números
    nfkd = unicodedata.normalize('NFKD', txt)
    no_accents = "".join([c for c in nfkd if not unicodedata.combining(c)])
    only_an = re.sub(r"[^A-Za-z0-9]", "", no_accents)
    return only_an.upper()


def generate_unique_product_code(nombre: str) -> str:
    """Genera un código de 4 caracteres a partir del nombre y garantiza unicidad.

    Regla:
    - Tomar las primeras 4 letras/números del nombre (normalizado). Si <4, completar con números.
    - Si ya existe, reemplazar el 4° carácter por la última letra distinta de vacío; si existe, por la anterior; y así sucesivamente.
    - Si todos existen, intentar con dígitos 0-9 en la 4° posición; si aún existe, probar A..Z.
    """
    base = _normalize_text(nombre)
    if not base:
        base = "PRD"
    # Tomar hasta 4, y si sobran, completar con números
    seed = base[:4]
    if len(seed) < 4:
        seed = (seed + "1234")[:4]
    seed = seed.upper()

    def _exists(code: str) -> bool:
        conn = get_connection(); cur = conn.cursor()
        try:
            cur.execute("SELECT 1 FROM products WHERE codigo_producto=? LIMIT 1", (code,))
            return cur.fetchone() is not None
        finally:
            try:
                conn.close()
            except Exception:
                pass

    code = seed
    if not _exists(code):
        return code

    # Intentar reemplazar el 4° por letras del nombre de atrás hacia adelante
    tail_letters = [c for c in base[::-1] if c.isalpha()]
    tried = set([code])
    for ch in tail_letters:
        cand = seed[:3] + ch.upper()
        if cand in tried:
            continue
        if not _exists(cand):
            return cand
        tried.add(cand)

    # Intentar con dígitos 0-9
    for d in "0123456789":
        cand = seed[:3] + d
        if cand in tried:
            continue
        if not _exists(cand):
            return cand
        tried.add(cand)

    # Fallback: A..Z
    for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        cand = seed[:3] + ch
        if cand in tried:
            continue
        if not _exists(cand):
            return cand
        tried.add(cand)

    # Último recurso: sufijo incremental numérico (aunque exceda 4, mantener compatibilidad)
    n = 1
    while True:
        cand = f"{seed}{n}"
        if not _exists(cand):
            return cand
        n += 1

