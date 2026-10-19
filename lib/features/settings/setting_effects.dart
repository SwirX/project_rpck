import 'package:project_rpck/ui/app_settings.dart';

/// Whether the discovery row belongs on the catalogue home.
///
/// Split out because the only thing that made this setting real is the
/// condition itself, and a condition in the middle of a sliver builder cannot
/// be tested without standing up the whole library page and its environment.
bool shouldShowTrending(AppSettings settings, {required bool searching}) =>
    settings.showTrending && !searching;

/// Whether the app should look for a new release on launch.
///
/// Turning this off has to stop the request, not merely hide the result, so the
/// caller skips the fetch entirely rather than checking afterwards.
bool shouldCheckForUpdates(AppSettings settings) => settings.autoUpdate;

/// Whether starting a download should ask first.
///
/// Off by default: a confirmation on every single download is friction most
/// people do not want, and it is the kind of thing that gets switched off and
/// then never switched back on.
bool shouldConfirmBeforeTransfer(AppSettings settings) =>
    settings.confirmBeforeTransfer;

/// Whether a finished transfer should raise a notice.
///
/// Read at the moment the transfer completes, so switching it off takes effect
/// for the next one without a restart.
bool shouldAnnounceCompletion(AppSettings settings) =>
    settings.notifyOnTransferComplete;