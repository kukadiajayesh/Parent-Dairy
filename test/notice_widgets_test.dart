import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/app/routes.dart';
import 'package:parent_academic_diary/core/theme/app_theme.dart';
import 'package:parent_academic_diary/data/app_state.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/features/notices/notice_detail_page.dart';
import 'package:parent_academic_diary/features/notices/notice_settings_page.dart';
import 'package:parent_academic_diary/features/notices/notices_page.dart';
import 'package:parent_academic_diary/features/settings/more_page.dart';

import 'notice_test_support.dart';

/// The notice screens over a fake Firestore (prompt 03 §G, widget tests).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoticeHarness h;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    h.dispose();
  });

  Future<void> pump(WidgetTester tester, AppState state, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            onGenerateRoute: Routes.onGenerateRoute,
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the inbox empty state names the rule, in both themes', (tester) async {
    h = NoticeHarness();
    final state = await tester.runAsync(() => h.start());
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pump(tester, state!, const NoticesPage());
      expect(find.text('No notices yet'), findsOneWidget, reason: '$brightness');
      expect(find.textContaining('only reads notifications from the apps you pick'), findsOneWidget);
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
    }
  });

  testWidgets('with capture off the list offers to turn it on', (tester) async {
    h = NoticeHarness(enabled: false);
    final state = await tester.runAsync(() => h.start());
    await pump(tester, state!, const NoticesPage());
    expect(find.text('Notification capture is off'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
  });

  testWidgets('a low-confidence notice sits in the inbox unarmed until Confirm is tapped', (tester) async {
    h = NoticeHarness();
    final state = await tester.runAsync(() async {
      final s = await h.start();
      h.platform.post(raw('Homework', 'Complete Maths worksheet 4 and submit by Friday.'));
      await s.drainNotices();
      await settle(12);
      return s;
    });
    final notice = state!.notices.single;
    expect(notice.confidence, 0.7);
    expect(notice.status, NoticeStatus.needsReview);
    expect(notice.reminderIds, isEmpty);
    expect(h.scheduler.scheduled, isEmpty);

    await pump(tester, state, const NoticesPage());
    expect(find.text('Inbox · 1'), findsOneWidget);
    expect(find.text('Assignment'), findsOneWidget);
    expect(find.text('Maths worksheet 4 and submit by'), findsNothing);

    await pump(tester, state, NoticeDetailPage(noticeId: notice.id));
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Convert to worksheet'), findsOneWidget);
    expect(find.textContaining('Will be set on confirm'), findsNWidgets(2));
    // Merely opening the screen armed nothing.
    expect(h.scheduler.scheduled, isEmpty);

    await tester.runAsync(() async {
      await tester.tap(find.text('Confirm'));
      await settle(12);
    });
    await tester.pumpAndSettle();
    expect(h.scheduler.scheduled.length, 2);
    expect(state.noticeById(notice.id)!.status, NoticeStatus.confirmed);
    expect(find.text('Confirmed'), findsWidgets);
  });

  testWidgets('the settings screen hides itself entirely on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    h = NoticeHarness(supported: false);
    final state = await tester.runAsync(() => h.start());
    expect(state!.noticeCaptureSupported, isFalse);

    await pump(tester, state, const NoticeSettingsPage());
    expect(find.text('Android only'), findsOneWidget);
    expect(find.text('Read school-app notifications'), findsNothing);
    expect(find.text('Choose apps'), findsNothing);

    await pump(tester, state, const MorePage());
    expect(find.text('SCHOOL NOTICES'), findsNothing);
    expect(find.text('Notification capture'), findsNothing);
    // The binding checks this before tearDown runs.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Android the settings screen shows the switch, permission and apps', (tester) async {
    h = NoticeHarness(granted: false);
    final state = await tester.runAsync(() => h.start());
    await pump(tester, state!, const NoticeSettingsPage());
    expect(find.text('Read school-app notifications'), findsOneWidget);
    expect(find.text('Grant access'), findsOneWidget);
    expect(find.text('Choose apps'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Delete all captured notices'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete all captured notices'), findsOneWidget);

    await pump(tester, state, const MorePage());
    expect(find.text('SCHOOL NOTICES'), findsOneWidget);
    expect(find.text('Notices'), findsOneWidget);
    expect(find.text('Notification capture'), findsOneWidget);
  });
}
