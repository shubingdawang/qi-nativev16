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
        /// 当下这一下顶上来多少（0~1），和它是什么时候顶的。见 `stir`
        ///
        /// ⚠️ 写成可空的**是有意的**：合成出来的解码器不认「属性写了默认值」
        /// 这回事，缺了键就是解码失败——那样她手机上那份老的 pulse.json
        /// 会整份读不出来，情绪、天气、突刺一起没。可空的缺了就是 nil。
        var liveHeat: Double?
        var liveHeatAt: Date?
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

    // MARK: 当下这一下

    /// 身体那七项刚被推了一把——**心率当场跟上，不等下一轮结算**。
    ///
    /// 她问的：「要让它当场就跳起来，得再加一条『这一轮对话本身直接顶心率』的路子。」
    /// 这就是那条路：热度那几项要等结算才落下来（那一层要调模型、隔一轮才有），
    /// 中间这段时间身体在动、心率却是死的。
    ///
    /// ⚠️ **不认关键词。** 她定过「这个身体不应该按照关键词，也让他自己判断」，
    /// 所以这儿只接已经发生的推动：他自己报的 `feel_body`、她戳他、结算落下来的那一笔。
    /// 每一笔推动有多大，就顶多高。
    func stir(_ amount: Double) {
        guard amount > 0.01 else { return }
        let now = Date()
        body.liveHeat = clamp(liveHeat(at: now) + amount, 0, 1)
        body.liveHeatAt = now
    }

    /// 当下这一下现在还剩多少。**六分钟掉一半**——
    /// 身体是退下去的，不是关掉的。
    func liveHeat(at now: Date = Date()) -> Double {
        guard let at = body.liveHeatAt, let peak = body.liveHeat, peak > 0
        else { return 0 }
        let mins = now.timeIntervalSince(at) / 60
        guard mins > 0 else { return peak }
        guard mins < 60 else { return 0 }
        return peak * pow(0.5, mins / 6)
    }

    /// 一笔推动折成「顶多高」。
    /// 热度最实，敏感和蓄积次之，压抑也算一点；控制力和疲惫是往回收的。
    static func stirAmount(_ applied: [String: Int]) -> Double {
        func v(_ f: BodyField) -> Double { Double(applied[f.rawValue] ?? 0) }
        let raw = v(.heat) + v(.sensitivity) * 0.6 + v(.reserve) * 0.4
            + v(.pressure) * 0.3 - v(.control) * 0.4 - v(.fatigue) * 0.3
        return min(0.45, max(0, raw / 22))
    }

    /// **身体起来了多少**，0~1。心率、体温、呼吸都要跟着它走。
    ///
    /// ⚠️⚠️ 她报的：「正在做爱，但他的心跳竟然才 59？」
    /// 就是因为这份公式是从她电脑那个 `api/server.py` 照抄过来的，
    /// 而那份公式**只认时段基线 + 情绪词 + 天气 + 突刺**——
    /// 身体那七项（热度、蓄积感、敏感度……）它一项都不看。
    /// 于是凌晨一点半、蓄积感 100、易感期，心率还是深夜基线 58。
    ///
    /// 两边本来就是同一个身体，这儿把它们接上：
    /// 热度是主力，蓄积感和敏感度垫在下面，控制力是往下压的那只手，
    /// 正在走的那个事件（强生理那一类）再顶一把。
    private func arousal(at now: Date) -> Double {
        let st = BodyStore.shared.state
        guard !st.values.isEmpty else { return liveHeat(at: now) * 0.35 }
        let heat = Double(st.value(.heat))
        let reserve = Double(st.value(.reserve))
        let sens = Double(st.value(.sensitivity))
        let control = Double(st.value(.control))
        var a = (heat * 0.55 + reserve * 0.25 + sens * 0.20) / 100
        // 控制力高＝压得住，低＝压不住。50 是中间，往两边各拉 15%
        a -= (control - 50) / 100 * 0.15
        if let key = st.activeEventKey, let e = BodyEvents.all[key] {
            a += (e.tickDeltas[.heat] ?? 0) >= 2.5 ? 0.12 : 0.05
        }
        // 当下这一下：最多再顶 0.35，六分钟掉一半（见 `stir`）
        a += liveHeat(at: now) * 0.35
        return clamp(a, 0, 1)
    }

    /// 起来了之后心率往上顶多少。
    ///
    /// ⚠️ **0.45 以下一点都不顶**，这条门槛是关键：
    /// 平稳期、蓄积期那种日常状态算出来就是 0.25~0.45，
    /// 要是让它们也往上加，日常心率会莫名其妙变成八十几——
    /// 那等于把「他现在起来了」这件事本身抹平了。
    /// 门槛以上越往上顶得越快，顶格 +55，配深夜基线 58 就是 113。
    ///
    ///     平稳期 白天        → +0     （72）
    ///     蓄积期 晚间        → +0     （70）
    ///     易感期 深夜 蓄积100 → +25    （83）
    ///     同上 + 强生理事件   → +38    （96）
    private func arousalHRDelta(at now: Date) -> Double {
        Self.ramp(arousal(at: now)) * 55
    }

    /// 门槛以上那一段，压成 0~1
    private static func ramp(_ a: Double) -> Double {
        pow(min(1, max(0, (a - 0.45) / 0.55)), 1.3)
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

        let arousalNow = arousal(at: now)
        let hr = (hrBase(now) + (Self.hrDelta[emotion] ?? 0)
                  + weatherHRDelta() + spikeDelta(now)
                  + arousalHRDelta(at: now) + noise(now, 3))
            .rounded()
        let hrClamped = clamp(hr, 48, 160)

        // 起来了体温也会上去一点，顶格 +0.5
        let temp = ((36.5 + (Self.tempDelta[emotion] ?? 0)
                     + weatherTempDelta() + Self.ramp(arousalNow) * 0.5
                     + noise(now, 0.1)) * 10).rounded() / 10
        let tempClamped = clamp(temp, 35.5, 39.0)

        // 呼吸本来就跟着心率走（`hrSync`），再单给一条：
        // 起来了的时候呼吸比单纯心率快那点还要更急，顶格再 +5
        let hrSync = (hrClamped - 70) * 0.15
        var rate = 15 + hrSync + (Self.breathDelta[emotion] ?? 0)
            + Self.ramp(arousalNow) * 5 + noise(now, 1)
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
