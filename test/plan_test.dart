import 'package:flutter_test/flutter_test.dart';
import 'package:tabata/engine/plan.dart';
import 'package:tabata/models/preset.dart';

void main() {
  test('classic phase sequence and total duration', () {
    final plan = IntervalPlan.fromPreset(Preset.classic);
    final kinds = plan.phases.map((phase) => phase.kind).toList();
    expect(kinds.first, PhaseKind.prep);
    expect(kinds.where((kind) => kind == PhaseKind.work), hasLength(8));
    expect(kinds.where((kind) => kind == PhaseKind.rest), hasLength(7));
    expect(kinds.last, PhaseKind.work);
    expect(plan.totalSeconds, 10 + 8 * 20 + 7 * 10);
    expect(plan.phases[1].round, 1);
    expect(plan.phases.last.round, 8);
  });

  test('sets use set rest instead of a trailing round rest', () {
    const preset = Preset(
      id: 'two',
      name: 'Two',
      prep: 5,
      work: 20,
      rest: 10,
      rounds: 2,
      sets: 2,
      setRest: 30,
      cooldown: 15,
    );
    final plan = IntervalPlan.fromPreset(preset);
    expect(plan.phases.map((phase) => phase.kind), [
      PhaseKind.prep,
      PhaseKind.work,
      PhaseKind.rest,
      PhaseKind.work,
      PhaseKind.setRest,
      PhaseKind.work,
      PhaseKind.rest,
      PhaseKind.work,
      PhaseKind.cooldown,
    ]);
    expect(plan.phases.map((phase) => phase.seconds), [
      5,
      20,
      10,
      20,
      30,
      20,
      10,
      20,
      15,
    ]);
    expect(plan.totalSeconds, 150);
    expect(plan.phases[4].set, 1);
    expect(plan.phases[5].set, 2);
    expect(plan.phases[5].round, 1);
  });

  test('zero rest and prep are omitted', () {
    const preset = Preset(
      id: 'bare',
      name: 'Bare',
      prep: 0,
      work: 20,
      rest: 0,
      rounds: 3,
      sets: 1,
      setRest: 0,
      cooldown: 0,
    );
    final plan = IntervalPlan.fromPreset(preset);
    expect(plan.phases.map((phase) => phase.kind), [
      PhaseKind.work,
      PhaseKind.work,
      PhaseKind.work,
    ]);
    expect(plan.totalSeconds, 60);
  });

  test('voice cues say workout and rest', () {
    const phase = Phase(
      kind: PhaseKind.work,
      seconds: 20,
      round: 3,
      rounds: 8,
      set: 1,
      sets: 1,
    );
    expect(voiceLines(phase), ['workout']);
    expect(
      voiceLines(
        const Phase(kind: PhaseKind.rest, seconds: 10, round: 3, rounds: 8),
      ),
      ['rest'],
    );
    expect(voiceLines(const Phase(kind: PhaseKind.setRest, seconds: 30)), [
      'rest',
    ]);
    expect(voiceLines(const Phase(kind: PhaseKind.prep, seconds: 10)), isEmpty);
    expect(
      voiceLines(const Phase(kind: PhaseKind.cooldown, seconds: 10)),
      isEmpty,
    );
    expect(phaseLabel(phase), 'ROUND 3/8 · WORK');
  });
}
