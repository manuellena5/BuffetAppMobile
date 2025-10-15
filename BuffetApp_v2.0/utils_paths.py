# utils_paths.py
import os, sys, shutil

APP_DIRNAME = "BuffetApp"

def appdata_dir() -> str:
    base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    path = os.path.join(base, APP_DIRNAME)
    os.makedirs(path, exist_ok=True)
    return path

def resource_path(rel_path: str) -> str:
    # Carpeta donde PyInstaller extrae los archivos (cuando es onefile)
    base = getattr(sys, "_MEIPASS", os.path.dirname(sys.argv[0]))
    return os.path.join(base, rel_path)

def ensure_user_file(rel_name: str) -> str:
    """
    Si no existe en AppData, copia el archivo incluido en el bundle (read-only)
    hacia AppData y devuelve la ruta en AppData.
    """
    dst = os.path.join(appdata_dir(), rel_name)
    if not os.path.exists(dst):
        src = resource_path(rel_name)
        if os.path.exists(src):
            try:
                shutil.copy2(src, dst)
            except Exception:
                # Si falla la copia, al menos asegura carpeta y crea vacío
                open(dst, "a", encoding="utf-8").close()
    return dst

# Rutas públicas que usarán los módulos
DB_PATH = ensure_user_file("barcancha.db")
CONFIG_PATH = ensure_user_file("config.json")
