import 'package:flutter/material.dart';

/// Helper centralizado para convertir nombres de iconos (guardados en DB)
/// a [IconData] de Material Icons.
///
/// Usado en categorías de movimientos, compromisos y acuerdos.
class CategoryIconHelper {
  CategoryIconHelper._();

  static const _iconMap = <String, IconData>{
    // Dinero y finanzas
    'attach_money': Icons.attach_money,
    'account_balance': Icons.account_balance,
    'account_balance_wallet': Icons.account_balance_wallet,
    'savings': Icons.savings,
    'paid': Icons.paid,
    'payment': Icons.payment,
    'receipt': Icons.receipt,
    'receipt_long': Icons.receipt_long,
    'credit_card': Icons.credit_card,
    'currency_exchange': Icons.currency_exchange,
    // Deportes y eventos
    'sports_soccer': Icons.sports_soccer,
    'sports': Icons.sports,
    'stadium': Icons.stadium,
    'confirmation_number': Icons.confirmation_number,
    'local_activity': Icons.local_activity,
    'sports_basketball': Icons.sports_basketball,
    'sports_volleyball': Icons.sports_volleyball,
    'fitness_center': Icons.fitness_center,
    // Personas y grupos
    'people': Icons.people,
    'groups': Icons.groups,
    'person': Icons.person,
    'card_membership': Icons.card_membership,
    'volunteer_activism': Icons.volunteer_activism,
    // Servicios
    'restaurant': Icons.restaurant,
    'restaurant_menu': Icons.restaurant_menu,
    'dinner_dining': Icons.dinner_dining,
    'local_bar': Icons.local_bar,
    'local_cafe': Icons.local_cafe,
    'cleaning_services': Icons.cleaning_services,
    'local_laundry_service': Icons.local_laundry_service,
    'medical_services': Icons.medical_services,
    'local_pharmacy': Icons.local_pharmacy,
    'ambulance': Icons.medical_services,
    'local_police': Icons.local_police,
    // Utilidades
    'bolt': Icons.bolt,
    'local_fire_department': Icons.local_fire_department,
    'water_drop': Icons.water_drop,
    'wifi': Icons.wifi,
    'phone': Icons.phone,
    // Mantenimiento y construcción
    'build': Icons.build,
    'construction': Icons.construction,
    'engineering': Icons.engineering,
    'hardware': Icons.hardware,
    'handyman': Icons.handyman,
    'plumbing': Icons.plumbing,
    'fence': Icons.fence,
    'pest_control': Icons.pest_control,
    // Transporte
    'directions_bus': Icons.directions_bus,
    'directions_car': Icons.directions_car,
    'local_shipping': Icons.local_shipping,
    'flight': Icons.flight,
    // Comunicación y publicidad
    'campaign': Icons.campaign,
    'notifications': Icons.notifications,
    'newspaper': Icons.newspaper,
    // Inventario y materiales
    'inventory_2': Icons.inventory_2,
    'checkroom': Icons.checkroom,
    'shopping_cart': Icons.shopping_cart,
    'local_mall': Icons.local_mall,
    // Administrativo
    'gavel': Icons.gavel,
    'shield': Icons.shield,
    'swap_horiz': Icons.swap_horiz,
    'casino': Icons.casino,
    'home': Icons.home,
    // Tendencias y métricas financieras
    'trending_up': Icons.trending_up,
    'trending_down': Icons.trending_down,
    'trending_flat': Icons.trending_flat,
    'show_chart': Icons.show_chart,
    'bar_chart': Icons.bar_chart,
    'percent': Icons.percent,
    // General
    'category': Icons.category,
    'label': Icons.label,
    'bookmark': Icons.bookmark,
    'star': Icons.star,
    'favorite': Icons.favorite,
  };

  /// Devuelve el [IconData] correspondiente al nombre guardado en DB.
  /// Si no se encuentra o es null, devuelve [Icons.category].
  static IconData fromName(String? iconName) {
    if (iconName == null || iconName.isEmpty) return Icons.category;
    return _iconMap[iconName] ?? Icons.category;
  }

  /// Mapa completo de iconos disponibles (para el selector de iconos).
  static Map<String, IconData> get availableIcons => _iconMap;
}
