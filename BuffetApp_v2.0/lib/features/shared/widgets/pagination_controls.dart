import 'package:flutter/material.dart';
import '../../../domain/paginated_result.dart';

/// Widget reutilizable para controles de paginación estilo numerado (1, 2, 3...)
/// 
/// Muestra información de rango y botones de navegación entre páginas.
/// Soporta modo compacto para pantallas pequeñas.
/// 
/// Ejemplo de uso:
/// ```dart
/// PaginationControls(
///   paginatedResult: _result,
///   onPageChanged: (page) {
///     setState(() => _currentPage = page);
///     _cargarDatos();
///   },
/// )
/// ```
class PaginationControls extends StatelessWidget {
  final PaginatedResult paginatedResult;
  final ValueChanged<int> onPageChanged;
  final bool compact;
  final bool showRangeInfo;

  const PaginationControls({
    super.key,
    required this.paginatedResult,
    required this.onPageChanged,
    this.compact = false,
    this.showRangeInfo = true,
  });

  @override
  Widget build(BuildContext context) {
    if (paginatedResult.totalCount == 0) {
      return const SizedBox.shrink();
    }

    final currentPage = paginatedResult.currentPage;
    final totalPages = paginatedResult.totalPages;

    // Botones de página a mostrar (1, 2, 3... o compacto)
    final pageButtons = _buildPageButtons(currentPage, totalPages);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Información de rango
          if (showRangeInfo)
            Flexible(
              child: Text(
                paginatedResult.rangeInfo,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const SizedBox.shrink(),

          // Controles de navegación
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Primera página
              IconButton(
                onPressed: currentPage > 1 ? () => onPageChanged(1) : null,
                icon: const Icon(Icons.first_page),
                tooltip: 'Primera página',
                iconSize: 20,
              ),

              // Página anterior
              IconButton(
                onPressed: paginatedResult.hasPreviousPage
                    ? () => onPageChanged(currentPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Anterior',
                iconSize: 20,
              ),

              // Botones de página
              if (!compact) ...pageButtons,

              // Indicador compacto
              if (compact)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '$currentPage / $totalPages',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),

              // Página siguiente
              IconButton(
                onPressed: paginatedResult.hasNextPage
                    ? () => onPageChanged(currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Siguiente',
                iconSize: 20,
              ),

              // Última página
              IconButton(
                onPressed: currentPage < totalPages
                    ? () => onPageChanged(totalPages)
                    : null,
                icon: const Icon(Icons.last_page),
                tooltip: 'Última página',
                iconSize: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageButtons(int currentPage, int totalPages) {
    final buttons = <Widget>[];

    // Mostrar máximo 5 botones de página
    int start = (currentPage - 2).clamp(1, totalPages);
    int end = (start + 4).clamp(1, totalPages);

    // Ajustar start si end está al límite
    if (end == totalPages && totalPages > 5) {
      start = (end - 4).clamp(1, totalPages);
    }

    for (int i = start; i <= end; i++) {
      buttons.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: _PageButton(
            pageNumber: i,
            isCurrentPage: i == currentPage,
            onPressed: () => onPageChanged(i),
          ),
        ),
      );
    }

    return buttons;
  }
}

class _PageButton extends StatelessWidget {
  final int pageNumber;
  final bool isCurrentPage;
  final VoidCallback onPressed;

  const _PageButton({
    required this.pageNumber,
    required this.isCurrentPage,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: isCurrentPage ? null : onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.all(8),
        backgroundColor: isCurrentPage
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        foregroundColor: isCurrentPage
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : null,
      ),
      child: Text(
        '$pageNumber',
        style: TextStyle(
          fontWeight: isCurrentPage ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// Variante compacta del widget de paginación
/// Solo muestra "N / M" y botones prev/next
class PaginationControlsCompact extends StatelessWidget {
  final PaginatedResult paginatedResult;
  final ValueChanged<int> onPageChanged;

  const PaginationControlsCompact({
    super.key,
    required this.paginatedResult,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PaginationControls(
      paginatedResult: paginatedResult,
      onPageChanged: onPageChanged,
      compact: true,
      showRangeInfo: false,
    );
  }
}
