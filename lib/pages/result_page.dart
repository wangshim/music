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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(result.isLyrics ? '歌词结果' : '转写结果'),
        centerTitle: true,
      ),
      body: result.isLyrics
          ? _buildLyrics(context, colorScheme)
          : _buildAsr(context, colorScheme),
    );
  }

  /// 歌词模式：纯文本歌词全文，可滚动复制，不展示歌曲信息
  Widget _buildLyrics(BuildContext context, ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 歌词全文卡片
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lyrics_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '歌词全文',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  result.lyrics,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.7,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 处理信息（不展示歌曲名/歌手）
        Card(
          elevation: 1,
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('已识别歌词'),
            subtitle: Text(
              '耗时 ${(result.elapsedMs / 1000).toStringAsFixed(2)} 秒',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 源文件信息
        Card(
          elevation: 1,
          child: ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('源文件'),
            subtitle: Text(
              result.filePath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 复制按钮
        OutlinedButton.icon(
          onPressed: () async {
            await _copyToClipboard(context, result.lyrics);
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('复制歌词'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '歌词为纯文本内容，不含时间轴',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
        ),
      ],
    );
  }

  /// ASR 转写模式（识曲失败回退）
  Widget _buildAsr(BuildContext context, ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 转写文字卡片
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.subject_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '语音转写（ASR 回退）',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  result.transcript,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 转写信息卡片
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      '转写信息',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoRow(label: 'ASR 模型', value: result.modelName),
                const SizedBox(height: 6),
                _InfoRow(
                  label: '转写耗时',
                  value: '${(result.elapsedMs / 1000).toStringAsFixed(2)} 秒',
                ),
                const SizedBox(height: 6),
                _InfoRow(
                  label: '音频时长',
                  value: '${result.audioDurationSec.toStringAsFixed(1)} 秒',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 源文件信息
        Card(
          elevation: 1,
          child: ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('源文件'),
            subtitle: Text(
              result.filePath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            await _copyToClipboard(context, result.transcript);
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('复制转写文本'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
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

/// 信息行组件
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
