import Foundation
import Speech
import AVFoundation

/// 按住麦克风说话，边说边转成文字填进输入框。
///
/// 用的是系统自带的识别，中文支持得不错，而且**不经过任何服务器**——
/// 你说的话不会被送去第三方，也不额外花钱。
@MainActor
final class SpeechRecognizer: ObservableObject {

    @Published var transcript = ""
    @Published var recording = false
    @Published var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    /// 认一个已经录好的文件。
    ///
    /// 为什么要这条路：按住说话时**同时**开麦克风录文件、又开一个
    /// AVAudioEngine 做实时识别，两个抢同一个输入，谁都录不干净。
    /// 改成只录文件，录完再认——这样她的语音也留下来了，
    /// 能在气泡里当语音条播，识别照样在本机做，不花钱也不上传。
    static func recognizeFile(_ url: URL) async -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")),
              recognizer.isAvailable
        else { return "" }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        // 本机识别。设备不支持的话系统会自己退回服务器那条，
        // 所以这里只是"优先"，不是保证。
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        return await withCheckedContinuation { continuation in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal {
                    done = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    done = true
                    continuation.resume(returning: "")
                }
            }
        }
    }

    /// 先问权限，同意了才开始
    func start() {
        error = nil
        transcript = ""

        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.error = "没给语音识别权限。去系统设置里打开就能用。"
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.error = "没给麦克风权限。"
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            error = "这台设备暂时用不了语音识别"
            return
        }
        stopEngine()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            // 尽量在本机识别，说的话不出这台手机
            if recognizer.supportsOnDeviceRecognition {
                req.requiresOnDeviceRecognition = true
            }
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }

            engine.prepare()
            try engine.start()
            recording = true

            task = recognizer.recognitionTask(with: req) { result, err in
                Task { @MainActor in
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if err != nil || (result?.isFinal ?? false) {
                        self.stopEngine()
                    }
                }
            }
        } catch {
            self.error = "开不了录音：" + error.localizedDescription
            stopEngine()
        }
    }

    /// 松手，返回识别到的那段话
    @discardableResult
    func stop() -> String {
        stopEngine()
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
