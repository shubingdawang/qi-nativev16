import Foundation
import AVFoundation

/// 把你说的话转成文字。
///
/// 两条路，各有各的好：
///
/// **系统本机**——不花钱、不联网、快，但只有字，没有你说话时是什么情绪。
///
/// **SenseVoice**——要一次调用的钱，但它**原生带情感识别**：
/// 返回里会夹着 <|HAPPY|> <|SAD|> <|ANGRY|> 这类标记，
/// 还能听出笑声、哭声、咳嗽。所以"分析语音里的情绪"这件事
/// 不用我们自己做，选对模型就有了。
enum VoiceInputMode: String, Codable, CaseIterable, Identifiable {
    case onDevice = "onDevice"
    case senseVoice = "senseVoice"
    case elevenLabs = "elevenLabs"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice:   return "本机识别"
        case .senseVoice: return "SenseVoice"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var note: String {
        switch self {
        case .onDevice:
            return "iOS 自带的，在你手机里跑。不联网、不要密钥、一分钱不花。只出文字，听不出情绪。"
        case .senseVoice:
            return "情绪听得最准：开心、难过、生气、意外都分得出，笑声哭声也认得。要 SiliconFlow 密钥，很便宜。"
        case .elevenLabs:
            return "用你已经配好的那个密钥，不用再注册。认得出笑声这类动静，但**给不出情绪**——它没有这个能力。"
        }
    }

    /// 这条路认不认得出情绪
    var hasEmotion: Bool { self == .senseVoice }
}

/// 转写的结果
struct Transcript {
    var text: String = ""
    /// 听出来的情绪，比如 开心 / 难过 / 生气
    var emotion: String = ""
    /// 听出来的动静，比如 笑声 / 哭声
    var events: [String] = []

    /// 给他看的那段。**情绪单独标出来**——
    /// 同样一句"没事"，笑着说和哭着说，是两件完全不同的事。
    var briefForModel: String {
        var s = text
        var notes: [String] = []
        if !emotion.isEmpty { notes.append("听起来\(emotion)") }
        if !events.isEmpty { notes.append(events.joined(separator: "、")) }
        if !notes.isEmpty {
            s += "\n（语音里：\(notes.joined(separator: "，")))"
        }
        return s
    }
}

enum SenseVoiceAPI {

    enum ASRError: LocalizedError {
        case needsKey
        case badStatus(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .needsKey:
                return "还没填 SiliconFlow 的密钥。去「设置 → 语音输入」填一个，或者换回本机识别。"
            case .badStatus(let code, let body):
                if code == 401 { return "密钥不对（401）" }
                if code == 429 { return "调用太频繁了（429），缓一下" }
                return "转写失败 \(code)：\(body.prefix(140))"
            case .empty: return "没听出内容，可能太短或者太吵"
            }
        }
    }

    /// SenseVoice 用这几个标记表示情绪和动静
    private static let emotionMap: [String: String] = [
        "HAPPY": "开心", "SAD": "难过", "ANGRY": "生气",
        "NEUTRAL": "", "FEARFUL": "害怕", "DISGUSTED": "嫌弃",
        "SURPRISED": "意外"
    ]
    private static let eventMap: [String: String] = [
        "Laughter": "笑了", "Cry": "哭了", "Applause": "鼓掌",
        "Cough": "咳嗽", "Sneeze": "打喷嚏", "BGM": "有背景音乐",
        "Speech": ""
    ]

    static func transcribe(_ fileURL: URL, key: String) async throws -> Transcript {
        guard !key.isEmpty else { throw ASRError.needsKey }
        guard let url = URL(string: "https://api.siliconflow.cn/v1/audio/transcriptions") else {
            throw ASRError.empty
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")

        let audio = try Data(contentsOf: fileURL)
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                .data(using: .utf8)!)
            body.append((value + "\r\n").data(using: .utf8)!)
        }
        field("model", "FunAudioLLM/SenseVoiceSmall")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
            .data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ASRError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw ASRError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["text"] as? String, !raw.isEmpty
        else { throw ASRError.empty }

        Task { @MainActor in UsageStore.shared.recordCall(.asr) }
        return parse(raw)
    }

    /// 把 <|HAPPY|><|Laughter|> 这些标记从正文里摘出来
    static func parse(_ raw: String) -> Transcript {
        var t = Transcript()
        var text = raw

        let pattern = #"<\|([^|]+)\|>"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = raw as NSString
            for m in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                guard m.numberOfRanges > 1 else { continue }
                let tag = ns.substring(with: m.range(at: 1))
                if let e = emotionMap[tag], !e.isEmpty {
                    t.emotion = e
                } else if let ev = eventMap[tag], !ev.isEmpty {
                    t.events.append(ev)
                }
            }
            text = raw.replacingOccurrences(of: pattern, with: "",
                                            options: .regularExpression)
        }
        t.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t
    }
}

// MARK: - 录音

/// 录一段。存成 m4a，转写完就删。
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {

    @Published var recording = false
    @Published var seconds: Double = 0
    /// 说话的大小声，画波形用
    @Published var level: Double = 0

    /// 这一条录音的振幅序列，`sampleInterval` 秒采一个。
    ///
    /// 画波形只要最新那一个值，但**听语气要整条**——
    /// 音量、停顿、语速都是从这串数里算出来的（见 VoiceProsody）。
    /// 一条十秒的语音也就 250 个 Double，两 KB 不到，留着不亏。
    private(set) var samples: [Double] = []
    /// 两个采样之间隔多久。
    /// 原来是 0.1 秒，太粗了——**短于 0.2 秒的停顿整个漏掉**，
    /// 而说话中间的停顿恰恰大多是那个量级。
    let sampleInterval: Double = 0.04

    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?
    private var fileURL: URL?
    private var startedAt: Date?

    func start() throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,        // 识别用 16k 就够，文件更小传得快
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        fileURL = url
        recording = true
        seconds = 0
        samples = []
        startedAt = Date()

        ticker = Task { @MainActor in
            while !Task.isCancelled, recording {
                try? await Task.sleep(
                    nanoseconds: UInt64(sampleInterval * 1_000_000_000))
                // 时长按真实时钟算，不靠累加。
                // Task.sleep 从来不准，一条十秒的语音累加下来能差好几百毫秒，
                // 而语速（字 / 秒）是拿它当分母的。
                if let s = startedAt { seconds = Date().timeIntervalSince(s) }
                r.updateMeters()
                // dB 是负数，-60 到 0，换算成 0~1
                let db = Double(r.averagePower(forChannel: 0))
                let v = max(0, min(1, (db + 55) / 55))
                level = v
                samples.append(v)
            }
        }
    }

    /// 停下来，返回录到的那个文件
    @discardableResult
    func stop() -> URL? {
        ticker?.cancel()
        ticker = nil
        recorder?.stop()
        recorder = nil
        recording = false
        level = 0
        // samples **故意不清空**：停下来之后正是要拿它去算语气的时候。
        // 下一次 start() 会把它重置。
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
        let url = fileURL
        fileURL = nil
        return url
    }

    func discard() {
        if let url = stop() {
            try? FileManager.default.removeItem(at: url)
        }
    }
}


// MARK: - ElevenLabs 那条路

/// 用 ElevenLabs 的 Scribe 转写。
///
/// 好处是**你已经有密钥了**，不用再注册一家。
/// 但要说清楚它的短板：它能标出笑声、掌声这类"动静"，
/// **却给不出情绪标签**——开心还是难过，它不判断。
/// 这不是我没接好，是这个模型就没有这项能力。
/// 想要情绪，还是得走 SenseVoice。
enum ElevenSTT {

    static func transcribe(_ fileURL: URL, key: String, baseURL: String) async throws -> Transcript {
        guard !key.isEmpty else { throw SenseVoiceAPI.ASRError.needsKey }

        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let root = base.isEmpty ? "https://api.elevenlabs.io" : base
        guard let url = URL(string: root + "/v1/speech-to-text") else {
            throw SenseVoiceAPI.ASRError.empty
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")

        let audio = try Data(contentsOf: fileURL)
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                .data(using: .utf8)!)
            body.append((value + "\r\n").data(using: .utf8)!)
        }
        field("model_id", "scribe_v1")
        // 把笑声这类动静标出来——这是它唯一能给的"情绪线索"
        field("tag_audio_events", "true")
        field("language_code", "zho")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
            .data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SenseVoiceAPI.ASRError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw SenseVoiceAPI.ASRError.badStatus(
                http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else { throw SenseVoiceAPI.ASRError.empty }

        var t = Transcript()
        // 动静被当成一种"词"混在正文里，形如 (laughter)，挑出来
        if let words = json["words"] as? [[String: Any]] {
            for w in words where (w["type"] as? String) == "audio_event" {
                guard let raw = w["text"] as? String else { continue }
                let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "()（） "))
                let map = ["laughter": "笑了", "laugh": "笑了",
                           "applause": "鼓掌", "crying": "哭了",
                           "cough": "咳嗽", "sigh": "叹气"]
                if let cn = map[clean.lowercased()] {
                    t.events.append(cn)
                }
            }
        }
        // 正文里那些括号标记去掉，不然读起来碍事
        t.text = text
            .replacingOccurrences(of: #"\([a-zA-Z ]+\)"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !t.text.isEmpty || !t.events.isEmpty else {
            throw SenseVoiceAPI.ASRError.empty
        }
        Task { @MainActor in UsageStore.shared.recordCall(.asr) }
        return t
    }
}
