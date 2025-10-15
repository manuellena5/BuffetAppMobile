import sqlite3
from utils_paths import DB_PATH


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

