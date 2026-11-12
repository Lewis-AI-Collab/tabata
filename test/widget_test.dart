import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabata/app.dart';
import 'package:tabata/data/store.dart';
import 'package:tabata/engine/clock.dart';
import 'package:tabata/models/preset.dart';
import 'package:tabata/models/session_log.dart';
import 'package:tabata/screens/editor_screen.dart';
import 'package:tabata/screens/log_screen.dart';
import 'package:tabata/screens/run_screen.dart';
import 'package:tabata/services/cues.dart';
import 'package:tabata/services/wake.dart';

void main() {
  Future<TabataStore> seeded() async {
    final store = TabataStore(MemoryBox());
    await store.ensureSeed();
    return store;
  }

  Widget app(TabataStore store, {Widget? home, CueSink? cues, WakeLock? wake}) {
    return TabataApp(
      store: store,
      cues: cues ?? SilentCues(),
      wake: wake ?? NoWake(),
      home: home,
    );
  }

  testWidgets('home lists the seeded preset', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();
    expect(find.text('Tabata'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('20/10 × 8'), findsOneWidget);
  });

  testWidgets('work stepper and ruler update the number', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(
      app(store, home: EditorScreen(preset: Preset.classic)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Classic'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('work-value'))).data,
      '20',
    );

    await tester.tap(find.byKey(const ValueKey('work-more')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('work-value'))).data,
      '25',
    );

    await tester.tap(find.byKey(const ValueKey('work-value')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ruler')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('ruler-value'))).data,
      '25',
    );

    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ruler')), findsNothing);
  });

  testWidgets('run screen holds a frozen stopwatch and stop logs the session', (
    tester,
  ) async {
    final store = await seeded();
    final cues = SilentCues();
    final wake = NoWake();
    await tester.pumpWidget(
      app(
        store,
        cues: cues,
        wake: wake,
        home: RunScreen(preset: Preset.classic, time: ManualTime()),
      ),
    );
    await tester.pump();

    expect(find.text('PREP'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('run-seconds'))).data,
      '10',
    );
    expect(find.text('00:00.0'), findsOneWidget);
    expect(wake.enabled, isTrue);
    expect(cues.bed, isTrue);
    expect(cues.spoken, isEmpty);
    expect(cues.ticks, 1);
    expect(cues.beeps, 0);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.byTooltip('Resume'), findsOneWidget);
    expect(wake.enabled, isFalse);
    expect(cues.bed, isFalse);

    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(wake.enabled, isTrue);
    expect(cues.ticks, 1);
    expect(cues.played, ['tick']);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Stopped early'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Grok'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(store.sessions(), hasLength(1));
    expect(store.sessions().single.completed, isFalse);
    expect(store.sessions().single.presetName, 'Classic');
    expect(wake.enabled, isFalse);

    await tester.tap(find.byTooltip('Scope'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week').last);
    await tester.pumpAndSettle();
    expect(find.text('WEEK'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a frozen stopwatch catches up 60s on the tick', (tester) async {
    final store = await seeded();
    final time = ManualTime();
    var now = DateTime(2026, 10, 22, 8);
    await tester.pumpWidget(
      app(
        store,
        home: RunScreen(preset: Preset.classic, time: time, now: () => now),
      ),
    );
    await tester.pump();
    expect(find.text('PREP'), findsOneWidget);
    expect(find.text('00:00.0'), findsOneWidget);

    now = now.add(const Duration(seconds: 60));
    await tester.pump();
    expect(time.elapsed, Duration.zero);
    expect(find.text('00:00.0'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(time.elapsed, Duration.zero);
    expect(find.text('01:00.0'), findsOneWidget);
    expect(find.text('ROUND 2/8 · REST'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('run-seconds'))).data,
      '10',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an ended interruption runs the tick hook', (tester) async {
    final store = await seeded();
    final cues = SilentCues();
    final time = ManualTime();
    var now = DateTime(2026, 10, 22, 8);
    await tester.pumpWidget(
      app(
        store,
        cues: cues,
        home: RunScreen(preset: Preset.classic, time: time, now: () => now),
      ),
    );
    await tester.pump();
    expect(cues.onInterruptionEnd, isNotNull);
    expect(find.text('00:00.0'), findsOneWidget);

    now = now.add(const Duration(seconds: 60));
    await tester.pump();
    expect(time.elapsed, Duration.zero);
    expect(find.text('00:00.0'), findsOneWidget);

    cues.onInterruptionEnd!.call();
    await tester.pump();
    expect(time.elapsed, Duration.zero);
    expect(find.text('01:00.0'), findsOneWidget);
    expect(find.text('ROUND 2/8 · REST'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a clock jump past the time left is logged interrupted', (
    tester,
  ) async {
    final store = await seeded();
    final time = ManualTime();
    var now = DateTime(2026, 10, 22, 8);
    const preset = Preset(
      id: 'short',
      name: 'Short',
      prep: 0,
      work: 20,
      rest: 10,
      rounds: 2,
      sets: 1,
      setRest: 0,
      cooldown: 0,
    );
    await tester.pumpWidget(
      app(
        store,
        home: RunScreen(preset: preset, time: time, now: () => now),
      ),
    );
    await tester.pump();

    time.advance(const Duration(seconds: 40));
    now = now.add(const Duration(seconds: 40));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('00:40.0'), findsOneWidget);

    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Interrupted'), findsOneWidget);
    expect(find.text('Stopped early'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    expect(store.sessions(), hasLength(1));
    final saved = store.sessions().single;
    expect(saved.interrupted, isTrue);
    expect(saved.completed, isFalse);
    expect(saved.statusLabel, 'Interrupted');
    expect(saved.totalSeconds, 40);
    expect(saved.presetName, 'Short');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the log shows interrupted apart from a manual stop', (
    tester,
  ) async {
    final store = TabataStore(MemoryBox());
    final started = DateTime(2026, 10, 22, 8, 15);
    await store.addSession(
      SessionLog.capture(
        preset: Preset.classic.copyWith(name: 'Nap'),
        startedAt: started,
        endedAt: started.add(const Duration(minutes: 3)),
        elapsed: const Duration(seconds: 200),
        completed: false,
        interrupted: true,
      ),
    );
    await tester.pumpWidget(app(store, home: const LogScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Nap'), findsOneWidget);
    expect(find.text('Interrupted'), findsOneWidget);
    expect(find.text('Stopped early'), findsNothing);
    expect(find.text('Completed'), findsNothing);

    await tester.tap(find.text('Nap'));
    await tester.pumpAndSettle();
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Interrupted'), findsNWidgets(2));
    expect(find.text('Stopped early'), findsNothing);
    expect(find.text('Completed'), findsNothing);
  });

  testWidgets('sound and voice icons are remembered', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();
    expect(_icon(tester, 'sound-toggle').icon, Icons.volume_up);
    expect(_icon(tester, 'voice-toggle').icon, Icons.record_voice_over);

    await tester.tap(find.byKey(const ValueKey('sound-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-toggle')));
    await tester.pumpAndSettle();
    expect(_icon(tester, 'sound-toggle').icon, Icons.volume_off);
    expect(_icon(tester, 'voice-toggle').icon, Icons.voice_over_off);
    expect(store.soundOn, isFalse);
    expect(store.voiceOn, isFalse);

    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();
    expect(_icon(tester, 'sound-toggle').icon, Icons.volume_off);
    expect(_icon(tester, 'voice-toggle').icon, Icons.voice_over_off);
  });

  testWidgets('a muted run stays quiet and does not tick again', (
    tester,
  ) async {
    final store = await seeded();
    final cues = SilentCues();
    final time = ManualTime();
    await tester.pumpWidget(
      app(
        store,
        cues: cues,
        home: RunScreen(preset: Preset.classic, time: time),
      ),
    );
    await tester.pump();
    expect(cues.played, ['tick']);

    await tester.tap(find.byKey(const ValueKey('sound-toggle')));
    await tester.pump();
    expect(_icon(tester, 'sound-toggle').icon, Icons.volume_off);
    time.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(cues.played, ['tick']);
    expect(cues.ticks, 1);
    expect(store.soundOn, isFalse);

    final again = SilentCues();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      app(
        store,
        cues: again,
        home: RunScreen(preset: Preset.classic, time: ManualTime()),
      ),
    );
    await tester.pump();
    expect(again.played, isEmpty);
    expect(_icon(tester, 'sound-toggle').icon, Icons.volume_off);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Icon _icon(WidgetTester tester, String key) {
  return tester.widget<Icon>(
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Icon)),
  );
}
