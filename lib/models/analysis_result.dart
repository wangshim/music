import '../services/asr_service.dart';

/// 音频分析结果。
///
/// 两种模式：
/// - 歌词模式（[isLyrics] = true）：识曲 + 拉取纯文本歌词（不展示歌曲信息）
/// - ASR 转写模式（[isLyrics] = false）：识曲失败后的本地语音转写兜底
class AnalysisResult {
  /// 被分析的音频文件路径
  final String filePath;

  /// 是否为歌词模式（true：纯歌词；false：ASR 转写）
  final bool isLyrics;

  /// 纯文本歌词（歌词模式）
  final String lyrics;

  /// 转写文字（ASR 模式）
  final String transcript;

  /// 歌词/转写耗时（毫秒）
  final int elapsedMs;

  /// 音频时长（秒）
  final double audioDurationSec;

  /// ASR 模型名称（ASR 模式）
  final String modelName;

  /// 歌词来源描述（内部调试用，不展示给用户）
  final String lyricsSource;

  const AnalysisResult({
    required this.filePath,
    required this.isLyrics,
    required this.lyrics,
    required this.transcript,
    required this.elapsedMs,
    required this.audioDurationSec,
    required this.modelName,
    required this.lyricsSource,
  });

  /// 由歌词识别结果构造（歌词模式）。
  factory AnalysisResult.fromLyrics({
    required String filePath,
    required String lyrics,
    required int elapsedMs,
    required double audioDurationSec,
    required String lyricsSource,
  }) {
    return AnalysisResult(
      filePath: filePath,
      isLyrics: true,
      lyrics: lyrics,
      transcript: '',
      elapsedMs: elapsedMs,
      audioDurationSec: audioDurationSec,
      modelName: '',
      lyricsSource: lyricsSource,
    );
  }

  /// 由 ASR 转写结果构造（ASR 兜底模式）。
  factory AnalysisResult.fromAsr(AsrTranscription asr, String filePath) {
    return AnalysisResult(
      filePath: filePath,
      isLyrics: false,
      lyrics: '',
      transcript: asr.text.isEmpty ? '（未识别到语音内容）' : asr.text,
      elapsedMs: asr.elapsedMs,
      audioDurationSec: asr.audioDurationSec,
      modelName: asr.modelName,
      lyricsSource: '',
    );
  }
}
