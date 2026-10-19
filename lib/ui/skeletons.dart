import 'package:flutter/material.dart';

import 'rpck_top_bar.dart';

/// Placeholder blocks shown while content is being fetched.
///
/// Shimmer is driven by a single repeating gradient rather than one animation
/// per tile: a grid of a few hundred independent controllers is a measurable
/// frame cost for an effect the user reads in the first half second.
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + _controller.value * 2.6, 0),
              end: Alignment(-0.4 + _controller.value * 2.6, 0),
              colors: const [
                RpckTheme.surface,
                Color(0xFF262626),
                RpckTheme.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton grid matching the catalogue tile layout.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, required this.columns, this.tileCount = 12});

  final int columns;
  final int tileCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolved = constraints.maxWidth < 560
            ? 2
            : constraints.maxWidth < 900
                ? 3
                : constraints.maxWidth < 1300
                    ? 4
                    : 6;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: resolved,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            childAspectRatio: 0.72,
          ),
          itemCount: tileCount,
          itemBuilder: (context, _) => const _SkeletonTile(),
        );
      },
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RpckTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SkeletonBox(width: double.infinity, height: 0, radius: 12)),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: 120, height: 12),
        ],
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
      children: [
        const SkeletonBox(width: double.infinity, height: 180, radius: 16),
        const SizedBox(height: 24),
        SkeletonBox(width: double.infinity, height: 14, radius: 6),
        const SizedBox(height: 10),
        SkeletonBox(width: 260, height: 14, radius: 6),
        const SizedBox(height: 10),
        SkeletonBox(width: 180, height: 14, radius: 6),
        const SizedBox(height: 32),
        const SkeletonBox(width: 140, height: 18, radius: 6),
        const SizedBox(height: 14),
        for (var row = 0; row < 5; row++) ...[
          const SkeletonBox(width: double.infinity, height: 12, radius: 6),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 26),
        const SkeletonBox(width: 140, height: 18, radius: 6),
        const SizedBox(height: 14),
        for (var card = 0; card < 3; card++) ...[
          const SkeletonBox(width: double.infinity, height: 64, radius: 12),
          const SizedBox(height: 10),
        ],
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