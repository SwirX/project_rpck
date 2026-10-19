import 'package:flutter/material.dart';

import 'rpck_top_bar.dart';
import 'tile_metrics.dart';

/// Placeholder blocks shown while content is being fetched.
///
/// Shimmer is driven by a single animation per block rather than one per tile,
/// and the palette is read inside build so a theme switch repaints it.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final highlight = palette == RpckPalette.light
        ? const Color(0xFFEDEEF1)
        : const Color(0xFF262626);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final drift = -1 + _controller.value * 2.6;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(drift, 0),
              end: Alignment(drift + 0.6, 0),
              colors: [palette.surface, highlight, palette.surface],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton grid matching the catalogue tile layout.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.tileCount = 12});

  final int tileCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      gridDelegate: tileGridDelegate,
      itemCount: tileCount,
      itemBuilder: (context, _) => Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.hairline),
        ),
        padding: const EdgeInsets.all(12),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SkeletonBox(
                width: double.infinity,
                height: double.infinity,
                radius: 12,
              ),
            ),
            SizedBox(height: 12),
            SkeletonBox(width: double.infinity, height: 12),
            SizedBox(height: 8),
            SkeletonBox(width: 90, height: 10),
          ],
        ),
      ),
    );
  }
}

/// Skeleton rows for a detail page.
class SkeletonDetail extends StatelessWidget {
  const SkeletonDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: const [
        SkeletonBox(width: double.infinity, height: 180, radius: 16),
        SizedBox(height: 24),
        SkeletonBox(width: double.infinity, height: 14, radius: 6),
        SizedBox(height: 10),
        SkeletonBox(width: 260, height: 14, radius: 6),
        SizedBox(height: 10),
        SkeletonBox(width: 180, height: 14, radius: 6),
        SizedBox(height: 32),
        SkeletonBox(width: 140, height: 18, radius: 6),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 12, radius: 6),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 12, radius: 6),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 12, radius: 6),
        SizedBox(height: 26),
        SkeletonBox(width: 140, height: 18, radius: 6),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 64, radius: 12),
        SizedBox(height: 10),
        SkeletonBox(width: double.infinity, height: 64, radius: 12),
      ],
    );
  }
}

/// Skeleton cards for the downloads list.
class SkeletonDownloadList extends StatelessWidget {
  const SkeletonDownloadList({super.key, this.cardCount = 4});

  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      itemCount: cardCount,
      itemBuilder: (context, _) => const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: SkeletonBox(width: double.infinity, height: 96, radius: 16),
      ),
    );
  }
}