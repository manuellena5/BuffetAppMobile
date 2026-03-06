import 'package:flutter/material.dart';

/// Skeleton loader con efecto shimmer, sin dependencias externas.
///
/// Uso básico:
/// ```dart
/// SkeletonLoader()  // muestra lista genérica de 5 items
/// SkeletonLoader.cards(count: 3)  // 3 tarjetas skeleton
/// SkeletonLoader.table(rows: 5, columns: 4)  // tabla skeleton
/// SkeletonLoader.custom(child: _myCustomSkeleton())  // hijo personalizado
/// ```
class SkeletonLoader extends StatefulWidget {
  final Widget child;

  const SkeletonLoader({super.key, required this.child});

  /// Lista genérica de items skeleton (por defecto 5).
  factory SkeletonLoader.list({Key? key, int count = 5}) {
    return SkeletonLoader(
      key: key,
      child: _SkeletonList(count: count),
    );
  }

  /// Tarjetas skeleton (estilo cards).
  factory SkeletonLoader.cards({Key? key, int count = 3}) {
    return SkeletonLoader(
      key: key,
      child: _SkeletonCards(count: count),
    );
  }

  /// Tabla skeleton con filas y columnas.
  factory SkeletonLoader.table({Key? key, int rows = 5, int columns = 4}) {
    return SkeletonLoader(
      key: key,
      child: _SkeletonTable(rows: rows, columns: columns),
    );
  }

  /// Skeleton personalizado — le aplica shimmer al hijo.
  factory SkeletonLoader.custom({Key? key, required Widget child}) {
    return SkeletonLoader(key: key, child: child);
  }

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0xFFE0E0E0),
                Color(0xFFF5F5F5),
                Color(0xFFE0E0E0),
              ],
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

// ─── Skeletons prefabricados ─────────────────────────────────

/// Barra rectangular skeleton.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Círculo skeleton.
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  final int count;
  const _SkeletonList({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(count, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                const SkeletonCircle(size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 14, width: (i % 2 == 0) ? 180 : 140),
                      const SizedBox(height: 8),
                      const SkeletonBox(height: 12, width: 100),
                    ],
                  ),
                ),
                const SkeletonBox(width: 60, height: 14),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _SkeletonCards extends StatelessWidget {
  final int count;
  const _SkeletonCards({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(count, (_) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(height: 16, width: 200),
                    SizedBox(height: 12),
                    SkeletonBox(height: 12),
                    SizedBox(height: 8),
                    SkeletonBox(height: 12, width: 150),
                    SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SkeletonBox(width: 80, height: 14),
                        SkeletonBox(width: 60, height: 14),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SkeletonTable extends StatelessWidget {
  final int rows;
  final int columns;
  const _SkeletonTable({required this.rows, required this.columns});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: List.generate(columns, (_) {
                return const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SkeletonBox(height: 14),
                  ),
                );
              }),
            ),
          ),
          const Divider(height: 1),
          // Rows
          ...List.generate(rows, (_) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: List.generate(columns, (_) {
                  return const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: SkeletonBox(height: 12),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }
}
