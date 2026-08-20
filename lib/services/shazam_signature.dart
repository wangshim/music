/// Shazam 音频指纹签名生成（Dart 移植）。
///
/// 算法移植自 shazamio（Python）的 SignatureGenerator / DecodedMessage：
/// - 输入：16kHz 单声道 16-bit PCM 样本
/// - 2048 点环形缓冲 + 128 样本滑窗 + 2048 点 FFT（1025 个 bin）
/// - 峰值识别分为 4 个频段，legacy 模式仅使用 0/1/2（3.5K-5.5K 不使用）
/// - 签名编码为 Shazam 私有二进制格式（CRC32 头 + TLV 频段峰值）
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// 环形缓冲（对齐 shazamio RingBuffer 语义）
class RingBuffer<T> {
  final List<T> _data;

  /// 下一个写入位置
  int position;

  /// 已写入元素个数
  int numWritten;

  RingBuffer(int size, T defaultValue)
      : _data = List<T>.filled(size, defaultValue),
        position = 0,
        numWritten = 0;

  /// 负索引语义与 Python 列表一致（-1 表示最后一个元素）
  T operator [](int index) {
    final i = index % _data.length;
    return _data[i < 0 ? i + _data.length : i];
  }

  void operator []=(int index, T value) {
    final i = index % _data.length;
    _data[i < 0 ? i + _data.length : i] = value;
  }

  void append(T value) {
    _data[position] = value;
    position = (position + 1) % _data.length;
    numWritten++;
  }
}

/// 频率峰
class FrequencyPeak {
  final int fftPassNumber;
  final int peakMagnitude;
  final int correctedPeakFrequencyBin;
  final int sampleRateHz;

  const FrequencyPeak(
    this.fftPassNumber,
    this.peakMagnitude,
    this.correctedPeakFrequencyBin,
    this.sampleRateHz,
  );
}

/// 解码后的签名消息（可编码为 Shazam 二进制/URI）
class DecodedMessage {
  final int sampleRateHz;
  int numberSamples;

  /// 频段 id -> 频率峰列表（频段 0/1/2）
  final Map<int, List<FrequencyPeak>> frequencyBandToSoundPeaks;

  DecodedMessage({
    required this.sampleRateHz,
    this.numberSamples = 0,
    Map<int, List<FrequencyPeak>>? frequencyBandToSoundPeaks,
  }) : frequencyBandToSoundPeaks = frequencyBandToSoundPeaks ?? {};

  int get totalPeaks =>
      frequencyBandToSoundPeaks.values.fold(0, (s, l) => s + l.length);

  /// 编码为 Shazam 私有二进制签名
  Uint8List encodeToBinary() {
    final contents = BytesBuilder();

    // 频带排序（0/1/2 升序），峰按 fft_pass 升序
    final bands = frequencyBandToSoundPeaks.keys.toList()..sort();
    for (final band in bands) {
      final peaks = frequencyBandToSoundPeaks[band]!.toList()
        ..sort((a, b) => a.fftPassNumber.compareTo(b.fftPassNumber));
      if (peaks.isEmpty) continue;

      final peaksBuf = BytesBuilder();
      var fftPassNumber = 0;
      for (final p in peaks) {
        assert(p.fftPassNumber >= fftPassNumber);
        if (p.fftPassNumber - fftPassNumber >= 255) {
          peaksBuf.addByte(0xFF);
          peaksBuf.add(_le32(p.fftPassNumber));
          fftPassNumber = p.fftPassNumber;
        }
        peaksBuf.addByte(p.fftPassNumber - fftPassNumber);
        peaksBuf.add(_le16(p.peakMagnitude));
        peaksBuf.add(_le16(p.correctedPeakFrequencyBin));
        fftPassNumber = p.fftPassNumber;
      }

      final peaksBytes = peaksBuf.toBytes();
      contents.add(_le32(0x60030040 + band));
      contents.add(_le32(peaksBytes.length));
      contents.add(peaksBytes);
      // 4 字节对齐 padding
      final padding = (-peaksBytes.length) % 4;
      if (padding > 0) contents.add(Uint8List(padding));
    }

    final contentsBytes = contents.toBytes();
    final sizeMinusHeader = contentsBytes.length + 8;

    // Header: 12 x uint32 LE = 48 字节
    final header = BytesBuilder();
    header.add(_le32(0xCAFE2580)); // magic1
    header.add(_le32(0)); // crc32（占位，最后回填）
    header.add(_le32(sizeMinusHeader));
    header.add(_le32(0x94119C00)); // magic2
    header.add(_le32(0)); // void1
    header.add(_le32(0)); // void1
    header.add(_le32(0)); // void1
    header.add(_le32(3 << 27)); // shifted_sample_rate_id = 0x18000000
    header.add(_le32(0)); // void2
    header.add(_le32(0)); // void2
    header.add(_le32(
      numberSamples + (sampleRateHz * 0.24).round(),
    )); // number_samples_plus_divided_sample_rate
    header.add(_le32((15 << 19) + 0x40000)); // fixed_value = 0x7C0000

    final body = BytesBuilder();
    body.add(header.toBytes());
    body.add(_le32(0x40000000));
    body.add(_le32(sizeMinusHeader));
    body.add(contentsBytes);

    final result = body.toBytes();
    // CRC-32 覆盖 offset 8 至末尾
    final crc = crc32(result.sublist(8));
    result.setRange(4, 8, _le32(crc));
    return result;
  }

  /// 编码为 data URI（用于 Shazam 识别请求）
  String encodeToUri() =>
      'data:audio/vnd.shazam.sig;base64,${base64Encode(encodeToBinary())}';
}

/// CRC-32 (IEEE 802.3，与 Python binascii.crc32 一致)
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[i] = c & 0xFFFFFFFF;
  }
  return table;
}

Uint8List _le16(int v) => Uint8List(2)
  ..[0] = v & 0xFF
  ..[1] = (v >> 8) & 0xFF;

Uint8List _le32(int v) => Uint8List(4)
  ..[0] = v & 0xFF
  ..[1] = (v >> 8) & 0xFF
  ..[2] = (v >> 16) & 0xFF
  ..[3] = (v >> 24) & 0xFF;

/// 2048 点 FFT 的旋转因子（预计算）
class _Twiddles {
  static const int n = 2048;
  static final Float64List re = _buildRe();
  static final Float64List im = _buildIm();

  static Float64List _buildRe() {
    final r = Float64List(n ~/ 2);
    for (var i = 0; i < n ~/ 2; i++) {
      r[i] = math.cos(-2 * math.pi * i / n);
    }
    return r;
  }

  static Float64List _buildIm() {
    final r = Float64List(n ~/ 2);
    for (var i = 0; i < n ~/ 2; i++) {
      r[i] = math.sin(-2 * math.pi * i / n);
    }
    return r;
  }
}

/// 对 2048 个实数做 rfft，返回 1025 个功率值 ((re^2+im^2)/(1<<17)，下限 1e-10)
Float64List rfftPower2048(List<double> input) {
  final re = Float64List(2048);
  final im = Float64List(2048);
  for (var i = 0; i < 2048; i++) {
    re[i] = input[i];
  }
  _fft2048(re, im);

  final out = Float64List(1025);
  for (var i = 0; i < 1025; i++) {
    final p = (re[i] * re[i] + im[i] * im[i]) / (1 << 17);
    out[i] = p < 1e-10 ? 1e-10 : p;
  }
  return out;
}

/// 2048 点迭代 radix-2 FFT（就地）
void _fft2048(Float64List re, Float64List im) {
  const n = 2048;
  // bit reversal
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  // butterflies
  for (var len = 2; len <= n; len <<= 1) {
    final half = len >> 1;
    final step = n ~/ len;
    for (var i = 0; i < n; i += len) {
      for (var j = i, k = 0; j < i + half; j++, k += step) {
        final wr = _Twiddles.re[k];
        final wi = _Twiddles.im[k];
        final tr = re[j + half] * wr - im[j + half] * wi;
        final ti = re[j + half] * wi + im[j + half] * wr;
        re[j + half] = re[j] - tr;
        im[j + half] = im[j] - ti;
        re[j] += tr;
        im[j] += ti;
      }
    }
  }
}

/// Hanning 窗口（np.hanning(2050)[1:-1] = 2048 个，去除首尾零值）
final List<double> _hanning2048 = _buildHanning();

List<double> _buildHanning() {
  final out = List<double>.filled(2048, 0);
  for (var i = 0; i < 2048; i++) {
    // np.hanning(n): 0.5 - 0.5*cos(2*pi*i/(n-1))，n=2050，i 取 1..2048
    out[i] = 0.5 - 0.5 * math.cos(2 * math.pi * (i + 1) / 2049);
  }
  return out;
}

/// Shazam 签名生成器（对齐 shazamio SignatureGenerator）
class SignatureGenerator {
  final List<int> _inputPendingProcessing = [];
  int _samplesProcessed = 0;

  RingBuffer<int> _ringBufferOfSamples = RingBuffer<int>(2048, 0);
  RingBuffer<Float64List> _fftOutputs =
      RingBuffer<Float64List>(256, Float64List(1025));
  RingBuffer<Float64List> _spreadFftOutput =
      RingBuffer<Float64List>(256, Float64List(1025));

  /// 单次签名覆盖的最大时长（秒）
  double maxTimeSeconds = 3.1;

  /// 单次签名最大峰数
  int maxPeaks = 255;

  final DecodedMessage _nextSignature = DecodedMessage(sampleRateHz: 16000);

  /// 输入 16-bit 16kHz 单声道 PCM 样本
  void feedInput(List<int> s16leMonoSamples) {
    _inputPendingProcessing.addAll(s16leMonoSamples);
  }

  /// 跳过开头 [seconds] 秒（用于长音频取中间片段）
  void skipBeginning(double seconds) {
    _samplesProcessed += (16000 * seconds).round();
  }

  /// 消费样本生成一个签名；样本不足时返回 null
  DecodedMessage? getNextSignature() {
    if (_inputPendingProcessing.length - _samplesProcessed < 128) return null;

    while (_inputPendingProcessing.length - _samplesProcessed >= 128 &&
        (_nextSignature.numberSamples / _nextSignature.sampleRateHz <
                maxTimeSeconds ||
            _nextSignature.totalPeaks < maxPeaks)) {
      _processInput(_inputPendingProcessing.sublist(
        _samplesProcessed,
        _samplesProcessed + 128,
      ));
      _samplesProcessed += 128;
    }

    // 重置缓冲，准备下一个签名
    _ringBufferOfSamples = RingBuffer<int>(2048, 0);
    _fftOutputs = RingBuffer<Float64List>(256, Float64List(1025));
    _spreadFftOutput = RingBuffer<Float64List>(256, Float64List(1025));

    return _nextSignature;
  }

  void _processInput(List<int> samples) {
    _nextSignature.numberSamples += samples.length;
    for (var i = 0; i < samples.length; i += 128) {
      _doFft(samples.sublist(i, i + 128));
      _doPeakSpreadingAndRecognition();
    }
  }

  void _doFft(List<int> batchOf128) {
    final pos = _ringBufferOfSamples.position;
    for (var i = 0; i < batchOf128.length; i++) {
      _ringBufferOfSamples[pos + i] = batchOf128[i];
    }
    _ringBufferOfSamples.position = (pos + batchOf128.length) % 2048;
    _ringBufferOfSamples.numWritten += batchOf128.length;

    // 从当前位置开始环形取 2048 个样本
    final excerpt = Float64List(2048);
    for (var i = 0; i < 2048; i++) {
      excerpt[i] =
          _ringBufferOfSamples[(_ringBufferOfSamples.position + i) % 2048]
              .toDouble();
    }
    // 加窗
    final windowed = Float64List(2048);
    for (var i = 0; i < 2048; i++) {
      windowed[i] = excerpt[i] * _hanning2048[i];
    }

    _fftOutputs.append(rfftPower2048(windowed));
  }

  void _doPeakSpreadingAndRecognition() {
    _doPeakSpreading();
    if (_spreadFftOutput.numWritten >= 46) {
      _doPeakRecognition();
    }
  }

  void _doPeakSpreading() {
    final originLastFft = _fftOutputs[_fftOutputs.position - 1];

    // temporary_array_1 = tile(origin,3).reshape(3,-1)，逐行 roll -1/-2 后按列取 max
    // max(axis=0)[:-3] 只取前 1022 列，尾部 3 列直接用 origin 值
    final originLastNp = Float64List(1025);
    for (var i = 0; i < 1022; i++) {
      final a = originLastFft[i];
      final b = originLastFft[i + 1];
      final c = originLastFft[i + 2];
      originLastNp[i] = a > b ? (a > c ? a : c) : (b > c ? b : c);
    }
    originLastNp[1022] = originLastFft[1022];
    originLastNp[1023] = originLastFft[1023];
    originLastNp[1024] = originLastFft[1024];

    final i1 = (_spreadFftOutput.position - 1) % 256;
    final i2 = (_spreadFftOutput.position - 3) % 256;
    final i3 = (_spreadFftOutput.position - 6) % 256;
    final s1 = _spreadFftOutput[i1];
    final s2 = _spreadFftOutput[i2];
    final s3 = _spreadFftOutput[i3];

    final n1 = Float64List(1025);
    final n2 = Float64List(1025);
    final n3 = Float64List(1025);
    for (var i = 0; i < 1025; i++) {
      final o = originLastNp[i];
      final v1 = o > s1[i] ? o : s1[i];
      n1[i] = v1;
      final v2 = v1 > s2[i] ? v1 : s2[i];
      n2[i] = v2;
      n3[i] = v2 > s3[i] ? v2 : s3[i];
    }
    _spreadFftOutput[i1] = n1;
    _spreadFftOutput[i2] = n2;
    _spreadFftOutput[i3] = n3;
    _spreadFftOutput.append(originLastNp);
  }

  void _doPeakRecognition() {
    final fftMinus46 = _fftOutputs[(_fftOutputs.position - 46) % 256];
    final fftMinus49 =
        _spreadFftOutput[(_spreadFftOutput.position - 49) % 256];

    for (var bin = 10; bin < 1015; bin++) {
      if (fftMinus46[bin] >= 1 / 64 && fftMinus46[bin] >= fftMinus49[bin - 1]) {
        // 频域局部最大值
        var maxNeighbor = 0.0;
        for (final off in const [-10, -7, -4, -3, 1, 2, 5, 8]) {
          final v = fftMinus49[bin + off];
          if (v > maxNeighbor) maxNeighbor = v;
        }
        if (fftMinus46[bin] > maxNeighbor) {
          // 时域局部最大值
          var maxOther = maxNeighbor;
          for (final off in const [
            -53,
            -45,
            165,
            172,
            179,
            186,
            193,
            200,
            214,
            221,
            228,
            235,
            242,
            249,
          ]) {
            final v = _spreadFftOutput[(_spreadFftOutput.position + off) % 256]
                [bin - 1];
            if (v > maxOther) maxOther = v;
          }
          if (fftMinus46[bin] > maxOther) {
            final fftNumber = _spreadFftOutput.numWritten - 46;
            final peakMagnitude =
                math.log(math.max(1 / 64, fftMinus46[bin])) * 1477.3 + 6144;
            final peakMagnitudeBefore =
                math.log(math.max(1 / 64, fftMinus46[bin - 1])) * 1477.3 + 6144;
            final peakMagnitudeAfter =
                math.log(math.max(1 / 64, fftMinus46[bin + 1])) * 1477.3 + 6144;

            final peakVariation1 = peakMagnitude * 2 -
                peakMagnitudeBefore -
                peakMagnitudeAfter;
            final peakVariation2 =
                (peakMagnitudeAfter - peakMagnitudeBefore) * 32 / peakVariation1;

            final correctedPeakFrequencyBin =
                bin * 64 + peakVariation2;
            final frequencyHz =
                correctedPeakFrequencyBin * (16000 / 2 / 1024 / 64);

            int band;
            if (frequencyHz > 250 && frequencyHz < 520) {
              band = 0;
            } else if (frequencyHz > 520 && frequencyHz < 1450) {
              band = 1;
            } else if (frequencyHz > 1450 && frequencyHz < 3500) {
              band = 2;
            } else if (frequencyHz > 5500 && frequencyHz <= 5500) {
              band = 3; // 永不成立（legacy 模式不使用 3.5K-5.5K），保持与 shazamio 一致
            } else {
              continue;
            }

            _nextSignature.frequencyBandToSoundPeaks.putIfAbsent(
              band,
              () => <FrequencyPeak>[],
            ).add(FrequencyPeak(
              fftNumber,
              peakMagnitude.toInt(),
              correctedPeakFrequencyBin.toInt(),
              16000,
            ));
          }
        }
      }
    }
  }
}
