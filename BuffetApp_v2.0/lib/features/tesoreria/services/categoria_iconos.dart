/// Catálogo de iconos predefinidos para categorías de movimientos
/// Basado en Material Symbols Outlined
class CategoriaIconos {
  static const List<Map<String, String>> iconos = [
    // Dinero y finanzas
    {'code': 'attach_money', 'label': 'Dinero'},
    {'code': 'account_balance', 'label': 'Banco'},
    {'code': 'account_balance_wallet', 'label': 'Billetera'},
    {'code': 'savings', 'label': 'Ahorros'},
    {'code': 'paid', 'label': 'Pagado'},
    {'code': 'payment', 'label': 'Pago'},
    {'code': 'receipt', 'label': 'Recibo'},
    {'code': 'receipt_long', 'label': 'Factura'},
    {'code': 'credit_card', 'label': 'Tarjeta'},
    {'code': 'currency_exchange', 'label': 'Cambio'},
    
    // Deportes y eventos
    {'code': 'sports_soccer', 'label': 'Fútbol'},
    {'code': 'sports', 'label': 'Deportes'},
    {'code': 'stadium', 'label': 'Estadio'},
    {'code': 'confirmation_number', 'label': 'Entradas'},
    {'code': 'local_activity', 'label': 'Actividades'},
    {'code': 'sports_basketball', 'label': 'Baloncesto'},
    {'code': 'sports_volleyball', 'label': 'Vóley'},
    {'code': 'fitness_center', 'label': 'Gimnasio'},
    
    // Personas y grupos
    {'code': 'people', 'label': 'Personas'},
    {'code': 'groups', 'label': 'Grupos'},
    {'code': 'person', 'label': 'Persona'},
    {'code': 'card_membership', 'label': 'Membresía'},
    {'code': 'volunteer_activism', 'label': 'Colaboración'},
    
    // Servicios
    {'code': 'restaurant', 'label': 'Restaurante'},
    {'code': 'restaurant_menu', 'label': 'Menú'},
    {'code': 'dinner_dining', 'label': 'Comida'},
    {'code': 'local_bar', 'label': 'Bar'},
    {'code': 'local_cafe', 'label': 'Café'},
    {'code': 'cleaning_services', 'label': 'Limpieza'},
    {'code': 'local_laundry_service', 'label': 'Lavandería'},
    {'code': 'medical_services', 'label': 'Servicios médicos'},
    {'code': 'local_pharmacy', 'label': 'Farmacia'},
    {'code': 'ambulance', 'label': 'Ambulancia'},
    {'code': 'local_police', 'label': 'Policía'},
    
    // Utilidades
    {'code': 'bolt', 'label': 'Electricidad'},
    {'code': 'local_fire_department', 'label': 'Gas'},
    {'code': 'water_drop', 'label': 'Agua'},
    {'code': 'wifi', 'label': 'Internet'},
    {'code': 'phone', 'label': 'Teléfono'},
    
    // Mantenimiento y construcción
    {'code': 'build', 'label': 'Mantenimiento'},
    {'code': 'construction', 'label': 'Construcción'},
    {'code': 'engineering', 'label': 'Obra'},
    {'code': 'hardware', 'label': 'Ferretería'},
    {'code': 'handyman', 'label': 'Reparaciones'},
    {'code': 'plumbing', 'label': 'Plomería'},
    {'code': 'fence', 'label': 'Cerco'},
    {'code': 'pest_control', 'label': 'Fumigación'},
    
    // Transporte
    {'code': 'directions_bus', 'label': 'Transporte'},
    {'code': 'directions_car', 'label': 'Auto'},
    {'code': 'local_shipping', 'label': 'Envío'},
    {'code': 'flight', 'label': 'Vuelo'},
    
    // Comunicación y publicidad
    {'code': 'campaign', 'label': 'Publicidad'},
    {'code': 'notifications', 'label': 'Notificaciones'},
    {'code': 'newspaper', 'label': 'Prensa'},
    
    // Inventario y materiales
    {'code': 'inventory_2', 'label': 'Inventario'},
    {'code': 'checkroom', 'label': 'Indumentaria'},
    {'code': 'shopping_cart', 'label': 'Compras'},
    {'code': 'local_mall', 'label': 'Tienda'},
    
    // Administrativo
    {'code': 'gavel', 'label': 'Legal/Multas'},
    {'code': 'shield', 'label': 'Seguros'},
    {'code': 'swap_horiz', 'label': 'Transferencias'},
    {'code': 'casino', 'label': 'Juegos'},
    {'code': 'home', 'label': 'Hogar/Local'},
    
    // General
    {'code': 'category', 'label': 'Categoría'},
    {'code': 'label', 'label': 'Etiqueta'},
    {'code': 'bookmark', 'label': 'Marcador'},
    {'code': 'star', 'label': 'Destacado'},
    {'code': 'favorite', 'label': 'Favorito'},
  ];
  
  /// Obtiene el label de un icono por su código
  static String? getLabelForCode(String code) {
    try {
      return iconos.firstWhere((i) => i['code'] == code)['label'];
    } catch (_) {
      return null;
    }
  }
  
  /// Valida si un código de icono existe
  static bool isValidIcon(String code) {
    return iconos.any((i) => i['code'] == code);
  }
}
