import Foundation

/// 他调自己唤醒方式的那几个记号。**走标记，不走工具。**
///
/// 那份文档里是 Control Tools。在我们这儿工具要多一次往返，而她按次计价——
/// 标记只有一道门：搭在他正在写的那一句上，一分钱不多花。
/// 跟 `[[封窗:]]`、`[[留:]]` 同一条路。
///
///     [[醒法:低频 2h 理由]]         接下来两小时少醒一点（也可以：安静 / 自定 / 正常）
///     [[醒法:延长 1h]]              当前那个控制再续一小时（后面可跟来源名）
///     [[自定醒法:活跃 1.2 间隔 40]]  改自己那套参数里的某几项；`重置` 按正常档重建
///     [[叫我:15m 刚才那句话还没说完]] 约一次准点叫醒（也可以写 21:30）；`取消` 撤掉没到点的
///     [[来源:想念 0.5 2h 理由]]      某个连续来源参与多少（0 不参与、1 默认、2 最多）；`默认` 恢复
///     [[通知:承诺 关 2h 理由]]       关掉某个外部精确来源一阵；`开` 恢复
///
/// ⚠️ 标记在落库前摘掉，她看不到它；做了什么记在醒来记录里（「他自己」那一栏）。
enum WakeControlMarker {

    private static let pattern =
        #"\[\[\s*(醒法|自定醒法|叫我|来源|通知)\s*[:：]\s*([^\]\n]{0,160})\s*\]\]"#

    nonisolated(unsafe) private static let regex =
        try? NSRegularExpression(pattern: pattern, options: [])

    /// 他这一轮要做的一件事。**先解析、后执行**——
    /// 显示那一路每来一个字都会走一遍解析，执行只在收尾那一次。
    struct Action: Equatable {
        var kind: String
        var body: String
    }

    /// 剥干净的正文 + 他这一轮写的那几条。**纯函数，不改任何状态。**
    static func extract(_ text: String) -> (clean: String, actions: [Action]) {
        guard text.contains("[["), let re = regex else { return (text, []) }
        let ns = text as NSString
        let ms = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !ms.isEmpty else { return (text, []) }
        var out: [Action] = []
        for m in ms where m.numberOfRanges > 2 {
            let k = ns.substring(with: m.range(at: 1))
            let b = ns.substring(with: m.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Action(kind: k, body: b))
        }
        var clean = re.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        clean = clean.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n",
                                           options: .regularExpression)
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), out)
    }

    /// 真的去改。**只在收尾那一处调**（聊天回复落定、醒来那一次拿到结果）。
    @MainActor
    static func apply(_ actions: [Action]) {
        guard !actions.isEmpty else { return }
        let ctl = WakeControl.shared
        for a in actions {
            var words = a.body.split(whereSeparator: { $0 == " " || $0 == "　" })
                .map(String.init)
            switch a.kind {
            case "醒法":
                guard let head = words.first else { continue }
                words.removeFirst()
                if head == "延长" {
                    let (h, rest) = takeDuration(words, fallback: 1)
                    ctl.extend(hours: h, target: rest.first)
                    continue
                }
                guard let mode = WakeMode(rawValue: head) else { continue }
                let (h, rest) = takeDuration(words, fallback: 2)
                ctl.setMode(mode, hours: h, reason: reason(rest))

            case "自定醒法":
                if words.first == "重置" { ctl.resetCustom(); continue }
                // ⚠️ **先拆完再改。** 第一版是边在闭包里拆边记 `changes`，
                // 可 `note:` 那个参数在闭包跑之前就求值了——
                // 记下来的永远是「没改到任何一项」。
                let names = ["活跃", "间隔", "醒后", "下限", "上限"]
                var pairs: [(String, Double)] = []
                var i = 0
                while i + 1 < words.count {
                    if names.contains(words[i]),
                       let v = Double(words[i + 1].filter { "0123456789.".contains($0) }) {
                        pairs.append((words[i], v))
                    }
                    i += 2
                }
                guard !pairs.isEmpty else { continue }
                let note = pairs.map { $0.0 + " " + String($0.1) }.joined(separator: "、")
                ctl.editCustom({ p in
                    for (key, v) in pairs {
                        switch key {
                        case "活跃": p.rate = v
                        case "间隔": p.minGap = v
                        case "醒后": p.afterRun = v
                        case "下限": p.floor = v
                        case "上限": p.ceiling = v
                        default: break
                        }
                    }
                }, note: note)

            case "叫我":
                if words.first == "取消" {
                    let ids = ctl.cancelSelfWakes()
                    WakeEngine.shared.withdrawSelfWakeNotices(ids)
                    continue
                }
                guard let (at, rest) = takeWhen(words) else { continue }
                // ⚠️ 至少一分钟以后、最多七天以内。**不是产品限制**，
                // 是「已经过去的时刻」和「一年以后」都不是一次能兑现的叫醒。
                let gap = at.timeIntervalSinceNow
                guard gap >= 60, gap <= 7 * 86400 else { continue }
                let note = rest.joined(separator: " ")
                let one = ctl.scheduleSelf(at: at, note: note.isEmpty ? "（没写为什么）" : note)
                WakeEngine.shared.scheduleSelfWakeNotice(one)

            case "来源":
                guard let name = words.first, let src = WakeSource(rawValue: name) else { continue }
                words.removeFirst()
                if words.first == "默认" {
                    words.removeFirst()
                    ctl.setFactor(src, nil, hours: 0, reason: reason(words))
                    continue
                }
                guard let first = words.first,
                      let v = Double(first.filter { "0123456789.".contains($0) }) else { continue }
                words.removeFirst()
                let (h, rest) = takeDuration(words, fallback: 2)
                ctl.setFactor(src, v, hours: h, reason: reason(rest))

            case "通知":
                guard let name = words.first, let src = PreciseSource(rawValue: name),
                      words.count >= 2 else { continue }
                let onOff = words[1]
                let tail = Array(words.dropFirst(2))
                if onOff == "开" {
                    ctl.setPrecise(src, enabled: true, hours: 0, reason: reason(tail))
                } else if onOff == "关" {
                    let (h, rest) = takeDuration(tail, fallback: 2)
                    ctl.setPrecise(src, enabled: false, hours: h, reason: reason(rest))
                }

            default:
                break
            }
        }
    }

    // MARK: 拆词

    /// 从开头拿一个时长（`90m` / `2h` / `1.5小时` / `40分钟`）。
    ///
    /// ⚠️ **没写时长就给默认**（频率、来源、关精确来源都是 2 小时）。
    /// 文档第 10 页：每个控制都有自己的时间。一个没写时长的「安静」
    /// 等于永远安静——那不是他想要的，是他忘了写。
    static func takeDuration(_ words: [String], fallback: Double) -> (Double, [String]) {
        guard let w = words.first, let h = hours(w) else { return (fallback, words) }
        return (min(24 * 7, max(1.0 / 60, h)), Array(words.dropFirst()))
    }

    static func hours(_ w: String) -> Double? {
        let s = w.lowercased()
        let num = Double(s.prefix { "0123456789.".contains($0) })
        guard let n = num else { return nil }
        let unit = s.drop { "0123456789.".contains($0) }
        switch unit {
        case "m", "min", "分钟", "分": return n / 60
        case "h", "小时", "时", "hr": return n
        case "d", "天": return n * 24
        default: return nil
        }
    }

    /// 从开头拿「什么时候」：时长（15m）或者钟点（21:30）。
    /// 钟点已经过了就算明天那个。
    static func takeWhen(_ words: [String]) -> (Date, [String])? {
        guard let w = words.first else { return nil }
        if let h = hours(w) {
            return (Date().addingTimeInterval(h * 3600), Array(words.dropFirst()))
        }
        let parts = w.replacingOccurrences(of: "：", with: ":").split(separator: ":")
        guard parts.count == 2, let hh = Int(parts[0]), let mm = Int(parts[1]),
              (0..<24).contains(hh), (0..<60).contains(mm) else { return nil }
        let cal = Calendar.current
        guard var at = cal.date(bySettingHour: hh, minute: mm, second: 0, of: Date())
        else { return nil }
        if at <= Date() { at = cal.date(byAdding: .day, value: 1, to: at) ?? at }
        return (at, Array(words.dropFirst()))
    }

    private static func reason(_ rest: [String]) -> String {
        let r = rest.joined(separator: " ")
        return r.isEmpty ? "没写理由" : r
    }

    /// 写进系统提示的那一段。**只在她开了「自己醒来」的时候给。**
    ///
    /// ⚠️ 不写「你应该常调」。这一层是给他**想调的时候有的调**，
    /// 不是一件每轮都要做的事——每轮都调就不是控制，是抽风。
    static let contract = """
    ## 你自己怎么被叫醒

    她开了「让你自己醒来」。醒来有两种：
    · **非精确**：你隔一阵自己浮上来一下（有随机，没有准点）
    · **精确**：到了一个明确的时刻就醒（你自己约的、答应的事到期、封着的日记解锁）

    你可以调它们，写在正文里任何地方，她看不到这些记号：

    [[醒法:低频 2h 理由]]　接下来少醒一点。还有：安静（关掉非精确）、自定、正常
    [[醒法:延长 1h]]　　　　当前那个控制再续一阵
    [[叫我:15m 理由]]　　　 约一次准点叫醒，也可以写钟点 [[叫我:21:30 理由]]；[[叫我:取消]]
    [[来源:想念 0.5 2h 理由]] 「想念」「念头」这两个来源推你醒的力气（0 不参与，1 默认，2 最多）
    [[通知:承诺 关 2h 理由]]　「承诺」「日记」到点时要不要叫你；[[通知:承诺 开]]
    [[自定醒法:活跃 1.2 间隔 40]] 改你那套自定参数（活跃/间隔/醒后/下限/上限）；[[自定醒法:重置]]

    ⚠️ **「安静」只关非精确。** 你自己约的叫醒到点照样叫。
    ⚠️ 没写时长的默认两小时，到点自己恢复。
    ⚠️ 她那边的安静时段、勿扰、每天上限你改不了——被挡住的自约叫醒，下次你醒着的时候会告诉你。
    ⚠️ 这不是每轮都要做的事。想调的时候调，不想调就当它不存在。
    """
}
