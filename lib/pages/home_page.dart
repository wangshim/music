import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'analyzing_page.dart';

/// 首页：选择音频 + 已选文件显示 + 开始分析入口
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 已选音频文件路径
  String? _filePath;

  /// 已选音频文件名
  String? _fileName;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSub;
  bool _playing = false;

  bool get _hasFile => _filePath != null;

  @override
  void initState() {
    super.initState();
    _playerSub = _player.playerStateStream.listen((state) {
      if (mounted && state.playing != _playing) {
        setState(() => _playing = state.playing);
      }
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// 选择音频文件
  Future<void> _pickAudio() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file == null || file.path == null) return;
    setState(() {
      _filePath = file.path;
      _fileName = file.name;
    });
  }

  /// 试听当前选中音频
  Future<void> _playPause() async {
    final path = _filePath;
    if (path == null) return;
    if (_player.playing) {
      await _player.pause();
      return;
    }
    try {
      await _player.setFilePath(path);
      _player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败：$e')),
        );
      }
    }
  }

  /// 进入分析流程
  Future<void> _startAnalyze() async {
    final path = _filePath;
    if (path == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnalyzingPage(filePath: path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          children: [
            _buildHeader(scheme, textTheme),
            const SizedBox(height: 36),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _hasFile
                  ? _buildFilePanel(scheme, textTheme)
                  : _buildPickPanel(scheme, textTheme),
            ),
            const SizedBox(height: 20),
            _buildHint(scheme, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, TextTheme textTheme) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.tertiary],
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.graphic_eq_rounded,
              color: Colors.white, size: 44),
        ),
        const SizedBox(height: 18),
        Text(
          '音频分析助手',
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '导入音频 · 自动识曲 · 纯文本歌词',
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 未选文件：突出的「选择音频文件」主操作
  Widget _buildPickPanel(ColorScheme scheme, TextTheme textTheme) {
    return Material(
      key: const ValueKey('pick'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _pickAudio,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.4),
              width: 1.6,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.26),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.library_music_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '选择音频文件',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '支持 MP3 / WAV / M4A / FLAC 等常见格式',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Icon(Icons.add_circle_rounded,
                  color: scheme.primary, size: 30),
            ],
          ),
        ),
      ),
    );
  }

  /// 已选文件：文件信息卡 + 开始识别入口
  Widget _buildFilePanel(ColorScheme scheme, TextTheme textTheme) {
    return Column(
      key: const ValueKey('file'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fileName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _filePath ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 32,
                icon: Icon(
                  _playing
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  color: scheme.primary,
                ),
                tooltip: _playing ? '暂停' : '试听',
                onPressed: _playPause,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _startAnalyze,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('开始识别歌词'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _pickAudio,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重新选择音频'),
        ),
      ],
    );
  }

  Widget _buildHint(ColorScheme scheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 16,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '选择音频后点击「开始识别歌词」即可获得纯文本歌词',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
