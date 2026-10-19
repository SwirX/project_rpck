import 'package:flutter/material.dart';

/// Layout metrics shared by every catalogue surface.
///
/// Declared in one place so a tile, its skeleton and any future list view
/// cannot drift apart. A tile that is a different size from the placeholder
/// that preceded it makes the grid visibly jump when content lands.

/// Aspect ratio of a catalogue tile, height over width.
const double tileAspectRatio = 0.66;

/// Widest a tile may become before another is placed beside it.
const double tileMaxCrossExtent = 220;

/// Gap between tiles on both axes.
const double tileSpacing = 18;

/// Padding around the grid.
const EdgeInsets tileGridPadding =
    EdgeInsets.fromLTRB(20, 20, 20, 32);

/// Delegate for the catalogue grid, used by both the real grid and the
/// skeleton so the two are laid out identically.
const SliverGridDelegateWithMaxCrossAxisExtent tileGridDelegate =
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: tileMaxCrossExtent,
      mainAxisSpacing: tileSpacing,
      crossAxisSpacing: tileSpacing,
      childAspectRatio: tileAspectRatio,
    );
