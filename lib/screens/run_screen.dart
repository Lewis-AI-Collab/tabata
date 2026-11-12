import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/clock.dart';
import '../engine/plan.dart';
import '../models/preset.dart';
import '../models/session_log.dart';
import '../services/cues.dart';
import '../services/wake.dart';
import '../theme/app_theme.dart';
import '../widgets/complete_sheet.dart';
import '../widgets/icon_tip.dart';
import '../widgets/run_view.dart';
import 'scope.dart';

class RunScreen extends StatefulWidget {
  const RunScreen({super.key, required this.preset, this.time, this.now});

  final Preset preset;

  /// Monotonic clock. Tests pass a [ManualTime]. The app uses a stopwatch,
  /// which keeps elapsed time accurate while the screen is locked.
  final MonotonicTime? time;

  /// Wall clock for sleep catch-up. Tests move this while [time] stays put.
  final DateTime Function()? now;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> with WidgetsBindingObserver {
  late final DateTime _startedAt;
  late final IntervalClock _clock;
  late final CueSink _cues;
  late final WakeLock _wake;
  ClockSample? _sample;
  Timer? _ticker;
  Future<void> _pending = Future<void>.value();
  var _done = false;
  var _sound = true;
  var _voice = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final scope = TabataScope.read(context);
    _cues = scope.cues;
    _wake = scope.wake;
    _sound = scope.store.soundOn;
    _voice = scope.store.voiceOn;
    _startedAt = DateTime.now();
    _clock = IntervalClock(
      IntervalPlan.fromPreset(widget.preset),
      time: widget.time,
      now: widget.now,
    );
    _cues.onInterruptionEnd = () {
      if (_done || !mounted) {
        return;
      }
      _onTick();
    };
    _clock.start();
    _sample = _clock.sample(sound: _sound, voice: _voice);
    _enqueue(_sample!.cues);
    unawaited(_cues.begin());
    unawaited(_wake.set(running: true, foreground: true));
    _startTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _cues.onInterruptionEnd = null;
    unawaited(_cues.end());
    unawaited(_wake.set(running: false, foreground: false));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground && !_done) {
      _clock.catchUp();
      if (_clock.status == RunStatus.running) {
        unawaited(_cues.begin());
      }
    }
    final running = _clock.status == RunStatus.running;
    unawaited(_wake.set(running: running, foreground: foreground));
    if (foreground && !_done) {
      _onTick();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _onTick(),
    );
  }

  void _onTick() {
    if (_done || !mounted) {
      return;
    }
    _clock.catchUp();
    if (_clock.status == RunStatus.interrupted) {
      unawaited(_finish(completed: false, interrupted: true, cues: const []));
      return;
    }
    final next = _clock.sample(sound: _sound, voice: _voice);
    setState(() => _sample = next);
    if (next.status == RunStatus.finished) {
      unawaited(_finish(completed: true, cues: next.cues));
    } else {
      _enqueue(next.cues);
    }
  }

  void _enqueue(List<Cue> cues) {
    if (cues.isEmpty) {
      return;
    }
    _pending = _pending.then((_) {
      final allowed = [
        for (final cue in cues)
          if (cue.kind == CueKind.voice ? _voice : _sound) cue,
      ];
      return playCues(_cues, allowed);
    });
  }

  Future<void> _toggleSound() async {
    final next = !_sound;
    setState(() => _sound = next);
    await TabataScope.of(context).store.setSoundOn(next);
    if (!next) {
      await _cues.cut();
    }
  }

  Future<void> _toggleVoice() async {
    final next = !_voice;
    setState(() => _voice = next);
    await TabataScope.of(context).store.setVoiceOn(next);
    if (!next) {
      await _cues.cut();
    }
  }

  Future<void> _togglePause() async {
    if (_done) {
      return;
    }
    if (_clock.status == RunStatus.paused) {
      _clock.resume();
      unawaited(_cues.begin());
      unawaited(_wake.set(running: true, foreground: true));
      _startTicker();
    } else {
      _clock.pause();
      _ticker?.cancel();
      unawaited(_cues.end());
      unawaited(_wake.set(running: false, foreground: true));
    }
    _onTick();
  }

  Future<void> _stop() async {
    if (_done) {
      return;
    }
    _clock.pause();
    await _finish(completed: false, cues: const []);
  }

  Future<void> _finish({
    required bool completed,
    bool interrupted = false,
    required List<Cue> cues,
  }) async {
    if (_done) {
      return;
    }
    _done = true;
    _ticker?.cancel();
    _enqueue(cues);
    await _pending;
    await _cues.end();
    await _wake.set(running: false, foreground: false);
    final log = SessionLog.capture(
      preset: widget.preset,
      startedAt: _startedAt,
      endedAt: DateTime.now(),
      elapsed: _clock.elapsed,
      completed: completed,
      interrupted: interrupted,
    );
    if (!mounted) {
      return;
    }
    final store = TabataScope.of(context).store;
    await store.addSession(log);
    if (!mounted) {
      return;
    }
    final history = store.sessions();
    await showCompleteSheet(context, log: log, history: history);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    final phase = sample?.phase;
    final kind = phase?.kind ?? PhaseKind.prep;
    return Scaffold(
      backgroundColor: tintFor(kind),
      body: Stack(
        children: [
          RunView(
            label: phase == null ? 'PREP' : phaseLabel(phase),
            seconds: sample?.displaySeconds ?? 0,
            progress: sample?.progress ?? 0,
            elapsed: sample?.elapsed ?? Duration.zero,
            paused: sample?.status == RunStatus.paused,
            tint: tintFor(kind),
            ring: ringFor(kind),
            onPause: () => unawaited(_togglePause()),
            onStop: () => unawaited(_stop()),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              left: false,
              right: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTip(
                      key: const ValueKey('sound-toggle'),
                      icon: _sound ? Icons.volume_up : Icons.volume_off,
                      message: 'Sound',
                      color: _sound ? AppColors.accent : AppColors.muted,
                      onPressed: () => unawaited(_toggleSound()),
                    ),
                    IconTip(
                      key: const ValueKey('voice-toggle'),
                      icon: _voice
                          ? Icons.record_voice_over
                          : Icons.voice_over_off,
                      message: 'Voice',
                      color: _voice ? AppColors.accent : AppColors.muted,
                      onPressed: () => unawaited(_toggleVoice()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
