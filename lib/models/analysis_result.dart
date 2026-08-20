import '../services/asr_service.dart';

/// 音频分析结果（转写为真实 ASR 数据，BPM/调性暂为占位，后续接入分析引擎）。
class AnalysisResult {
  /// 被分析的音频文件路径
  final String filePath;

  /// 转写文字（真实本地 ASR 输出）
  final String transcript;

  /// BPM（占位）
  final int bpm;

  /// 调性（占位）
  final String key;

  /// ASR 模型名称
  final String modelName;

  /// 转写耗时（毫秒）
  final int elapsedMs;

  /// 模型加载耗时（毫秒）
  final int loadMs;

  /// 音频时长（秒）
  final double audioDurationSec;

  const AnalysisResult({
    required this.filePath,
    required this.transcript,
    required this.bpm,
    required this.key,
    required this.modelName,
    required this.elapsedMs,
    required this.loadMs,
    required this.audioDurationSec,
  });

  /// 由 ASR 转写结果构造（BPM/调性保持占位）。
  factory AnalysisResult.fromAsr(AsrTranscription asr, String filePath) {
    return AnalysisResult(
      filePath: filePath,
      transcript: asr.text.isEmpty ? '（未识别到语音内容）' : asr.text,
      bpm: 0,
      key: '待分析',
      modelName: asr.modelName,
      elapsedMs: asr.elapsedMs,
      loadMs: asr.loadMs,
      audioDurationSec: asr.audioDurationSec,
    );
  }

  /// 生成一组占位结果，仅用于界面演示。
  factory AnalysisResult.placeholder(String filePath) {
    return AnalysisResult(
      filePath: filePath,
      transcript:
          '（占位内容）这是音频转写结果的示例文本。'
          '后续接入本地语音识别引擎后，此处将显示音频中的完整文字内容。',
      bpm: 120,
      key: 'C 大调 / A 小调',
      modelName: '占位模型',
      elapsedMs: 0,
      loadMs: 0,
      audioDurationSec: 0,
    );
  }
}
