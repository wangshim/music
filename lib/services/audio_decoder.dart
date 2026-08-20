import 'package:flutter/services.dart';

/// 与原生层交互的通道封装：
/// 1. 获取 flutter_assets 根路径（sherpa-onnx C API 需要真实文件路径）；
/// 2. 将任意音频文件解码为 16kHz 单声道 WAV（供 readWave 读取）。
class AudioDecoder {
  static const MethodChannel _channel =
      MethodChannel('audio_analyzer_app/audio');

  AudioDecoder._();

  /// 获取 flutter_assets 根目录（Android: dataDir，iOS: bundle 路径）
  static Future<String?> getFlutterAssetsRoot() async {
    try {
      return await _channel.invokeMethod<String>('getFlutterAssetsRoot');
    } catch (_) {
      return null;
    }
  }

  /// 将 [path] 指向的音频解码为 16kHz 单声道 WAV 临时文件，返回其路径。
  static Future<String> decodeToWav(String path) async {
    final result =
        await _channel.invokeMethod<String>('decodeAudio', {'path': path});
    if (result == null || result.isEmpty) {
      throw Exception('原生解码失败，未返回 WAV 路径');
    }
    return result;
  }
}
