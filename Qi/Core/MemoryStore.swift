import Foundation

// MARK: - 记忆库（本机版）
//
// 原来这套东西跑在她电脑上：一个 Node 写的 MCP 服务（memory-mcp.js），
// 前面挂 caddy 反代到公网，手机这边当远程 MCP 连过去。
// 代价是**电脑必须一直开着**——关一次机，他就失忆一次。
//
// 这个文件把那台服务整个搬进 App：
//   · 数据结构跟原来的 JSON 一模一样（字段名都没改），导进来就能用
//   · 38 个工具全部在本机实现，不走网络
//   · 文件存在 Documents/Memory/ 下面，跟聊天记录一起被 iOS 备份走
//
// 也就是说：电脑可以关了，Tailscale 可以不开了。

// MARK: 数据结构

/// 批注。原文划掉、批注标红，不动原文只叠观点。
struct MemoryAnnotation: Codable, Hashable {
    var original: String
    var correction: String
    var author: String
    var created_at: String
}

/// 把批注叠到正文上。
///
/// ## 她要的到底是什么
///
/// 她的原话：「假如文字是 binbin 而我要批注为 bingbing，
/// 我想要的效果是 ~~binbin~~bingbing，划线是红色的。」
///
/// 以前不是这样：批注是**另起一行**挂在正文屁股后面，
/// 写成「⤷ 饼饼批注：把「binbin」改成「bingbing」」。
/// 那是一句**关于**这条记忆的话，不是这条记忆改好的样子——
/// 她还得自己在脑子里把那句话套回原文里去。
///
/// 现在原地改：在正文里找到那一句，画成 `~~原句~~批注`。
/// `MD.inline` 认得 `~~`，画出来就是红色删除线接着改对的那半。
/// **原文一个字都没动**——存的还是原来那份，叠出来的只是显示的样子。
///
/// 挑不着的（她一句都没挑、或者原句已经被后来的改动冲掉了）
/// 照旧在末尾另起一行，不闷声丢掉。
enum Annotated {

    /// 批注那一段的记号：`⟪原句⟫→批注`。
    ///
    /// ⚠️ **是红色下划线，不是删除线。**
    /// 上一版画成了 `~~原句~~批注`（红色删除线），她说：
    /// 「我想要的是 binbin 红色下划线右箭头 bingbing，
    ///   之前说的删除线是口误了。」
    ///
    /// 划掉和标注是两件事：**划掉是「这个不算了」，
    /// 而她做的是「这个念作那个」——原文没有错，只是要在旁边补一句。**
    /// 下划线加箭头才是那个意思。
    ///
    /// 用 `⟪⟫`（U+27EA/27EB）当记号：正文里几乎不可能出现，
    /// 而且落到模型眼里读作「binbin→bingbing」，意思一点没丢。
    static let open: String = "⟪"
    static let close: String = "⟫"
    static let arrow: String = "→"

    /// 批注**本身**的记号：`⟬改成什么⟭` → 红色（不带下划线）。
    ///
    /// ⚠️ 为什么要第二个记号：
    ///
    /// 她截图给我看「没有红色下划线」，而她那条批注**没挑原句**
    /// （`original` 是空的），所以走的是「另起一行」那一支。
    /// 而我把那一支写成了**纯文本**——于是既没有下划线（本来就没有原句可划），
    /// **红色也一起丢了**。
    ///
    /// 上一版这一支在 `MemoryLibraryView` 里是单独一个 `ForEach` 画的、
    /// 带着 `.red`；我把它并进正文之后，颜色跟着那个 `ForEach` 一起没了。
    ///
    /// ⚠️ 记一句：**把一段内容从「单独渲染」并进「正文」的时候，
    /// 它原来那身样式不会跟着走。** 并之前先问一句「它原来是什么颜色」。
    static let redOpen: String = "⟬"
    static let redClose: String = "⟭"

    /// 正文 + 批注 → 显示用的那份文本
    static func apply(_ text: String, _ anns: [MemoryAnnotation]?) -> String {
        guard let anns, !anns.isEmpty else { return text }
        var out = text
        var loose: [String] = []
        for a in anns {
            let original = a.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let correction = a.correction.trimmingCharacters(in: .whitespacesAndNewlines)
            // 原句还在正文里 → 原地画成 ⟪原句⟫→批注
            // 原句红色下划线，箭头和批注也红——整段读起来是一处修改，
            // 不是「一半是原文一半是别人插进来的字」。
            if !original.isEmpty, let r = out.range(of: original) {
                out.replaceSubrange(
                    r, with: open + original + close
                        + redOpen + arrow + correction + redClose)
                continue
            }
            // 没挑句子，或者找不着了 → 挂在末尾，别丢。
            // ⚠️ 这一支现在也能删了（见 `MemoryStore.removeAnnotation`）——
            // 她那两条 `⤷ 饼饼批注：bingbing` 就是这么来的：
            // 写的时候一句都没挑，所以锚不到位置。
            // ⚠️ 这两支也要包红。**上一版忘了**，她看到的就是一行黑字。
            if original.isEmpty {
                loose.append("⤷ \(a.author)：" + redOpen + correction + redClose)
            } else {
                loose.append("⤷ \(a.author)：" + open + original + close
                             + redOpen + arrow + correction + redClose)
            }
        }
        if !loose.isEmpty { out += "\n" + loose.joined(separator: "\n") }
        return out
    }
}

struct MemoryItem: Codable, Identifiable, Hashable {
    var id: String
    var content: String
    var tags: [String]
    var level: Int
    var author: String
    var created_at: String
    var updated_at: String
    var annotations: [MemoryAnnotation]?

    // MARK: 时序那几样（照 getzep/graphiti 那套搬的）
    //
    // 她点名要的就是 graphiti——**时序知识图谱**。它跟普通记忆库的区别只有一句：
    // **事实会过期，但过期的事实不删。**
    //
    //   · 「她在苍南」和「她在日本」不是矛盾，是**先后**
    //   · 删掉旧的那条，就等于他从来不知道她曾经在苍南
    //   · 所以旧的留着，只指一下后面接了哪条
    //
    // ⚠️ **「作废」这一半整个撤掉了**（她定的，v123）：
    // 「此前的记忆都算的，不要告诉他从现在起不算数了，
    //  只是存进了新的记忆，不需要否定前面的记忆。」
    // 后来又说了一次：「不算数的记忆全部恢复，不要不算数。」
    //
    // 所以现在：
    //   · `add_memory` 只写 `superseded_by`（一条线，不是一次否定）
    //   · **`invalid_at` 一个字都不再写**，老数据里写过的**在启动时清干净**
    //     （见 `reload` 里那段迁移）
    //   · 搜索、浮现、图、清单——**没有任何一处再按「算不算数」筛过**
    //
    // `invalid_at` 这个字段只剩一个用处：**读得懂老文件**，不至于解不出来。

    /// 这条事实**从什么时候起**成立。不填就是记下来那天。
    var valid_from: String?
    /// ⚠️ **已经废弃的字段。** 老文件里可能有值，读进来之后会被清掉，
    /// 新的一个字都不写。留着它只是为了别让老文件解不出来。
    var invalid_at: String?
    /// 后面接着哪一条（新那条的 id）。**这不是「作废」，是「后来还有一条」**
    var superseded_by: String?
    /// 这条里提到的人和东西。顺着它能把散落各处的记忆串起来——
    /// 这是 graphiti 那个「图」在本机的轻量版：不建真图，
    /// 靠实体名当边，够用而且不用维护一张图。
    var entities: [String]?

    // MARK: 浮沉那几样（照 P0luz/Ombre-Brain 搬的，算法在 MemoryRecall.swift）
    //
    // graphiti 那半管的是「这条后面接着哪一条」，Ombre 管的是另一件事：
    // **这些里面，现在最该被看见的是哪几条。**
    // 两套不打架——前者是先后，后者是轻重。
    // （「算不算数」那一档已经没有了：全都算数。）

    /// 改之前那一版正文。**只在「记错了、改对」的时候留**，
    /// 显示成 ~~旧的~~ 新的。
    ///
    /// ⚠️ 这跟 supersedes 那套是**两件事**，她当初正好撞上过：
    /// 他把七夕记成 2025 年，她让他改成 2026——这是**记错了**，
    /// 该直接改掉、把错的划掉；他却当成「事实变了」，
    /// 于是屏幕上还挂着 2025 那行。
    ///
    ///   · **记错了** → update_memory 改掉，旧的留成删除线
    ///   · **事情变了**（她从苍南搬到日本）→ add_memory + supersedes，
    ///     两条接成一条线，**都留着、都算数**
    var previous: String?

    /// 钉住的核心信念。钉住的**不衰减**，永远浮在最上面。
    /// 上限 20 条（Ombre 原话：稀缺才逼出重要）。
    var pinned: Bool?
    /// 这件事**了结了没有**。
    /// 空的＝没标过，当成已了结、不额外打扰；
    /// 明确标成 false 的才算「还悬着」，浮出的时候抬一档。
    var resolved: Bool?

    /// 屏幕上和给他看的正文。改过的话，**错的划掉、对的跟在后面**。
    var display: String {
        guard let old = previous, !old.isEmpty, old != content else { return content }
        return "~~" + old + "~~ " + content
    }

    /// 工具里认的是 ID 前八位，跟原来那套一致
    var shortID: String { String(id.prefix(8)) }

    init(id: String, content: String, tags: [String], level: Int,
         author: String, created_at: String, updated_at: String,
         annotations: [MemoryAnnotation]? = nil,
         valid_from: String? = nil, invalid_at: String? = nil,
         superseded_by: String? = nil, entities: [String]? = nil,
         pinned: Bool? = nil, resolved: Bool? = nil, previous: String? = nil) {
        self.id = id; self.content = content; self.tags = tags
        self.level = level; self.author = author
        self.created_at = created_at; self.updated_at = updated_at
        self.annotations = annotations
        self.valid_from = valid_from; self.invalid_at = invalid_at
        self.superseded_by = superseded_by; self.entities = entities
        self.pinned = pinned; self.resolved = resolved
        self.previous = previous
    }

    /// 电脑那边的 memories.json 里，level 有的是数字 5，有的是字符串 "5"
    /// ——JS 不在乎，Swift 在乎。合成的解码器碰上字符串直接整个文件报废，
    /// 所以这里自己解一遍，两种写法都认。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        level = (try? c.decode(JSONNumberOrString.self, forKey: .level))?.intValue ?? 3
        author = (try? c.decode(String.self, forKey: .author)) ?? "阿晏"
        created_at = (try? c.decode(String.self, forKey: .created_at)) ?? ""
        updated_at = (try? c.decode(String.self, forKey: .updated_at)) ?? created_at
        annotations = try? c.decode([MemoryAnnotation].self, forKey: .annotations)
        // 这四样是后加的，老记录里没有——**必须是可选的、必须 try?**，
        // 不然她那几百条老记忆会整份读不出来
        valid_from = try? c.decode(String.self, forKey: .valid_from)
        invalid_at = try? c.decode(String.self, forKey: .invalid_at)
        superseded_by = try? c.decode(String.self, forKey: .superseded_by)
        entities = try? c.decode([String].self, forKey: .entities)
        pinned = try? c.decode(Bool.self, forKey: .pinned)
        resolved = try? c.decode(Bool.self, forKey: .resolved)
        previous = try? c.decode(String.self, forKey: .previous)
    }
}

/// 从一句话里抠出「提到了谁、提到了什么」。
///
/// graphiti 那边这一步是拿模型做的（实体抽取 + 消歧）。**我们不调模型**——
/// 那样每存一条记忆就要花一次钱，违反她定的那条铁律。
/// 所以走一套穷办法，但穷得诚实：
///
///   · 引号里的（「」""）几乎一定是个东西
///   · 已经在别的记忆里出现过的实体，再遇到就认出来（**越用越准**）
///   · tags 本来就是她自己标的，直接算实体
///
/// 抠不出来就空着。**宁可少抠也别乱抠**——抠错了会把不相干的记忆串到一起。
enum MemoryEntities {

    static func pull(_ text: String, tags: [String], known: [String]) -> [String] {
        var out: [String] = []

        // 引号里的
        for (open, close) in [("「", "」"), ("\u{201C}", "\u{201D}"), ("\"", "\"")] {
            var rest = Substring(text)
            while let a = rest.range(of: open),
                  let b = rest.range(of: close, range: a.upperBound..<rest.endIndex) {
                let inner = String(rest[a.upperBound..<b.lowerBound])
                if (1...14).contains(inner.count) { out.append(inner) }
                rest = rest[b.upperBound...]
            }
        }
        // 见过的实体，再遇到就认
        for k in known where k.count >= 2 && text.contains(k) { out.append(k) }
        out.append(contentsOf: tags.filter { $0.count >= 2 })

        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
    }
}

/// 一个可能是数字、也可能是字符串的字段
enum JSONNumberOrString: Codable {
    case int(Int)
    case text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .int(Int(v)); return }
        if let v = try? c.decode(String.self) { self = .text(v); return }
        throw DecodingError.typeMismatch(
            Int.self, .init(codingPath: c.codingPath, debugDescription: "既不是数字也不是字符串"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v):  try c.encode(v)
        case .text(let v): try c.encode(v)
        }
    }

    /// 换算成整数。
    ///
    /// **这个方法必须放在这儿，不能放进 MemoryStore。**
    /// MemoryStore 整个类是 @MainActor 的，它的静态方法也跟着被隔离；
    /// 而 `MemoryItem.init(from:)` 是解码器在任意线程上调的（nonisolated），
    /// 从那里去调一个 MainActor 的方法，编译就报错。
    var intValue: Int? {
        switch self {
        case .int(let n):  return n
        case .text(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        }
    }
}

/// 那一天某个人的心情。电脑那边存的是 `{m, note, t}`，不是一个光秃秃的 emoji。
struct MoodEntry: Codable, Hashable {
    var m: String
    var note: String?
    var t: String?
}

struct DiaryItem: Codable, Identifiable, Hashable {
    var id: String
    var author: String
    var content: String
    var mood: String?
    var images: [String]?
    var annotations: [MemoryAnnotation]?
    var created_at: String
    var updated_at: String

    var shortID: String { String(id.prefix(8)) }
}

/// 一条**还没进库的**记忆。
///
/// 出处：wusaki0723/Aelios。它那套是「4 小时抽一次事实 → 候选队列 →
/// 夜里整理，人点头才转正」。我们把中间那两步砍了（都要调模型），
/// 只留最有用的一头一尾：**他拿不准的东西先落在这儿，她点头才进正式库。**
///
/// 为什么值得单开一个盒子：她在第 40 条里说得很清楚——
/// 「猜出来的东西不替他填进那一栏」。同一条道理放到记忆上就是这个队列。
/// 他觉得像但不确定的事，写进来等她看一眼，不直接算成事实。
struct MemoryCandidate: Codable, Identifiable, Hashable {
    var id: String
    var content: String
    var tags: [String] = []
    var level: Int = 3
    var author: String = "阿晏"
    /// 他为什么觉得这值得记。她看的就是这一句。
    var why: String = ""
    var created_at: String = ""

    var shortID: String { String(id.prefix(8)) }

    init(id: String, content: String, tags: [String] = [], level: Int = 3,
         author: String = "阿晏", why: String = "", created_at: String = "") {
        self.id = id; self.content = content; self.tags = tags
        self.level = level; self.author = author
        self.why = why; self.created_at = created_at
    }

    /// **合成的解码器不拿默认值补缺失的键**，缺一个就整份文件读不出来。
    /// 这份 json 两边都写（手机和电脑），手写改坏一个字段不该毁掉整栏，所以自己解。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        content = try c.decode(String.self, forKey: .content)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        level = (try? c.decode(JSONNumberOrString.self, forKey: .level))?.intValue ?? 3
        author = (try? c.decode(String.self, forKey: .author)) ?? "阿晏"
        why = (try? c.decode(String.self, forKey: .why)) ?? ""
        created_at = (try? c.decode(String.self, forKey: .created_at)) ?? ""
    }
}

/// 一个只有他俩懂的词。
///
/// 出处：Aelios 的 `glossary_set` / 术语索引。
/// 记忆库存的是「发生了什么」，术语表存的是「这个词在我们这儿是什么意思」——
/// 「小屋」「阿晏」「换窗」这种，靠搜记忆是搜不明白的，
/// 因为它们从来不作为一件事被记下来，只是被反复使用。
struct GlossaryEntry: Codable, Identifiable, Hashable {
    var term: String
    var meaning: String
    var updated_at: String = ""

    var id: String { term }

    init(term: String, meaning: String, updated_at: String = "") {
        self.term = term; self.meaning = meaning; self.updated_at = updated_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term)
        meaning = (try? c.decode(String.self, forKey: .meaning)) ?? ""
        updated_at = (try? c.decode(String.self, forKey: .updated_at)) ?? ""
    }
}

/// 叙事脊椎。
///
/// 换窗（这一窗额度用完、换个新窗口接着聊）总觉得"哪里不对劲"，
/// 症结不在记忆库存得够不够，而在**把换窗当成了记忆库的事**。
/// 记忆库管的是长期耐久的东西；换窗要的是另一样：
/// 一份确定性拼出来的「启动包」，只负责把这一窗的工作接过去。
///
/// 这四行就是启动包的骨架，照 swap-tutorial 里那个说法：
///   · 走到这里 —— 做完了什么、系统进展到哪
///   · 今天身边 —— 她现在的生活状态
///   · 我们之间 —— 最近的关系事实
///   · 别忘了   —— 还没收口的线索、进行到一半的事
struct NarrativeSpine: Codable, Hashable {
    var here: String = ""      // 走到这里
    var life: String = ""      // 今天身边
    var us: String = ""        // 我们之间
    var open: String = ""      // 别忘了
    var updated_at: String = ""

    var isEmpty: Bool {
        here.isEmpty && life.isEmpty && us.isEmpty && open.isEmpty
    }
}

/// 「现在处于什么阶段」那段话。wake_up 第一眼看到的就是它。
struct StateNote: Codable, Hashable {
    var text: String = ""
    var updated_at: String = ""
    var by: String?
    var archived_at: String?
}

struct PartnerMessage: Codable, Hashable {
    var text: String = ""
    var author: String = "饼饼"
    var created_at: String = ""
    var read: Bool = false
}

struct PeriodRecord: Codable, Hashable {
    var start: String
    var end: String?
}

struct PeriodNote: Codable, Hashable {
    var author: String
    var text: String
    var time: String
}

struct PeriodBook: Codable {
    var records: [PeriodRecord] = []
    /// 日期 → 那天的几条备注
    var notes: [String: [PeriodNote]] = [:]
}

// 下面两个的 id 都是**可选**的。
//
// Swift 合成的解码器不会拿默认值去补缺失的键——写成 `var id: String = ...`
// 的话，电脑那边的 json 里只要没有 id 这一项，整个文件就解不出来。
// 写成可选就没这个问题，缺了就是 nil。

struct EmotionalEvent: Codable, Hashable, Identifiable {
    var id: String?
    var emotion: String
    var event: String
    var severity: Int
    var created_at: String
}

/// 记忆改过什么的流水
struct MemoryLogEntry: Codable, Hashable, Identifiable {
    var id: String?
    var time: String
    var action: String
    var by: String
    var memId: String
    var beforeText: String?
    var afterText: String?
}

/// 他答应过的一件事。
///
/// 来路有两条，走的是同一个盒子：
///   · 他在回话里随手写 `[[promise:陪你把这个 App 做完]]`，
///     显示的时候标记会被抠掉，这条悄悄落进来
///   · 他主动调 `make_promise` 郑重记一笔
///
/// 为什么要单独存：答应过的事跟"记忆"不是一回事。记忆是发生过什么，
/// 承诺是**还欠着什么**——它有状态（做没做到），而且没做到的那些
/// 每次醒来都该重新看见一遍。混进记忆库就沉底了。
struct Promise: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    var madeAt: String
    /// 说好什么时候之前（可不填）
    var due: String?
    var done: Bool = false
    var doneAt: String?
    /// 在哪个窗口答应的，方便回头翻
    var conversationID: String?

    var shortID: String { String(id.prefix(8)) }
}

struct TranscriptMsg: Codable, Hashable {
    var role: String
    var text: String
}

/// 一份存档对话的**索引**。正文单独一个文件，不跟着索引一起进内存——
/// 19 份就有 5 MB，全读进来手机会喘。
struct TranscriptMeta: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var imported_at: String
    var summary: String?
    var count: Int
}

/// 存档对话的正文
struct TranscriptFile: Codable {
    var id: String
    var title: String
    var imported_at: String
    var summary: String?
    var msgs: [TranscriptMsg]
}

// MARK: - 从他的话里把承诺抠出来

/// 「隐藏标记法」：让他在正文里写标记，后端解析出来落库，
/// 再把标记从正文里剥干净——她看到的还是一句正常的话。
///
/// 好处是他不用为了记一件事专门调一次工具（那会打断说话的节奏，
/// 也多一次往返）；坏处是格式他可能写歪，所以这里认得宽松一点：
/// `[[promise:...]]`、`[promise:...]`、`[[承诺:...]]`、`[承诺:...]` 都收，
/// 中英文冒号也都认。
enum PromiseMarker {

    private static let pattern =
        #"\[{1,2}\s*(?:promise|承诺)\s*[:：]\s*([^\]\n]{1,120})\s*\]{1,2}"#

    /// 返回：剥干净的正文 + 抠出来的几条承诺
    static func extract(_ text: String) -> (clean: String, promises: [String]) {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]) else { return (text, []) }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, []) }

        var found: [String] = []
        for m in matches where m.numberOfRanges > 1 {
            let r = m.range(at: 1)
            guard r.location != NSNotFound else { continue }
            let one = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            if !one.isEmpty { found.append(one) }
        }

        var clean = regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        // 标记单独占一行的话，剥完会留下一行空白，顺手收掉
        clean = clean.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        return (clean, found)
    }
}

// MARK: - 仓库

@MainActor
final class MemoryStore: ObservableObject {

    static let shared = MemoryStore()

    @Published var memories: [MemoryItem] = []
    @Published var diaries: [DiaryItem] = []
    /// 「我是谁」。原来是一整段纯文本。
    @Published var identity: String = ""
    @Published var currentState = StateNote()
    @Published var stateHistory: [StateNote] = []
    /// 聊到哪儿了。额度突然断掉的时候靠它接上。
    @Published var checkpoint: StateNote?
    /// 换窗用的那四行
    @Published var spine = NarrativeSpine()
    /// 说好的和说好不做的。换窗最容易丢的就是这一类——
    /// 它不像"事件"那样值得写进记忆，但丢了对方立刻就变了个人。
    @Published var rules: [String] = []
    /// 还没做完的事
    @Published var openTasks: [String] = []
    /// 他答应过的事
    @Published var promises: [Promise] = []
    /// 「写给下一个你」。他自己写的那封长信，五块结构。
    /// 有它的时候 wake_up 用它当身份认知——它比那段简介深得多。
    @Published var letter: StateNote?
    @Published var partnerMessage: PartnerMessage?
    @Published var periods = PeriodBook()
    /// 日期 → 谁（ayang / bingbing）→ 那天的心情
    @Published var moods: [String: [String: MoodEntry]] = [:]
    @Published var emotionalEvents: [EmotionalEvent] = []
    @Published var log: [MemoryLogEntry] = []
    @Published var transcripts: [TranscriptMeta] = []
    /// 等她点头的候选记忆（Aelios 那套的本机版）
    @Published var candidates: [MemoryCandidate] = []
    /// 他俩之间的黑话
    @Published var glossary: [GlossaryEntry] = []

    private init() { reload() }

    // MARK: 文件位置

    static var root: URL {
        let url = Storage.documentsURL.appendingPathComponent("Memory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static var transcriptsDir: URL {
        let url = root.appendingPathComponent("transcripts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private func url(_ name: String) -> URL { Self.root.appendingPathComponent(name) }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    // MARK: 读写

    /// 新的在上、旧的在下。
    ///
    /// 从电脑那边导进来的 json 是按写入顺序排的，也就是**最旧的在最前面**，
    /// 直接显示就是倒着看。这里统一按时间倒排一次，
    /// 界面、工具输出、wake_up 全都跟着对了——不用在三个地方各排一遍。
    private func sortNewestFirst() {
        memories.sort { $0.created_at > $1.created_at }
        diaries.sort { $0.created_at > $1.created_at }
        transcripts.sort { $0.imported_at > $1.imported_at }
    }

    func reload() {
        memories = read([MemoryItem].self, "memories.json") ?? []
        // 老文件里被标成「从某天起不算数」的那些，**全部恢复**。
        // 她的原话：「不算数的记忆全部恢复，不要不算数。」
        // 清一次就落盘，下次启动这儿就什么都不用做了。
        if memories.contains(where: { !($0.invalid_at ?? "").isEmpty }) {
            for i in memories.indices { memories[i].invalid_at = nil }
            write(memories, "memories.json")
        }
        diaries = read([DiaryItem].self, "diaries.json") ?? []
        identity = (try? String(contentsOf: url("identity.txt"), encoding: .utf8)) ?? ""
        currentState = read(StateNote.self, "current_state.json") ?? StateNote()
        stateHistory = read([StateNote].self, "state_history.json") ?? []
        checkpoint = read(StateNote.self, "live_checkpoint.json")
        spine = read(NarrativeSpine.self, "spine.json") ?? NarrativeSpine()
        rules = read([String].self, "rules.json") ?? []
        openTasks = read([String].self, "open_tasks.json") ?? []
        promises = read([Promise].self, "promises.json") ?? []
        letter = read(StateNote.self, "letter.json")
        partnerMessage = read(PartnerMessage.self, "partner_message.json")
        periods = read(PeriodBook.self, "periods.json") ?? PeriodBook()
        moods = read([String: [String: MoodEntry]].self, "moods.json") ?? [:]
        emotionalEvents = read([EmotionalEvent].self, "emotional_events.json") ?? []
        log = read([MemoryLogEntry].self, "memories_log.json") ?? []
        transcripts = read([TranscriptMeta].self, "transcripts.json") ?? []
        candidates = read([MemoryCandidate].self, "candidates.json") ?? []
        glossary = read([GlossaryEntry].self, "glossary.json") ?? []
        sortNewestFirst()
    }

    func saveMemories() { write(memories, "memories.json") }
    func saveCandidates() { write(candidates, "candidates.json") }
    func saveGlossary() { write(glossary, "glossary.json") }
    func saveDiaries() { write(diaries, "diaries.json") }
    func saveState() {
        write(currentState, "current_state.json")
        write(stateHistory, "state_history.json")
    }
    func saveSpine() {
        write(spine, "spine.json")
        write(rules, "rules.json")
        write(openTasks, "open_tasks.json")
    }
    func savePromises() { write(promises, "promises.json") }

    func saveLetter() {
        if let letter { write(letter, "letter.json") }
        else { try? FileManager.default.removeItem(at: url("letter.json")) }
    }

    /// 还欠着的那些，先看有期限的、期限近的排前面
    var openPromises: [Promise] {
        promises.filter { !$0.done }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            default:           return a.madeAt > b.madeAt
            }
        }
    }

    /// 记一条承诺。同一句话不重复记——他可能在几轮里反复说同一件事。
    @discardableResult
    func addPromise(_ text: String, due: String? = nil,
                    conversationID: String? = nil) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        guard !promises.contains(where: { !$0.done && $0.text == t }) else { return false }
        promises.insert(Promise(text: t, madeAt: Self.now, due: due,
                                conversationID: conversationID), at: 0)
        savePromises()
        return true
    }

    func saveCheckpoint() {
        if let checkpoint { write(checkpoint, "live_checkpoint.json") }
        else { try? FileManager.default.removeItem(at: url("live_checkpoint.json")) }
    }
    func savePartner() {
        if let partnerMessage { write(partnerMessage, "partner_message.json") }
        else { try? FileManager.default.removeItem(at: url("partner_message.json")) }
    }
    func savePeriods() { write(periods, "periods.json") }
    func saveMoods() { write(moods, "moods.json") }
    func saveEvents() { write(emotionalEvents, "emotional_events.json") }
    func saveLog() { write(log, "memories_log.json") }
    func saveTranscriptIndex() { write(transcripts, "transcripts.json") }
    func saveIdentity() {
        try? identity.write(to: url("identity.txt"), atomically: true, encoding: .utf8)
    }

    /// 库里到底有没有东西。没有的话工具不给出去，
    /// 免得他兴冲冲查了一圈发现什么都没有。
    var isEmpty: Bool {
        memories.isEmpty && diaries.isEmpty && transcripts.isEmpty
            && identity.isEmpty && currentState.text.isEmpty
    }

    var summaryLine: String {
        "\(memories.count) 条记忆 · \(diaries.count) 篇日记 · \(transcripts.count) 份存档"
            + (candidates.isEmpty ? "" : " · \(candidates.count) 条等你点头")
    }

    // MARK: 存档对话的正文

    func transcript(_ id: String) -> TranscriptFile? {
        let u = Self.transcriptsDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(TranscriptFile.self, from: data)
    }

    func saveTranscript(_ t: TranscriptFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(t) else { return }
        let u = Self.transcriptsDir.appendingPathComponent("\(t.id).json")
        try? data.write(to: u, options: .atomic)

        if let i = transcripts.firstIndex(where: { $0.id == t.id }) {
            transcripts[i] = TranscriptMeta(id: t.id, title: t.title,
                                            imported_at: t.imported_at,
                                            summary: t.summary, count: t.msgs.count)
        } else {
            transcripts.append(TranscriptMeta(id: t.id, title: t.title,
                                              imported_at: t.imported_at,
                                              summary: t.summary, count: t.msgs.count))
        }
        saveTranscriptIndex()
    }

    func deleteTranscript(_ id: String) {
        try? FileManager.default.removeItem(
            at: Self.transcriptsDir.appendingPathComponent("\(id).json"))
        transcripts.removeAll { $0.id == id }
        saveTranscriptIndex()
    }

    // MARK: 小工具

    static var now: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// 心情那份文件里，人名的键是英文的：ayang / bingbing。
    /// 他调工具的时候写的是中文，这儿翻一下，不然会在同一份文件里
    /// 存出两套键来。
    static func moodKey(_ who: String) -> String {
        switch who {
        case "阿晏", "ayang", "ayan": return "ayang"
        case "饼饼", "bingbing":       return "bingbing"
        default:                       return who
        }
    }

    static func moodName(_ key: String) -> String {
        switch key {
        case "ayang":    return "阿晏"
        case "bingbing": return "饼饼"
        default:         return key
        }
    }

    /// 找一条记忆。传全 ID 或者前八位都认。
    func memoryIndex(_ id: String) -> Int? {
        memories.firstIndex { $0.id == id || $0.id.hasPrefix(id) }
    }

    func diaryIndex(_ id: String) -> Int? {
        diaries.firstIndex { $0.id == id || $0.id.hasPrefix(id) }
    }

    // MARK: 批注：写错了要能删

    /// 她的原话：「批注删除功能，如果写错了就删不掉了有点麻烦。」
    ///
    /// 对——批注是**叠在原文上的一层**，叠错了就得能揭掉。
    /// 一个只能加不能减的功能，用一次就不敢再用第二次。
    ///
    /// ⚠️ **不走工具那条路。** 删自己写错的批注是她的事，
    /// 不该在他那份工具清单里多一件他永远不该用的东西。
    /// 直接改 store、直接落盘。

    /// 这条记忆／这篇日记上挂着哪几条批注（给菜单摆出来用）。
    /// 返回的是「谁写的：写了什么」。
    func annotationLabels(memory id: String) -> [String] {
        guard let i = memoryIndex(id) else { return [] }
        return (memories[i].annotations ?? []).map { $0.author + "：" + $0.correction }
    }

    func annotationLabels(diary id: String) -> [String] {
        guard let i = diaryIndex(id) else { return [] }
        return (diaries[i].annotations ?? []).map { $0.author + "：" + $0.correction }
    }

    @discardableResult
    func removeAnnotation(memory id: String, at index: Int) -> Bool {
        guard let i = memoryIndex(id),
              var anns = memories[i].annotations,
              anns.indices.contains(index) else { return false }
        anns.remove(at: index)
        memories[i].annotations = anns.isEmpty ? nil : anns
        memories[i].updated_at = MemoryStore.now
        saveMemories()
        return true
    }

    @discardableResult
    func removeAnnotation(diary id: String, at index: Int) -> Bool {
        guard let i = diaryIndex(id),
              var anns = diaries[i].annotations,
              anns.indices.contains(index) else { return false }
        anns.remove(at: index)
        diaries[i].annotations = anns.isEmpty ? nil : anns
        diaries[i].updated_at = MemoryStore.now
        saveDiaries()
        return true
    }

    func note(_ action: String, by: String, memID: String,
              before: String? = nil, after: String? = nil) {
        log.insert(MemoryLogEntry(id: UUID().uuidString, time: Self.now,
                                  action: action, by: by, memId: memID,
                                  beforeText: before, afterText: after),
                   at: 0)
        if log.count > 200 { log = Array(log.prefix(200)) }
        saveLog()
    }

    // MARK: 浮沉、钉住、候选（这一摊的算法都在 MemoryRecall.swift）

    /// 已经钉住的条数。上限 20，见 `MemoryRecall.pinLimit`。
    var pinnedCount: Int { memories.filter { $0.pinned == true }.count }

    /// 现在最该被看见的几条。零参数——不用他想好要搜什么。
    ///
    /// 排序 = 重要度 ×（钉住的翻倍）×（还悬着的抬一档），同分的新的在前。
    /// **不按时间打折**——她不要遗忘曲线，理由写在 MemoryRecall.swift 里。
    func surfaced(_ limit: Int = 6) -> [MemoryItem] {
        memories
            .sorted(by: MemoryRecall.surfaceOrder)
            .prefix(limit).map { $0 }
    }

    /// 抠实体的时候要给它一份「已经见过的实体」，越用越准
    var knownEntities: [String] {
        Array(Set(memories.flatMap { $0.entities ?? [] })).prefix(300).map { $0 }
    }

    /// 真正把一条记忆放进库里。工具和「收进去」按钮走的是同一条路，
    /// 免得两边各建一遍、字段慢慢长歪。
    @discardableResult
    func insertMemory(content: String, tags: [String], level: Int,
                      author: String, since: String? = nil) -> MemoryItem {
        var item = MemoryItem(
            id: UUID().uuidString, content: content,
            tags: tags, level: max(1, min(5, level)),
            author: author.isEmpty ? "阿晏" : author,
            created_at: Self.now, updated_at: Self.now)
        item.valid_from = (since?.isEmpty == false) ? since : Self.now
        let ents = MemoryEntities.pull(content, tags: tags, known: knownEntities)
        item.entities = ents.isEmpty ? nil : ents
        memories.insert(item, at: 0)
        saveMemories()
        note("新增", by: item.author, memID: item.id, after: content)
        return item
    }

    /// 她点头：候选转正。
    @discardableResult
    func acceptCandidate(_ id: String) -> MemoryItem? {
        guard let i = candidates.firstIndex(where: { $0.id == id || $0.id.hasPrefix(id) })
        else { return nil }
        let c = candidates.remove(at: i)
        saveCandidates()
        return insertMemory(content: c.content, tags: c.tags,
                            level: c.level, author: c.author)
    }

    /// 她摇头：丢掉，不进库。
    @discardableResult
    func dropCandidate(_ id: String) -> Bool {
        guard let i = candidates.firstIndex(where: { $0.id == id || $0.id.hasPrefix(id) })
        else { return false }
        candidates.remove(at: i)
        saveCandidates()
        return true
    }

    // MARK: 导入

    struct ImportReport {
        var lines: [String] = []
        var failed: [String] = []
        var text: String {
            var s = lines.joined(separator: "\n")
            if !failed.isEmpty {
                s += "\n\n没读进来的：" + failed.joined(separator: "、")
            }
            return s.isEmpty ? "没认出任何一个文件。" : s
        }
    }

    /// 从电脑上那套导进来。
    ///
    /// 按**文件名**认：memories.json、diaries.json、periods.json……
    /// transcripts 文件夹里那些散文件也认——它们没有固定名字，
    /// 但内容里有 id / title / msgs 三样，照这个认。
    func importFiles(_ urls: [URL]) -> ImportReport {
        var report = ImportReport()

        for u in urls {
            let needsStop = u.startAccessingSecurityScopedResource()
            defer { if needsStop { u.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: u) else {
                report.failed.append(u.lastPathComponent)
                continue
            }
            let name = u.lastPathComponent.lowercased()
            let dec = JSONDecoder()

            switch name {
            case "memories.json":
                if let v = try? dec.decode([MemoryItem].self, from: data) {
                    memories = v; saveMemories()
                    report.lines.append("记忆 \(v.count) 条")
                } else { report.failed.append(name) }

            case "diaries.json":
                if let v = try? dec.decode([DiaryItem].self, from: data) {
                    diaries = v; saveDiaries()
                    report.lines.append("日记 \(v.count) 篇")
                } else { report.failed.append(name) }

            case "identity.json", "identity.txt":
                if let v = try? dec.decode(String.self, from: data) {
                    identity = v; saveIdentity()
                    report.lines.append("身份认知")
                } else if let s = String(data: data, encoding: .utf8) {
                    identity = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n "))
                    saveIdentity()
                    report.lines.append("身份认知")
                } else { report.failed.append(name) }

            case "current_state.json":
                if let v = try? dec.decode(StateNote.self, from: data) {
                    currentState = v; saveState()
                    report.lines.append("当前状态")
                } else { report.failed.append(name) }

            case "state_history.json":
                if let v = try? dec.decode([StateNote].self, from: data) {
                    stateHistory = v; saveState()
                    report.lines.append("状态历史 \(v.count) 条")
                } else { report.failed.append(name) }

            case "live_checkpoint.json":
                if let v = try? dec.decode(StateNote.self, from: data) {
                    checkpoint = v; saveCheckpoint()
                    report.lines.append("进度点")
                } else { report.failed.append(name) }

            case "spine.json":
                if let v = try? dec.decode(NarrativeSpine.self, from: data) {
                    spine = v; saveSpine()
                    report.lines.append("叙事脊椎")
                } else { report.failed.append(name) }

            case "rules.json":
                if let v = try? dec.decode([String].self, from: data) {
                    rules = v; saveSpine()
                    report.lines.append("规矩 \(v.count) 条")
                } else { report.failed.append(name) }

            case "open_tasks.json":
                if let v = try? dec.decode([String].self, from: data) {
                    openTasks = v; saveSpine()
                    report.lines.append("待办 \(v.count) 条")
                } else { report.failed.append(name) }

            case "promises.json":
                if let v = try? dec.decode([Promise].self, from: data) {
                    promises = v; savePromises()
                    report.lines.append("承诺 \(v.count) 条")
                } else { report.failed.append(name) }

            case "letter.json":
                if let v = try? dec.decode(StateNote.self, from: data) {
                    letter = v; saveLetter()
                    report.lines.append("写给下一个你")
                } else { report.failed.append(name) }

            case "partner_message.json":
                if let v = try? dec.decode(PartnerMessage.self, from: data) {
                    partnerMessage = v; savePartner()
                    report.lines.append("留言")
                } else { report.failed.append(name) }

            case "periods.json":
                if let v = try? dec.decode(PeriodBook.self, from: data) {
                    periods = v; savePeriods()
                    report.lines.append("经期 \(v.records.count) 次")
                } else { report.failed.append(name) }

            case "moods.json":
                if let v = try? dec.decode([String: [String: MoodEntry]].self, from: data) {
                    moods = v; saveMoods()
                    report.lines.append("心情 \(v.count) 天")
                } else { report.failed.append(name) }

            case "emotional_events.json":
                if let v = try? dec.decode([EmotionalEvent].self, from: data) {
                    emotionalEvents = v; saveEvents()
                    report.lines.append("情绪事件 \(v.count) 条")
                } else { report.failed.append(name) }

            case "candidates.json":
                if let v = try? dec.decode([MemoryCandidate].self, from: data) {
                    candidates = v; saveCandidates()
                    report.lines.append("待收的候选 \(v.count) 条")
                } else { report.failed.append(name) }

            case "glossary.json":
                if let v = try? dec.decode([GlossaryEntry].self, from: data) {
                    glossary = v; saveGlossary()
                    report.lines.append("黑话 \(v.count) 个")
                } else { report.failed.append(name) }

            case "memories_log.json":
                // 电脑那边的流水里 before/after 是对象，这边只留文字，
                // 认不出来就跳过，不值得为它卡住整次导入
                if let v = try? dec.decode([MemoryLogEntry].self, from: data) {
                    log = v; saveLog()
                    report.lines.append("修改流水 \(v.count) 条")
                }

            default:
                // transcripts 文件夹里那些
                if let t = try? dec.decode(TranscriptFile.self, from: data) {
                    saveTranscript(t)
                    report.lines.append("存档「\(t.title)」\(t.msgs.count) 条")
                } else {
                    // 认不出来再试一次 claude.ai 导出的那个格式
                    // （conversations.json，一个数组，正文在 chat_messages 里）
                    let convs = ClaudeExport.parse(data)
                    if convs.isEmpty {
                        report.failed.append(u.lastPathComponent)
                    } else {
                        for t in convs { saveTranscript(t) }
                        let total = convs.reduce(0) { $0 + $1.msgs.count }
                        report.lines.append("claude.ai \(convs.count) 段对话、\(total) 条")
                    }
                }
            }
        }
        // 导进来的是按写入顺序排的，最旧的在最前面，得倒过来
        sortNewestFirst()
        saveMemories()
        saveDiaries()
        return report
    }

    /// 全部导出成一个文件夹，方便再倒回电脑
    func exportBundle() -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("记忆库-\(Self.today)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        func put<T: Encodable>(_ v: T, _ n: String) {
            if let d = try? encoder.encode(v) {
                try? d.write(to: dir.appendingPathComponent(n))
            }
        }
        put(memories, "memories.json")
        put(candidates, "candidates.json")
        put(glossary, "glossary.json")
        put(diaries, "diaries.json")
        put(currentState, "current_state.json")
        put(stateHistory, "state_history.json")
        put(periods, "periods.json")
        put(moods, "moods.json")
        put(emotionalEvents, "emotional_events.json")
        put(log, "memories_log.json")
        put(spine, "spine.json")
        put(rules, "rules.json")
        put(openTasks, "open_tasks.json")
        put(promises, "promises.json")
        if let letter { put(letter, "letter.json") }
        if let checkpoint { put(checkpoint, "live_checkpoint.json") }
        if let partnerMessage { put(partnerMessage, "partner_message.json") }
        try? identity.write(to: dir.appendingPathComponent("identity.txt"),
                            atomically: true, encoding: .utf8)

        let tdir = dir.appendingPathComponent("transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: tdir, withIntermediateDirectories: true)
        for meta in transcripts {
            if let t = transcript(meta.id), let d = try? encoder.encode(t) {
                try? d.write(to: tdir.appendingPathComponent("\(meta.id).json"))
            }
        }
        return dir
    }

    /// 全部清空。导错了、或者想重来的时候用。
    func wipe() {
        try? FileManager.default.removeItem(at: Self.root)
        memories = []; diaries = []; identity = ""
        currentState = StateNote(); stateHistory = []
        checkpoint = nil; partnerMessage = nil
        periods = PeriodBook(); moods = [:]
        emotionalEvents = []; log = []; transcripts = []
        candidates = []; glossary = []
        promises = []; spine = NarrativeSpine(); rules = []; openTasks = []
        letter = nil
    }
}
