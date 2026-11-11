import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'audio_decoder.dart';

/// 单次转写结果
class AsrTranscription {
  /// 完整转写文本
  final String text;

  /// 转写耗时（毫秒）
  final int elapsedMs;

  /// 模型名称
  final String modelName;

  /// 模型加载耗时（毫秒）
  final int loadMs;

  /// 音频时长（秒）
  final double audioDurationSec;

  const AsrTranscription({
    required this.text,
    required this.elapsedMs,
    required this.modelName,
    required this.loadMs,
    required this.audioDurationSec,
  });
}

/// 基于 sherpa-onnx SenseVoice（非流式）的本地离线语音转写服务。
///
/// 流程：平台通道解码任意音频 -> WAV(16k 单声道) -> sherpa-onnx
/// OfflineRecognizer 一次性识别（自带标点与逆文本规整）。
class AsrService {
  AsrService._();

  static final AsrService instance = AsrService._();

  /// 模型目录（flutter assets 内）
  static const String modelDir =
      'assets/models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17';

  /// 需要从 assets 解压的模型文件（相对 [modelDir]）
  static const List<String> modelFiles = [
    'model.int8.onnx',
    'tokens.txt',
  ];

  /// 模型展示名
  static const String modelName = 'SenseVoice-Small 中英日韩粤 (int8 · 非流式)';

  /// 解压缓存目录名（与旧流式模型缓存区分，避免读到不完整旧文件）
  static const String _cacheFolder = 'audio_analyzer_models_sensevoice';

  /// 单段最长秒数。SenseVoice 为短音频模型，超长音频按低能量点切段后
  /// 逐段离线识别再拼接，避免长音频内存膨胀与识别质量下降。
  static const int _maxSegmentSeconds = 25;

  /// 句末标点（用于跨段拼接时判断是否需要补标点）
  static final RegExp _punctEnd = RegExp(r'[，。！？；：、,.!?;:）】”"』」]$');

  OfflineRecognizer? _recognizer;

  /// 解压后的模型目录（应用可写目录，非 assets 只读路径）
  String? _extractedDir;

  bool _bindingsInitialized = false;

  bool _initialized = false;

  Future<void>? _initFuture;

  /// 是否已初始化（模型可用）
  bool get isInitialized => _initialized;

  /// 初始化原生绑定并将 assets 内的模型文件解压到应用可写目录。
  ///
  /// sherpa-onnx 的 C++ 层需要真实文件路径；Android 上 Flutter assets
  /// 位于 APK 内部（assets/flutter_assets/...），不能直接作为文件读取，
  /// 因此必须先用 rootBundle 把模型字节解压到可写目录（如 cache），
  /// 再将解压后的路径传给 OfflineRecognizer。
  Future<void> init() {
    if (_initialized) return Future<void>.value();
    final pending = _initFuture;
    if (pending != null) return pending;
    final future = _doInit().whenComplete(() {
      // 失败时允许下次重试
      if (!_initialized) _initFuture = null;
    });
    _initFuture = future;
    return future;
  }

  Future<void> _doInit() async {
    if (!_bindingsInitialized) {
      initBindings();
      _bindingsInitialized = true;
    }
    _extractedDir ??= await _extractModelAssets();
    if (_extractedDir == null || _extractedDir!.isEmpty) {
      throw Exception('模型文件解压失败');
    }
    _initialized = true;
  }

  /// 将 [modelDir] 下的模型文件解压到应用 cache 目录，返回目录路径。
  ///
  /// SenseVoice 的 int8 模型约 228MB，写入时按 8MB 分块落盘，
  /// 避免一次性再分配一份等大的内存。
  Future<String> _extractModelAssets() async {
    final targetDir = Directory('${Directory.systemTemp.path}/$_cacheFolder');
    await targetDir.create(recursive: true);

    for (final name in modelFiles) {
      final target = File('${targetDir.path}/$name');
      // 已存在且非空则复用（避免每次启动重复解压 228MB 模型）
      if (target.existsSync() && target.lengthSync() > 0) continue;

      final data = await rootBundle.load('$modelDir/$name');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      // 先写临时文件，写完整后再原子重命名：避免解压中途被杀进程留下
      // 半截文件，导致下次启动跳过解压却加载模型失败。
      final tmp = File('${target.path}.tmp');
      final raf = await tmp.open(mode: FileMode.write);
      try {
        const int chunkSize = 8 * 1024 * 1024;
        for (int offset = 0; offset < bytes.length; offset += chunkSize) {
          final int end = math.min(offset + chunkSize, bytes.length);
          await raf.writeFrom(bytes, offset, end);
        }
        await raf.flush();
      } finally {
        await raf.close();
      }
      await tmp.rename(target.path);
    }
    return targetDir.path;
  }

  /// 将 assets 内相对路径解析为解压后可读的绝对路径
  String _resolve(String rel) => '$_extractedDir/$rel';

  /// 按 CPU 核心数选择解码线程数（2~4，兼顾速度与功耗）
  int _resolveThreads() {
    final int cores = Platform.numberOfProcessors;
    if (cores <= 2) return 2;
    if (cores >= 4) return 4;
    return cores;
  }

  OfflineRecognizer _buildRecognizer() {
    final model = OfflineModelConfig(
      senseVoice: OfflineSenseVoiceModelConfig(
        model: _resolve('model.int8.onnx'),
        language: 'zh',
        // 开启逆文本规整：输出标点、阿拉伯数字等更自然的书面文本
        useInverseTextNormalization: true,
      ),
      tokens: _resolve('tokens.txt'),
      numThreads: _resolveThreads(),
      provider: 'cpu',
      debug: false,
    );
    final config = OfflineRecognizerConfig(
      feat: const FeatureConfig(sampleRate: 16000, featureDim: 80),
      model: model,
      decodingMethod: 'greedy_search',
    );
    return OfflineRecognizer(config);
  }

  /// 转写一个音频文件（任意常见格式，平台通道负责解码）。
  ///
  /// [onProgress] 进度回调：百分比(0-100) + 当前已识别的部分文本
  /// （非流式识别没有中间结果，识别过程中 partialText 为已完成段落文本）。
  Future<AsrTranscription> transcribeFile(
    String filePath, {
    void Function(int percent, String partialText)? onProgress,
  }) async {
    await init();
    onProgress?.call(3, '');

    final loadWatch = Stopwatch()..start();
    _recognizer ??= _buildRecognizer();
    final recognizer = _recognizer!;
    loadWatch.stop();
    onProgress?.call(8, '');

    final wavPath = await AudioDecoder.decodeToWav(filePath);
    try {
      final wave = readWave(wavPath);
      if (wave.samples.isEmpty || wave.sampleRate <= 0) {
        throw Exception('音频解码失败：无法读取为可识别的 PCM 数据');
      }
      onProgress?.call(15, '');

      final transcribeWatch = Stopwatch()..start();
      final text = await _transcribeOffline(
        recognizer,
        wave.samples,
        wave.sampleRate,
        onProgress: onProgress,
      );
      transcribeWatch.stop();

      return AsrTranscription(
        text: text.trim(),
        elapsedMs: transcribeWatch.elapsedMilliseconds,
        modelName: modelName,
        loadMs: loadWatch.elapsedMilliseconds,
        audioDurationSec: wave.samples.length / wave.sampleRate,
      );
    } finally {
      // 清理平台解码产生的临时 wav
      try {
        if (File(wavPath).existsSync()) File(wavPath).deleteSync();
      } catch (_) {}
    }
  }

  /// 非流式整段识别：短音频一次识别，长音频切段后逐段识别并拼接。
  Future<String> _transcribeOffline(
    OfflineRecognizer recognizer,
    Float32List samples,
    int sampleRate, {
    void Function(int percent, String partialText)? onProgress,
  }) async {
    final List<Float32List> segments = _splitSegments(samples, sampleRate);
    final List<String> parts = [];

    for (int i = 0; i < segments.length; i++) {
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: segments[i], sampleRate: sampleRate);
        recognizer.decode(stream);
        final String part = recognizer.getResult(stream).text.trim();
        if (part.isNotEmpty) parts.add(part);
      } finally {
        stream.free();
      }
      onProgress?.call(
        15 + ((i + 1) * 85 ~/ segments.length),
        _mergeSegments(parts),
      );
      // 让出事件循环，保证 UI 进度刷新
      await Future<void>.delayed(Duration.zero);
    }

    final text = _mergeSegments(parts);
    onProgress?.call(100, text);
    return text;
  }

  /// 按最长 [_maxSegmentSeconds] 秒切段，切点尽量落在低能量（静音）处，
  /// 减少把词句切断的概率。
  List<Float32List> _splitSegments(Float32List samples, int sampleRate) {
    final int maxLen = sampleRate * _maxSegmentSeconds;
    if (samples.length <= maxLen) return <Float32List>[samples];

    final List<Float32List> out = [];
    int start = 0;
    while (start < samples.length) {
      int end = math.min(start + maxLen, samples.length);
      if (end < samples.length) {
        final int quiet = _quietCut(samples, end - sampleRate ~/ 2, end);
        if (quiet > start + sampleRate * 2) end = quiet;
      }
      out.add(Float32List.sublistView(samples, start, end));
      start = end;
    }
    return out;
  }

  /// 在 [from, to) 区间内寻找 100ms 能量最低的窗口，返回窗口中心位置。
  int _quietCut(Float32List samples, int from, int to) {
    const int win = 1600; // 100ms @16k
    if (from < 0) from = 0;
    int bestPos = to;
    double bestEnergy = double.infinity;
    for (int p = from; p + win <= to; p += win) {
      double energy = 0;
      for (int i = p; i < p + win; i++) {
        energy += samples[i] * samples[i];
      }
      if (energy < bestEnergy) {
        bestEnergy = energy;
        bestPos = p + win ~/ 2;
      }
    }
    return bestPos;
  }

  /// 拼接分段文本：上段已有句末标点则直接连接，否则中文补逗号、西文补空格。
  String _mergeSegments(List<String> parts) {
    if (parts.isEmpty) return '';
    final buffer = StringBuffer();
    for (final String part in parts) {
      if (part.isEmpty) continue;
      if (buffer.isEmpty) {
        buffer.write(part);
        continue;
      }
      final String acc = buffer.toString();
      final String last = acc.substring(acc.length - 1);
      if (_punctEnd.hasMatch(last)) {
        buffer.write(part);
      } else {
        final int code = last.codeUnitAt(0);
        final bool isCjk = code >= 0x4E00 && code <= 0x9FFF;
        buffer.write(isCjk ? '，' : ' ');
        buffer.write(part);
      }
    }
    return buffer.toString();
  }
}
