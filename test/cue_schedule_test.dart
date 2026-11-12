import 'package:flutter_test/flutter_test.dart';
import 'package:tabata/engine/clock.dart';
import 'package:tabata/engine/plan.dart';
import 'package:tabata/models/preset.dart';
import 'package:tabata/services/cues.dart';

/// Walks a plan against [SilentCues], the stand-in for the device player.
class _Run {
  _Run(Preset preset, {this.sound = true, this.voice = true})
    : time = ManualTime(),
      sink = SilentCues() {
    clock = IntervalClock(IntervalPlan.fromPreset(preset), time: time)..start();
  }

  final bool sound;
  final bool voice;
  final ManualTime time;
  final SilentCues sink;
  late final IntervalClock clock;

  Future<void> take() {
    return playCues(sink, clock.sample(sound: sound, voice: voice).cues);
  }

  Future<void> seconds(int count) async {
    for (var i = 0; i < count; i++) {
      time.advance(const Duration(seconds: 1));
      await take();
    }
  }
}

Preset _lane({
  int prep = 0,
  int work = 20,
  int rest = 10,
  int rounds = 1,
  int sets = 1,
  int setRest = 0,
  int cooldown = 0,
}) {
  return Preset(
    id: 'lane',
    name: 'Lane',
    prep: prep,
    work: work,
    rest: rest,
    rounds: rounds,
    sets: sets,
    setRest: setRest,
    cooldown: cooldown,
  );
}

void main() {
  test('the final beep window is the single constant 5', () {
    expect(finalBeepSeconds, 5);
  });

  test('work and rest say the word, then tick, then beep', () async {
    final run = _Run(_lane(work: 8, rest: 6, rounds: 2));
    await run.take();
    await run.seconds(8 + 6 - 1);
    expect(run.sink.played, [
      'workout',
      'tick',
      'tick',
      'beep',
      'beep',
      'beep',
      'beep',
      'beep',
      'rest',
      'beep',
      'beep',
      'beep',
      'beep',
      'beep',
    ]);
    expect(run.clock.status, RunStatus.running);
    final held = run.clock.sample();
    expect(held.phase!.kind, PhaseKind.rest);
    expect(held.displaySeconds, 1);
    expect(held.cues, isEmpty);
  });

  test('second 6 is still a tick and second 5 is the first beep', () async {
    final run = _Run(_lane(work: 7, rest: 0));
    await run.take();
    await run.seconds(6);
    expect(run.clock.status, RunStatus.running);
    expect(run.clock.sample().displaySeconds, 1);
    expect(run.sink.played, [
      'workout',
      'tick',
      'beep',
      'beep',
      'beep',
      'beep',
      'beep',
    ]);
    expect(run.sink.ticks, 1);
    expect(run.sink.beeps, 5);

    await run.seconds(1);
    expect(run.clock.status, RunStatus.finished);
    expect(run.sink.played.last, 'beep');
    expect(run.sink.beeps, 6);
  });

  test('intervals shorter than 5 seconds', () async {
    final run = _Run(_lane(prep: 3, work: 4, rest: 2, rounds: 2));
    await run.take();
    await run.seconds(13);
    expect(run.clock.status, RunStatus.finished);
    expect(run.sink.played, [
      'beep',
      'beep',
      'beep',
      'workout',
      'beep',
      'beep',
      'beep',
      'rest',
      'beep',
      'workout',
      'beep',
      'beep',
      'beep',
      'beep',
    ]);
  });

  test('a one second work or rest is only the word', () async {
    final run = _Run(_lane(work: 1, rest: 1, rounds: 2));
    await run.take();
    await run.seconds(3);
    expect(run.clock.status, RunStatus.finished);
    expect(run.sink.played, ['workout', 'rest', 'workout', 'beep']);
    expect(run.sink.ticks, 0);
  });

  test('the same displayed second does not fire twice', () async {
    final run = _Run(_lane(work: 20, rest: 0));
    await run.take();
    await run.take();
    run.time.advance(const Duration(milliseconds: 400));
    await run.take();
    run.time.advance(const Duration(milliseconds: 400));
    await run.take();
    expect(run.sink.played, ['workout']);

    run.time.advance(const Duration(milliseconds: 200));
    await run.take();
    expect(run.sink.played, ['workout', 'tick']);
    expect(run.clock.sample().displaySeconds, 19);
  });

  test('pause and resume do not repeat the current second', () async {
    final run = _Run(_lane(work: 20, rest: 0));
    await run.take();
    await run.seconds(2);
    expect(run.sink.played, ['workout', 'tick', 'tick']);

    run.clock.pause();
    run.time.advance(const Duration(seconds: 5));
    await run.take();
    expect(run.clock.status, RunStatus.paused);
    expect(run.sink.played, ['workout', 'tick', 'tick']);

    run.clock.resume();
    await run.take();
    expect(run.sink.played, ['workout', 'tick', 'tick']);

    await run.seconds(1);
    expect(run.sink.played, ['workout', 'tick', 'tick', 'tick']);
    expect(run.clock.sample().displaySeconds, 17);
  });

  test('a skip plays only the second it lands on', () async {
    final run = _Run(_lane(work: 20, rest: 10, rounds: 2));
    await run.take();
    run.time.advance(const Duration(seconds: 8));
    await run.take();
    run.time.advance(const Duration(seconds: 12));
    await run.take();
    await run.take();
    expect(run.sink.played, ['workout', 'tick', 'rest']);
    expect(run.clock.sample().phase!.kind, PhaseKind.rest);
    expect(run.clock.sample().displaySeconds, 10);
  });

  test('set rest says rest', () async {
    final run = _Run(_lane(work: 1, rest: 0, rounds: 1, sets: 2, setRest: 10));
    await run.take();
    await run.seconds(1);
    expect(run.clock.sample().phase!.kind, PhaseKind.setRest);
    expect(run.sink.played, ['workout', 'rest']);
    expect(run.sink.ticks, 0);
  });

  test('a long interval stays one sound per displayed second', () async {
    final run = _Run(_lane(work: 30, rest: 0));
    await run.take();
    await run.seconds(29);
    expect(run.clock.status, RunStatus.running);
    expect(run.sink.played, [
      'workout',
      for (var second = 29; second >= 6; second--) 'tick',
      for (var second = 0; second < finalBeepSeconds; second++) 'beep',
    ]);
    expect(run.sink.ticks, 24);
    expect(run.sink.beeps, finalBeepSeconds);
    expect(run.sink.played, hasLength(30));

    await run.seconds(1);
    expect(run.clock.status, RunStatus.finished);
    expect(run.sink.beeps, finalBeepSeconds + 1);
  });

  test('sound off plays words only', () async {
    final run = _Run(_lane(prep: 3, work: 4, rest: 2, rounds: 2), sound: false);
    await run.take();
    await run.seconds(13);
    expect(run.clock.status, RunStatus.finished);
    expect(run.sink.played, ['workout', 'rest', 'workout']);
    expect(run.sink.ticks, 0);
    expect(run.sink.beeps, 0);
  });

  test('voice off plays the tick or beep the word replaced', () async {
    final run = _Run(_lane(work: 7, rest: 0), voice: false);
    await run.take();
    await run.seconds(7);
    expect(run.sink.spoken, isEmpty);
    expect(run.sink.played, [
      'tick',
      'tick',
      'beep',
      'beep',
      'beep',
      'beep',
      'beep',
      'beep',
    ]);

    final short = _Run(_lane(work: 4, rest: 1, rounds: 2), voice: false);
    await short.take();
    await short.seconds(9);
    expect(short.clock.status, RunStatus.finished);
    expect(short.sink.spoken, isEmpty);
    expect(short.sink.played, List.filled(10, 'beep'));
  });

  test('sound and voice off stay silent, including the end', () async {
    final run = _Run(_lane(work: 7, rest: 0), sound: false, voice: false);
    await run.take();
    await run.seconds(7);
    expect(run.clock.status, RunStatus.finished);
    expect(run.sink.played, isEmpty);
  });

  test('silence and a spoken count stay behind one switch', () {
    const work = Phase(kind: PhaseKind.work, seconds: 20, round: 1, rounds: 1);
    const prep = Phase(kind: PhaseKind.prep, seconds: 8);

    expect(
      cueForSecond(
        phase: work,
        second: 12,
        intervalStart: false,
        style: SecondCueStyle.silent,
      ),
      isNull,
    );
    expect(
      cueForSecond(
        phase: work,
        second: 20,
        intervalStart: true,
        style: SecondCueStyle.silent,
      )!.text,
      'workout',
    );

    final spoken = cueForSecond(
      phase: prep,
      second: 4,
      intervalStart: false,
      style: SecondCueStyle.spoken,
    );
    expect(spoken!.kind, CueKind.voice);
    expect(spoken.text, '4');

    final opening = cueForSecond(
      phase: work,
      second: 4,
      intervalStart: true,
      style: SecondCueStyle.spoken,
    );
    expect(opening!.text, 'workout');

    expect(
      cueForSecond(
        phase: work,
        second: 4,
        intervalStart: true,
        voice: false,
        style: SecondCueStyle.spoken,
      )!.kind,
      CueKind.beep,
    );
    expect(
      cueForSecond(
        phase: work,
        second: 12,
        intervalStart: false,
        style: SecondCueStyle.spoken,
      )!.kind,
      CueKind.tick,
    );
  });
}
