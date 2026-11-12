import 'dart:async';

import 'package:flutter/material.dart';

import '../models/preset.dart';
import '../theme/app_theme.dart';
import '../widgets/icon_tip.dart';
import 'editor_screen.dart';
import 'log_screen.dart';
import 'run_screen.dart';
import 'scope.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Preset> _presets = [];
  var _sound = true;
  var _voice = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _read();
  }

  void _read() {
    final store = TabataScope.of(context).store;
    _presets = store.presets();
    _sound = store.soundOn;
    _voice = store.voiceOn;
  }

  void _reload() {
    setState(_read);
  }

  Future<void> _toggleSound() async {
    final next = !_sound;
    await TabataScope.of(context).store.setSoundOn(next);
    if (mounted) {
      setState(() => _sound = next);
    }
  }

  Future<void> _toggleVoice() async {
    final next = !_voice;
    await TabataScope.of(context).store.setVoiceOn(next);
    if (mounted) {
      setState(() => _voice = next);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) {
      _reload();
    }
  }

  Future<void> _menu(BuildContext button, Preset preset) async {
    final box = button.findRenderObject();
    final overlay = Navigator.of(button).overlay?.context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox) {
      return;
    }
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final action = await showMenu<String>(
      context: button,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'edit') {
      await _open(EditorScreen(preset: preset));
      return;
    }
    await _delete(preset);
  }

  Future<void> _delete(Preset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(preset.name),
        actions: [
          IconTip(
            icon: Icons.close,
            message: 'Cancel',
            onPressed: () => Navigator.pop(context, false),
          ),
          IconTip(
            icon: Icons.delete,
            message: 'Delete',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await TabataScope.of(context).store.deletePreset(preset.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tabata'),
        actions: [
          IconTip(
            key: const ValueKey('sound-toggle'),
            icon: _sound ? Icons.volume_up : Icons.volume_off,
            message: 'Sound',
            color: _sound ? AppColors.accent : AppColors.muted,
            onPressed: () => unawaited(_toggleSound()),
          ),
          IconTip(
            key: const ValueKey('voice-toggle'),
            icon: _voice ? Icons.record_voice_over : Icons.voice_over_off,
            message: 'Voice',
            color: _voice ? AppColors.accent : AppColors.muted,
            onPressed: () => unawaited(_toggleVoice()),
          ),
          IconTip(
            icon: Icons.history,
            message: 'Log',
            onPressed: () => _open(const LogScreen()),
          ),
          IconTip(
            icon: Icons.add,
            message: 'New',
            onPressed: () => _open(EditorScreen(preset: Preset.draft())),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _presets.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final preset = _presets[index];
          return Container(
            key: ValueKey('preset-${preset.id}'),
            decoration: cardBox(),
            padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        preset.cardLine,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Start',
                  child: Material(
                    color: AppColors.accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _open(RunScreen(preset: preset)),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.play_arrow, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                Builder(
                  builder: (button) => IconTip(
                    icon: Icons.more_vert,
                    message: 'Menu',
                    color: AppColors.ink,
                    onPressed: () => _menu(button, preset),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
