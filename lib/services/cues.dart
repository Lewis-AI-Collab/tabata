import '../engine/clock.dart';

abstract class CueSink {
  /// Fired when an audio interruption ends and the silent loop should resume.
  void Function()? onInterruptionEnd;

  Future<void> begin();
  Future<void> end();

  /// Stops a tick, beep, or word already playing. The silent loop keeps going
  /// so a muted timer is not suspended.
  Future<void> cut();

  Future<void> tick();
  Future<void> beep();
  Future<void> speak(String text);
}

class SilentCues implements CueSink {
  @override
  void Function()? onInterruptionEnd;

  int ticks = 0;
  int beeps = 0;
  final List<String> spoken = [];
  final List<String> played = [];
  bool bed = false;

  @override
  Future<void> begin() async {
    bed = true;
  }

  @override
  Future<void> end() async {
    bed = false;
  }

  @override
  Future<void> cut() async {}

  @override
  Future<void> tick() async {
    ticks += 1;
    played.add('tick');
  }

  @override
  Future<void> beep() async {
    beeps += 1;
    played.add('beep');
  }

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    played.add(text);
  }
}

/// Plays [cues] in order. The clock already decided which one sound belongs
/// to this second, so a word is not joined with a tick.
Future<void> playCues(CueSink sink, List<Cue> cues) async {
  for (final cue in cues) {
    switch (cue.kind) {
      case CueKind.tick:
        await sink.tick();
      case CueKind.beep:
        await sink.beep();
      case CueKind.voice:
        if (cue.text != null) {
          await sink.speak(cue.text!);
        }
    }
  }
}
