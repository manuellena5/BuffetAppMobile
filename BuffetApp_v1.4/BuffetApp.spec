# BuffetApp.spec — portable ONEDIR, incluye pandas/numpy/pywin32/win32com
from PyInstaller.utils.hooks import collect_all
from PyInstaller.building.build_main import Analysis, PYZ, EXE, COLLECT
from pathlib import Path
import os

# Usar el cwd en vez de __file__
proj_dir = Path(os.getcwd())
icon_file = proj_dir / "icon.ico"  # opcional; quitá el parámetro icon si no existe

datas, binaries, hiddenimports = [], [], []

# Recolectar todo de paquetes “pesados” que PyInstaller a veces omite
for pkg in ("pandas", "numpy", "pywin32", "win32com"):
    try:
        d, b, h = collect_all(pkg)
        datas += d
        binaries += b
        hiddenimports += h
    except Exception:
        pass

# Archivos de tu app que necesitás junto al .exe
datas += [(str(proj_dir / "icon_salir.png"), ".")]

a = Analysis(
    ['main.py'],
    pathex=[str(proj_dir)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports + [
        # Algunos submódulos de pywin32
        'win32timezone', 'win32print', 'win32ui', 'win32con',
        'win32com', 'win32com.client', 'win32com.server'
    ],
    noarchive=False,   # OK dejar comprimido el PYZ
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
    upx=False,         # dejalo en False si el antivirus se pone celoso
    name='BuffetApp'
)
