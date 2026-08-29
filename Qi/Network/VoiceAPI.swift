import Foundation
import AVFoundation
import UIKit

// MARK: - 语音服务

/// 语音合成的配置。目前照着 ElevenLabs 的接口来，
/// 别家如果也是「基址 + 密钥 + 模型 + 音色」这套，改个基址一般也能用。
struct VoiceService: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var apiKey: String = ""
    var baseURL: String = "https://api.elevenlabs.io"
    var model: String = "eleven_v3"
    var voiceID: String = ""
    var enabled: Bool = true

    var ready: Bool { !apiKey.isEmpty && !voiceID.isEmpty }
}

extension VoiceService {
    /// 先把你给的两个音色填好，装上就能用，不用再手打一遍
    static var defaults: [VoiceService] {
        // 密钥不写进代码——仓库是公开的，写进去等于贴在墙上。
        // 装好之后去「设置 → 语音」填一次就行，存在手机上。
        let key = ""
        // ⚠️ 原来那两条（「阿晏 第六版」CtCNvok… / 「阿晏 第五版」bRx3Dxd…）
        // **她要求删掉**，换成下面这一个。
        return [
            VoiceService(name: "阿晏", apiKey: key,
                         model: "eleven_v3",
                         voiceID: "H75Yik9xnLHtKbnc0mSB", enabled: true)
        ]
    }
}

enum TTSAPI {

    enum TTSError: LocalizedError {
        case notConfigured
        case badStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "还没配好语音服务"
            case .badStatus(let code, let body):
                if code == 401 { return "语音服务的密钥不对（401）" }
                if code == 422 { return "音色 ID 或模型名不对（422）" }
                return "语音服务返回 \(code)：\(body.prefix(140))"
            }
        }
    }

    /// 合成一段语音，返回 mp3 数据
    static func synthesize(_ text: String, with service: VoiceService) async throws -> Data {
        guard service.ready else { throw TTSError.notConfigured }

        let base = service.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/text-to-speech/\(service.voiceID)") else {
            throw TTSError.notConfigured
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        req.setValue(service.apiKey, forHTTPHeaderField: "xi-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": service.model,
            "voice_settings": [
                "stability": 0.45,
                "similarity_boost": 0.8,
                "style": 0.35,
                "use_speaker_boost": true
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw TTSError.notConfigured }
        guard (200..<300).contains(http.statusCode) else {
            throw TTSError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        Task { @MainActor in UsageStore.shared.recordCall(.tts) }
        return data
    }

    // MARK: 兜底链

    /// 合成的结果。**要让调用方知道这次是不是退到系统音了**——
    /// 悄悄换成另一个声音而不说，比没声音更让人错乱。
    struct Spoken {
        var data: Data?
        /// 退到 iOS 自带的合成器了（没有音频文件，得当场念）
        var systemVoice = false
        var note = ""
    }

    /// 把配着的音色**挨个试一遍**，全挂了退到系统合成。
    ///
    /// 以前只用 `activeVoice`——也就是列表里第一个能用的。
    /// 那一家一挂（密钥过期、额度用完、网断了），**就彻底没声音**，
    /// 而她可能配了第二个音色正闲着。
    ///
    /// 参考里那条链是 ElevenLabs → edge-tts → 系统合成。
    /// 中间那档我们接不了（要她电脑上跑东西，又是一条要维护的链路），
    /// 所以做成：**她配的每一个 → iOS 自带的**。
    ///
    /// 系统那个音色难听，这一点不装懂——但**有声音好过没声音**，
    /// 而且返回值里会写明这次是退下来的，界面照实说。
    static func speak(_ text: String, using services: [VoiceService]) async -> Spoken {
        let usable = services.filter { $0.enabled && $0.ready }
        var errors: [String] = []

        for v in usable {
            do {
                let data = try await synthesize(text, with: v)
                if errors.isEmpty { return Spoken(data: data) }
                // 前面有挂掉的，说一声换了谁
                return Spoken(data: data, note: "换成「\(v.name)」念的。")
            } catch {
                errors.append("\(v.name)：\(error.localizedDescription)")
            }
        }

        if usable.isEmpty {
            return Spoken(systemVoice: true, note: "还没配音色，用的是系统的声音。")
        }
        return Spoken(systemVoice: true,
                      note: "配的音色都没通，退回系统的声音了。\n"
                          + errors.joined(separator: "\n"))
    }
}

// MARK: - 系统自带的那个声音

/// iOS 自带的合成器。
///
/// **这是兜底，不是选项**——音色是机械的，跟她配的那个不是一回事。
/// 但配的那家挂掉的时候，有一个机械的声音总好过一片安静。
///
/// 它**不产生文件**：系统这套是直接出声，拿不到音频数据。
/// 所以退到这一档的时候没有语音条可以回听，界面上要说清楚。
@MainActor
final class SystemVoice {

    static let shared = SystemVoice()
    private let synth = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        stop()
        try? AVAudioSession.sharedInstance()
            .setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        // 默认那个语速念中文偏快，压一点点更像说话
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        synth.speak(u)
    }

    /// 还在念吗。**免提要用**——他还在出声就开始录，录进去的是他自己。
    var isSpeaking: Bool { synth.isSpeaking }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }
}

// MARK: - 存和放

enum VoiceStore {

    static var dir: URL {
        let url = Storage.documentsURL.appendingPathComponent("Voices", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    static func save(_ data: Data, ext: String = "mp3") -> String? {
        let name = UUID().uuidString + "." + ext
        do {
            try data.write(to: url(name), options: .atomic)
            return name
        } catch { return nil }
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    /// 大概多少秒。mp3 没读头，按常见码率估个数，只是给进度条看的
    static func duration(_ name: String) -> Double {
        let path = url(name)
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: path.path)[.size] as? Int else { return 0 }
        // 她自己录的是 16k 单声道的 m4a，码率比 TTS 那个 mp3 低不少，
        // 按同一个数去除会算出一条长得离谱的语音条
        let bytesPerSecond: Double = name.hasSuffix(".m4a") ? 2200 : 4000
        return max(1, Double(size) / bytesPerSecond)
    }
}

/// 全局就一个播放器，同一时刻只放一条
@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = VoicePlayer()

    @Published var playingName: String?
    private var player: AVAudioPlayer?

    func toggle(_ fileName: String) {
        if playingName == fileName {
            stop()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: VoiceStore.url(fileName))
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            playingName = fileName
        } catch {
            playingName = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingName = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playingName = nil
            self.player = nil
        }
    }
}

// MARK: - 联网找图

/// 去 Openverse 找图。那是个免费图库，不用密钥，
/// 而且能只筛可商用的，省得拿到不能用的图。
enum WebImageSearch {

    enum SearchError: LocalizedError {
        case nothing(String)
        case network

        var errorDescription: String? {
            switch self {
            case .nothing(let q): return "网上没搜到跟「\(q)」对得上的图"
            case .network: return "连不上图库，检查一下网络"
            }
        }
    }

    static func find(_ query: String) async throws -> UIImage {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string:
            "https://api.openverse.org/v1/images/?q=\(q)&license_type=commercial&page_size=6")
        else { throw SearchError.network }

        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], !results.isEmpty
        else { throw SearchError.nothing(query) }

        // 前几条挨个试，有的直链会挂
        for item in results.prefix(6) {
            let link = (item["url"] as? String) ?? (item["thumbnail"] as? String)
            guard let link, let imageURL = URL(string: link) else { continue }
            guard let (bytes, resp) = try? await URLSession.shared.data(from: imageURL),
                  let hr = resp as? HTTPURLResponse, (200..<300).contains(hr.statusCode),
                  let image = UIImage(data: bytes)
            else { continue }
            return image
        }
        throw SearchError.nothing(query)
    }
}
