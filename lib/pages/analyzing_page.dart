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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在识别歌词'),
        automaticallyImplyLeading: false,
      ),
      body: _lyricsError != null
          ? _buildError(scheme, textTheme)
          : _buildProgress(scheme, textTheme),
    );
  }

  Widget _buildProgress(ColorScheme scheme, TextTheme textTheme) {
    final fileName = widget.filePath.split(RegExp(r'[/\\]')).last;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(strokeWidth: 4.5),
                  ),
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 30,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            _stage,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '正在为你识别歌词，请稍候…',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (fileName.isNotEmpty)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note_rounded,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme scheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.music_off_rounded,
                  size: 40,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              '歌词识别失败',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                _lyricsError ?? '',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _fallbackAsr,
              icon: const Icon(Icons.transcribe_rounded),
              label: const Text('回退到语音转写'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回重试'),
            ),
          ],
        ),
      ),
    );
  }
}
