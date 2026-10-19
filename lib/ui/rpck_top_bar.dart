import 'package:flutter/material.dart';

/// Theme constants shared by the top bar and the pages that sit under it.
abstract final class RpckTheme {
  static const primary = Color(0xFF3D8BFF);
  static const secondary = Color(0xFFB14DFF);

  static const darkBackground = Color(0xFF000000);
  static const darkSurface = Color(0xFF141414);
  static const darkSurfaceHigh = Color(0xFF1E1E1E);

  static const lightBackground = Color(0xFFF4F5F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFFFFFFF);

  static LinearGradient get accent => const LinearGradient(
        colors: [primary, secondary],
      );
}

/// Colours for the active brightness.
///
/// Every surface resolves through here so a theme switch cannot leave a
/// hard-coded dark widget behind on a light background.
class RpckPalette extends ThemeExtension<RpckPalette> {
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color onSurface;
  final Color muted;
  final Color hairline;

  const RpckPalette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.onSurface,
    required this.muted,
    required this.hairline,
  });

  static const dark = RpckPalette(
    background: RpckTheme.darkBackground,
    surface: RpckTheme.darkSurface,
    surfaceHigh: RpckTheme.darkSurfaceHigh,
    onSurface: Colors.white,
    muted: Color(0xFF8A8A8A),
    hairline: Color(0x1AFFFFFF),
  );

  static const light = RpckPalette(
    background: RpckTheme.lightBackground,
    surface: RpckTheme.lightSurface,
    surfaceHigh: RpckTheme.lightSurfaceHigh,
    onSurface: Color(0xFF14161A),
    muted: Color(0xFF61656C),
    hairline: Color(0x14000000),
  );

  @override
  RpckPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? onSurface,
    Color? muted,
    Color? hairline,
  }) =>
      RpckPalette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        onSurface: onSurface ?? this.onSurface,
        muted: muted ?? this.muted,
        hairline: hairline ?? this.hairline,
      );

  @override
  RpckPalette lerp(RpckPalette? other, double t) {
    if (other == null) return this;
    return RpckPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
    );
  }
}

/// Reads the palette for the active brightness.
extension RpckPaletteAccess on BuildContext {
  RpckPalette get palette => Theme.of(this).extension<RpckPalette>() ?? RpckPalette.dark;
}

/// The application's top bar.
///
/// Self-sizing on purpose. A previous version pinned a fixed height and placed
/// the search field inside it, so any wrapped title pushed past the box and
/// Flutter reported a bottom overflow.
class RpckTopBar extends StatelessWidget {
  const RpckTopBar({
    super.key,
    required this.leading,
    this.search,
    this.trailing = const [],
  });

  /// Slot at the left edge. Hosts either a back button or the wordmark.
  ///
  /// Deliberately not also rendered here: an earlier version drew a wordmark of
  /// its own *and* accepted this slot, so the library passed one in and the word
  /// mark appeared twice.
  final Widget leading;

  /// Optional search field, rendered as a full width row beneath the title.
  final Widget? search;

  /// Actions rendered at the right edge, in order.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Flexible but loose, so the slot keeps its natural width and is
              // only squeezed when the actions leave it no room. Expanding it
              // outright made IconButton centre its glyph, which put a back
              // arrow in the middle of the bar on any screen with no trailing
              // actions.
              Flexible(child: leading),
              const Expanded(child: SizedBox.shrink()),
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
  const RpckWordmark({super.key, this.fontSize = 24});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => RpckTheme.accent.createShader(bounds),
      child: Text(
        'PRJCT RPCK',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
          color: context.palette.onSurface,
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
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: onPressed,
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            icon: Icon(icon, color: active ? RpckTheme.primary : palette.onSurface),
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
        style: TextStyle(
          fontSize: 17,
          color: context.palette.muted,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}