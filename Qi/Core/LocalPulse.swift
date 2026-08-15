import Foundation

/// 心跳，本机版。
///
/// 原来这是她电脑上跑的一个 FastAPI 服务（PulseEngine），一秒一 tick。
/// 但把 `api/server.py` 从头看到尾会发现一件事：
/// **那些数值根本不是"累积"出来的，是每次请求现算的。**
/// 心率 = 时段基线 + 情绪偏移 + 天气偏移 + 突刺衰减 + 一条慢正弦抖动，
/// 体温、呼吸同理。也就是说它是个纯函数，输入只有「当前时间 + 几个存着的状态」。
///
/// 纯函数就没有理由必须跑在电脑上。这个文件把那几条公式原样搬到 Swift 里，
/// 常数一个没改（`EMOTION_HR_DELTA`、`hr_base` 的分时段基线、
/// 突刺的 `exp(-t/8)` 衰减、`sin(t) * 0.6 + sin(t*2.7+1.3) * 0.4` 那条噪声），
/// 所以算出来的数跟电脑那边是一样的。
///
/// 留在电脑上的只有一样：`PulseEngine/main.py` 那个一秒一次的 tick 循环。
/// 那个循环的作用是让 pulse.json 里的数慢慢爬向目标值——可 `/pulse` 接口
/// 压根不读那几个数，读的是 emotion / fatigue / nervous / spike。
/// 所以少了它，什么都不缺。
@MainActor
final class LocalPulse: ObservableObject {

    static let shared = LocalPulse()

    /// 存着的那几个状态。变的时候才写文件，不需要定时器。
    struct Body: Codable {
        var emotion: String = "calm"
        var emotionReason: String = ""
        var emotionUpdatedAt: Date?
        var nervous: String = "relaxed"
        var fatigue: Double = 0
        var spikeAt: Date?
        var spikeMagnitude: Double = 0
        /// 天气温度（摄氏）。填了就参与计算，不填当没有。
        var weatherTempC: Double?
    }

    @Published var body = Body() {
        didSet { save() }
    }

    private init() {
        body = Storage.load(Body.self, from: "pulse.json") ?? Body()
    }

    private func save() { Storage.save(body, to: "pulse.json") }

    // MARK: 公式（照抄 api/server.py）

    private static let hrDelta: [String: Double] = [
        "calm": 0, "happy": 10, "sad": -3, "angry": 15, "nervous": 18, "tired": -5
    ]
    private static let tempDelta: [String: Double] = [
        "calm": 0, "happy": 0.15, "sad": -0.1, "angry": 0.25, "nervous": 0.2, "tired": -0.1
    ]
    private static let breathDelta: [String: Double] = [
        "calm": 0, "happy": 1, "sad": -1, "angry": 3, "nervous": 3, "tired": -1
    ]

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    /// 心率基线，按时段
    private func hrBase(_ now: Date) -> Double {
        let h = Calendar.current.component(.hour, from: now)
        switch h {
        case 1..<6:   return 58   // 深夜
        case 6..<9:   return 66   // 清晨
        case 9..<18:  return 72   // 白天
        case 18..<23: return 70   // 晚间
        default:      return 62   // 23 点到 1 点
        }
    }

    private func weatherHRDelta() -> Double {
        guard let t = body.weatherTempC else { return 0 }
        if t >= 34 { return 8 }
        if t >= 30 { return 5 }
        if t <= 5 { return 4 }
        return 0
    }

    private func weatherTempDelta() -> Double {
        guard let t = body.weatherTempC else { return 0 }
        if t >= 34 { return 0.3 }
        if t >= 30 { return 0.15 }
        if t <= 5 { return -0.2 }
        return 0
    }

    /// 突发事件：心率短时突刺，指数衰减，一分钟内有效
    private func spikeDelta(_ now: Date) -> Double {
        guard let at = body.spikeAt, body.spikeMagnitude != 0 else { return 0 }
        let elapsed = now.timeIntervalSince(at)
        guard elapsed >= 0, elapsed <= 60 else { return 0 }
        return body.spikeMagnitude * exp(-elapsed / 8.0)
    }

    /// 自然抖动。两条慢正弦叠起来，比随机数像真的——
    /// 真身体不会每秒跳一个无关的数。
    private func noise(_ now: Date, _ amplitude: Double) -> Double {
        let t = now.timeIntervalSince1970 / 45.0
        return (sin(t) * 0.6 + sin(t * 2.7 + 1.3) * 0.4) * amplitude
    }

    /// 现在算什么情绪：三十分钟内主动设过就听那个，否则回落到身体判断
    private var effectiveEmotion: String {
        if let at = body.emotionUpdatedAt, Date().timeIntervalSince(at) < 30 * 60 {
            return body.emotion
        }
        if body.fatigue >= 0.7 { return "tired" }
        if body.nervous == "tense" || body.nervous == "alert" { return "nervous" }
        return "calm"
    }

    // MARK: 出一份快照

    func snapshot(at now: Date = Date()) -> PulseAPI.Snapshot {
        let emotion = effectiveEmotion

        let hr = (hrBase(now) + (Self.hrDelta[emotion] ?? 0)
                  + weatherHRDelta() + spikeDelta(now) + noise(now, 3))
            .rounded()
        let hrClamped = clamp(hr, 48, 160)

        let temp = ((36.5 + (Self.tempDelta[emotion] ?? 0)
                     + weatherTempDelta() + noise(now, 0.1)) * 10).rounded() / 10
        let tempClamped = clamp(temp, 35.5, 39.0)

        let hrSync = (hrClamped - 70) * 0.15
        var rate = 15 + hrSync + (Self.breathDelta[emotion] ?? 0) + noise(now, 1)
        rate = clamp(rate, 8, 35)

        let depth = 1.0 - (rate - 8) / 27
        let depthLabel: String
        switch depth {
        case let d where d > 0.8: depthLabel = "很深很长"
        case let d where d > 0.6: depthLabel = "深长"
        case let d where d > 0.4: depthLabel = "平稳"
        case let d where d > 0.2: depthLabel = "偏浅"
        default:                  depthLabel = "急促"
        }

        let breathRounded = rate.rounded()
        record(hr: Int(hrClamped), emotion: emotion, at: now)

        var snap = PulseAPI.Snapshot()
        snap.heartRate = Int(hrClamped)
        snap.breathing = Int(breathRounded)
        snap.breathDepth = depthLabel
        snap.temperature = tempClamped
        snap.chord = chord(hr: hrClamped, temp: tempClamped, breath: breathRounded)
        snap.fatigue = body.fatigue
        snap.emotion = Self.emotionCN[emotion] ?? emotion
        snap.nervous = Self.nervousCN[body.nervous] ?? body.nervous
        snap.updatedAt = ISO8601DateFormatter().string(from: now)
        snap.fetchedAt = now
        return snap
    }

    /// 把心率／体温／呼吸三个维度翻成一个和弦标签。
    /// 用和弦不用 happy/sad 这种词，是因为身体状态本来就不该被一个情绪词概括。
    private func chord(hr: Double, temp: Double, breath: Double) -> String {
        let energy = clamp((hr - 48) / (160 - 48), 0, 1)
        let warmth = clamp((temp - 35.5) / (39.0 - 35.5), 0, 1)
        let tension = clamp(breath / 35, 0, 1)

        if energy < 0.25 { return "C6" }
        if energy < 0.45 { return warmth >= 0.5 ? "Gmaj7" : "Fmaj7" }
        if energy < 0.65 { return tension > 0.5 ? "Dm7" : "Em7" }
        if energy < 0.85 { return "Bm7" }
        return "F#dim"
    }

    static let emotionCN: [String: String] = [
        "calm": "平静", "happy": "愉快", "sad": "低落",
        "angry": "生气", "nervous": "紧张", "tired": "疲惫"
    ]
    static let nervousCN: [String: String] = [
        "relaxed": "放松", "tense": "紧绷", "alert": "警觉", "normal": "正常"
    ]

    // MARK: 改状态

    func setEmotion(_ key: String, reason: String = "") {
        let allowed = ["calm", "happy", "sad", "angry", "nervous", "tired"]
        guard allowed.contains(key) else { return }
        body.emotion = key
        body.emotionReason = reason
        body.emotionUpdatedAt = Date()
        body.nervous = (key == "nervous" || key == "angry") ? "tense" : "relaxed"
    }

    func spike(_ magnitude: Double = 25) {
        body.spikeAt = Date()
        body.spikeMagnitude = magnitude
    }

    func setWeather(tempC: Double?) {
        body.weatherTempC = tempC
    }

    // MARK: 心率历史

    /// 一分钟最多记一条，跟电脑那版一样，不然一天几万个点
    private var lastRecordedMinute: String?

    private func record(hr: Int, emotion: String, at now: Date) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let minute = f.string(from: now)
        guard lastRecordedMinute != minute else { return }
        lastRecordedMinute = minute

        let day = String(minute.prefix(10))
        var points = Storage.load([PulsePoint].self, from: "pulse-\(day).json") ?? []
        points.append(PulsePoint(ts: ISO8601DateFormatter().string(from: now),
                                 hr: hr, emotion: emotion))
        // 一天最多 1440 条，超了就掐掉最早的
        if points.count > 1440 { points = Array(points.suffix(1440)) }
        Storage.save(points, to: "pulse-\(day).json")
    }

    struct PulsePoint: Codable {
        var ts: String
        var hr: Int
        var emotion: String
    }

    func history(day: String? = nil, limit: Int = 200) -> [PulseAPI.HistoryPoint] {
        let d = day ?? MemoryStore.today
        let points = Storage.load([PulsePoint].self, from: "pulse-\(d).json") ?? []
        return points.suffix(limit).map {
            PulseAPI.HistoryPoint(time: String($0.ts.dropFirst(11).prefix(5)), hr: $0.hr)
        }
    }

    /// 给他看的一段话，`get_pulse_status` 那个工具用
    func brief() -> String {
        let s = snapshot()
        var out = "心跳 \(s.heartRate)、呼吸 \(s.breathing)（\(s.breathDepth)）、"
        out += "体温 \(String(format: "%.1f", s.temperature))"
        out += "。现在是\(s.emotion)，身体\(s.nervous)，和弦 \(s.chord)。"
        if let at = body.emotionUpdatedAt,
           Date().timeIntervalSince(at) < 30 * 60,
           !body.emotionReason.isEmpty {
            out += "（\(body.emotionReason)）"
        }
        return out
    }
}
