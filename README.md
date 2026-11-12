# Tabata

An offline interval timer for the phone. Presets, the countdown, beeps, spoken cues, and the session log stay on the device.

There is no account, no cloud, and no network call.

## Install on an iPhone

A Mac, Flutter 3.47 stable, and Xcode. Plug the iPhone in, unlock it, and tap Trust.

Clone onto a normal local disk. Do not put the project in iCloud Drive, in Documents if that folder is synced, or in a Grok folder. Flutter's build tools fail on those paths.

```bash
git clone https://github.com/Lewis-AI-Collab/tabata.git
cd tabata
flutter pub get
flutter run --release
```

`flutter run --release` builds and installs Tabata on the plugged-in iPhone. The bundle id is `com.lewisagi.tabata`.

### Install with Xcode and a Personal Team

1. Open `ios/Runner.xcworkspace` in Xcode.
2. In the project navigator, select the **Runner** project, then the **Runner** target.
3. Open **Signing & Capabilities**.
4. Turn on **Automatically manage signing**.
5. Set **Team** to your Personal Team, the free Apple ID you use for development.
6. Leave the bundle id as `com.lewisagi.tabata`.
7. Plug in the iPhone, choose it as the run destination, and press Run.

After the team is set, `flutter run --release` from the project folder installs the same build.

A free Apple ID can install the app on your own phone. That install lasts about seven days, then you run it again.

## What you get

Saved presets: name, prep, work, rest, rounds, sets, rest between sets, and cooldown. There is no cap.

The running screen is a large countdown. The background tints for work and rest. A soft tick marks each second. The last five seconds of an interval are a sharper beep. Work starts with the spoken word "workout" and rest starts with "rest". That word takes the place of the tick or beep on the first second, so the two do not play together. Prep and cooldown have no word. The sound icon turns every cue off, including the spoken words. The voice icon turns only the words off, and the tick or beep for that second plays instead. Neither icon has a caption. Both choices are kept on the phone.

The tick, the beep, and the spoken words are short clips in the app, so they stay in time with the clock and work with no network. The tones are original and public domain (CC0). The words were synthesized with SVOX Pico (Apache-2.0). See `assets/audio/LICENSE.txt`. One constant, `finalBeepSeconds`, is the five-second threshold. `secondCueStyle` can silence the ticks and beeps without moving the clock. The spoken words stay.

The countdown reads a monotonic stopwatch while the app is open, so setting the clock back does not rewind it. On iOS that clock pauses while the phone sleeps. Each tick, when the app returns, and when an audio interruption ends, a wall-clock lead of more than a second is added. A lead longer than the time left ends the workout interrupted instead of completed. Sounds are taken from that same clock, one per displayed second, so a long session does not drift and a pause, resume, or jump does not play a second time. Nothing plays while the timer is paused or stopped. A finished workout ends on one beep. iOS `UIBackgroundModes` includes `audio`, and the audio session category is playback, so the silent switch does not mute the cues. The session uses `mixWithOthers`, so other audio keeps playing. It does not use `duckOthers`: a silent loop keeps the process awake for the whole workout, and ducking would hold music down the entire time. On Android the session asks for transient may-duck focus, so other apps may lower their volume while the timer is running. The silent switch and music ducking can only be confirmed on a phone. A silent loop keeps the process awake so the cues still fire with the screen locked. If a call, Siri, or an alarm interrupts that loop, it starts again when the interruption ends. `wakelock_plus` holds the screen on only while the timer is running in the foreground.

Finished and stopped sessions are logged on the phone. Copy, Grok, and Share hand over one plain-text block for a session, a day, or a week: heading, date, preset, work, rest, rounds, sets, total time, and completed, stopped early, or interrupted. Paste that block into any AI. Share uses the system sheet, and on iPad the popover is anchored to the button.

## Tests

```bash
flutter analyze
flutter test
```

Screenshots in `docs/screenshots` are rendered with Roboto, which ships in the app (Apache-2.0, see `assets/fonts/LICENSE-roboto.txt`).
