import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../storefront/storefront_game.dart';
import '../../ui/rpck_top_bar.dart';

/// Screenshots the storefront publishes, as a strip that opens full size.
///
/// Thumbnails in the strip rather than the full captures: twelve 1920x1080
/// images on one page is several megabytes of decoding for pictures the user may
/// never open.
class ScreenshotGallery extends StatelessWidget {
  final List<StorefrontShot> shots;

  const ScreenshotGallery({super.key, required this.shots});

  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('Screenshots (${shots.length})'),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: shots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _Thumbnail(
              shot: shots[index],
              onTap: () => _open(context, index),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap to enlarge',
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );
  }

  void _open(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: shots[index].full,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.white54,
                    size: 40,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final StorefrontShot shot;
  final VoidCallback onTap;

  const _Thumbnail({required this.shot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 160,
          child: CachedNetworkImage(
            imageUrl: shot.thumbnail,
            fit: BoxFit.cover,
            placeholder: (_, __) => ColoredBox(color: palette.surfaceHigh),
            errorWidget: (_, __, ___) => ColoredBox(
              color: palette.surfaceHigh,
              child: Icon(Icons.broken_image_outlined, color: palette.muted),
            ),
          ),
        ),
      ),
    );
  }
}
