import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Сжатие записи разговора WAV → M4A (AAC) для вложения в Битрикс24.
    // Встроенный AVFoundation, без сторонних библиотек.
    if let registrar = self.registrar(forPlugin: "AudioConvert") {
      let channel = FlutterMethodChannel(name: "kz.svet.offline/audio", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "wavToM4a",
              let args = call.arguments as? [String: Any],
              let input = args["input"] as? String,
              let output = args["output"] as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        let bitrate = args["bitrate"] as? Int ?? 64000
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            try AppDelegate.wavToM4a(input: input, output: output, bitrate: bitrate)
            DispatchQueue.main.async { result(output) }
          } catch {
            try? FileManager.default.removeItem(atPath: output)
            DispatchQueue.main.async {
              result(FlutterError(code: "CONVERT_FAILED", message: error.localizedDescription, details: nil))
            }
          }
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  static func wavToM4a(input: String, output: String, bitrate: Int) throws {
    let inFile = try AVAudioFile(forReading: URL(fileURLWithPath: input))
    let format = inFile.processingFormat
    try? FileManager.default.removeItem(atPath: output)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: format.channelCount,
      AVEncoderBitRateKey: bitrate,
    ]
    let outFile = try AVAudioFile(forWriting: URL(fileURLWithPath: output), settings: settings,
                                  commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
      throw NSError(domain: "AudioConvert", code: 1)
    }
    while inFile.framePosition < inFile.length {
      try inFile.read(into: buffer)
      if buffer.frameLength == 0 { break }
      try outFile.write(from: buffer)
    }
  }
}
