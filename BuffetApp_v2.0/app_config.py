"""Gestión de configuración de la app en AppData (config.json).

- Persiste un device_id único por equipo (UUID4) y un device_name editable.
- Provee utilidades para leer/guardar configuración de forma segura.
"""
from __future__ import annotations

import json
import os
import platform
import uuid
from typing import Any, Dict

from utils_paths import CONFIG_PATH


DEFAULTS: Dict[str, Any] = {
    "ancho_boton": 20,
    "alto_boton": 2,
    "color_boton": "#f0f0f0",
    "fuente_boton": "Arial",
    "lenguaje": "es",
    "printer_name": None,
}


def _read_file() -> Dict[str, Any]:
    if not os.path.exists(CONFIG_PATH) or os.path.getsize(CONFIG_PATH) == 0:
        return {}
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f) or {}
    except Exception:
        return {}


def _write_file(cfg: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)


def get_config() -> Dict[str, Any]:
    """Lee la configuración combinando defaults y valores guardados.

    Garantiza que existan `device_id` y `device_name`.
    """
    cfg = {**DEFAULTS}
    cfg.update(_read_file())
    changed = False
    if not cfg.get("device_id"):
        cfg["device_id"] = str(uuid.uuid4())
        changed = True
    if not cfg.get("device_name"):
        hostname = platform.node() or "Equipo"
        cfg["device_name"] = f"{hostname}"
        changed = True
    if changed:
        _write_file(cfg)
    return cfg


def save_config(new_cfg: Dict[str, Any]) -> None:
    cfg = get_config()
    cfg.update(new_cfg or {})
    _write_file(cfg)


def get_device_id() -> str:
    return get_config().get("device_id")


def get_device_name() -> str:
    return get_config().get("device_name")


def set_device_name(name: str) -> None:
    save_config({"device_name": (name or "").strip() or get_device_name()})


def set_device_id(new_id: str) -> None:
    """Permite reemplazar manualmente el device_id (uso avanzado).

    Nota: cambiar este valor no actualiza filas existentes en la DB.
    """
    new_id = (new_id or "").strip()
    # Validar formato superficial UUID
    try:
        uuid.UUID(new_id)
    except Exception:
        # Aceptar cualquier string no vacío si el usuario insiste
        if not new_id:
            raise ValueError("device_id no puede ser vacío")
    save_config({"device_id": new_id})


# -------- Impresora seleccionada ---------
def get_printer_name() -> str | None:
    """Devuelve el nombre de la impresora configurada por el usuario, o None si no hay selección.

    Nota: si es None, se debe usar la impresora predeterminada de Windows.
    """
    return get_config().get("printer_name")


def set_printer_name(name: str | None) -> None:
    """Guarda el nombre de la impresora seleccionada. Pasar None para limpiar y usar la predeterminada del sistema."""
    save_config({"printer_name": name})
