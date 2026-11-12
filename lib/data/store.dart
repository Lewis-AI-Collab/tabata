import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/preset.dart';
import '../models/session_log.dart';

abstract class KeyValue {
  String? read(String key);
  Future<void> write(String key, String value);
}

class MemoryBox implements KeyValue {
  final Map<String, String> data = {};

  @override
  String? read(String key) => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

class PrefsBox implements KeyValue {
  PrefsBox(this.prefs);

  final SharedPreferences prefs;

  @override
  String? read(String key) => prefs.getString(key);

  @override
  Future<void> write(String key, String value) => prefs.setString(key, value);
}

class TabataStore {
  TabataStore(this.box);

  final KeyValue box;

  static const presetsKey = 'presets.v1';
  static const sessionsKey = 'sessions.v1';
  static const soundKey = 'sound.v1';
  static const voiceKey = 'voice.v1';

  /// Missing keys stay on, so a first launch ticks and speaks.
  bool get soundOn => box.read(soundKey) != '0';

  bool get voiceOn => box.read(voiceKey) != '0';

  Future<void> setSoundOn(bool value) {
    return box.write(soundKey, value ? '1' : '0');
  }

  Future<void> setVoiceOn(bool value) {
    return box.write(voiceKey, value ? '1' : '0');
  }

  Future<void> ensureSeed() async {
    if (box.read(presetsKey) != null) {
      return;
    }
    await _writePresets(const [Preset.classic]);
  }

  List<Preset> presets() => _readList(presetsKey, Preset.fromJson);

  Future<void> savePreset(Preset preset) async {
    final next = preset.normalized();
    final all = presets();
    final index = all.indexWhere((item) => item.id == next.id);
    if (index >= 0) {
      all[index] = next;
    } else {
      all.add(next);
    }
    await _writePresets(all);
  }

  Future<void> deletePreset(String id) async {
    final all = presets()..removeWhere((item) => item.id == id);
    await _writePresets(all);
  }

  List<SessionLog> sessions() => _readList(sessionsKey, SessionLog.fromJson);

  Future<void> addSession(SessionLog log) async {
    final all = sessions()..add(log);
    await _writeSessions(all);
  }

  List<T> _readList<T>(
    String key,
    T Function(Map<String, dynamic> json) decode,
  ) {
    final raw = box.read(key);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      final out = <T>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        try {
          out.add(decode(item.cast<String, dynamic>()));
        } on FormatException {
          // One corrupt record does not drop the rest of the list.
        } on TypeError {
          // A cast on a wrong JSON type throws TypeError, not FormatException.
        }
      }
      return out;
    } on FormatException {
      return [];
    }
  }

  Future<void> _writePresets(List<Preset> presets) {
    return box.write(
      presetsKey,
      jsonEncode([for (final preset in presets) preset.toJson()]),
    );
  }

  Future<void> _writeSessions(List<SessionLog> sessions) {
    return box.write(
      sessionsKey,
      jsonEncode([for (final session in sessions) session.toJson()]),
    );
  }
}
