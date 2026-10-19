import 'package:flutter/foundation.dart';

import 'app_settings.dart';

/// The live settings, owned by the app environment.
///
/// The services that honour a setting are built before any widget exists, so
/// they cannot reach an `InheritedWidget`. They read [current] at the moment
/// they need a value instead of capturing one at construction. That is what let
/// seven settings sit in the preferences store controlling nothing: only
/// `themeMode` was ever read back out, and only by the widget tree.
class SettingsController extends ChangeNotifier {
  AppSettings _current;

  SettingsController([AppSettings initial = const AppSettings()])
      : _current = initial;

  AppSettings get current => _current;

  /// Applies [mutate], tells dependents, then persists.
  ///
  /// Notification comes first so the UI reflects the choice on this frame
  /// rather than after a disk write. A failed write is reported but does not
  /// undo the change, because the alternative is a control that appears not to
  /// work at all.
  Future<void> update(AppSettings Function(AppSettings current) mutate) async {
    final next = mutate(_current);
    if (identical(next, _current)) return;
    _current = next;
    notifyListeners();
    try {
      await next.persist();
    } catch (error) {
      debugPrint('settings could not be persisted: $error');
    }
  }
}