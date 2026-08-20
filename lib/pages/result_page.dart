import 'package:flutter/material.dart';

import '../models/analysis_result.dart';

/// 结果展示页：文字转写（真实 ASR）+ BPM + 调性（占位）+ 耗时/模型信息
class ResultPage extends StatelessWidget {
  final AnalysisResult result;

  const ResultPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('分析结果'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 指标卡片：BPM / 调性（占位）
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.speed_rounded,
                  label: 'BPM',
                  value: result.bpm > 0 ? '${result.bpm}' : '待分析',
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  icon: Icons.music_note_rounded,
                  label: '调性',
                  value: result.key,
                  color: colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                        '文字转写',
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
                  _InfoRow(label: '转写耗时', value: '${(result.elapsedMs / 1000).toStringAsFixed(2)} 秒'),
                  const SizedBox(height: 6),
                  _InfoRow(label: '模型加载', value: '${(result.loadMs / 1000).toStringAsFixed(2)} 秒'),
                  const SizedBox(height: 6),
                  _InfoRow(label: '音频时长', value: '${result.audioDurationSec.toStringAsFixed(1)} 秒'),
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
          // 导出占位按钮（后续接入导出能力）
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('导出功能开发中，敬请期待')),
              );
            },
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('导出分析报告'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'BPM / 调性待接入分析引擎',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

/// 指标卡片组件
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
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
