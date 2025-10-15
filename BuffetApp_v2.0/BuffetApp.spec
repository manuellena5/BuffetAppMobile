"""BuffetApp.spec
Optimizada para tamaño: se eliminaron pandas/numpy porque:
 - numpy: no hay ningun import.
 - pandas: solo se usa de forma diferida en historial_view para exportar (import pandas as pd dentro de una función). Si el usuario NO exporta, no se necesita. Para reducir MB no lo incluimos por defecto.
Si se requiere soporte de exportación a Excel en un futuro, instalar pandas y añadirlo manualmente.
"""
from PyInstaller.building.build_main import Analysis, PYZ, EXE, COLLECT
from pathlib import Path
import os

# Cuando PyInstaller ejecuta el spec, __file__ no siempre está definido de la forma esperada.
# Usamos el cwd y nos aseguramos que apunte a la carpeta donde está main.py.
proj_dir = Path.cwd() / 'BuffetApp_v1.4'
if not (proj_dir / 'main.py').exists():
    # fallback: intentar el parent de este spec si se ejecuta desde dentro
    maybe = Path.cwd()
    if (maybe / 'main.py').exists():
        proj_dir = maybe
icon_file = proj_dir / "icon.ico"

# Resources explícitos
icon_salir = proj_dir / "icon_salir.png"
icon_app_256 = proj_dir / "cdm_mitre_white_app_256.png"
icon_app_2048 = proj_dir / "cdm_mitre_white_app_2048.png"
datas = []
for extra_icon in (icon_salir, icon_app_256, icon_app_2048):
    if extra_icon.exists():
        datas.append((str(extra_icon), "."))

binaries = []
hiddenimports = []

# pywin32: solo módulos realmente utilizados en impresión (imports diferidos en código)
hiddenimports += [
    'win32print', 'win32ui', 'win32con', 'win32timezone'
]

a = Analysis(
    ['main.py'],
    pathex=[str(proj_dir)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    name='BuffetApp',
    console=False,
    icon=str(icon_file) if icon_file.exists() else None
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    name='BuffetApp'
)
