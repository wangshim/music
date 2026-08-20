import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../services/asr_service.dart';
import '../services/audio_decoder.dart';
import '../services/lyrics_recognizer.dart';
import 'result_page.dart';

/// 分析中状态页：
/// 主流程 = 识曲 + 拉取纯文本歌词；
/// 失败时可回退到本地 ASR 转写（保留原功能）。
class AnalyzingPage extends StatefulWidget {
  /// 被分析的音频文件路径
  final String filePath;

  const AnalyzingPage({super.key, required this.filePath});

  @override
  State<AnalyzingPage> createState() => _AnalyzingPageState();
}

class _AnalyzingPageState extends State<AnalyzingPage> {
  /// 当前阶段：解码 / 识曲 / 拉歌词 / 回退ASR
  String _stage = '正在解码音频…';
  String? _lyricsError;

  @override
  void initState() {
    super.initState();
    _runLyrics();
  }

  /// 主流程：解码 -> 识曲 -> 拉取纯歌词
  Future<void> _runLyrics() async {
    try {
      setState(() => _stage = '正在解码音频…');
      final wavPath = await AudioDecoder.decodeToWav(widget.filePath);

      setState(() => _stage = '正在识别歌曲并匹配歌词…');
      final outcome =
          await LyricsRecognizer.instance.recognizeAndFetchLyrics(wavPath);

      if (!mounted) return;
      if (!outcome.matched || outcome.lyrics == null) {
        setState(() {
          _lyricsError = outcome.error ??
              (outcome.matched ? '未找到该歌曲的歌词' : '未能识别出该音频对应的歌曲');
        });
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultPage(
            result: AnalysisResult.fromLyrics(
              filePath: widget.filePath,
              lyrics: outcome.lyrics!,
              elapsedMs: outcome.elapsedMs,
              audioDurationSec: 0,
              lyricsSource: outcome.source,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _lyricsError = e.toString());
    }
  }

  /// 回退：本地 ASR 转写（原功能）
  Future<void> _fallbackAsr() async {
    setState(() {
      _lyricsError = null;
      _stage = '正在本地离线转写…';
    });
    try {
      final asr = await AsrService.instance.transcribeFile(widget.filePath);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultPage(
            result: AnalysisResult.fromAsr(asr, widget.filePath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _lyricsError = 'ASR 转写失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在识别歌词'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: _lyricsError != null
          ? _buildError(colorScheme)
          : _buildProgress(colorScheme),
    );
  }

  Widget _buildProgress(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          const Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(strokeWidth: 5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _stage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '音频指纹识曲 · 在线匹配歌词 · ASR 兜底',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          Text(
            widget.filePath,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off_rounded, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              '歌词识别失败',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _lyricsError ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _fallbackAsr,
              icon: const Icon(Icons.transcribe_rounded),
              label: const Text('回退到语音转写'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回重试'),
            ),
          ],
        ),
      ),
    );
  }
}
