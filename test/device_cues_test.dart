import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tabata/services/device_cues.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the audio session mixes and ignores the silent switch', () {
    final config = DeviceCues.sessionConfig;
    final options = config.avAudioSessionCategoryOptions!;

    expect(config.avAudioSessionCategory, AVAudioSessionCategory.playback);
    expect(options, AVAudioSessionCategoryOptions.mixWithOthers);
    expect(options.value, AVAudioSessionCategoryOptions.mixWithOthers.value);
    expect(options.contains(AVAudioSessionCategoryOptions.duckOthers), isFalse);
    expect(
      options.contains(
        AVAudioSessionCategoryOptions.interruptSpokenAudioAndMixWithOthers,
      ),
      isFalse,
    );
    expect(config.avAudioSessionMode, AVAudioSessionMode.defaultMode);
    expect(
      config.androidAudioFocusGainType,
      AndroidAudioFocusGainType.gainTransientMayDuck,
    );
    expect(config.androidWillPauseWhenDucked, isFalse);
    expect(DeviceCues.ttsCategory, IosTextToSpeechAudioCategory.playback);
    expect(DeviceCues.ttsOptions, [
      IosTextToSpeechAudioCategoryOptions.mixWithOthers,
    ]);
  });

  test('overlapping loads share one future', () async {
    var calls = 0;
    final gate = Completer<void>();
    final cues = DeviceCues(
      load: () {
        calls += 1;
        return gate.future;
      },
    );

    final first = cues.ensureReady();
    final second = cues.ensureReady();
    expect(calls, 1);

    gate.complete();
    await first;
    await second;
    await cues.ensureReady();
    expect(calls, 1);
  });

  test('a failed load can be tried again', () async {
    var calls = 0;
    final cues = DeviceCues(
      load: () async {
        calls += 1;
        if (calls == 1) {
          throw StateError('Loading interrupted');
        }
      },
    );

    await expectLater(cues.ensureReady(), throwsStateError);
    await cues.ensureReady();
    expect(calls, 2);
  });
}
