import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/analysis_result.dart';

/// 结果展示页。
///
/// 两种模式：
/// - 歌词模式：展示纯文本歌词全文（可滚动），不展示歌曲名/歌手，无时间轴高亮
/// - ASR 转写模式（识曲失败回退）：展示本地语音转写文字
class ResultPage extends StatelessWidget {
  final AnalysisResult result;

  const ResultPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final copyText = result.isLyrics ? result.lyrics : result.transcript;

    return Scaffold(
      appBar: AppBar(
        title: Text(result.isLyrics ? '歌词结果' : '转写结果'),
        actions: [
          IconButton(
            tooltip: '复制',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => _copyToClipboard(context, copyText),
          ),
        ],
      ),
      body: result.isLyrics
          ? _buildLyrics(context, scheme, textTheme)
          : _buildAsr(context, scheme, textTheme),
    );
  }

  /// 歌词模式：纯文本歌词全文，可滚动复制，不展示歌曲信息
  Widget _buildLyrics(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 歌词全文卡片
        _whiteCard(
          scheme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconBox(scheme, Icons.lyrics_rounded),
                  const SizedBox(width: 10),
                  Text(
                    '歌词全文',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                result.lyrics,
                style: textTheme.bodyLarge?.copyWith(
                  height: 1.8,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 元信息卡片
        _whiteCard(
          scheme,
          child: Column(
            children: [
              _metaRow(
                scheme,
                textTheme,
                icon: Icons.timer_outlined,
                label: '识别耗时',
                value: '${(result.elapsedMs / 1000).toStringAsFixed(1)} 秒',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              _metaRow(
                scheme,
                textTheme,
                icon: Icons.insert_drive_file_outlined,
                label: '源文件',
                value: result.filePath,
                valueMaxLines: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () async {
            await _copyToClipboard(context, result.lyrics);
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('复制歌词'),
        ),
        const SizedBox(height: 10),
        Text(
          '纯文本歌词 · 已去除时间轴标记',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: scheme.outline,
          ),
        ),
      ],
    );
  }

  /// ASR 转写模式（识曲失败回退）
  Widget _buildAsr(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 转写文字卡片
        _whiteCard(
          scheme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconBox(scheme, Icons.subject_rounded),
                  const SizedBox(width: 10),
                  Text(
                    '语音转写（ASR 回退）',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                result.transcript,
                style: textTheme.bodyLarge?.copyWith(
                  height: 1.7,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 转写信息卡片
        _whiteCard(
          scheme,
          child: Column(
            children: [
              _metaRow(
                scheme,
                textTheme,
                icon: Icons.settings_outlined,
                label: 'ASR 模型',
                value: result.modelName,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              _metaRow(
                scheme,
                textTheme,
                icon: Icons.timer_outlined,
                label: '转写耗时',
                value: '${(result.elapsedMs / 1000).toStringAsFixed(1)} 秒',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              _metaRow(
                scheme,
                textTheme,
                icon: Icons.hourglass_bottom_rounded,
                label: '音频时长',
                value: '${result.audioDurationSec.toStringAsFixed(1)} 秒',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              _metaRow(
                scheme,
                textTheme,
                icon: Icons.insert_drive_file_outlined,
                label: '源文件',
                value: result.filePath,
                valueMaxLines: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () async {
            await _copyToClipboard(context, result.transcript);
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('复制转写文本'),
        ),
      ],
    );
  }

  /// 白色圆角卡片容器
  Widget _whiteCard(
    ColorScheme scheme, {
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: child,
    );
  }

  /// 圆形小图标块
  Widget _iconBox(ColorScheme scheme, IconData icon) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
    );
  }

  /// 图标 + 标签 + 值 的信息行
  Widget _metaRow(
    ColorScheme scheme,
    TextTheme textTheme, {
    required IconData icon,
    required String label,
    required String value,
    int valueMaxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: valueMaxLines,
            overflow: valueMaxLines > 1 ? TextOverflow.ellipsis : null,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }
}
