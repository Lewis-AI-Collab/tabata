import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabata/data/store.dart';
import 'package:tabata/models/preset.dart';
import 'package:tabata/models/session_log.dart';

void main() {
  test('sound and voice default on and survive a new store', () async {
    final box = MemoryBox();
    final store = TabataStore(box);
    expect(store.soundOn, isTrue);
    expect(store.voiceOn, isTrue);

    await store.setSoundOn(false);
    await store.setVoiceOn(false);
    final again = TabataStore(box);
    expect(again.soundOn, isFalse);
    expect(again.voiceOn, isFalse);

    await again.setSoundOn(true);
    expect(TabataStore(box).soundOn, isTrue);
    expect(TabataStore(box).voiceOn, isFalse);
  });

  test('preset crud survives a new store on the same box', () async {
    final box = MemoryBox();
    final store = TabataStore(box);
    await store.ensureSeed();
    expect(store.presets().map((preset) => preset.name), ['Classic']);

    await store.ensureSeed();
    expect(store.presets(), hasLength(1));

    final extra = Preset.draft().copyWith(
      name: '  Short  ',
      work: 10,
      rest: 5,
      rounds: 4,
    );
    await store.savePreset(extra);
    expect(store.presets().map((preset) => preset.name), ['Classic', 'Short']);

    await store.savePreset(extra.copyWith(name: 'Tiny', rest: 0));
    final updated = store.presets()[1];
    expect(updated.name, 'Tiny');
    expect(updated.work, 10);
    expect(updated.rest, 0);
    expect(updated.id, extra.id);

    await store.deletePreset('classic');
    expect(store.presets().map((preset) => preset.id), [extra.id]);

    final reloaded = TabataStore(box);
    expect(reloaded.presets().single.name, 'Tiny');
    expect(reloaded.presets().single.cardLine, '10/0 × 4');
  });

  test('presets are not capped', () async {
    final store = TabataStore(MemoryBox());
    for (var i = 0; i < 40; i++) {
      await store.savePreset(
        Preset(
          id: 'p$i',
          name: 'P$i',
          prep: 0,
          work: 20,
          rest: 10,
          rounds: 8,
          sets: 1,
          setRest: 0,
          cooldown: 0,
        ),
      );
    }
    expect(store.presets(), hasLength(40));
    expect(store.presets().last.name, 'P39');
  });

  test('session log appends and reloads', () async {
    final box = MemoryBox();
    final store = TabataStore(box);
    final started = DateTime(2026, 10, 16, 8, 41);
    await store.addSession(
      SessionLog.capture(
        preset: Preset.classic,
        startedAt: started,
        endedAt: started.add(const Duration(minutes: 4)),
        elapsed: const Duration(minutes: 4),
        completed: true,
      ),
    );
    await store.addSession(
      SessionLog.capture(
        preset: Preset.classic.copyWith(name: 'Short'),
        startedAt: started.add(const Duration(hours: 2)),
        endedAt: started.add(const Duration(hours: 2, seconds: 65)),
        elapsed: const Duration(seconds: 65),
        completed: false,
      ),
    );
    final again = TabataStore(box).sessions();
    expect(again, hasLength(2));
    expect(again.first.completed, isTrue);
    expect(again.first.totalSeconds, 240);
    expect(again.last.statusLabel, 'Stopped early');
    expect(again.last.presetName, 'Short');
  });

  test('an interrupted session reloads as interrupted', () async {
    final box = MemoryBox();
    final store = TabataStore(box);
    final started = DateTime(2026, 10, 22, 8, 15);
    await store.addSession(
      SessionLog.capture(
        preset: Preset.classic,
        startedAt: started,
        endedAt: started.add(const Duration(minutes: 3)),
        elapsed: const Duration(seconds: 200),
        completed: false,
        interrupted: true,
      ),
    );
    final again = TabataStore(box).sessions().single;
    expect(again.interrupted, isTrue);
    expect(again.completed, isFalse);
    expect(again.totalSeconds, 200);
    expect(again.statusLabel, 'Interrupted');
    expect(again.statusLabel, isNot('Stopped early'));
    expect(again.statusLabel, isNot('Completed'));

    final legacy = Map<String, dynamic>.from(again.toJson())
      ..remove('interrupted');
    expect(SessionLog.fromJson(legacy).statusLabel, 'Stopped early');
    expect(
      SessionLog.fromJson({
        ...again.toJson(),
        'interrupted': false,
        'completed': true,
      }).statusLabel,
      'Completed',
    );
  });

  test('an old saved session without the interrupted key loads correctly', () {
    final started = DateTime(2026, 10, 16, 8, 41);
    final ended = started.add(const Duration(minutes: 4));
    final box = MemoryBox()
      ..data[TabataStore.sessionsKey] = jsonEncode([
        {
          'id': '${started.microsecondsSinceEpoch}',
          'presetId': 'classic',
          'presetName': 'Classic',
          'prep': 10,
          'work': 20,
          'rest': 10,
          'rounds': 8,
          'sets': 1,
          'setRest': 0,
          'cooldown': 0,
          'startedAt': started.toIso8601String(),
          'endedAt': ended.toIso8601String(),
          'totalSeconds': 240,
          'completed': true,
        },
      ]);
    final session = TabataStore(box).sessions().single;
    expect(session.id, '${started.microsecondsSinceEpoch}');
    expect(session.presetId, 'classic');
    expect(session.presetName, 'Classic');
    expect(session.prep, 10);
    expect(session.work, 20);
    expect(session.rest, 10);
    expect(session.rounds, 8);
    expect(session.sets, 1);
    expect(session.setRest, 0);
    expect(session.cooldown, 0);
    expect(session.startedAt, started);
    expect(session.endedAt, ended);
    expect(session.totalSeconds, 240);
    expect(session.completed, isTrue);
    expect(session.interrupted, isFalse);
    expect(session.statusLabel, 'Completed');
  });

  test('json marked interrupted and completed loads as not completed', () {
    final started = DateTime(2026, 10, 22, 8, 15);
    final captured = SessionLog.capture(
      preset: Preset.classic,
      startedAt: started,
      endedAt: started.add(const Duration(minutes: 3)),
      elapsed: const Duration(seconds: 200),
      completed: true,
      interrupted: true,
    );
    expect(captured.completed, isFalse);
    expect(captured.interrupted, isTrue);

    final saved = captured.toJson();
    saved['completed'] = true;
    saved['interrupted'] = true;
    final loaded = TabataStore(
      MemoryBox()..data[TabataStore.sessionsKey] = jsonEncode([saved]),
    ).sessions().single;
    expect(loaded.completed, isFalse);
    expect(loaded.interrupted, isTrue);
    expect(loaded.statusLabel, 'Interrupted');
    expect(loaded.statusLabel, isNot('Completed'));
    expect(loaded.statusLabel, isNot('Stopped early'));
    expect(loaded.totalSeconds, 200);
  });

  test('broken json reads as an empty list', () {
    final box = MemoryBox()..data[TabataStore.presetsKey] = '{';
    expect(TabataStore(box).presets(), isEmpty);
  });

  test('bad preset and session entries are skipped', () {
    final started = DateTime(2026, 10, 16, 8, 41);
    final session = SessionLog.capture(
      preset: Preset.classic,
      startedAt: started,
      endedAt: started.add(const Duration(minutes: 4)),
      elapsed: const Duration(minutes: 4),
      completed: true,
    );
    final box = MemoryBox()
      ..data[TabataStore.presetsKey] = jsonEncode([
        {'id': 7, 'name': 'Broken'},
        Preset.classic.toJson(),
        {'id': 'x', 'name': 3},
        'nope',
      ])
      ..data[TabataStore.sessionsKey] = jsonEncode([
        {...session.toJson(), 'startedAt': 12},
        session.toJson(),
        {
          'id': 'bad',
          'presetId': 'p',
          'presetName': 'P',
          'startedAt': 'nope',
          'endedAt': 'also-nope',
        },
        {'id': 1, 'startedAt': started.toIso8601String()},
      ]);
    final store = TabataStore(box);
    expect(store.presets().map((preset) => preset.name), ['Classic']);
    expect(store.sessions(), hasLength(1));
    expect(store.sessions().single.presetName, 'Classic');
    expect(store.sessions().single.totalSeconds, 240);
  });
}
