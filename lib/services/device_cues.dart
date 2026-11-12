import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'cues.dart';

/// One in-flight [load], shared by every caller.
///
/// A success stays memoised. A failure is forgotten so the next call can try
/// again. [begin] and the first tick both load the players; without this they
/// call `setAsset` at the same time and just_audio aborts the keep-awake loop.
class SharedLoad {
  Future<void>? _pending;

  Future<void> call(Future<void> Function() load) {
    final pending = _pending;
    if (pending != null) {
      return pending;
    }
    final run = Future<void>.sync(load);
    _pending = run;
    return run.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (identical(_pending, run)) {
          _pending = null;
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
  }
}

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
/// "workout" and "rest" are bundled clips. Anything else falls back to the
/// platform voice. Clips are preloaded so a cue starts on the clock sample
/// instead of waiting on a synthesizer.
class DeviceCues implements CueSink {
  DeviceCues({Future<void> Function()? load}) : _loadOverride = load;

  @override
  void Function()? onInterruptionEnd;

  /// Playback mixes with other audio and does not yield to the silent switch.
  /// Android may duck other apps, and it must not pause us when it does.
  static const sessionConfig = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    avAudioSessionMode: AVAudioSessionMode.defaultMode,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
    androidWillPauseWhenDucked: false,
  );

  static const ttsCategory = IosTextToSpeechAudioCategory.playback;

  static const ttsOptions = <IosTextToSpeechAudioCategoryOptions>[
    IosTextToSpeechAudioCategoryOptions.mixWithOthers,
  ];

  static const voiceAssets = <String, String>{
    'workout': 'assets/audio/workout.wav',
    'rest': 'assets/audio/rest.wav',
  };

  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _beep = AudioPlayer();
  final AudioPlayer _bed = AudioPlayer();
  final Map<String, AudioPlayer> _voices = {};
  final FlutterTts _tts = FlutterTts();
  final Future<void> Function()? _loadOverride;
  final SharedLoad _gate = SharedLoad();
  var _ready = false;
  var _bedOn = false;
  var _listening = false;

  /// Loads the session and clips once, even if [begin] and a cue overlap.
  @visibleForTesting
  Future<void> ensureReady() => _ensure();

  Future<void> _ensure() {
    if (_ready) {
      return Future<void>.value();
    }
    return _gate.call(() async {
      final override = _loadOverride;
      if (override != null) {
        await override();
      } else {
        await _openSession();
      }
      _ready = true;
    });
  }

  Future<void> _openSession() async {
    final session = await AudioSession.instance;
    await session.configure(sessionConfig);
    await session.setActive(true);
    await _tts.setSharedInstance(true);
    await _tts.setIosAudioCategory(ttsCategory, ttsOptions);
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tick.setAsset('assets/audio/tick.wav');
    // Softer than the beep (volume 1, louder waveform) and loud enough to
    // sit over music.
    await _tick.setVolume(0.6);
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
