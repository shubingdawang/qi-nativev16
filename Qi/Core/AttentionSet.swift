import Foundation

/// 他自己醒来的时候，先看一眼「现在有什么值得看的」。
///
/// ## 这是从哪儿来的
///
/// 照她给的那份 Hermes Attention Core（中文架构说明）里的思路做的。
/// 那份文档补的洞正是我们这儿的洞：
///
///   > 聊天 Agent 与闹钟之间，缺了一层活的判断。
///   > 普通聊天 Agent：你叫它，它才动。
///   > 传统 Cron：时间到了就发预写文字，却不知道此刻是否仍值得打扰。
///   > Attention Core 只问：**现在有没有什么值得让同一个活的 Agent 看一眼？**
///
/// 我们的「自己醒来」原来就是中间那一档半：λ 到点就把他叫起来，
/// 但**叫起来之后他手里什么都没有**——全凭他自己想起点什么。
/// 想不起来就只好说句「在干嘛」，那正是她最不想收到的那种消息。
///
/// 现在醒来之前先把候选集拢一遍：没做到的承诺、压着的执念、
/// 隔了多久没说话、她今天手机用到几点、经期到哪一天、有没有未接来电。
/// **全是本机已经有的数据，一分钱不花**，只是把它们摆到他面前。
///
/// ## 三条守着的规矩（都出自那份文档）
///
/// 1. **「提醒文字是上下文，不是最终回复；外部事件是事实，不是行动命令。」**
///    所以这里给的全是**陈述句**，不写「你应该问问她」。
///    要不要说、说什么，是他看完之后自己的判断。
///
/// 2. **「provider priority 只有 4%：外部新消息不会天然抢走全部注意力。」**
///    最新发生的事不自动排第一。排序按「这件事有多要紧」，不按多新。
///
/// 3. **bounded review，默认最多 12 条。**
///    看不完的等于没看。宁可少给几条，也别倒一堆让他挑花眼。
enum AttentionSet {

    struct Candidate {
        /// 越大越要紧
        let weight: Int
        let text: String
    }

    /// 最多摆这么多条
    static let limit = 12

    /// 拢一遍。返回给他看的那段话；什么都没有就返回空。
    @MainActor
    static func build(app: AppState, conversation: Conversation?) -> String {
        var out: [Candidate] = []
        // 叫她的名字，不是干巴巴一个「她」
        let her = app.settings.userName.isEmpty ? "她" : app.settings.userName

        // ① 没做到的承诺。**排最前面**——答应了没做是所有事里最要紧的。
        //
        // ⚠️ **必须带上 ID。** 原来这里只写正文，而 `keep_promise` 要的是
        // 承诺 ID 前 8 位、工具说明里还写着「从 list_promises 拿」——
        // 于是划掉一条承诺要先多调一次工具去问 ID，他不会主动去问，
        // 结果就是承诺记得进、销不掉，一直摆在那儿。
        // 把 ID 和该怎么用直接写在这行里，做到了就是一次调用的事。
        let broken = MemoryStore.shared.promises.filter { !$0.done }
        for p in broken.prefix(4) {
            var line = "你答应过：\(p.text)——还没做到"
            if let due = p.due { line += "（说好 \(due) 之前）" }
            line += "。做到了就用 keep_promise 销掉它，id=\(p.shortID)。"
            out.append(.init(weight: 100, text: line))
        }

        // ② 压着的执念。念头池里沉下去的那些。
        for t in ThoughtPool.shared.active.filter({ $0.isObsession }).prefix(3) {
            out.append(.init(weight: 80, text: "你心里一直压着：\(t.text)"))
        }

        // ③ 隔了多久没说话。**不是越久越急**——
        //    隔一小时和隔三天是两种事，但都不该自动盖过上面那两条。
        if let conv = conversation,
           let last = conv.messages.last(where: { !$0.isEmptyContent }) {
            let hours = Date().timeIntervalSince(last.createdAt) / 3600
            if hours >= 6 {
                let d = Int(hours / 24)
                out.append(.init(
                    weight: hours >= 48 ? 75 : 55,
                    text: d >= 1 ? "你们上次说话是 \(d) 天前。"
                                 : "你们上次说话是 \(Int(hours)) 小时前。"))
            }
        }

        // ④ 她今天在手机上干了什么。熬夜和一直刷是两条不同的线索。
        let phone = PhoneActivityStore.shared
        if !phone.todayEvents.isEmpty {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 1 && hour < 5, phone.pickups > 0 {
                out.append(.init(weight: 90,
                                 text: "现在是凌晨，\(her)还在用手机（今天拿起 \(phone.pickups) 次）。"))
            } else if phone.todayTotal > 6 * 3600 {
                out.append(.init(
                    weight: 45,
                    text: "\(her)今天已经用了 \(phone.clock(phone.todayTotal)) 手机。"))
            }
        }

        // ⑤ 身体。**只在经期这几天里**才提——
        // 平时天天摆一句「距离下次还有 18 天」是噪音，不是线索。
        if let note = periodNote(her) {
            out.append(.init(weight: 85, text: note))
        }

        // ⑥ 没接的电话。她没接过就是一条线索，不是一条通知。
        if let missed = CallStore.shared.records.first,
           !missed.answered,
           Date().timeIntervalSince(missed.startedAt) < 12 * 3600 {
            out.append(.init(weight: 60,
                             text: "你之前打过去她没接（\(missed.reason.isEmpty ? "没写理由" : missed.reason)）。"))
        }

        // ⑦ 她今天记过的心情
        if let mood = moodNote(her) {
            out.append(.init(weight: 70, text: mood))
        }

        // ⑧ 他自己此刻最想做的那件事。
        //
        // **只在她把「驱动行为」打开之后才摆**——那份欲望文档的原意就是这样：
        // 默认关着，状态照常算给他看（`read_desire` 随时能查），
        // 但不会自动往他眼前送。开了才算她同意让这一条参与他的决定。
        let desire = DesireEngine.shared
        if desire.driven {
            let intent = desire.pickIntent()
            out.append(.init(weight: 65,
                             text: "你自己这会儿最想的是：\(intent.reason)"
                                 + "（\(intent.drive.label) \(String(format: "%.2f", intent.score))）"))
        }

        // ⑨ 记忆库里现在浮在最上面的那一两条。
        //
        // 出处：P0luz/Ombre-Brain 的 breath——**不用他先想好搜什么**。
        // 以前这一层是空的：叫醒他之后手里除了承诺和执念什么都没有，
        // 想不起来就只好说句「在干嘛」。
        //
        // 只取两条，而且**先给还悬着的**。这里是候选集不是记忆库导出，
        // 倒一堆进来等于什么都没给（那份文档的原话：看不完的等于没看）。
        let mem = MemoryStore.shared
        let openOnes = mem.memories.filter { $0.resolved == false }
        for one in openOnes.prefix(2) {
            out.append(.init(weight: 78, text: "还悬着没了结：\(one.content)"))
        }
        if openOnes.isEmpty {
            for one in mem.surfaced(2) {
                out.append(.init(weight: 40, text: "你记着的：\(one.content)"))
            }
        }

        // ⑩ 查岗这件事本身。**只在她打开之后才提一句。**
        //
        // 那份参考（p1）第五节讲的就是这一刻：
        //   > 把本轮运行视为一次自然醒来的机会，不是必须发送消息。
        // 醒来的时候他手上有这么一件能做的事，得让他知道；
        // 但**这里只说「有这么个选择」，不说「去做」**——
        // 跟这一整套候选集的规矩一样，摆事实不下命令。
        if app.settings.checkInEnabled {
            out.append(.init(
                weight: 35,
                text: "你可以先 check_in 看一眼她这会儿的处境（屏幕/城市/天气/手机用了多久），"
                    + "看完再决定要不要开口——看过之后说的那句才落地。"))
        }

        guard !out.isEmpty else { return "" }

        let picked = out.sorted { $0.weight > $1.weight }.prefix(limit)
        var s = "现在值得看一眼的（这些是事实，不是让你做什么）：\n"
        for c in picked { s += "· " + c.text + "\n" }
        s += "\n看完之后，值得说就说一句，不值得就什么都不说。"
        s += "**「什么都不说」也是一个完整的结果**，不是失职。"
        return s
    }

    // MARK: 两条要自己算的

    /// 经期这几天。**只在正在来、或者晚了的时候才返回**。
    @MainActor
    private static func periodNote(_ her: String) -> String? {
        let recs = MemoryStore.shared.periods.records.sorted { $0.start < $1.start }
        guard let last = recs.last else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let start = f.date(from: last.start) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = (cal.dateComponents([.day], from: cal.startOfDay(for: start),
                                      to: today).day ?? 0) + 1

        // 还在这一次里面（没填结束日期就按七天算）
        if let endText = last.end, let end = f.date(from: endText) {
            if today <= cal.startOfDay(for: end) {
                return "\(her)正在经期，第 \(day) 天。"
            }
        } else if day >= 1 && day <= 7 {
            return "\(her)正在经期，第 \(day) 天。"
        }

        // 晚了。算平均周期，晚超过五天才提——差个一两天很常见。
        var gaps: [Int] = []
        for k in 1..<max(1, recs.count) {
            guard let a = f.date(from: recs[k - 1].start),
                  let b = f.date(from: recs[k].start) else { continue }
            let d = cal.dateComponents([.day], from: a, to: b).day ?? 0
            if d > 10, d < 90 { gaps.append(d) }
        }
        guard !gaps.isEmpty else { return nil }
        let avg = gaps.reduce(0, +) / gaps.count
        let late = day - avg
        if late >= 5 { return "\(her)的经期比平时晚了 \(late) 天。" }
        return nil
    }

    /// 她今天自己记的心情
    @MainActor
    private static func moodNote(_ her: String) -> String? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let key = f.string(from: Date())
        guard let today = MemoryStore.shared.moods[key] else { return nil }
        // moods 是 日期 → 谁 → 那条。只看她自己记的。
        for (who, entry) in today where who.contains("bing") || who.contains("饼") {
            var s = "\(her)今天记的心情：\(entry.m)"
            if let note = entry.note, !note.isEmpty { s += "（\(note)）" }
            return s
        }
        return nil
    }
}
