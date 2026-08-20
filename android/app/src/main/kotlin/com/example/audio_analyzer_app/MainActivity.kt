package com.example.audio_analyzer_app

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val channelName = "audio_analyzer_app/audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFlutterAssetsRoot" -> {
                        // flutter_assets 位于应用 dataDir 下
                        result.success(applicationInfo.dataDir)
                    }
                    "decodeAudio" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_args", "缺少音频路径", null)
                        } else {
                            try {
                                val wavPath = decodeToWav(path)
                                result.success(wavPath)
                            } catch (e: Exception) {
                                result.error("decode_failed", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 使用 MediaExtractor + MediaCodec 将任意常见音频解码为 16kHz 单声道 int16 WAV。
     * 返回临时文件路径。
     */
    private fun decodeToWav(srcPath: String): String {
        val extractor = MediaExtractor()
        extractor.setDataSource(srcPath)
        val format = findAudioFormat(extractor) ?: run {
            extractor.release()
            throw Exception("未找到音频轨道")
        }
        val mime = format.getString(MediaFormat.KEY_MIME)!!
        val srcSampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE))
            format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100
        val srcChannels = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT))
            format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 1

        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(format, null, null, 0)
        decoder.start()

        val allPcm = java.io.ByteArrayOutputStream()
        val bufferInfo = MediaCodec.BufferInfo()
        var sawInputEOS = false
        var sawOutputEOS = false

        while (!sawOutputEOS) {
            // 输入
            if (!sawInputEOS) {
                val inIndex = decoder.dequeueInputBuffer(10_000)
                if (inIndex >= 0) {
                    val inBuf = decoder.getInputBuffer(inIndex)!!
                    val sampleSize = extractor.readSampleData(inBuf, 0)
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(
                            inIndex, 0, 0, 0L,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM
                        )
                        sawInputEOS = true
                    } else {
                        decoder.queueInputBuffer(
                            inIndex, 0, sampleSize,
                            extractor.sampleTime,
                            0
                        )
                        extractor.advance()
                    }
                }
            }
            // 输出
            val outIndex = decoder.dequeueOutputBuffer(bufferInfo, 10_000)
            if (outIndex >= 0) {
                if (bufferInfo.size > 0) {
                    val outBuf = decoder.getOutputBuffer(outIndex)!!
                    outBuf.position(bufferInfo.offset)
                    outBuf.limit(bufferInfo.offset + bufferInfo.size)
                    val bytes = ByteArray(bufferInfo.size)
                    outBuf.get(bytes)
                    allPcm.write(bytes)
                }
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    sawOutputEOS = true
                }
                decoder.releaseOutputBuffer(outIndex, false)
            }
        }
        decoder.stop()
        decoder.release()
        extractor.release()

        val raw = allPcm.toByteArray()
        val wavBytes = resampleTo16kMono(
            raw,
            srcSampleRate,
            srcChannels
        )
        val outFile = File(cacheDir, "asr_decode_${System.currentTimeMillis()}.wav")
        writeWav(outFile, wavBytes, 16000, 1)
        return outFile.absolutePath
    }

    private fun findAudioFormat(extractor: MediaExtractor): MediaFormat? {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith("audio/") == true) {
                extractor.selectTrack(i)
                return format
            }
        }
        return null
    }

    /**
     * 将解码原始 PCM(可能多声道/非16k) 转为 16kHz 单声道 int16。
     * 解码输出通常为 PCM 16-bit little-endian。
     */
    private fun resampleTo16kMono(raw: ByteArray, srcRate: Int, srcChannels: Int): ByteArray {
        if (raw.isEmpty()) return ByteArray(0)
        // 16-bit little endian
        val sampleCount = raw.size / 2
        // 混音到单声道 float
        val monoFloat = FloatArray(sampleCount / srcChannels)
        val byteBuf = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
        for (i in monoFloat.indices) {
            var sum = 0
            for (c in 0 until srcChannels) {
                sum += byteBuf.getShort((i * srcChannels + c) * 2).toInt()
            }
            monoFloat[i] = (sum / srcChannels) / 32768f
        }
        // 重采样
        val targetRate = 16000
        if (srcRate == targetRate) {
            return toInt16WavPcm(monoFloat)
        }
        val ratio = srcRate.toDouble() / targetRate.toDouble()
        val outLen = (monoFloat.size / ratio).toInt().coerceAtLeast(1)
        val out = FloatArray(outLen)
        for (i in out.indices) {
            val pos = i * ratio
            val idx = pos.toInt()
            val frac = pos - idx
            val s0 = monoFloat.getOrElse(idx) { monoFloat.last() }
            val s1 = monoFloat.getOrElse(idx + 1) { monoFloat.last() }
            out[i] = s0 + (s1 - s0) * frac.toFloat()
        }
        return toInt16WavPcm(out)
    }

    private fun toInt16WavPcm(samples: FloatArray): ByteArray {
        val out = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (s in samples) {
            val v = (s.coerceIn(-1f, 1f) * 32767f).toInt()
            out.putShort(v.toShort())
        }
        return out.array()
    }

    /** 写标准 WAV(PCM 16-bit) 文件头 + 数据 */
    private fun writeWav(file: File, pcm: ByteArray, sampleRate: Int, channels: Int) {
        val dataSize = pcm.size
        val byteRate = sampleRate * channels * 2
        val blockAlign = channels * 2
        BufferedOutputStream(FileOutputStream(file)).use { os ->
            os.write("RIFF".toByteArray(Charsets.US_ASCII))
            os.write(int32Le(36 + dataSize))
            os.write("WAVE".toByteArray(Charsets.US_ASCII))
            os.write("fmt ".toByteArray(Charsets.US_ASCII))
            os.write(int32Le(16))
            os.write(int16Le(1)) // PCM
            os.write(int16Le(channels))
            os.write(int32Le(sampleRate))
            os.write(int32Le(byteRate))
            os.write(int16Le(blockAlign))
            os.write(int16Le(16)) // bits per sample
            os.write("data".toByteArray(Charsets.US_ASCII))
            os.write(int32Le(dataSize))
            os.write(pcm)
        }
    }

    private fun int32Le(v: Int): ByteArray {
        return ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array()
    }

    private fun int16Le(v: Int): ByteArray {
        return ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(v.toShort()).array()
    }
}
