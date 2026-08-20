import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let controller = window?.rootViewController as? FlutterViewController
    let channel = FlutterMethodChannel(
      name: "audio_analyzer_app/audio",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "getFlutterAssetsRoot":
        // flutter_assets 位于 App bundle 内
        result(Bundle.main.bundlePath)
      case "decodeAudio":
        guard let path = (call.arguments as? [String: Any])?["path"] as? String,
              !path.isEmpty else {
          result(FlutterError(code: "bad_args", message: "缺少音频路径", details: nil))
          return
        }
        do {
          let wavPath = try self.decodeToWav(srcPath: path)
          result(wavPath)
        } catch {
          result(FlutterError(code: "decode_failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 使用 AVAudioFile + AVAudioConverter 将音频解码为 16kHz 单声道 int16 WAV。
  private func decodeToWav(srcPath: String) throws -> String {
    let url = URL(fileURLWithPath: srcPath)
    let audioFile = try AVAudioFile(forReading: url)

    let srcFormat = audioFile.processingFormat
    let srcRate = srcFormat.sampleRate
    let srcChannels = Int(srcFormat.channelCount)

    let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 16000,
      channels: 1,
      interleaved: true
    )!

    // 重采样/混音：先转 float 单声道 16k，再写 int16 wav
    let floatFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16000,
      channels: 1,
      interleaved: false
    )!
    let converter = AVAudioConverter(from: srcFormat, to: floatFormat)!

    var pcmFloats: [Float] = []
    let frameCapacity = AVAudioFrameCount(4096)
    let inputBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCapacity)!

    while true {
      let status = audioFile.read(into: inputBuffer, frameCount: frameCapacity)
      if status == .eof && inputBuffer.frameLength == 0 { break }

      let ratio = 16000.0 / srcRate
      let outCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 16)
      let outBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: outCapacity)!

      var error: NSError?
      let convStatus = converter.convert(to: outBuffer, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return inputBuffer
      }
      if convStatus == .error || error != nil {
        break
      }
      if outBuffer.frameLength > 0 {
        let channelData = outBuffer.floatChannelData![0]
        for i in 0..<Int(outBuffer.frameLength) {
          pcmFloats.append(channelData[i])
        }
      }
      if status == .eof { break }
    }

    // 若源为单声道且已经是 16k，可直接用；否则按 float 单声道输出处理
    // 上面 converter 已处理重采样与混音（转 float 单声道 16k）

    let wavPath = NSTemporaryDirectory() + "asr_decode_\(Int(Date().timeIntervalSince1970 * 1000)).wav"
    try writeWav(path: wavPath, floats: pcmFloats, sampleRate: 16000)
    return wavPath
  }

  private func writeWav(path: String, floats: [Float], sampleRate: Int) throws {
    let pcm = floats.map { v -> Int16 in
      let clamped = max(-1.0, min(1.0, Double(v)))
      return Int16(clamped * 32767.0)
    }

    let dataSize = pcm.count * 2
    let byteRate = sampleRate * 2

    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    data.append(UInt32(36 + dataSize).littleEndianBytes)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    data.append(UInt32(16).littleEndianBytes)
    data.append(UInt16(1).littleEndianBytes)
    data.append(UInt16(1).littleEndianBytes)
    data.append(UInt32(sampleRate).littleEndianBytes)
    data.append(UInt32(byteRate).littleEndianBytes)
    data.append(UInt16(2).littleEndianBytes)
    data.append(UInt16(16).littleEndianBytes)
    data.append(contentsOf: Array("data".utf8))
    data.append(UInt32(dataSize).littleEndianBytes)
    for s in pcm {
      data.append(UInt16(bitPattern: s).littleEndianBytes)
    }
    try data.write(to: URL(fileURLWithPath: path))
  }
}

extension FixedWidthInteger {
  var littleEndianBytes: Data {
    var little = littleEndian
    return Data(bytes: &little, count: MemoryLayout<Self>.size)
  }
}
