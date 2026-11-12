import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'cues.dart';

/// Resumes the silent loop when an interruption ends, then notifies the timer.
///
/// [begin] is true while the interruption is starting. [bedOn] is true while
/// the loop should be playing. [onInterruptionEnd] lets the countdown catch
/// up the time the stopwatch missed.
void handleAudioInterruption({
  required bool begin,
  required bool bedOn,
  required void Function() resumeBed,
  void Function()? onInterruptionEnd,
}) {
  if (begin || !bedOn) {
    return;
  }
  resumeBed();
  onInterruptionEnd?.call();
}

/// Ticks, beeps, spoken words, and a silent loop that keeps iOS from
/// suspending the timer. The loop is digital silence so it does not hiss
/// over other audio.
///
/// The session category is playback, so the iPhone silent switch does not
/// mute the cues. [AVAudioSessionCategoryOptions.mixWithOthers] keeps music
/// playing. duckOthers is not set: the silent loop runs for the whole
/// workout, and ducking would hold music down the entire time. Android asks
/// for transient may-duck focus, so other apps may lower their volume while
/// that session is active.
///
/// Words and counts are bundled clips. Anything else falls back to the
/// platform voice. Clips are preloaded so a cue starts on the clock sample
/// instead of waiting on a synthesizer.
class DeviceCues implements CueSink {
  @override
  void Function()? onInterruptionEnd;

  static const voiceAssets = <String, String>{
    'workout': 'assets/audio/workout.wav',
    'rest': 'assets/audio/rest.wav',
    '1': 'assets/audio/count_1.wav',
    '2': 'assets/audio/count_2.wav',
    '3': 'assets/audio/count_3.wav',
    '4': 'assets/audio/count_4.wav',
    '5': 'assets/audio/count_5.wav',
  };

  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _beep = AudioPlayer();
  final AudioPlayer _bed = AudioPlayer();
  final Map<String, AudioPlayer> _voices = {};
  final FlutterTts _tts = FlutterTts();
  var _ready = false;
  var _bedOn = false;
  var _listening = false;

  Future<void> _ensure() async {
    if (_ready) {
      return;
    }
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ),
    );
    await session.setActive(true);
    await _tts.setSharedInstance(true);
    await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
      IosTextToSpeechAudioCategoryOptions.mixWithOthers,
    ]);
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tick.setAsset('assets/audio/tick.wav');
    await _tick.setVolume(0.35);
    await _beep.setAsset('assets/audio/beep.wav');
    await _beep.setVolume(1);
    for (final entry in voiceAssets.entries) {
      final player = _voices.putIfAbsent(entry.key, AudioPlayer.new);
      await player.setAsset(entry.value);
      await player.setVolume(1);
    }
    await _bed.setAsset('assets/audio/bed.wav');
    await _bed.setVolume(0.35);
    await _bed.setLoopMode(LoopMode.one);
    if (!_listening) {
      _listening = true;
      session.interruptionEventStream.listen(_onInterruption);
    }
    _ready = true;
  }

  /// A phone call, Siri, or an alarm stops the silent loop. When that
  /// interruption ends, start it again so iOS does not suspend the timer.
  void _onInterruption(AudioInterruptionEvent event) {
    handleAudioInterruption(
      begin: event.begin,
      bedOn: _bedOn,
      resumeBed: () => unawaited(_resumeBed()),
      onInterruptionEnd: onInterruptionEnd,
    );
  }

  Future<void> _resumeBed() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      unawaited(_bed.play());
    } on Object {
      // The next foreground resume calls [begin] again.
    }
  }

  @override
  Future<void> begin() async {
    try {
      await _ensure();
      _bedOn = true;
      if (_bed.playing) {
        return;
      }
      unawaited(_bed.play());
    } on Object {
      _ready = false;
      _bedOn = false;
    }
  }

  @override
  Future<void> end() async {
    try {
      _bedOn = false;
      await cut();
      await _bed.stop();
    } on Object {
      // The player can already be released.
    }
  }

  @override
  Future<void> cut() async {
    try {
      await _tick.stop();
      await _beep.stop();
      for (final player in _voices.values) {
        await player.stop();
      }
      await _tts.stop();
    } on Object {
      // A player that never started can throw on stop.
    }
  }

  Future<void> _play(AudioPlayer player) async {
    await player.seek(Duration.zero);
    // Start and return. Waiting for the clip to finish would push the next
    // second's cue late. Clips are shorter than a second, and the clock
    // will not start another sound on this same second.
    unawaited(
      player.play().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  @override
  Future<void> tick() async {
    try {
      await _ensure();
      await _play(_tick);
    } on Object {
      // A missed tick should not stop the clock.
    }
  }

  @override
  Future<void> beep() async {
    try {
      await _ensure();
      await _play(_beep);
    } on Object {
      // A missed beep should not stop the clock.
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _ensure();
      final clip = _voices[text];
      if (clip != null) {
        await _play(clip);
        return;
      }
      await _tts.speak(text);
    } on Object {
      // Voice is best-effort if the synth is busy.
    }
  }
}
