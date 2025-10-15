"""Theme configuration for BuffetApp.

Provides centralized fonts and widget styling helpers
so that the application has a consistent look and feel.
"""

import tkinter as tk
from tkinter import ttk
from typing import Dict, Any

FONT_FAMILY = "Segoe UI"

# Fuentes básicas
FONTS = {
    'normal': (FONT_FAMILY, 11),
    'bold': (FONT_FAMILY, 11, 'bold'),
    'title': (FONT_FAMILY, 16, 'bold'),
    'subtitle': (FONT_FAMILY, 14),
    'button': (FONT_FAMILY, 12),
    'button_bold': (FONT_FAMILY, 12, 'bold')
}

# Estilos para la pantalla de Login (responsive / mobile-friendly)
LOGIN = {
    'title_font': (FONT_FAMILY, 28, 'bold'),
    'label_font': (FONT_FAMILY, 16),
    'entry_font': (FONT_FAMILY, 16),
    'button_font': (FONT_FAMILY, 16, 'bold'),
    'padding_x': 24,
    'padding_y': 12,
    'width': 36,
}

# Tamaños de iconos usados en la aplicación (ajustables desde tema)
ICON_SIZES = {
    'small': 16,
    'normal': 24,
    'large': 48,
    'kpi': 56,
}

# Versión de la aplicación (se mostrará en el título de la ventana)
APP_VERSION = "BuffetApp_v1.5"

# Parámetros específicos para la vista de ventas / carrito (fáciles de ajustar desde aquí)
CART = {
    'button_font': (FONT_FAMILY, 20, 'bold'),   # botones principales (Cobrar/Cancelar)
    'button_padx': 20,
    'button_pady': 10,
    'total_font': (FONT_FAMILY, 22, 'bold'),    # etiqueta Total
    'item_font': (FONT_FAMILY, 14),             # texto de items en carrito
    'subtotal_font': (FONT_FAMILY, 14, 'bold'), # subtotal por item
    'qty_button_font': (FONT_FAMILY, 12),       # botones +/- (aumentado 1 punto)
}

# Fuentes predefinidas para compatibilidad
TITLE_FONT = FONTS['title']
TEXT_FONT = FONTS['normal']

# Colores base
COLORS = {
    'primary': '#FFFFFF',       # Blanco principal
    'secondary': '#0B61FF',     # Azul (reemplaza negro)
    'background': '#F3F4F6',    # Gris claro para fondo
    'surface': '#FFFFFF',       # Blanco para superficies
    'accent': '#0B61FF',        # Azul para acentos (reemplaza negro)
    'text': "#060606",          # Azul para texto principal (reemplaza negro)
    'text_secondary': '#475569', # Gris para texto secundario
    'error': '#F43F5E',        # Rojo error
    'success': '#22C55E',      # Verde éxito
    'disabled_bg': '#EFEFF1',   # fondo para widgets no editables
    'disabled_fg': '#6B7280',   # texto para widgets no editables
}

# Colores para estados financieros
FINANCE_COLORS = {
    'positive_bg': '#E8F5E9',
    'positive_fg': '#2E7D32',
    'negative_bg': '#FFEBEE',
    'negative_fg': '#C62828',
    'transfer_bg': '#E3F2FD',
    'transfer_fg': '#1565C0',
    'total_sales_bg': '#1976D2',
    'total_sales_fg': '#FFFFFF',
}



# Estilos de botones
BUTTON_FONT = FONTS['button']
BUTTON_BG = COLORS['accent']
BUTTON_FG = COLORS['primary']

# Base style applied to all buttons
_BASE_BUTTON_STYLE = {
    "font": BUTTON_FONT,
    "bg": BUTTON_BG,
    "fg": BUTTON_FG,
    "activebackground": BUTTON_BG,
    "activeforeground": BUTTON_FG,
    "bd": 0,
    "padx": 10,
    "pady": 5,
}

# Variant styles for specific screens
BUTTON_STYLES = {
    "ventas": {"font": CART['button_font'], "padx": CART['button_padx'], "pady": CART['button_pady'], "width": 12},
    "productos": {"width": 7, "height": 1},
    # Variantes semánticas reutilizables
    "success": {"bg": COLORS['success'], "fg": COLORS['primary'], "activebackground": COLORS['success'], "activeforeground": COLORS['primary']},
    "primary": {"bg": COLORS['accent'], "fg": COLORS['primary'], "activebackground": COLORS['accent'], "activeforeground": COLORS['primary']},
    "danger": {"bg": COLORS['error'], "fg": COLORS['primary'], "activebackground": COLORS['error'], "activeforeground": COLORS['primary']},
}


def format_currency(amount: float, include_sign: bool = False) -> str:
    """Formatea montos en pesos argentinos"""
    try:
        formatted = f"$ {abs(amount):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
        if include_sign and amount < 0:
            return f"-{formatted}"
        return formatted
    except:
        return f"$ 0,00"

def create_themed_style() -> Dict[str, Dict[str, Any]]:
    """Crea estilos temáticos para widgets comunes"""
    return {
        'button': {
            'bg': COLORS['accent'],
            'fg': COLORS['primary'],
            'font': FONTS['button_bold'],
            'relief': 'raised',
            'padx': 10,
            'pady': 5
        },
        'frame': {
            'bg': COLORS['background'],
            'relief': 'flat'
        },
        'label': {
            'bg': COLORS['surface'],
            'fg': COLORS['text'],
            'font': FONTS['normal']
        },
        'entry': {
            'bg': COLORS['surface'],
            'fg': COLORS['text'],
            'font': FONTS['normal']
        }
    }

def apply_theme(widget: tk.Widget, style_name: str = None) -> None:
    """Aplica el tema al widget especificado"""
    styles = create_themed_style()
    if style_name and style_name in styles:
        for key, value in styles[style_name].items():
            try:
                widget[key] = value
            except tk.TclError:
                pass

def themed_button(parent: tk.Widget, **kwargs) -> tk.Button:
    """Crea un botón con el tema aplicado"""
    button = tk.Button(parent)
    apply_theme(button, 'button')
    button.configure(**kwargs)
    return button

def apply_button_style(button: tk.Button, style: str = None, **overrides) -> None:
    """Aplica el estilo predefinido a un botón.

    Parámetros:
    - button: widget Button a estilizar
    - style: clave opcional en BUTTON_STYLES para aplicar variante
    - overrides: pares clave/valor que se aplican con button.configure(**overrides)
    """
    # aplica estilo base
    apply_theme(button, 'button')

    # aplica variante si existe
    if style and style in BUTTON_STYLES:
        for key, val in BUTTON_STYLES[style].items():
            try:
                # intenta configurar como opción de widget
                button[key] = val
            except Exception:
                try:
                    button.configure({key: val})
                except Exception:
                    pass

    # aplica overrides (bg/fg, font, width, height, etc.)
    if overrides:
        try:
            button.configure(**overrides)
        except Exception:
            for k, v in overrides.items():
                try:
                    button[k] = v
                except Exception:
                    pass

def apply_treeview_style():
    """Configure and return a namespaced Treeview style (App.Treeview).

    This avoids mutating the global "Treeview" style which can cause
    font/size changes across unrelated screens when multiple views
    configure styles at different times.
    """
    style = ttk.Style()
    # Create a namespaced style for application Treeviews
    style_name = "App.Treeview"
    style.configure(style_name,
                    font=FONTS['normal'],
                    rowheight=25,
                    background=COLORS['surface'],
                    foreground=COLORS['text'],
                    fieldbackground=COLORS['surface'])

    style.configure(f"{style_name}.Heading",
                    background=COLORS['background'],
                    foreground=COLORS['text'],
                    font=FONTS['bold'])

    style.map(style_name,
              background=[('selected', COLORS['accent'])],
              foreground=[('selected', COLORS['primary'])])

    return style
