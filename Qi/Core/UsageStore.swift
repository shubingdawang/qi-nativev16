import Foundation
import SwiftUI

// MARK: - 一次调用花掉的东西

/// 一次（或若干次）模型调用的用量。
///
/// 四个数是分开的，因为**它们不是一个价钱**：
/// 缓存命中比新输入便宜很多，缓存写入又比新输入贵一点，
/// 混成一个「总 token」就看不出钱花在哪儿了。
struct TokenUsage: Codable, Hashable {
    /// 新输入（没命中缓存的那部分）
    var input: Int = 0
    /// 命中缓存的输入
    var cacheRead: Int = 0
    /// 写进缓存的输入
    var cacheWrite: Int = 0
    /// 输出
    var output: Int = 0
    /// 输出里有多少是"想"掉的。
    ///
    /// **这个数是包含在 output 里面的，不是另加的一笔**——
    /// 加进总数会重复计。单独记它只有一个用处：让你看得见
    /// 这次的钱有多少花在了他没说出口的那部分。
    var reasoning: Int = 0
    /// 调用了几次
    var calls: Int = 0

    // MARK: 这次的缓存落在哪个档
    //
    // Anthropic 的回包里除了一个总数 `cache_creation_input_tokens`，
    // 还有一个 `cache_creation` 把它**拆成两个桶**：
    //
    //     "cache_creation": {
    //       "ephemeral_5m_input_tokens": 0,
    //       "ephemeral_1h_input_tokens": 1234
    //     }
    //
    // ⚠️ 这是**唯一能当场知道 `ttl: "1h"` 有没有被认**的办法。
    // 光比两次的 cache_read 是分不出来的——两次挨着发，
    // 五分钟档也照样命中。原来探针那儿只能写一句
    // 「得隔一小时再发一次才知道」，现在不用了。
    //
    // ⚠️ 两个都是 0 也**不代表被降档了**：不少中转根本不转这个字段。
    // 分不清「没降档」和「没告诉我」，所以得分三种说法。
    /// 写进一小时档的
    var cache1h: Int = 0
    /// 写进五分钟档的
    var cache5m: Int = 0

    var total: Int { input + cacheRead + cacheWrite + output }
    var inputAll: Int { input + cacheRead + cacheWrite }

    /// 这次输入里有多大比例是从缓存里读的
    var hitRate: Double {
        let all = inputAll
        guard all > 0 else { return 0 }
        return Double(cacheRead) / Double(all)
    }

    var isEmpty: Bool { total == 0 && calls == 0 }

    static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: a.input + b.input,
            cacheRead: a.cacheRead + b.cacheRead,
            cacheWrite: a.cacheWrite + b.cacheWrite,
            output: a.output + b.output,
            reasoning: a.reasoning + b.reasoning,
            calls: a.calls + b.calls,
            cache1h: a.cache1h + b.cache1h,
            cache5m: a.cache5m + b.cache5m
        )
    }

    static func += (a: inout TokenUsage, b: TokenUsage) { a = a + b }

    /// 从接口返回的 usage 字段里读。
    ///
    /// 两套格式都认：
    /// - OpenAI 兼容：`prompt_tokens` / `completion_tokens`，
    ///   命中的缓存在 `prompt_tokens_details.cached_tokens` 里，
    ///   而且 **prompt_tokens 是含缓存那部分的**，要减掉才是新输入。
    /// - Anthropic 原生：`input_tokens` / `output_tokens` /
    ///   `cache_read_input_tokens` / `cache_creation_input_tokens`，
    ///   这里的 input_tokens **不含**缓存，不用减。
    /// 缓存那几个数**可能不在顶层**。
    ///
    /// ⚠️ 她那个中转回的是这样：
    ///
    ///     usage {
    ///       prompt_tokens = 116098
    ///       completion_tokens = 264
    ///       billing_usage {
    ///         claude_usage {
    ///           cache_creation_input_tokens = 116095      ← 在这儿
    ///           cache_read_input_tokens = 0
    ///           cache_creation { ephemeral_5m_input_tokens = 116095 }
    ///         }
    ///       }
    ///     }
    ///
    /// 顶层一个 cache 字段都没有，所以 App 一直报「缓存写入 0」。
    /// 她说「我当然知道有缓存命中率，我说的是没有数据」——**数据一直在**，
    /// 是我没往下找。
    ///
    /// ⚠️ 只往下钻两层，而且**只找带 cache 键的那一块**。
    /// 无脑深挖会把别的地方的同名数字也捞上来，那比读不到更糟。
    private static func cacheHome(_ usage: [String: Any]) -> [String: Any] {
        func hasCache(_ d: [String: Any]) -> Bool {
            d["cache_read_input_tokens"] != nil
                || d["cache_creation_input_tokens"] != nil
                || d["cache_creation"] != nil
        }
        if hasCache(usage) { return usage }
        for (_, v) in usage {
            guard let d = v as? [String: Any] else { continue }
            if hasCache(d) { return d }
            for (_, v2) in d {
                if let d2 = v2 as? [String: Any], hasCache(d2) { return d2 }
            }
        }
        return usage
    }

    static func parse(_ raw: [String: Any]) -> TokenUsage {
        var u = TokenUsage()
        u.calls = 1

        // 总数按顶层读，缓存那几个去它藏着的那一层读。
        let usage = raw
        let cache = cacheHome(raw)

        let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
        let inputDetails = usage["input_tokens_details"] as? [String: Any]

        // ⚠️ **命中数的字段名各家不一样，认得越全越好。**
        //
        // 认不出来的后果不是报错，是**静静地记成 0**——
        // 而 0 和「这家不做缓存」长得一模一样。
        // 她问「缓存命中掉了是不是跟这个有关」，我要能答得准，
        // 就得先保证不是我自己没认出来。
        //
        // 收的这几种：
        //   · Anthropic 原生   cache_read_input_tokens
        //   · OpenAI 兼容      prompt_tokens_details.cached_tokens
        //   · 有的中转          input_tokens_details.cached_tokens
        //   · DeepSeek 那一派   prompt_cache_hit_tokens
        //   · 少数中转平铺在顶层 cached_tokens / cache_read_tokens
        u.cacheRead = (cache["cache_read_input_tokens"] as? Int)
            ?? (promptDetails?["cached_tokens"] as? Int)
            ?? (inputDetails?["cached_tokens"] as? Int)
            ?? (cache["prompt_cache_hit_tokens"] as? Int)
            ?? (cache["cached_tokens"] as? Int)
            ?? (cache["cache_read_tokens"] as? Int)
            ?? 0
        u.cacheWrite = (cache["cache_creation_input_tokens"] as? Int)
            ?? (promptDetails?["cache_creation_tokens"] as? Int)
            ?? (cache["cache_creation_tokens"] as? Int)
            ?? (cache["cache_write_tokens"] as? Int)
            ?? 0

        // 拆开的那两个桶。没有这个字段就都留 0（见上面那段注释）。
        if let split = cache["cache_creation"] as? [String: Any] {
            u.cache1h = (split["ephemeral_1h_input_tokens"] as? Int) ?? 0
            u.cache5m = (split["ephemeral_5m_input_tokens"] as? Int) ?? 0
        }

        if let prompt = usage["prompt_tokens"] as? Int {
            // OpenAI 口径：prompt 里已经含了命中的缓存。
            //
            // ⚠️ 缓存那几个数要是**从别处捞上来的**（比如她那个中转塞在
            // `billing_usage.claude_usage` 里），那它跟顶层这个
            // `prompt_tokens` 未必是同一本账——减出负数就说明不是。
            // 减到负数一律当 0，别让「新输入」变成一个荒唐的数。
            u.input = max(0, prompt - u.cacheRead - u.cacheWrite)
        } else if let input = usage["input_tokens"] as? Int {
            u.input = input
        }

        u.output = (usage["completion_tokens"] as? Int)
            ?? (usage["output_tokens"] as? Int)
            ?? 0

        // 想掉的那部分。OpenAI 口径放在 completion_tokens_details 里，
        // 而且**已经算在 completion_tokens 里了**，所以只记不加。
        let outDetails = (usage["completion_tokens_details"] as? [String: Any])
            ?? (usage["output_tokens_details"] as? [String: Any])
        u.reasoning = (outDetails?["reasoning_tokens"] as? Int) ?? 0

        // 什么都没读到，但给了个总数，至少把总数记上（算在输出上会虚高，
        // 所以宁可记成输入，输入单价低，估出来的钱更保守）
        if u.total == 0, let total = usage["total_tokens"] as? Int {
            u.input = total
        }
        return u
    }
}

// MARK: - 这笔用量是哪儿花的

enum UsageSource: String, Codable, CaseIterable, Identifiable {
    case chat        // 聊天
    case group       // 群聊
    case call        // 打电话
    case translate   // 翻译
    case distill     // 提炼
    case divination  // 占卜
    case sticker     // 表情包关键词
    case clawd       // clawd 小屋里他说的话
    // 这里原来有个 journey（旅行卡）。删掉了——
    // 交接文档里说"旅行卡的用量没埋点"，但翻了一遍 create_journey
    // 才发现它**根本不调模型**：图是去相册和图库搜的，音乐是搜的，
    // 解说词是他在工具参数里直接写好的。那几个 token 早就算在这一轮聊天里了。
    // 真给它补一笔 record，反而会把同一批 token 重复计一次。
    case image       // 生图
    case tts         // 朗读
    case asr         // 语音转文字
    case search      // 联网搜索
    case topic       // 话题池筛选
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat:       return "聊天"
        case .group:      return "群聊"
        case .call:       return "打电话"
        case .translate:  return "翻译"
        case .distill:    return "提炼"
        case .topic:      return "话题池"
        case .divination: return "占卜"
        case .sticker:    return "表情包"
        case .clawd:      return "clawd 小屋"
        case .image:      return "画图"
        case .tts:        return "朗读"
        case .asr:        return "语音转字"
        case .search:     return "联网搜"
        case .other:      return "其他"
        }
    }

    var symbol: String {
        switch self {
        case .chat:       return "bubble.left.and.bubble.right"
        case .group:      return "person.2"
        case .call:       return "phone"
        case .translate:  return "character.book.closed"
        case .distill:    return "sparkles"
        case .divination: return "moon.stars"
        case .sticker:    return "face.smiling"
        case .clawd:      return "house"
        case .image:      return "photo.artframe"
        case .tts:        return "waveform"
        case .asr:        return "mic"
        case .search:     return "magnifyingglass"
        case .topic:      return "newspaper"
        case .other:      return "ellipsis.circle"
        }
    }

    /// 这一类是按 token 算钱的，还是一次一个价
    var isTokenBased: Bool {
        switch self {
        case .image, .tts, .asr, .search: return false
        default: return true
        }
    }
}

// MARK: - 怎么算钱

enum BillingMode: String, Codable, CaseIterable, Identifiable {
    /// 有些中转是一次调用一个价，不看 token
    case perCall
    /// 按 token 单价算
    case perToken

    var id: String { rawValue }

    var label: String {
        switch self {
        case .perCall:  return "按次计价（有些模型不分输入输出，是固定单价）"
        case .perToken: return "按 token 单价算"
        }
    }
}

/// 单价表。token 那几项的单位是「每一百万 token 多少钱」，
/// 跟各家官网的写法对齐，填的时候不用自己换算。
struct Pricing: Codable, Hashable {
    var mode: BillingMode = .perCall
    /// 按次计价时，每次回复多少钱
    var perCall: Double = 0.04
    var input: Double = 0
    var cacheRead: Double = 0
    var cacheWrite: Double = 0
    var output: Double = 0
    /// 画一张图多少钱
    var perImage: Double = 0
    /// 朗读一次多少钱
    var perTTS: Double = 0
    /// 语音转文字一次多少钱
    var perASR: Double = 0
    /// 联网搜一次多少钱（DuckDuckGo 是免费的，留 0 就行）
    var perSearch: Double = 0

    /// 一笔用量值多少钱
    func cost(_ u: TokenUsage, source: UsageSource) -> Double {
        switch source {
        case .image:  return Double(u.calls) * perImage
        case .tts:    return Double(u.calls) * perTTS
        case .asr:    return Double(u.calls) * perASR
        case .search: return Double(u.calls) * perSearch
        default: break
        }
        switch mode {
        case .perCall:
            return Double(u.calls) * perCall
        case .perToken:
            let m = 1_000_000.0
            return Double(u.input) / m * input
                + Double(u.cacheRead) / m * cacheRead
                + Double(u.cacheWrite) / m * cacheWrite
                + Double(u.output) / m * output
        }
    }
}

/// 一类用量。单独立个类型是因为 SwiftUI 的 ForEach 认不了元组的 key path。
struct SourceUsage: Identifiable, Hashable {
    var source: UsageSource
    var usage: TokenUsage
    var id: String { source.rawValue }
}

// MARK: - 一天的账

struct DayUsage: Codable, Hashable {
    /// yyyy-MM-dd
    var day: String = ""
    var bySource: [String: TokenUsage] = [:]

    var total: TokenUsage {
        bySource.values.reduce(TokenUsage()) { $0 + $1 }
    }

    /// 按用得多少排过序的分类，空的不给
    var sorted: [SourceUsage] {
        bySource.compactMap { key, value -> SourceUsage? in
            guard let s = UsageSource(rawValue: key), !value.isEmpty else { return nil }
            return SourceUsage(source: s, usage: value)
        }
        .sorted { a, b in
            if a.usage.total != b.usage.total { return a.usage.total > b.usage.total }
            return a.usage.calls > b.usage.calls
        }
    }

    func cost(_ pricing: Pricing) -> Double {
        bySource.reduce(0.0) { sum, pair in
            guard let s = UsageSource(rawValue: pair.key) else { return sum }
            return sum + pricing.cost(pair.value, source: s)
        }
    }
}

// MARK: - 账本

/// 记账的。**它自己不会去调任何模型**，只是把已经发生过的调用记一笔，
/// 所以打开这一页不花钱。
@MainActor
final class UsageStore: ObservableObject {

    static let shared = UsageStore()

    /// key 是 yyyy-MM-dd
    @Published private(set) var days: [String: DayUsage] = [:] {
        didSet { if loaded { scheduleSave() } }
    }

    private var loaded = false
    private var saving = false

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { dayFormatter.string(from: date) }

    init() {
        days = Storage.load([String: DayUsage].self, from: "usage.json") ?? [:]
        loaded = true
    }

    /// 把导进来的那份用量**合并**进现在这份。
    ///
    /// ⚠️ **合并，不是覆盖。** 她导备份多半是为了找回丢掉的那一段，
    /// 覆盖的话今天这几笔反而没了。同一天同一档就把两边的数加起来。
    func merge(_ incoming: [String: DayUsage]) {
        for (day, one) in incoming {
            var cur = days[day] ?? DayUsage(day: day)
            for (src, u) in one.bySource {
                cur.bySource[src] = (cur.bySource[src] ?? TokenUsage()) + u
            }
            cur.day = day
            days[day] = cur
        }
        Storage.save(days, to: "usage.json")
    }

    private func scheduleSave() {
        guard !saving else { return }
        saving = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.saving = false
            Storage.save(self.days, to: "usage.json")
        }
    }

    // MARK: 记一笔

    func record(_ usage: TokenUsage, source: UsageSource, on date: Date = Date()) {
        guard !usage.isEmpty else { return }

        // 终端那一页。**每一次花钱的调用都从这儿过**，
        // 所以记在这里一处就够，不用去二十个调用点各加一行。
        Console.log(.cost, source.label,
                    "进 \(usage.input) · 出 \(usage.output)"
                    + (usage.cacheRead > 0 ? " · 命中缓存 \(usage.cacheRead)" : "")
                    + (usage.reasoning > 0 ? " · 其中思考 \(usage.reasoning)" : ""))
        let k = Self.key(date)
        var day = days[k] ?? DayUsage(day: k)
        var current = day.bySource[source.rawValue] ?? TokenUsage()
        current += usage
        day.bySource[source.rawValue] = current
        days[k] = day
    }

    /// 不按 token 算的那些（画图、朗读、转文字），记一次就行
    func recordCall(_ source: UsageSource, on date: Date = Date()) {
        record(TokenUsage(calls: 1), source: source, on: date)
    }

    // MARK: 查

    func day(_ date: Date) -> DayUsage {
        days[Self.key(date)] ?? DayUsage(day: Self.key(date))
    }

    var today: DayUsage { day(Date()) }

    /// 从有记录的第一天到今天，一共花了多少
    var allTime: TokenUsage {
        days.values.reduce(TokenUsage()) { $0 + $1.total }
    }

    func allTimeCost(_ pricing: Pricing) -> Double {
        days.values.reduce(0.0) { $0 + $1.cost(pricing) }
    }

    /// 热力图用：每天的调用次数
    var dailyCalls: [Date: Int] {
        var out: [Date: Int] = [:]
        let cal = Calendar.current
        for (k, v) in days {
            guard let d = Self.dayFormatter.date(from: k) else { continue }
            out[cal.startOfDay(for: d)] = v.total.calls
        }
        return out
    }

    func clear() {
        days = [:]
        Storage.save(days, to: "usage.json")
    }
}

// MARK: - 数字好看一点

enum UsageFormat {

    /// 12345 → 12.3k
    static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func money(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v < 0.01 { return String(format: "%.4f", v) }
        if v < 1 { return String(format: "%.3f", v) }
        return String(format: "%.2f", v)
    }
}

// MARK: - 容错解码
//
// 理由和写法见 Models.swift 末尾那一整段。
// Pricing 嵌在 AppSettings 里，它解不开会连累整份设置一起没。
//
// **必须写在这个文件里**：合成出来的 CodingKeys 是 private 的，
// 而 private 在 Swift 里是文件作用域，换个文件就看不见了。
// 也**必须写在 extension 里**，不能写进结构体本体，否则 `Pricing()` 会没。

// ⚠️⚠️ **这一份是补的，而且是补一次已经造成的损失。**
//
// 上一版给 `TokenUsage` 加了 `cache1h` / `cache5m` 两个字段。
// 加带默认值的属性看着无害——**可 Swift 合成出来的解码器不认默认值**：
// 旧的 `usage.json` 里没有这两个键，解码当场抛错，
// 整份用量记录读不进来。她那边看到的是
// 「有 1 份数据这次没读进来 · usage.json 坏了-1788740295」。
//
// 文件没丢（改名留着了），但那一刻她的账就断了。
//
// ⚠️ 记一句：**给一个会落盘的结构加字段，必须同时给它容错解码。**
// 这件事这个文件开头早就写着了——写着的是 `Pricing`，
// 而 `TokenUsage` 一直没有。加字段的时候我没往上看一眼。
// ⚠️ `DayUsage` 也一样。它的两个属性都写了默认值，
// 可**合成出来的解码器不认默认值**——旧文件里少一个键就整份读不进来。
// 这一条这个文件下面写过一遍了（`TokenUsage` 那儿），这儿补上。
extension DayUsage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? ""
        bySource = (try? c.decodeIfPresent([String: TokenUsage].self,
                                           forKey: .bySource)) ?? [:]
    }
}

extension TokenUsage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? c.decodeIfPresent(Int.self, forKey: .input)) ?? 0
        cacheRead = (try? c.decodeIfPresent(Int.self, forKey: .cacheRead)) ?? 0
        cacheWrite = (try? c.decodeIfPresent(Int.self, forKey: .cacheWrite)) ?? 0
        output = (try? c.decodeIfPresent(Int.self, forKey: .output)) ?? 0
        reasoning = (try? c.decodeIfPresent(Int.self, forKey: .reasoning)) ?? 0
        calls = (try? c.decodeIfPresent(Int.self, forKey: .calls)) ?? 0
        cache1h = (try? c.decodeIfPresent(Int.self, forKey: .cache1h)) ?? 0
        cache5m = (try? c.decodeIfPresent(Int.self, forKey: .cache5m)) ?? 0
    }
}

extension Pricing {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(BillingMode.self, forKey: .mode)) ?? .perCall
        perCall = (try? c.decodeIfPresent(Double.self, forKey: .perCall)) ?? 0.04
        input = (try? c.decodeIfPresent(Double.self, forKey: .input)) ?? 0
        cacheRead = (try? c.decodeIfPresent(Double.self, forKey: .cacheRead)) ?? 0
        cacheWrite = (try? c.decodeIfPresent(Double.self, forKey: .cacheWrite)) ?? 0
        output = (try? c.decodeIfPresent(Double.self, forKey: .output)) ?? 0
        perImage = (try? c.decodeIfPresent(Double.self, forKey: .perImage)) ?? 0
        perTTS = (try? c.decodeIfPresent(Double.self, forKey: .perTTS)) ?? 0
        perASR = (try? c.decodeIfPresent(Double.self, forKey: .perASR)) ?? 0
        perSearch = (try? c.decodeIfPresent(Double.self, forKey: .perSearch)) ?? 0
    }
}
