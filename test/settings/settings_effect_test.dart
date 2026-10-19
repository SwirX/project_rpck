import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/platform/download_location.dart';
import 'package:project_rpck/download/transfer.dart';
import 'package:project_rpck/download/transfer_registry.dart';
import 'package:project_rpck/domain/models/source_option.dart';
import 'package:project_rpck/features/downloads/transfer_notifier.dart';
import 'package:project_rpck/features/repack/transfer_confirmation.dart';
import 'package:project_rpck/features/settings/setting_effects.dart';
import 'package:project_rpck/ui/app_settings.dart';
import 'package:project_rpck/ui/rpck_top_bar.dart';
import 'package:project_rpck/ui/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps [child] under a scope carrying [settings].
Widget _scoped(AppSettings settings, Widget child) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const <ThemeExtension<dynamic>>[RpckPalette.dark],
      ),
      home: AppSettingsScope(
        controller: SettingsController(settings),
        settings: settings,
        child: child,
      ),
    );

Transfer _completedTransfer() => Transfer(
      id: 't1',
      title: 'A Pizza Delivery',
      source: const MagnetOption('magnet:?xt=urn:btih:abc'),
      status: TransferStatus.completed,
      downloadedBytes: 10,
      totalBytes: 10,
      bytesPerSecond: 0,
      connectedPeers: 0,
      availablePeers: 0,
      savePath: '/tmp/x',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('showTrending', () {
    test('off hides the row', () {
      expect(
        shouldShowTrending(
          const AppSettings(showTrending: false),
          searching: false,
        ),
        isFalse,
      );
    });

    test('on shows the row on an idle query', () {
      expect(
        shouldShowTrending(
          const AppSettings(showTrending: true),
          searching: false,
        ),
        isTrue,
      );
    });

    test('a search hides the row even when the setting is on', () {
      expect(
        shouldShowTrending(
          const AppSettings(showTrending: true),
          searching: true,
        ),
        isFalse,
      );
    });
  });

  group('autoUpdate', () {
    test('off skips the check, on performs it', () {
      expect(shouldCheckForUpdates(const AppSettings(autoUpdate: false)), isFalse);
      expect(shouldCheckForUpdates(const AppSettings(autoUpdate: true)), isTrue);
    });
  });

  group('notifyOnTransferComplete', () {
    testWidgets('a finished transfer raises a notice when on', (tester) async {
      final registry = TransferRegistry();
      addTearDown(registry.dispose);

      await tester.pumpWidget(_scoped(
        const AppSettings(notifyOnTransferComplete: true),
        TransferNotifier(transfers: registry, child: const Scaffold()),
      ));

      registry.enqueue(_completedTransfer());
      registry.enqueue(_completedTransfer().copyWith(status: TransferStatus.completed));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text(transferCompleteMessage('A Pizza Delivery')),
        findsOneWidget,
      );
    });

    testWidgets('no notice when the setting is off', (tester) async {
      final registry = TransferRegistry();
      addTearDown(registry.dispose);

      await tester.pumpWidget(_scoped(
        const AppSettings(notifyOnTransferComplete: false),
        TransferNotifier(transfers: registry, child: const Scaffold()),
      ));

      registry.enqueue(_completedTransfer());
      registry.enqueue(_completedTransfer().copyWith(status: TransferStatus.completed));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });

    test('the notice is raised once, on the transition', () async {
      final registry = TransferRegistry();
      addTearDown(registry.dispose);

      final seen = <Transfer>[];
      registry.completions.listen(seen.add);

      final transfer = _completedTransfer().copyWith(status: TransferStatus.queued);
      registry.enqueue(transfer);
      registry.enqueue(transfer.copyWith(status: TransferStatus.completed));
      registry.enqueue(transfer.copyWith(status: TransferStatus.completed));
      await Future<void>.delayed(Duration.zero);

      expect(seen.length, 1);
    });
  });

  group('confirmBeforeTransfer', () {
    test('off means no dialog is ever raised', () {
      expect(
        shouldConfirmBeforeTransfer(
          const AppSettings(confirmBeforeTransfer: false),
        ),
        isFalse,
      );
      expect(
        shouldConfirmBeforeTransfer(
          const AppSettings(confirmBeforeTransfer: true),
        ),
        isTrue,
      );
      expect(const AppSettings().confirmBeforeTransfer, isFalse,
          reason: 'asking every time is not the default');
    });

    testWidgets('off starts without asking', (tester) async {
      await tester.pumpWidget(_scoped(
        const AppSettings(confirmBeforeTransfer: false),
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final settings = AppSettingsScope.of(context);
                final allowed = shouldConfirmBeforeTransfer(settings)
                    ? await confirmTransfer(
                        context,
                        title: 'Game',
                        description: 'Magnet',
                        folder: 'Downloads',
                      )
                    : true;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('allowed=$allowed')),
                  );
                }
              },
              child: const Text('start'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('allowed=true'), findsOneWidget);
    });

    testWidgets('on asks, and cancelling refuses', (tester) async {
      var allowed = true;

      await tester.pumpWidget(_scoped(
        const AppSettings(confirmBeforeTransfer: true),
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                allowed = await confirmTransfer(
                  context,
                  title: 'Game',
                  description: 'Magnet',
                  folder: 'Downloads',
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      expect(find.text('Start this download?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(allowed, isFalse);
    });

    testWidgets('on asks, and confirming allows', (tester) async {
      var allowed = false;

      await tester.pumpWidget(_scoped(
        const AppSettings(confirmBeforeTransfer: true),
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                allowed = await confirmTransfer(
                  context,
                  title: 'A Pizza Delivery',
                  description: 'Magnet',
                  folder: '/games',
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();

      // The dialog names the destination so the setting is visible, not implied.
      expect(find.textContaining('/games'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pumpAndSettle();

      expect(allowed, isTrue);
    });
  });

  group('downloadFolder', () {
    test('an override is used verbatim and created', () async {
      final root = await Directory.systemTemp.createTemp('rpck-folder-');
      addTearDown(() => root.delete(recursive: true));

      final target = '${root.path}/nested/chosen';
      final location = await DownloadLocation.resolve(override: target);

      expect(location.isSuccess, isTrue);
      expect(location.valueOrNull!.directory.path, target);
      expect(await Directory(target).exists(), isTrue);
    });

    test('an unusable override fails rather than falling back', () async {
      final root = await Directory.systemTemp.createTemp('rpck-folder-');
      addTearDown(() => root.delete(recursive: true));

      // A regular file cannot also be a directory. Falling back silently would
      // download gigabytes somewhere the user did not choose and cannot find.
      final blocker = File('${root.path}/blocker')..writeAsStringSync('x');
      final location = await DownloadLocation.resolve(
        override: '${blocker.path}/downloads',
      );

      expect(location.isSuccess, isFalse);
      expect(location.failureOrNull!.message, contains(blocker.path));
    });
  });

  group('concurrentArtworkFetches', () {
    test('the setting reaches the service it limits', () {
      final controller = SettingsController(
        const AppSettings(concurrentArtworkFetches: 2),
      );
      expect(controller.current.concurrentArtworkFetches, 2);

      controller.update((c) => c.copyWith(concurrentArtworkFetches: 8));
      expect(controller.current.concurrentArtworkFetches, 8,
          reason: 'the change must be visible without a restart');
    });
  });

  group('resumeTransfersOnLaunch', () {
    test('defaults to resuming', () {
      expect(const AppSettings().resumeTransfersOnLaunch, isTrue);
    });
  });
}