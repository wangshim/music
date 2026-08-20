import 'dart:io';
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

/// 基于 sherpa-onnx 的本地离线中文语音转写服务。
///
/// 流程：平台通道解码任意音频 -> WAV(16k 单声道) -> sherpa-onnx 流式识别。
class AsrService {
  AsrService._();

  static final AsrService instance = AsrService._();

  /// 模型目录（flutter assets 内）
  static const String modelDir =
      'assets/models/sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23';

  /// 需要从 assets 解压的模型文件（相对 [modelDir]）
  static const List<String> modelFiles = [
    'encoder-epoch-99-avg-1.int8.onnx',
    'decoder-epoch-99-avg-1.int8.onnx',
    'joiner-epoch-99-avg-1.int8.onnx',
    'tokens.txt',
  ];

  /// 模型展示名
  static const String modelName = 'sherpa-onnx 流式 Zipformer 中文 14M (int8)';

  OnlineRecognizer? _recognizer;

  /// 解压后的模型目录（应用可写目录，非 assets 只读路径）
  String? _extractedDir;

  bool _bindingsInitialized = false;

  bool _initialized = false;

  /// 是否已初始化（模型可用）
  bool get isInitialized => _initialized;

  /// 初始化原生绑定并将 assets 内的模型文件解压到应用可写目录。
  ///
  /// sherpa-onnx 的 C++ 层需要真实文件路径；Android 上 Flutter assets
  /// 位于 APK 内部（assets/flutter_assets/...），不能直接作为文件读取，
  /// 因此必须先用 rootBundle 把模型字节解压到可写目录（如 cache），
  /// 再将解压后的路径传给 OnlineRecognizer。
  Future<void> init() async {
    if (_initialized) return;
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
  Future<String> _extractModelAssets() async {
    final cacheDir = Directory.systemTemp;
    final targetDir = Directory('${cacheDir.path}/audio_analyzer_models');
    await targetDir.create(recursive: true);

    for (final name in modelFiles) {
      final target = File('${targetDir.path}/$name');
      // 已存在且非空则复用（避免每次启动重复解压）
      if (target.existsSync() && target.lengthSync() > 0) continue;
      final data = await rootBundle.load('$modelDir/$name');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await target.writeAsBytes(bytes, flush: true);
    }
    return targetDir.path;
  }

  /// 将 assets 内相对路径解析为解压后可读的绝对路径
  String _resolve(String rel) => '$_extractedDir/$rel';

  OnlineRecognizer _buildRecognizer() {
    final model = OnlineModelConfig(
      tokens: _resolve('tokens.txt'),
      transducer: OnlineTransducerModelConfig(
        encoder: _resolve('encoder-epoch-99-avg-1.int8.onnx'),
        decoder: _resolve('decoder-epoch-99-avg-1.int8.onnx'),
        joiner: _resolve('joiner-epoch-99-avg-1.int8.onnx'),
      ),
      numThreads: 2,
      provider: 'cpu',
      debug: false,
    );
    final config = OnlineRecognizerConfig(
      feat: const FeatureConfig(sampleRate: 16000, featureDim: 80),
      model: model,
      decodingMethod: 'greedy_search',
      enableEndpoint: false,
      maxActivePaths: 4,
    );
    return OnlineRecognizer(config);
  }

  /// 转写一个音频文件（任意常见格式，平台通道负责解码）。
  ///
  /// [onProgress] 进度回调：百分比(0-100) + 当前已识别的部分文本。
  Future<AsrTranscription> transcribeFile(
    String filePath, {
    void Function(int percent, String partialText)? onProgress,
  }) async {
    await init();

    final loadWatch = Stopwatch()..start();
    _recognizer ??= _buildRecognizer();
    final recognizer = _recognizer!;
    loadWatch.stop();

    final decodeWatch = Stopwatch()..start();
    final wavPath = await AudioDecoder.decodeToWav(filePath);
    final wave = readWave(wavPath);
    decodeWatch.stop();
    if (wave.samples.isEmpty || wave.sampleRate <= 0) {
      throw Exception('音频解码失败：无法读取为可识别的 PCM 数据');
    }

    try {
      final transcribeWatch = Stopwatch()..start();
      final text = await _transcribeStreaming(
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

  /// 分块流式转写（每块 1 秒 16000 采样点）
  Future<String> _transcribeStreaming(
    OnlineRecognizer recognizer,
    Float32List samples,
    int sampleRate, {
    void Function(int percent, String partialText)? onProgress,
  }) async {
    final stream = recognizer.createStream();
    const int chunkSamples = 16000; // 1 秒
    final int total = samples.length;
    String lastText = '';

    for (int i = 0; i < total; i += chunkSamples) {
      final int end = (i + chunkSamples < total) ? i + chunkSamples : total;
      final chunk = Float32List.fromList(samples.sublist(i, end));
      stream.acceptWaveform(samples: chunk, sampleRate: sampleRate);
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      lastText = recognizer.getResult(stream).text;
      onProgress?.call(end * 100 ~/ total, lastText);
      // 让出事件循环，保证 UI 进度刷新
      await Future<void>.delayed(Duration.zero);
    }

    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    final finalText = recognizer.getResult(stream).text;
    onProgress?.call(100, finalText);
    return finalText;
  }
}
