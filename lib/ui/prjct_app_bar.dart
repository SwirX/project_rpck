import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The application's top bar.
///
/// Deliberately not `Scaffold.appBar`: the prototype used the Material AppBar
/// on some pages and a hand-rolled `Positioned` back button on others, so the
/// two did not agree on height, spacing or typography. This widget is the only
/// place that decides what the top of the screen looks like.
class PrjctAppBar extends StatelessWidget {
  const PrjctAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.searchField,
    this.actions = const [],
    this.height = 132,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Optional inline search, rendered under the title row.
  final Widget? searchField;

  final List<Widget> actions;

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.bebasNeue(
                        fontSize: 34,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          letterSpacing: .4,
                        ),
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          if (searchField != null) ...[
            const SizedBox(height: 14),
            SizedBox(height: 44, child: searchField),
          ],
        ],
      ),
    );
  }
}

/// Circular action button used in [PrjctAppBar.actions].
class PrjctAppBarAction extends StatelessWidget {
  const PrjctAppBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white),
    );

    if (badge <= 0) return button;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge > 9 ? '9+' : '$badge',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}