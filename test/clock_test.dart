import 'package:flutter_test/flutter_test.dart';
import 'package:tabata/engine/clock.dart';
import 'package:tabata/engine/plan.dart';
import 'package:tabata/models/preset.dart';

void main() {
  const preset = Preset(
    id: 't',
    name: 'T',
    prep: 0,
    work: 20,
    rest: 10,
    rounds: 2,
    sets: 1,
    setRest: 0,
    cooldown: 0,
  );

  IntervalPlan plan() => IntervalPlan.fromPreset(preset);

  test('pause freezes the clock and resume follows monotonic time', () {
    final time = ManualTime();
    final clock = IntervalClock(plan(), time: time);
    clock.start();

    final opened = clock.sample();
    expect(opened.displaySeconds, 20);
    expect(opened.cues, hasLength(1));
    expect(opened.cues.single.kind, CueKind.voice);
    expect(opened.cues.single.text, 'workout');

    time.advance(const Duration(seconds: 17));
    final atThree = clock.sample();
    expect(atThree.displaySeconds, 3);
    expect(atThree.remaining, const Duration(seconds: 3));
    expect(atThree.cues, hasLength(1));
    expect(atThree.cues.single.kind, CueKind.beep);

    time.advance(const Duration(milliseconds: 500));
    final stillThree = clock.sample();
    expect(stillThree.displaySeconds, 3);
    expect(stillThree.cues, isEmpty);

    time.advance(const Duration(milliseconds: 500));
    final atTwo = clock.sample();
    expect(atTwo.displaySeconds, 2);
    expect(atTwo.cues.single.kind, CueKind.beep);

    clock.pause();
    time.advance(const Duration(seconds: 82));
    final held = clock.sample();
    expect(held.status, RunStatus.paused);
    expect(held.elapsed, const Duration(seconds: 18));
    expect(held.displaySeconds, 2);
    expect(held.phaseIndex, 0);
    expect(held.cues, isEmpty);

    clock.resume();
    time.advance(const Duration(seconds: 1));
    final after = clock.sample();
    expect(after.status, RunStatus.running);
    expect(after.elapsed, const Duration(seconds: 19));
    expect(after.displaySeconds, 1);
    expect(after.cues.single.kind, CueKind.beep);
  });

  test('a background gap lands on the phase for that elapsed time', () {
    final time = ManualTime();
    final clock = IntervalClock(plan(), time: time);
    clock.start();

    time.advance(const Duration(seconds: 25));
    final landed = clock.sample();
    expect(landed.status, RunStatus.running);
    expect(landed.phaseIndex, 1);
    expect(landed.phase!.kind, PhaseKind.rest);
    expect(landed.remaining, const Duration(seconds: 5));
    expect(landed.cues, hasLength(1));
    expect(landed.cues.single.kind, CueKind.beep);

    time.advance(const Duration(seconds: 7));
    final next = clock.sample();
    expect(next.phaseIndex, 2);
    expect(next.phase!.round, 2);
    expect(next.displaySeconds, 18);
    expect(next.cues, hasLength(1));
    expect(next.cues.single.kind, CueKind.tick);
  });

  test('the stopwatch keeps elapsed time while nobody is sampling', () async {
    final clock = IntervalClock(plan());
    clock.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final sample = clock.sample();
    expect(sample.status, RunStatus.running);
    expect(sample.elapsed, greaterThan(Duration.zero));
    clock.pause();
    final frozen = clock.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(clock.sample().elapsed, frozen);
    expect(clock.status, RunStatus.paused);
  });

  test('jumping past the end finishes once', () {
    final time = ManualTime();
    final clock = IntervalClock(plan(), time: time);
    clock.start();
    time.advance(const Duration(seconds: 50));
    final done = clock.sample();
    expect(done.status, RunStatus.finished);
    expect(done.elapsed, plan().total);
    expect(done.cues, hasLength(1));
    expect(done.cues.single.kind, CueKind.beep);

    time.advance(const Duration(seconds: 30));
    final again = clock.sample();
    expect(again.status, RunStatus.finished);
    expect(again.cues, isEmpty);
    expect(again.elapsed, const Duration(seconds: 50));
  });

  test('a short work interval speaks once and does not also beep', () {
    for (final seconds in [1, 2, 3, 4, 5]) {
      final time = ManualTime();
      final clock = IntervalClock(
        IntervalPlan.fromPreset(
          Preset(
            id: 's$seconds',
            name: 'S',
            prep: 0,
            work: seconds,
            rest: 0,
            rounds: 1,
            sets: 1,
            setRest: 0,
            cooldown: 0,
          ),
        ),
        time: time,
      );
      clock.start();
      final opened = clock.sample();
      expect(opened.displaySeconds, seconds, reason: '$seconds s');
      expect(opened.cues.map((cue) => cue.text), ['workout']);
      expect(
        opened.cues.where((cue) => cue.kind == CueKind.beep),
        isEmpty,
        reason: '$seconds s opening',
      );

      if (seconds == 1) {
        continue;
      }
      time.advance(const Duration(seconds: 1));
      final next = clock.sample();
      expect(next.displaySeconds, seconds - 1);
      expect(next.cues, hasLength(1));
      expect(next.cues.single.kind, CueKind.beep);
    }
  });

  test('locate treats a phase boundary as the start of the next phase', () {
    final built = plan();
    expect(built.phases, hasLength(3));

    final start = locate(built, Duration.zero);
    expect(start.index, 0);
    expect(start.into, Duration.zero);
    expect(start.remaining, const Duration(seconds: 20));

    final before = locate(
      built,
      const Duration(seconds: 20) - const Duration(microseconds: 1),
    );
    expect(before.index, 0);
    expect(before.remaining, const Duration(microseconds: 1));

    final boundary = locate(built, const Duration(seconds: 20));
    expect(boundary.index, 1);
    expect(boundary.phase.kind, PhaseKind.rest);
    expect(boundary.into, Duration.zero);
    expect(boundary.remaining, const Duration(seconds: 10));

    final restEnd = locate(built, const Duration(seconds: 30));
    expect(restEnd.index, 2);
    expect(restEnd.into, Duration.zero);
    expect(restEnd.remaining, const Duration(seconds: 20));

    final done = locate(built, const Duration(seconds: 50));
    expect(done.index, 2);
    expect(done.into, const Duration(seconds: 20));
    expect(done.remaining, Duration.zero);

    final past = locate(built, const Duration(seconds: 80));
    expect(past.index, 2);
    expect(past.into, const Duration(seconds: 20));
    expect(past.remaining, Duration.zero);

    expect(
      () => locate(const IntervalPlan([]), Duration.zero),
      throwsStateError,
    );
  });

  test('a frozen stopwatch catches up 60s of wall time on resume', () {
    // 25/15: at 60s the phase is round 2 work, 5s remaining.
    const slept = Preset(
      id: 'slept',
      name: 'Slept',
      prep: 0,
      work: 25,
      rest: 15,
      rounds: 4,
      sets: 1,
      setRest: 0,
      cooldown: 0,
    );
    final time = ManualTime();
    var now = DateTime(2026, 10, 16, 8);
    final clock = IntervalClock(
      IntervalPlan.fromPreset(slept),
      time: time,
      now: () => now,
    );
    clock.start();
    final opened = clock.sample();
    expect(opened.phaseIndex, 0);
    expect(opened.phase!.round, 1);
    expect(opened.elapsed, Duration.zero);

    now = now.add(const Duration(seconds: 60));
    expect(clock.elapsed, Duration.zero);

    clock.catchUp();
    final landed = clock.sample();
    expect(landed.elapsed, const Duration(seconds: 60));
    expect(landed.phaseIndex, 2);
    expect(landed.phase!.kind, PhaseKind.work);
    expect(landed.phase!.round, 2);
    expect(landed.remaining, const Duration(seconds: 5));

    clock.catchUp();
    expect(clock.elapsed, const Duration(seconds: 60));
  });

  test('a one second wall lead and a pause do not move the stopwatch', () {
    const slept = Preset(
      id: 'slept',
      name: 'Slept',
      prep: 0,
      work: 25,
      rest: 15,
      rounds: 4,
      sets: 1,
      setRest: 0,
      cooldown: 0,
    );
    final time = ManualTime();
    var now = DateTime(2026, 10, 16, 8);
    final clock = IntervalClock(
      IntervalPlan.fromPreset(slept),
      time: time,
      now: () => now,
    );
    clock.start();

    now = now.add(IntervalClock.catchUpThreshold);
    clock.catchUp();
    expect(clock.elapsed, Duration.zero);
    expect(clock.sample().phaseIndex, 0);

    time.advance(const Duration(seconds: 10));
    now = now.add(const Duration(seconds: 10));
    clock.pause();
    now = now.add(const Duration(seconds: 60));
    clock.catchUp();
    expect(clock.status, RunStatus.paused);
    expect(clock.elapsed, const Duration(seconds: 10));

    clock.resume();
    now = now.add(const Duration(seconds: 60));
    clock.catchUp();
    expect(clock.elapsed, const Duration(seconds: 70));
    final landed = clock.sample();
    expect(landed.phase!.kind, PhaseKind.rest);
    expect(landed.phase!.round, 2);
  });

  test('setting the wall clock back 60s does not change elapsed time', () {
    final time = ManualTime();
    var now = DateTime(2026, 10, 16, 8);
    final clock = IntervalClock(plan(), time: time, now: () => now);
    clock.start();
    time.advance(const Duration(seconds: 18));
    now = now.add(const Duration(seconds: 18));
    clock.catchUp();
    expect(clock.elapsed, const Duration(seconds: 18));
    expect(clock.sample().displaySeconds, 2);

    now = now.subtract(const Duration(seconds: 60));
    clock.catchUp();
    expect(clock.elapsed, const Duration(seconds: 18));
    expect(clock.sample().displaySeconds, 2);
    expect(clock.sample().phaseIndex, 0);
    expect(clock.status, RunStatus.running);
  });

  test('a forward gap equal to the time left finishes the workout', () {
    final time = ManualTime();
    var now = DateTime(2026, 10, 16, 8);
    final built = plan();
    final clock = IntervalClock(built, time: time, now: () => now);
    clock.start();
    time.advance(const Duration(seconds: 40));
    now = now.add(const Duration(seconds: 40));
    clock.catchUp();
    expect(clock.elapsed, const Duration(seconds: 40));

    now = now.add(const Duration(seconds: 10));
    clock.catchUp();
    expect(clock.elapsed, built.total);
    expect(clock.status, RunStatus.finished);
    final done = clock.sample();
    expect(done.elapsed, built.total);
    expect(done.remaining, Duration.zero);
    expect(done.cues.single.kind, CueKind.beep);
  });

  test('a forward gap bigger than the time left ends interrupted', () {
    // 10s left. Adding the 60s gap, or clamping it to those 10s, both land
    // on plan.total because elapsed already clamps. That would look completed.
    final time = ManualTime();
    var now = DateTime(2026, 10, 16, 8);
    final built = plan();
    final clock = IntervalClock(built, time: time, now: () => now);
    clock.start();
    time.advance(const Duration(seconds: 40));
    now = now.add(const Duration(seconds: 40));
    clock.catchUp();
    expect(clock.elapsed, const Duration(seconds: 40));

    now = now.add(const Duration(seconds: 60));
    clock.catchUp();
    expect(clock.status, RunStatus.interrupted);
    expect(clock.elapsed, const Duration(seconds: 40));
    final held = clock.sample();
    expect(held.status, RunStatus.interrupted);
    expect(held.elapsed, const Duration(seconds: 40));
    expect(held.cues, isEmpty);

    clock.catchUp();
    expect(clock.status, RunStatus.interrupted);
    expect(clock.elapsed, const Duration(seconds: 40));
  });

  test('a 100s gap at 200s of a 240s plan ends interrupted', () {
    // 40s left. A gap of 100s is past the time left, and under the full plan.
    final time = ManualTime();
    var now = DateTime(2026, 10, 22, 8);
    final built = IntervalPlan.fromPreset(Preset.classic);
    expect(built.total, const Duration(seconds: 240));
    final clock = IntervalClock(built, time: time, now: () => now);
    clock.start();
    time.advance(const Duration(seconds: 200));
    now = now.add(const Duration(seconds: 200));
    clock.catchUp();
    expect(clock.elapsed, const Duration(seconds: 200));
    expect(clock.status, RunStatus.running);

    now = now.add(const Duration(seconds: 100));
    clock.catchUp();
    expect(clock.status, RunStatus.interrupted);
    expect(clock.elapsed, const Duration(seconds: 200));
  });
}
