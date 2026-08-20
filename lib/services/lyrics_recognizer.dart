import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'shazam_signature.dart';
import 't2s.dart';
import 'wav_utils.dart';

/// 识别结果（歌曲信息仅在内部使用，不展示给用户）
class RecognizeResult {
  final bool matched;
  final String? title;
  final String? artist;
  final String? error;

  const RecognizeResult.matched({required this.title, required this.artist})
      : matched = true,
        error = null;

  const RecognizeResult.failed(this.error) : matched = false, title = null, artist = null;
}

/// 识曲 + 歌词最终结果
class LyricsOutcome {
  /// 是否成功拿到纯文本歌词
  final bool matched;

  /// 最终纯文本歌词（简体，无时间轴）；失败时为 null
  final String? lyrics;

  /// 来源描述（用于调试）
  final String source;

  /// 中文错误说明（失败时）
  final String? error;

  /// 总耗时（毫秒）
  final int elapsedMs;

  const LyricsOutcome._({
    required this.matched,
    required this.lyrics,
    required this.source,
    required this.error,
    required this.elapsedMs,
  });

  factory LyricsOutcome.ok({
    required String lyrics,
    required String source,
    required int elapsedMs,
  }) {
    return LyricsOutcome._(
      matched: true,
      lyrics: lyrics,
      source: source,
      error: null,
      elapsedMs: elapsedMs,
    );
  }

  factory LyricsOutcome.fail(String error, {int elapsedMs = 0}) {
    return LyricsOutcome._(
      matched: false,
      lyrics: null,
      source: '',
      error: error,
      elapsedMs: elapsedMs,
    );
  }
}

/// 识曲 + 歌词服务
///
/// 流程：
/// 1. 读取 16k 单声道 WAV -> PCM16
/// 2. Shazam 音频指纹（本实现）-> 调用 api.shazam.com 识别接口匹配歌曲
/// 3. lrclib.net 拉取歌词（synced LRC 优先）
/// 4. 剥离时间轴标记 + 繁体转简体，输出纯文本歌词
/// 5. 失败抛出带中文说明的异常，由调用方提供 ASR 回退入口
class LyricsRecognizer {
  LyricsRecognizer._();

  static final LyricsRecognizer instance = LyricsRecognizer._();

  /// 用户代理列表（请求轮换，降低被限流概率）
  static const List<String> _userAgents = [
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UD1A.230803.041) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
  ];

  static String _ua() => _userAgents[_randomIndex(_userAgents.length)];

  static int _randomIndex(int n) => math.Random().nextInt(n);

  /// 完整流程：识别 + 拉歌词 -> 纯文本歌词
  ///
  /// 不抛业务异常：失败时返回 [LyricsOutcome.matched] = false，
  /// [LyricsOutcome.error] 携带中文原因，供 UI 直接展示并引导回退 ASR。
  Future<LyricsOutcome> recognizeAndFetchLyrics(String wavPath) async {
    final sw = Stopwatch()..start();
    try {
      final track = await recognizeOnly(wavPath);
      if (!track.matched) {
        return LyricsOutcome.fail(track.error ?? '未能识别出该音频对应的歌曲');
      }
      final outcome = await _fetchLyrics(track);
      return LyricsOutcome.ok(
        lyrics: outcome.lyrics ?? '',
        source: outcome.source,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } on Exception catch (e) {
      return LyricsOutcome.fail(
        e.toString().replaceFirst('Exception: ', ''),
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// 仅识别歌曲（不拉歌词）。供测试与诊断使用。
  ///
  /// 失败时返回 RecognizeResult.failed(中文原因)，不抛异常。
  Future<RecognizeResult> recognizeOnly(String wavPath) async {
    // 1. 解析 WAV
    final WavPcm wav;
    try {
      wav = parseWavToPcm16(wavPath);
    } catch (e) {
      throw Exception('音频解码失败：$e');
    }
    if (wav.samples16.length < 16000) {
      throw Exception('音频过短（不足 1 秒），无法识别');
    }

    // 2. Shazam 识曲
    final track = await _recognize(wav);
    return track;
  }

  /// Shazam 识别，返回 (title, artist)
  Future<RecognizeResult> _recognize(WavPcm wav) async {
    // 生成签名：长音频取中间 12 秒（对齐 shazamio 策略）
    final gen = SignatureGenerator();
    gen.maxTimeSeconds = 12;
    gen.feedInput(wav.samples16);
    if (wav.durationSeconds > 12 * 3) {
      gen.skipBeginning((wav.durationSeconds / 2) - 6);
    }

    final signature = gen.getNextSignature();
    if (signature == null || signature.totalPeaks == 0) {
      return const RecognizeResult.failed('未能从音频中提取到有效指纹');
    }

    final uri = signature.encodeToUri();
    final sampleMs = (signature.numberSamples / 16).round();

    // 构造 Shazam 识别请求
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uuid = _uuid();
      final url = 'https://amp.shazam.com/discovery/v5/en-US/GB/'
          'iphone/-/tag/$uuid/$uuid'
          '?sync=true&webv3=true&sampling=true&connected='
          '&shazamapiversion=v3&sharehub=true&hubv5minorversion=v5.1'
          '&hidelb=true&video=v3';

      final body = jsonEncode({
        'timezone': 'Asia/Shanghai',
        'signature': {'uri': uri, 'samplems': sampleMs},
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'context': {},
        'geolocation': {},
      });

      final request = await http.postUrl(Uri.parse(url));
      request.headers
        ..set('X-Shazam-Platform', 'IPHONE')
        ..set('X-Shazam-AppVersion', '14.1.0')
        ..set('Accept', '*/*')
        ..set('Accept-Language', 'en-US')
        ..set('Content-Type', 'application/json')
        ..set('User-Agent', _ua());
      request.add(utf8.encode(body));

      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      final text = _decodeResponse(response, bytes);
      if (response.statusCode != 200) {
        return RecognizeResult.failed('Shazam 识别服务异常（HTTP ${response.statusCode}）');
      }

      final decoded = jsonDecode(text);
      final track = decoded is Map ? decoded['track'] : null;
      if (track is Map && track['title'] is String) {
        final title = track['title'] as String;
        final artist = track['subtitle'] is String
            ? track['subtitle'] as String
            : '';
        if (title.trim().isEmpty) {
          return const RecognizeResult.failed('未能匹配到歌曲');
        }
        return RecognizeResult.matched(title: title.trim(), artist: artist.trim());
      }
      return const RecognizeResult.failed('未能匹配到歌曲');
    } on SocketException {
      return const RecognizeResult.failed('网络连接失败，请检查网络后重试');
    } on HttpException {
      return const RecognizeResult.failed('网络请求异常，请稍后重试');
    } finally {
      http.close(force: true);
    }
  }

  /// 从 lrclib.net 拉取歌词并清理
  Future<LyricsOutcome> _fetchLyrics(RecognizeResult track) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final url = 'https://lrclib.net/api/search'
          '?track_name=${Uri.encodeQueryComponent(T2s.convert(track.title!))}'
          '&artist_name=${Uri.encodeQueryComponent(T2s.convert(track.artist ?? ''))}';

      final request = await http.getUrl(Uri.parse(url));
      request.headers
        ..set('Accept', 'application/json')
        ..set('User-Agent', _ua());
      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      final text = _decodeResponse(response, bytes);
      if (response.statusCode != 200) {
        throw Exception('歌词服务异常（HTTP ${response.statusCode}）');
      }

      final list = jsonDecode(text);
      if (list is! List || list.isEmpty) {
        throw Exception('未找到该歌曲的歌词');
      }

      // 优先取有同步歌词（LRC）的第一条，其次纯文本
      String? raw;
      var source = '';
      for (final item in list) {
        if (item is! Map) continue;
        final synced = item['syncedLyrics'];
        final plain = item['plainLyrics'];
        if (synced is String && synced.trim().isNotEmpty) {
          raw = synced;
          source = 'lrclib-synced';
          break;
        }
        if (plain is String && plain.trim().isNotEmpty) {
          raw = plain;
          source = 'lrclib-plain';
          break;
        }
      }
      if (raw == null || raw.trim().isEmpty) {
        throw Exception('该歌曲暂无歌词数据');
      }

      // 剥离时间轴标记 [mm:ss.xx] / [mm:ss]
      final stripped = raw
          .replaceAll(RegExp(r'\[\d{1,2}:\d{2}(\.\d+)?\]'), '')
          .replaceAll('\r\n', '\n')
          .trim();

      // 繁体转简体
      final simplified = T2s.convert(stripped);

      if (simplified.trim().isEmpty) {
        throw Exception('歌词内容为空');
      }
      return LyricsOutcome.ok(
        lyrics: simplified,
        source: source,
        elapsedMs: 0,
      );
    } on SocketException {
      throw Exception('网络连接失败，无法获取歌词');
    } on HttpException {
      throw Exception('网络请求异常，无法获取歌词');
    } finally {
      http.close(force: true);
    }
  }

  /// 解码响应体（处理 gzip 压缩，解码失败回退原文）
  static String _decodeResponse(HttpClientResponse response, List<int> bytes) {
    var gzipped = false;
    response.headers.forEach((name, values) {
      if (name.toLowerCase() == 'content-encoding' &&
          values.any((v) => v.toLowerCase().contains('gzip'))) {
        gzipped = true;
      }
    });
    if (gzipped) {
      try {
        return utf8.decode(gzip.decode(bytes), allowMalformed: true);
      } catch (_) {
        // 响应头声称 gzip 但内容非 gzip（部分代理/网关行为），按原文处理
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _uuid() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
