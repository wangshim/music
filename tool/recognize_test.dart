// Windows 端 Dart 实测脚本：识曲 + 歌词
//
// 用法：
//   dart run tool/recognize_test.dart <音频文件> [--only-recognize]
// 说明：
//   - 通过 ffmpeg 将任意音频转为 16k 单声道 WAV 后走完整识别流程
//   - --only-recognize 只测识别（打印匹配到的歌曲信息，仅测试用，App 内不展示）
import 'dart:io';

import 'package:audio_analyzer_app/services/lyrics_recognizer.dart';
import 'package:audio_analyzer_app/services/wav_utils.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('用法: dart run tool/recognize_test.dart <音频文件> [--only-recognize]');
    exit(1);
  }
  final audioPath = args[0];
  final onlyRecognize = args.contains('--only-recognize');
  if (!File(audioPath).existsSync()) {
    stdout.writeln('文件不存在: $audioPath');
    exit(1);
  }

  // ffmpeg 转 16k 单声道 wav
  final wavPath =
      '${Directory.systemTemp.path}/recognize_test_${DateTime.now().millisecondsSinceEpoch}.wav';
  stdout.writeln('[1/4] ffmpeg 解码 -> 16k mono wav ...');
  final ff = await Process.run(
    'ffmpeg',
    ['-y', '-i', audioPath, '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', wavPath],
  );
  if (ff.exitCode != 0) {
    stdout.writeln('ffmpeg 失败: ${ff.stderr}');
    exit(2);
  }

  final wav = parseWavToPcm16(wavPath);
  stdout.writeln('      wav: ${wav.sourceSampleRate}Hz/${wav.sourceChannels}ch '
      '-> 16k mono, 时长 ${wav.durationSeconds.toStringAsFixed(1)}s, '
      '样本 ${wav.samples16.length}');

  stdout.writeln('[2/4] Shazam 识别中 ...');
  final sw = Stopwatch()..start();
  final recognizer = LyricsRecognizer.instance;
  final track = await recognizer.recognizeOnly(wavPath);
  sw.stop();
  stdout.writeln('     耗时 ${sw.elapsedMilliseconds}ms');
  if (!track.matched) {
    stdout.writeln('RESULT: RECOGNIZE_FAIL');
    stdout.writeln('REASON: ${track.error}');
    exit(3);
  }
  stdout.writeln('     匹配歌曲: ${track.title} - ${track.artist}');

  if (onlyRecognize) {
    stdout.writeln('RESULT: OK (only-recognize)');
    exit(0);
  }

  stdout.writeln('[3/4] lrclib 拉歌词中 ...');
  final sw2 = Stopwatch()..start();
  final outcome = await recognizer.recognizeAndFetchLyrics(wavPath);
  sw2.stop();
  if (!outcome.matched) {
    stdout.writeln('     耗时 ${sw2.elapsedMilliseconds}ms');
    stdout.writeln('RESULT: LYRICS_FAIL');
    stdout.writeln('ERROR: ${outcome.error}');
    exit(4);
  }
  stdout.writeln('     耗时 ${sw2.elapsedMilliseconds}ms, 来源 ${outcome.source}');
  stdout.writeln('     歌词长度 ${outcome.lyrics!.length} 字符');
  stdout.writeln('[4/4] 歌词内容:');
  stdout.writeln('----------------------------------------');
  stdout.writeln(outcome.lyrics!);
  stdout.writeln('----------------------------------------');
  stdout.writeln('RESULT: OK');
  exit(0);
}
