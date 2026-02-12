/// Resultado paginado genérico para cualquier tipo de entidad
/// 
/// Proporciona metadatos completos de paginación y helpers útiles
/// para implementar controles de navegación en la UI.
/// 
/// Uso típico:
/// ```dart
/// final result = await service.getItemsPaginados(page: 2, pageSize: 50);
/// print(result.rangeInfo); // "51-100 de 243"
/// if (result.hasNextPage) {
///   // mostrar botón "Siguiente"
/// }
/// ```
class PaginatedResult<T> {
  final List<T> items;
  final int totalCount;
  final int pageSize;
  final int currentPage;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPreviousPage;

  PaginatedResult({
    required this.items,
    required this.totalCount,
    required this.pageSize,
    required this.currentPage,
  })  : totalPages = totalCount == 0 ? 1 : (totalCount / pageSize).ceil(),
        hasNextPage = currentPage < (totalCount == 0 ? 1 : (totalCount / pageSize).ceil()),
        hasPreviousPage = currentPage > 1;

  /// Crea un resultado vacío (sin items)
  factory PaginatedResult.empty() {
    return PaginatedResult<T>(
      items: [],
      totalCount: 0,
      pageSize: 50,
      currentPage: 1,
    );
  }

  /// Información de rango de items mostrados (ej: "1-50 de 243")
  String get rangeInfo {
    if (totalCount == 0) return '0 de 0';
    final start = ((currentPage - 1) * pageSize) + 1;
    final end = (currentPage * pageSize).clamp(0, totalCount);
    return '$start-$end de $totalCount';
  }

  /// Descripción legible del estado de paginación
  String get description {
    if (totalCount == 0) return 'Sin resultados';
    if (totalPages == 1) return '$totalCount resultado${totalCount == 1 ? '' : 's'}';
    return 'Página $currentPage de $totalPages ($totalCount total)';
  }

  /// Helper para determinar si está en la primera página
  bool get isFirstPage => currentPage == 1;

  /// Helper para determinar si está en la última página
  bool get isLastPage => currentPage >= totalPages;

  /// Retorna true si hay resultados
  bool get isNotEmpty => items.isNotEmpty;

  /// Retorna true si no hay resultados
  bool get isEmpty => items.isEmpty;
}
