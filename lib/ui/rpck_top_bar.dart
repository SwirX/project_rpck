import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme constants shared by the top bar and the pages that sit under it.
abstract final class RpckTheme {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF141414);
  static const surfaceHigh = Color(0xFF1E1E1E);
  static const primary = Color(0xFF3D8BFF);
  static const secondary = Color(0xFFB14DFF);
  static const muted = Color(0xFF8A8A8A);
  static const hairline = Color(0x1AFFFFFF);

  static LinearGradient get accent => const LinearGradient(
        colors: [primary, secondary],
      );
}

/// The application's top bar.
///
/// Self-sizing on purpose. The previous version pinned a fixed height and
/// placed the search field inside it, so any title that wrapped, or the 48px
/// title stack plus the 44px field, pushed past the box and Flutter reported a
/// bottom overflow of 27px. Nothing here is given a fixed height: the bar
/// measures its children and the page scrolls under it.
class RpckTopBar extends StatelessWidget {
  const RpckTopBar({
    super.key,
    required this.leading,
    this.search,
    this.trailing = const [],
  });

  /// Back button or equivalent, rendered at the left edge.
  final Widget leading;

  /// Optional search field, rendered as a full width row beneath the title.
  final Widget? search;

  /// Actions rendered at the right edge, in order.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      decoration: const BoxDecoration(
        color: RpckTheme.background,
        border: Border(bottom: BorderSide(color: RpckTheme.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 6),
              const Expanded(child: RpckWordmark()),
              ...trailing,
            ],
          ),
          if (search != null) ...[
            const SizedBox(height: 12),
            search!,
          ],
        ],
      ),
    );
  }
}

/// The PRJCT RPCK wordmark.
class RpckWordmark extends StatelessWidget {
  const RpckWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => RpckTheme.accent.createShader(bounds),
      child: const Text(
        'PRJCT RPCK',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.6,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Circular action button for the top bar.
class TopBarAction extends StatelessWidget {
  const TopBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = 0,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Non-zero renders a count pill, used for active transfers.
  final int badge;

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: onPressed,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            icon: Icon(icon, color: active ? RpckTheme.primary : Colors.white),
          ),
          if (badge > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 17),
                decoration: BoxDecoration(
                  color: RpckTheme.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A section label that matches the wordmark's typographic voice.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.bebasNeue(
          fontSize: 18,
          color: RpckTheme.muted,
          letterSpacing: 2,
        ),
      ),
    );
  }
}