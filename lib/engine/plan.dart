import '../models/preset.dart';

enum PhaseKind { prep, work, rest, setRest, cooldown }

class Phase {
  const Phase({
    required this.kind,
    required this.seconds,
    this.round = 0,
    this.rounds = 0,
    this.set = 0,
    this.sets = 0,
  });

  final PhaseKind kind;
  final int seconds;
  final int round;
  final int rounds;
  final int set;
  final int sets;

  Duration get duration => Duration(seconds: seconds);
}

class IntervalPlan {
  const IntervalPlan(this.phases);

  final List<Phase> phases;

  int get totalSeconds => phases.fold(0, (sum, phase) => sum + phase.seconds);

  Duration get total => Duration(seconds: totalSeconds);

  /// Prep, then each set of work/rest rounds, then cooldown.
  ///
  /// Rest after a round is skipped on the last round of a set. The gap between
  /// sets is the set rest, not another round rest. A zero duration is omitted.
  static IntervalPlan fromPreset(Preset preset) {
    final phases = <Phase>[];
    final rounds = preset.rounds;
    final sets = preset.sets;
    if (preset.prep > 0) {
      phases.add(Phase(kind: PhaseKind.prep, seconds: preset.prep, sets: sets));
    }
    for (var set = 1; set <= sets; set++) {
      for (var round = 1; round <= rounds; round++) {
        phases.add(
          Phase(
            kind: PhaseKind.work,
            seconds: preset.work,
            round: round,
            rounds: rounds,
            set: set,
            sets: sets,
          ),
        );
        final lastRound = round == rounds;
        final lastSet = set == sets;
        if (!lastRound && preset.rest > 0) {
          phases.add(
            Phase(
              kind: PhaseKind.rest,
              seconds: preset.rest,
              round: round,
              rounds: rounds,
              set: set,
              sets: sets,
            ),
          );
        } else if (lastRound && !lastSet && preset.setRest > 0) {
          phases.add(
            Phase(
              kind: PhaseKind.setRest,
              seconds: preset.setRest,
              round: round,
              rounds: rounds,
              set: set,
              sets: sets,
            ),
          );
        }
      }
    }
    if (preset.cooldown > 0) {
      phases.add(
        Phase(kind: PhaseKind.cooldown, seconds: preset.cooldown, sets: sets),
      );
    }
    return IntervalPlan(phases);
  }
}

/// One spoken word at the start of work or rest. Prep and cooldown stay
/// quiet. The round stays on screen; it is not spoken.
List<String> voiceLines(Phase phase) {
  return switch (phase.kind) {
    PhaseKind.work => const ['workout'],
    PhaseKind.rest || PhaseKind.setRest => const ['rest'],
    PhaseKind.prep || PhaseKind.cooldown => const [],
  };
}

String phaseLabel(Phase phase) {
  return switch (phase.kind) {
    PhaseKind.work => _round('WORK', phase),
    PhaseKind.rest => _round('REST', phase),
    PhaseKind.setRest => 'SET ${phase.set}/${phase.sets} · REST',
    PhaseKind.prep => 'PREP',
    PhaseKind.cooldown => 'COOLDOWN',
  };
}

String _round(String name, Phase phase) {
  final label = 'ROUND ${phase.round}/${phase.rounds} · $name';
  if (phase.sets > 1) {
    return 'SET ${phase.set} · $label';
  }
  return label;
}

int displaySeconds(Duration remaining) {
  if (remaining <= Duration.zero) {
    return 0;
  }
  final ms = remaining.inMilliseconds;
  return (ms + 999) ~/ 1000;
}
