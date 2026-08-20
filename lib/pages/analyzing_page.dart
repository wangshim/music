import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../services/asr_service.dart';
import 'result_page.dart';

/// 分析中状态页：真实调用本地 ASR 转写，展示进度与部分结果
class AnalyzingPage extends StatefulWidget {
  /// 被分析的音频文件路径
  final String filePath;

  const AnalyzingPage({super.key, required this.filePath});

  @override
  State<AnalyzingPage> createState() => _AnalyzingPageState();
}

class _AnalyzingPageState extends State<AnalyzingPage> {
  int _percent = 0;
  String _partialText = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final asr = await AsrService.instance.transcribeFile(
        widget.filePath,
        onProgress: (percent, text) {
          if (mounted) {
            setState(() {
              _percent = percent;
              _partialText = text;
            });
          }
        },
      );
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
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在分析'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: _error != null
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
          const SizedBox(height: 24),
          const Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(strokeWidth: 5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '正在本地离线转写…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'sherpa-onnx 流式中文模型 · 数据不离开设备',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _percent / 100,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '进度 $_percent%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          // 已识别的部分文字
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _partialText.isEmpty
                  ? Text(
                      '正在聆听音频内容…',
                      style: TextStyle(color: colorScheme.outline),
                    )
                  : SingleChildScrollView(
                      child: Text(
                        _partialText,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              height: 1.6,
                            ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
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
            Icon(Icons.error_outline_rounded, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              '转写失败',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
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
