import 'dart:io';
import 'dart:typed_data';

/// WAV 解析结果：16kHz 单声道 16-bit PCM
class WavPcm {
  /// 原始采样率（解析自 fmt chunk）
  final int sourceSampleRate;

  /// 原始声道数
  final int sourceChannels;

  /// 输出样本（16-bit 有符号，-32768..32767）
  final List<int> samples16;

  /// 输出采样率（恒为 16000）
  final int sampleRate = 16000;

  double get durationSeconds => samples16.length / sampleRate;

  WavPcm({
    required this.sourceSampleRate,
    required this.sourceChannels,
    required this.samples16,
  });
}

/// 解析 WAV 文件为 16kHz 单声道 PCM16。
///
/// 支持：8/16/24/32-bit PCM、32-bit float；自动混音为单声道、
/// 线性重采样到 16000Hz。音轨极短时前置补零到至少 1 秒，保证
/// Shazam 签名生成器能产出有效样本。
WavPcm parseWavToPcm16(String wavPath) {
  final bytes = File(wavPath).readAsBytesSync();
  if (bytes.length < 44) {
    throw Exception('WAV 文件不完整（不足 44 字节）');
  }
  if (_ascii(bytes, 0, 4) != 'RIFF' || _ascii(bytes, 8, 4) != 'WAVE') {
    throw Exception('不是有效的 WAV 文件（RIFF/WAVE 头缺失）');
  }

  var offset = 12;
  int? fmtChunkOffset;
  int? dataChunkOffset;
  int? dataChunkLength;

  while (offset + 8 <= bytes.length) {
    final chunkId = _ascii(bytes, offset, 4);
    final chunkSize = bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    if (chunkId == 'fmt ') {
      fmtChunkOffset = offset + 8;
    } else if (chunkId == 'data') {
      dataChunkOffset = offset + 8;
      dataChunkLength = chunkSize;
      break;
    }
    offset += 8 + chunkSize + (chunkSize & 1); // 偶数对齐
  }

  if (fmtChunkOffset == null || dataChunkOffset == null) {
    throw Exception('WAV 缺少 fmt/data chunk');
  }
  final audioFormat =
      _u16(bytes, fmtChunkOffset); // 1=PCM, 3=float, 0xFFFE=extensible
  final channels = _u16(bytes, fmtChunkOffset + 2);
  final sampleRate = _u32(bytes, fmtChunkOffset + 4);
  final bitsPerSample = _u16(bytes, fmtChunkOffset + 14);
  if (channels == 0 || sampleRate <= 0) {
    throw Exception('WAV 参数无效（channels=$channels, rate=$sampleRate）');
  }

  var fmt = audioFormat;
  if (fmt == 0xFFFE) {
    // extensible：subformat GUID 前两字节为真实格式
    final extFmtOffset = fmtChunkOffset + 24;
    if (extFmtOffset + 2 <= bytes.length) {
      fmt = _u16(bytes, extFmtOffset);
    }
  }
  if (fmt != 1 && fmt != 3) {
    throw Exception('不支持的 WAV 编码格式: $fmt（仅支持 PCM/float）');
  }

  final dataLen = dataChunkLength != null
      ? (dataChunkLength < bytes.length - dataChunkOffset
          ? dataChunkLength
          : bytes.length - dataChunkOffset)
      : bytes.length - dataChunkOffset;

  final bytesPerSample = (bitsPerSample / 8).ceil();
  final frameCount = dataLen ~/ (bytesPerSample * channels);

  // 解码为多声道浮点样本
  final interleaved = Float32List(frameCount * channels);
  for (var i = 0; i < frameCount * channels; i++) {
    final pos = dataChunkOffset + i * bytesPerSample;
    double v;
    if (fmt == 3) {
      // 32-bit float
      v = ByteData.sublistView(bytes, pos, pos + 4).getFloat32(0, Endian.little);
    } else {
      switch (bitsPerSample) {
        case 8:
          v = (bytes[pos] - 128) / 128.0;
        case 16:
          v = ByteData.sublistView(bytes, pos, pos + 2)
                  .getInt16(0, Endian.little) /
              32768.0;
        case 24:
          final raw = bytes[pos] |
              (bytes[pos + 1] << 8) |
              (bytes[pos + 2] << 16);
          v = (raw >= 0x800000 ? raw - 0x1000000 : raw) / 8388608.0;
        case 32:
          v = ByteData.sublistView(bytes, pos, pos + 4)
                  .getInt32(0, Endian.little) /
              2147483648.0;
        default:
          throw Exception('不支持的位深: $bitsPerSample');
      }
    }
    interleaved[i] = v.clamp(-1.0, 1.0);
  }

  // 混音为单声道
  final mono = Float32List(frameCount);
  if (channels == 1) {
    for (var i = 0; i < frameCount; i++) {
      mono[i] = interleaved[i];
    }
  } else {
    for (var i = 0; i < frameCount; i++) {
      var sum = 0.0;
      for (var c = 0; c < channels; c++) {
        sum += interleaved[i * channels + c];
      }
      mono[i] = sum / channels;
    }
  }

  // 重采样到 16000（线性插值）
  final Float32List resampled;
  if (sampleRate == 16000) {
    resampled = mono;
  } else {
    final ratio = sampleRate / 16000.0;
    final outLen = (frameCount / ratio).floor();
    resampled = Float32List(outLen);
    for (var i = 0; i < outLen; i++) {
      final srcPos = i * ratio;
      final idx = srcPos.floor();
      final frac = srcPos - idx;
      if (idx + 1 < frameCount) {
        resampled[i] = mono[idx] * (1 - frac) + mono[idx + 1] * frac;
      } else {
        resampled[i] = mono[idx];
      }
    }
  }

  // 转 16-bit，过短时补零到至少 1 秒
  final minSamples = 16000;
  final outLen = resampled.length < minSamples ? minSamples : resampled.length;
  final samples16 = Int16List(outLen);
  for (var i = 0; i < resampled.length; i++) {
    samples16[i] = (resampled[i] * 32767).round().clamp(-32768, 32767);
  }
  // 剩余部分保持 0

  return WavPcm(
    sourceSampleRate: sampleRate,
    sourceChannels: channels,
    samples16: samples16.toList(),
  );
}

String _ascii(Uint8List b, int start, int len) =>
    String.fromCharCodes(b.sublist(start, start + len));

int _u16(Uint8List b, int offset) =>
    b[offset] | (b[offset + 1] << 8);

int _u32(Uint8List b, int offset) =>
    b[offset] | (b[offset + 1] << 8) | (b[offset + 2] << 16) | (b[offset + 3] << 24);
