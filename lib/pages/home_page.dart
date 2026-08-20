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
  String? _selectedFilePath;

  /// 已选音频文件名
  String? _selectedFileName;

  final AudioPlayer _player = AudioPlayer();

  bool get _hasFile => _selectedFilePath != null;

  /// 选择音频文件
  Future<void> _pickAudio() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file == null || file.path == null) return;

    setState(() {
      _selectedFilePath = file.path;
      _selectedFileName = file.name;
    });
  }

  /// 试听当前选中音频（just_audio 集成验证）
  Future<void> _playPause() async {
    final path = _selectedFilePath;
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

  /// 进入分析流程（模拟分析中 -> 结果页）
  Future<void> _startAnalyze() async {
    final path = _selectedFilePath;
    if (path == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalyzingPage(filePath: path),
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('音频分析助手'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.audiotrack_rounded,
              size: 96,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '导入音频，识别纯歌词',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '识曲匹配歌词 · 失败自动回退语音转写',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            // 已选文件卡片
            if (_hasFile) ...[
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.music_note_rounded),
                  title: Text(
                    _selectedFileName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _selectedFilePath ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: '试听',
                    onPressed: _playPause,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 选择音频按钮
            FilledButton.icon(
              onPressed: _pickAudio,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(_hasFile ? '重新选择音频' : '选择音频文件'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            // 开始分析按钮
            FilledButton.tonalIcon(
              onPressed: _hasFile ? _startAnalyze : null,
              icon: const Icon(Icons.lyrics_rounded),
              label: const Text('开始识别歌词'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const Spacer(),
            Text(
              '识曲+歌词已实现；ASR 转写作为失败兜底保留',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
