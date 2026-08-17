import Foundation

/// 听她**怎么说**，不只听她说了什么。
///
/// 这一套的核心只有一句话，三份互不相干的参考撞在了一起：
///
/// > **不要用写死的声学阈值，要跟这个人自己的平时比。**
///
/// ears 说「同一个音高，对 A 是平静，对 B 是低落」；
/// callhome 的 TONE_CUES 拿 85 条真实录音实测，说「写死阈值换个麦克风就漂」；
/// 而且它在中文里**压根不成立**——普通话四声天生把基频起伏推高，
/// 拿基频判断「激动」等于把说话本身当激动。
///
/// 所以这里不判断「她是不是难过」，只回答一个更老实的问题：
/// **这一句，跟她自己平时比，偏了多少。**
///
/// ## 为什么没有音高
///
/// 音高要 FFT / 自相关，是这摊里唯一的硬骨头。
/// 但音量、语速、停顿三样从录音的电平采样里就能出，
/// 而「比平时轻、停顿比平时多」这种话已经很有用了。
/// 先把八成的价值拿到手。
///
/// ## 加音高的时候记得
///
/// 现在这些全是纯算术，几百个浮点数跑一遍是微秒级，**没有超时的必要**。
/// 但 cove 那份 PDF 的坑 8 写得很清楚：他们把语气分析放在关键路径上，
/// ASR 只花 0.9 秒，语气分析同步等了八秒，用户看到的是「识别很慢」。
/// **以后谁往这儿加 FFT 或者加模型调用，必须先套一个 250–350ms 的硬预算，
/// 超时就省略，绝不允许挡住正式回答。**

// MARK: - 一句话的声学特征

struct ProsodyFeatures: Codable, Hashable {
    /// 真正在说话的那一段有多长（掐掉首尾静音）
    var speechSeconds: Double = 0
    /// 有声帧的平均振幅
    var energy: Double = 0
    /// 说话中间的停顿占了多少（不算首尾）
    var pauseRatio: Double = 0
    /// 语速：字 / 秒
    var tempo: Double = 0

    var usable: Bool { speechSeconds >= 0.6 }
}

enum VoiceProsody {

    /// 从录音期间采到的振幅序列里算特征。
    ///
    /// `samples` 是 0~1 的振幅，`interval` 是两个采样之间隔多少秒。
    /// `text` 是转写出来的字，只用来算语速。
    static func features(samples: [Double],
                        interval: Double,
                        text: String) -> ProsodyFeatures {
        var f = ProsodyFeatures()
        guard samples.count >= 4, interval > 0 else { return f }

        // 静音门限**跟着这一条自己的响度走**，不写死。
        // 手机离嘴远近、麦克风增益、环境噪声每次都不一样，
        // 一个固定的 0.05 在这条上是静音，在下一条上可能是正常说话。
        let sorted = samples.sorted()
        let p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
        let floor = max(0.04, p90 * 0.22)

        // 掐掉首尾静音：按下按钮到开口、说完到松手，那两段不算她的停顿
        guard let first = samples.firstIndex(where: { $0 > floor }),
              let last = samples.lastIndex(where: { $0 > floor }),
              last > first
        else { return f }

        let span = Array(samples[first...last])
        f.speechSeconds = Double(span.count) * interval

        let voiced = span.filter { $0 > floor }
        guard !voiced.isEmpty else { return f }
        f.energy = voiced.reduce(0, +) / Double(voiced.count)
        f.pauseRatio = Double(span.count - voiced.count) / Double(span.count)

        let chars = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if f.speechSeconds > 0.2 {
            f.tempo = Double(chars) / f.speechSeconds
        }
        return f
    }
}

// MARK: - 她自己的平时

/// 她说话的个人基线。
///
/// 用**中位数 ± MAD**，不用平均值和标准差：偶尔在地铁上、在户外录的那几句
/// 会把平均值和方差拽得很偏，中位数几乎不动。这也是 ears 的做法。
///
/// 攒够 8 条才开口说「跟平时比」——不到 8 条它不知道什么叫「平时」，
/// 这时候说什么都是瞎猜。**宁可不说，也不要说错**。
@MainActor
final class VoiceBaseline: ObservableObject {

    static let shared = VoiceBaseline()

    /// 只留最近这些条。搬了家、换了麦克风、感冒一周，
    /// 旧的那些迟早会滚出窗口，它自己会重新认识她。
    private let window = 40
    /// 攒够几条才敢说话
    private let minimum = 8

    private var history: [ProsodyFeatures] = []

    private init() {
        history = Storage.load([ProsodyFeatures].self, from: "voice-baseline.json") ?? []
    }

    /// 记一条进去。**只有正常完成的那一轮才该调这个**——
    /// 被取消的、太短的、识别失败的都不算数，
    /// 不然基线会被半截音频污染（cove PDF 第 10 节末尾那条）。
    func remember(_ f: ProsodyFeatures) {
        guard f.usable else { return }
        history.append(f)
        if history.count > window { history.removeFirst(history.count - window) }
        Storage.save(history, to: "voice-baseline.json")
    }

    /// 认识她认识到什么程度了，给设置页显示
    var progress: (have: Int, need: Int) { (min(history.count, minimum), minimum) }

    var ready: Bool { history.count >= minimum }

    /// 这一句跟她平时比，偏在哪儿。
    ///
    /// 最多说两条。ears 那句话说得对：**一条错的线索比没有线索更糟**，
    /// 所以只报偏得最明显的，剩下的宁可不说。
    func note(for f: ProsodyFeatures) -> String {
        guard f.usable, ready else { return "" }

        var cues: [(z: Double, text: String)] = []

        if let z = z(f.energy, history.map(\.energy), allowZero: false) {
            cues.append((abs(z), phrase(z, high: "比平时大声", low: "比平时轻")))
        }
        // 停顿是唯一一个「0 也是真值」的：一句话中间真的可以一次都不停。
        // 音量和语速是 0 只说明没测出来，那种要剔掉。
        if let z = z(f.pauseRatio, history.map(\.pauseRatio), allowZero: true) {
            cues.append((abs(z), phrase(z, high: "停顿比平时多", low: "比平时连贯")))
        }
        if f.tempo > 0, let z = z(f.tempo, history.map(\.tempo), allowZero: false) {
            cues.append((abs(z), phrase(z, high: "语速比平时快", low: "说得比平时慢")))
        }

        let picked = cues.filter { !$0.text.isEmpty }
            .sorted { $0.z > $1.z }
            .prefix(2)
            .map(\.text)
        return picked.joined(separator: "，")
    }

    // MARK: 稳健统计

    /// 这个值在她自己的分布里偏了几个「稳健标准差」。
    /// 偏得不够明显就返回 nil——那就是「跟平时差不多」，不值一提。
    private func z(_ value: Double, _ all: [Double], allowZero: Bool) -> Double? {
        let xs = allowZero ? all : all.filter { $0 > 0 }
        guard xs.count >= minimum else { return nil }
        let med = median(xs)
        let mad = median(xs.map { abs($0 - med) })
        // 1.4826 是把 MAD 换算成标准差的那个常数（正态分布下两者等价）
        let scale = 1.4826 * mad
        guard scale > 1e-6 else { return nil }
        return (value - med) / scale
    }

    /// 偏得不够就不说。0.9 以下算「跟平时差不多」。
    private func phrase(_ z: Double, high: String, low: String) -> String {
        let word = z > 0 ? high : low
        if abs(z) < 0.9 { return "" }
        if abs(z) < 1.8 { return "有点" + word }
        return "明显" + word
    }

    private func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// 换了麦克风、搬了家、感冒了一周——重新认识她
    func reset() {
        history = []
        Storage.save(history, to: "voice-baseline.json")
    }
}
