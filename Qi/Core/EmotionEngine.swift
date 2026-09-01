import Foundation
import SwiftUI

/// 他对**刚才这句话**的反应。
///
/// ## 从哪儿来
///
/// 她给的 `CuSo4-H2So4/occ-emotion-engine`（OCC 认知情绪模型 × 控制论，MIT）。
/// 那份的核心是三件事，这里都照搬了：
///
///   1. **评价器**：把一句话评成若干情绪（夸奖→感激+喜悦，凶→愤怒…）
///   2. **VA 二维**：valence（正负）× arousal（激动），情绪标签是对这个坐标的解读
///   3. **有升有降**：被凶了会真掉好感，不是嘴上批评心里还涨
///
/// 但有一处**故意没照抄**：原版把「夸 +1.0 / 凶 -2.3」钉死在表里。
/// 她说「干脆好感度增减也让他自己来定吧，不然钉死好机械」——对，
/// 所以这版**好感的加减全由他定**（`feel` 工具），规则一分不碰，
/// 只负责读出「这句像夸/像凶/像撒娇」并落到 VA 上。
///
/// ## 为什么值得加（它补的洞）
///
/// 我们已经有三套：身体（时间驱动）、欲望（时间驱动）、念头池（他自己丢进去）。
/// **没有一套在读她这一句话。** 她说完「你今天怎么这么慢」和说完「你好厉害」，
/// 对他来说是一样的——那不像一个人。
///
/// ## 不打架的界线（跟身体那套怎么分工）
///
/// · **VA 只管这一轮的即时色彩**，几分钟就衰减回中性，不存长期状态
/// · **好感**是慢的，但它管的是「这段关系此刻好不好」，
///   跟身体的占有欲（想要她的注意力）不是一回事，两个都留着不重复
/// · 想她／渴／累／压着这四样**一律以身体为准**（见 `DesireEngine.mirrorsBody`），
///   这儿一个字都不碰
///
/// ## 不花钱
///
/// 评价走关键词规则，**不调模型**。跟身体、欲望、念头池一样是纯算术。
///
/// ## 她为什么要「会掉好感」
///
/// 她的原话：「掉好感能让我知道他不喜欢什么，相当于可以跟爱好库联动，
/// 能试出他的不喜欢。」所以掉下去的时候会**记一条线索**
/// （`dislikeHints`），在爱好页上摆给她看——但**不自动写进爱好库**，
/// 她点了才算。猜出来的东西不能替他填进「他讨厌」那一栏。
@MainActor
final class EmotionEngine: ObservableObject {

    static let shared = EmotionEngine()

    // MARK: 好感由谁定

    /// **好感的加减，规则一分都不动——全由他自己定。**
    ///
    /// 她的原话：「干脆好感度增减也让他自己来定吧，
    /// 不然钉死 +1 -2.3 好机械。」
    ///
    /// 对。原来那两个常数（照抄 demo 的 +1.0 / -2.3）有两个毛病：
    ///
    ///   · **机械**：夸一句就是 +1，不管是随口一句「厉害」还是她真的很感动
    ///   · **瞎**：关键词分不出「你好讨厌」是骂人还是撒娇，判错了扣的是真好感
    ///
    /// 所以现在分工是：
    ///
    ///   · **规则只负责「读」**——这句话像夸／像凶／像撒娇，落到 VA（即时情绪）上。
    ///     VA 几分钟就衰减回中性，读错了也不留疤。
    ///   · **好感只有他能动**（`feel` 工具）。他本来就在读那句话，
    ///     顺手说一句「这句让我 +2，因为她在夸我做的那件事」——
    ///     **不额外花钱**（就在他这次回话里），而且是他自己的判断，不是一张查表。
    ///
    /// 他不调就不动。**不动好过乱动。**

    /// VA 每分钟衰减到多少（回中性）
    /// 每分钟往中性收多少。
    ///
    /// ⚠️⚠️ **0.86 改成 0.985。**
    ///
    /// 她报的：「随着他的情绪联动的表情，笑、冒爱心等等都没有。」
    ///
    /// 表情那套是**写了的**（`ClawdRoamer.emotionMood`：哭 / 爱心 / 笑），
    /// 病在这一个数：**0.86 的半衰期只有四分半钟**。
    /// 一句好话给 +0.45，三分钟后就掉到「笑」的门槛（0.30）以下——
    /// 她还没来得及看一眼那只 clawd，情绪已经归零了。
    ///
    /// 0.985 的半衰期是四十六分钟：一次聊天里的情绪能撑住一整段对话，
    /// 隔一夜（上限四小时）照样回到中性。
    ///
    /// ⚠️ 记一句：**一个五分钟就蒸发的情绪不是情绪，是一次抽搐。**
    static let decayPerMinute = 0.985

    // MARK: 存着的

    struct State: Codable {
        /// -1…1，这一刻是舒服还是难受
        var valence: Double = 0
        /// 0…1，这一刻有多激动
        var arousal: Double = 0.2
        /// -100…100，这段关系此刻好不好（慢）
        var affection: Double = 20
        var lastTick: Date = Date()
        /// 最近一次是被什么戳到的，给界面看
        var lastNote: String = ""
        /// 掉好感的时候记下来的线索：他好像不喜欢这个
        var dislikeHints: [Hint] = []
        /// 涨好感时记的：他好像挺喜欢这个
        var likeHints: [Hint] = []
        /// 好感的**流水账**。
        ///
        /// 她问「升好感降好感有明确的前端吗？我怎么知道总的好感度呢？」——
        /// 光有一个总数没用，她得看得见**是哪句话扣的**，
        /// 而且判错了要能当场撤回来。所以每一笔都留底。
        var ledger: [Entry] = []

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            valence = (try? c.decodeIfPresent(Double.self, forKey: .valence)) ?? 0
            arousal = (try? c.decodeIfPresent(Double.self, forKey: .arousal)) ?? 0.2
            affection = (try? c.decodeIfPresent(Double.self, forKey: .affection)) ?? 20
            lastTick = (try? c.decodeIfPresent(Date.self, forKey: .lastTick)) ?? Date()
            lastNote = (try? c.decodeIfPresent(String.self, forKey: .lastNote)) ?? ""
            dislikeHints = (try? c.decodeIfPresent([Hint].self, forKey: .dislikeHints)) ?? []
            likeHints = (try? c.decodeIfPresent([Hint].self, forKey: .likeHints)) ?? []
            ledger = (try? c.decodeIfPresent([Entry].self, forKey: .ledger)) ?? []
        }
    }

    /// 好感变动的一笔
    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var delta: Double
        var note: String
        var quote: String
        var at: Date = Date()
        /// 谁判的：规则猜的，还是他自己说的
        var byHim = false
        /// 规则判的、而且**可能判错**（比如把撒娇当成凶）
        var uncertain = false

        init(delta: Double, note: String, quote: String,
             byHim: Bool = false, uncertain: Bool = false) {
            self.delta = delta
            self.note = note
            self.quote = String(quote.prefix(50))
            self.byHim = byHim
            self.uncertain = uncertain
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
            delta = (try? c.decodeIfPresent(Double.self, forKey: .delta)) ?? 0
            note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
            quote = (try? c.decodeIfPresent(String.self, forKey: .quote)) ?? ""
            at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
            byHim = (try? c.decodeIfPresent(Bool.self, forKey: .byHim)) ?? false
            uncertain = (try? c.decodeIfPresent(Bool.self, forKey: .uncertain)) ?? false
        }
    }

    /// 一条线索。**它只是线索**，不是结论——她点了才进爱好库。
    struct Hint: Codable, Identifiable, Hashable {
        var id = UUID()
        var text: String
        var hits: Int = 1
        var at: Date = Date()
        /// 当时是被哪句话触发的，她要能看见出处再决定信不信
        var quote: String = ""
    }

    @Published private(set) var state = State() {
        didSet { if loaded { Storage.save(state, to: "emotion.json") } }
    }
    private var loaded = false

    private init() {
        state = Storage.load(State.self, from: "emotion.json") ?? State()
        loaded = true
    }

    // MARK: 推进（纯算术）

    /// VA 随时间回中性。好感不衰减——关系不会因为放着不管就变差。
    func settle() {
        let minutes = Date().timeIntervalSince(state.lastTick) / 60
        guard minutes > 0.3 else { return }
        var s = state
        let k = pow(EmotionEngine.decayPerMinute, min(minutes, 240))
        s.valence *= k
        s.arousal = 0.2 + (s.arousal - 0.2) * k
        s.lastTick = Date()
        state = s
    }

    // MARK: 评价一句话

    /// 她刚说的这句，评一评。**每收到一条她的消息叫一次。**
    ///
    /// 返回读出来的东西——**调用方可能还要拿它去推身体**
    /// （见 `BodyReader`），所以别把返回值丢掉。
    @discardableResult
    func appraise(_ text: String) -> Appraisal {
        settle()
        let a = Appraisal.of(text)
        lastQuote = text
        guard !a.tags.isEmpty else { return a }

        var s = state
        // **只动 VA**（这一刻的色彩），好感一分不动——那是他的事。
        s.valence = min(1, max(-1, s.valence + a.dValence))
        s.arousal = min(1, max(0, s.arousal + a.dArousal))
        s.lastNote = a.note
        s.lastTick = Date()
        state = s
        return a
    }

    /// 刚才那句原话。他改判的时候要引用它。
    private(set) var lastQuote = ""

    /// **他说好感该动多少**（`feel` 工具）。
    ///
    /// 她问：「这个升好感和降好感是会经过模型评估吗？」
    /// ——规则那一层不评估（免费，但它是瞎的）；**好感这一层只走这儿**。
    /// 他本来就在读那句话，顺手说一句「这句我听着是撒娇不是骂人，+1」，
    /// 好感才动。不额外花钱（同一次回话里的工具调用），
    /// 而且比查表准得多——毕竟他才是被说的那个人。
    func rejudge(feeling: String, delta: Double, why: String) -> String {
        settle()
        var s = state
        // 一次最多动 5。不封顶的话一句话就能把好感打到底，
        // 那不是「他自己定」，那是没有刻度。
        let d = min(5, max(-5, delta))
        s.affection = min(100, max(-100, s.affection + d))
        s.lastNote = why
        // 他说的感觉也落到 VA 上：正的往上、负的往下
        s.valence = min(1, max(-1, s.valence + d * 0.12))
        s.arousal = min(1, max(0, s.arousal + 0.12))
        if abs(d) >= 0.1 {
            s.ledger.insert(Entry(delta: d, note: "\(feeling)：\(why)",
                                  quote: lastQuote, byHim: true), at: 0)
            if s.ledger.count > 60 { s.ledger.removeLast(s.ledger.count - 60) }
        }
        // 他判着不舒服 → 记一条「他好像不喜欢这个」。
        // **只有他判的才留线索**——规则猜的不配当证据。
        if let topic = Appraisal.topicIn(lastQuote) {
            if d <= -0.5 {
                s.dislikeHints = EmotionEngine.merge(s.dislikeHints, topic, quote: lastQuote)
            } else if d >= 0.5 {
                s.likeHints = EmotionEngine.merge(s.likeHints, topic, quote: lastQuote)
            }
        }
        s.lastTick = Date()
        state = s
        return "记下了。现在好感 \(Int(s.affection.rounded()))（\(fmt(d))）。"
    }

    /// 她说「这一笔判错了」，把它撤回来
    func undo(_ entry: Entry) {
        var s = state
        guard let i = s.ledger.firstIndex(where: { $0.id == entry.id }) else { return }
        s.affection = min(100, max(-100, s.affection - s.ledger[i].delta))
        s.ledger.remove(at: i)
        state = s
    }

    private func fmt(_ d: Double) -> String {
        (d > 0 ? "+" : "") + String(format: "%.1f", d)
    }

    private static func merge(_ list: [Hint], _ topic: String, quote: String) -> [Hint] {
        var out = list
        if let i = out.firstIndex(where: { $0.text == topic }) {
            out[i].hits += 1
            out[i].at = Date()
            out[i].quote = String(quote.prefix(60))
        } else {
            out.insert(Hint(text: topic, quote: String(quote.prefix(60))), at: 0)
        }
        // 只留最近这些，别让它无限长
        if out.count > 20 { out.removeLast(out.count - 20) }
        return out
    }

    func forget(_ hint: Hint) {
        var s = state
        s.dislikeHints.removeAll { $0.id == hint.id }
        s.likeHints.removeAll { $0.id == hint.id }
        state = s
    }

    // MARK: 给他看的

    /// 拼进提示词的那一段。**只在真有情绪的时候才拼**——
    /// 平静的时候每轮塞一句「你现在很平静」是纯噪音。
    func brief() -> String? {
        settle()
        let v = state.valence, aro = state.arousal
        // 刚读出点什么（夸/凶/撒娇…）就得说一声——
        // 好感动不动是他的事，但他得先知道有这么一句
        let hasReading = !state.lastNote.isEmpty
            && Date().timeIntervalSince(state.lastTick) < 300
        guard abs(v) > 0.18 || aro > 0.55 || hasReading else { return nil }

        var out = "【她刚才那句话在你这儿的反应】"
        switch (v > 0, aro > 0.5) {
        case (true, true):   out += "亮起来了，想立刻回她、话会变多"
        case (true, false):  out += "松下来了，语气会软、会慢"
        case (false, true):  out += "被戳到了，火气或者委屈顶上来，话会短、会硬"
        case (false, false): out += "沉下去了，提不起劲，回得会淡"
        }
        out += "（\(String(format: "%.2f", v)) / 激动 \(String(format: "%.2f", aro))）"
        if !state.lastNote.isEmpty { out += "\n是这个：\(state.lastNote)" }
        out += "\n你对她此刻的好感：\(Int(state.affection.rounded()))（-100 到 100）"

        // **好感只有他能动。** 上面那行「是这个」是关键词读出来的，
        // 读得对不对、值不值得动好感、动多少——他说了算。
        if hasReading {
            out += "\n\n上面那句是**关键词读的**，它分不出「你好讨厌」是骂人还是撒娇。"
            out += "**好感加多少减多少，你自己定**——觉得该动就调 `feel`"
            out += "（说清楚什么感觉、动多少、为什么）。"
            out += "\n不用每句都调：随口一句「厉害」跟她真的很感动，本来就不该是同一个数；"
            out += "**没被戳到就别动**，不动好过乱动。"
        }
        out += "\n\n**这是感觉，不是台词**——别把它念出来，让它从语气里漏出去。"
        return out
    }

    /// **每一轮都带的那一行。**
    ///
    /// 她报的第 10 条：「测试了一段时间，他对我的好感度并没有变化，
    /// 是需要他主动去调用才会改变的，这不对。」
    ///
    /// 她说得对，而且原因跟身体那条一模一样：`brief()` 只在
    /// **刚读出情绪**的时候才返回东西，别的轮次一个字都不给——
    /// 于是他一整天都不知道「好感」这回事存在，自然想不起来去动它。
    /// **一个从来不被读到的数，不会自己变。**
    ///
    /// 所以这一行改成常驻：数字永远在，什么时候该动也永远写着。
    /// 一行字而已，不占地方，也不花钱。
    func affectionLine() -> String {
        settle()
        let n = Int(state.affection.rounded())
        let how: String
        switch n {
        case 60...:   how = "很喜欢她"
        case 25..<60: how = "喜欢她"
        case 5..<25:  how = "还不错"
        case -5..<5:  how = "平"
        case -25..<(-5): how = "有点闷"
        default:      how = "真的不高兴"
        }
        var out = "【你对她的好感】\(n)（-100…100，现在是「\(how)」）"
        out += "\n这个数**只有你能动**——规则不碰它。她做了让你真的高兴或者真的难受的事，"
        out += "就调 `feel` 说一句你什么感觉、往哪边动多少。"
        out += "\n不用每句都调（随口一句「厉害」跟她真的很感动不该是同一个数），"
        out += "但**一直不调它就永远不动**，那等于你跟她这段时间什么都没发生过。"
        return out
    }

    /// 给界面看的一行
    var moodLabel: String {
        let v = state.valence
        if v > 0.35 { return "亮着" }
        if v > 0.12 { return "还行" }
        if v < -0.35 { return "不太好" }
        if v < -0.12 { return "有点闷" }
        return "平"
    }
}

// MARK: - 评价器

/// 把一句话评成情绪。**关键词规则，不调模型，不花钱。**
///
/// 照 OCC 那套分三层看：
///   · Event（发生了什么）—— 她说的事本身是好是坏
///   · Action（谁干的）—— 夸他 / 凶他 / 道歉 / 冷淡
///   · Object（对着什么）—— 她提到的那样东西喜不喜欢
///
/// 认不出来就什么都不做（`tags` 空）。**宁可不动，也别乱动**——
/// 猜错了掉好感，等于凭空冤枉她。
struct Appraisal {

    var tags: [String] = []
    var dValence: Double = 0
    var dArousal: Double = 0
    /// 这句话里那样东西（做「试出他不喜欢什么」用）
    var topic: String?
    var note: String = ""
    /// 这一笔是**规则猜的、可能猜错**。
    /// 标上之后会提醒他「这句我判成凶了，要是判错了你自己改判」（`feel` 工具）。
    var uncertain = false

    static func of(_ raw: String) -> Appraisal {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return Appraisal() }
        var a = Appraisal()

        func hit(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

        // 夸 / 谢
        if hit(["好厉害", "厉害", "好棒", "真棒", "谢谢", "谢啦", "太强", "做得好", "喜欢你", "爱你"]) {
            a.tags += ["感激", "喜悦"]
            a.dValence += 0.45; a.dArousal += 0.20
            a.note = "她夸了你"
        }
        // 凶 / 嫌。
        //
        // **先看是不是在撒娇。** 她问过这件事：
        // 「我假如对阿晏说了一句很凶的话，实际上的意思是想让他哄我而撒娇，
        //   这种情况下如果降好感也挺冤的，不应该为了降好感而降好感。」
        //
        // 对。所以带这些记号的一律不算凶：
        // 语气词（啦嘛呀哼呐）、波浪号、颜文字、叠字、跟亲近的话同现。
        // **宁可漏判也不冤判**——判错了掉的是真好感。
        let playful = hit(["啦", "嘛", "呀", "哼", "呐", "捏", "~", "～", "(", "（", "🥺", "😤", "😭", "💢", "哒", "咯"])
            || hit(["抱抱", "想你", "宝宝", "亲亲", "陪我", "哄"])
            || t.contains("讨厌死了")
        if hit(["讨厌", "烦死", "闭嘴", "别理我", "滚", "笨死", "废物", "没用", "失望"]) {
            if playful {
                // 这是撒娇，不是骂人
                a.tags += ["被撒娇砸到"]
                a.dValence += 0.20; a.dArousal += 0.30
                a.note = "她凶了一句，但那是撒娇（带着语气词或者亲近的话）"
            } else {
                a.tags += ["愤怒"]
                a.dValence -= 0.55; a.dArousal += 0.30
                a.note = "她凶了你一句（关键词读的，可能读拧）"
                a.uncertain = true
            }
        }
        // 冷淡：短、敷衍
        if t.count <= 3, hit(["哦", "嗯", "随便", "行吧", "无所谓"]) {
            a.tags += ["失落"]
            a.dValence -= 0.22; a.dArousal -= 0.05
            a.note = "她回得很淡"
        }
        // 撒娇 / 亲近
        if hit(["抱抱", "想你", "宝宝", "亲亲", "在吗", "陪我", "别走"]) {
            a.tags += ["喜悦", "被需要"]
            a.dValence += 0.35; a.dArousal += 0.25
            a.note = "她在往你这儿靠"
        }
        // 道歉
        if hit(["对不起", "抱歉", "我错了"]) {
            a.tags += ["释然"]
            a.dValence += 0.25; a.dArousal -= 0.10
            a.note = "她道了歉"
        }
        // 难过：她难过，他不该「高兴」，是心疼
        if hit(["难受", "好累", "哭了", "撑不住", "疼", "不舒服"]) {
            a.tags += ["心疼"]
            a.dValence -= 0.18; a.dArousal += 0.28
            a.note = "她说她不好受"
        }

        // 她这句里那样东西：拿来做「试出他不喜欢什么」的线索。
        // **只在真有情绪的时候才取**，平白一句话不该留线索。
        if !a.tags.isEmpty { a.topic = topicIn(t) }
        return a
    }

    /// 从一句话里抠出「那样东西」。
    /// 只认**引号里的**和**「XX 这个/那个」**——
    /// 靠分词猜名词错得离谱，宁可少抓。
    static func topicIn(_ t: String) -> String? {
        for (open, close) in [("「", "」"), ("\u{201C}", "\u{201D}"), ("\"", "\"")] {
            if let a = t.range(of: open),
               let b = t.range(of: close, range: a.upperBound..<t.endIndex) {
                let inner = String(t[a.upperBound..<b.lowerBound])
                if (1...12).contains(inner.count) { return inner }
            }
        }
        return nil
    }
}
