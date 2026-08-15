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
    /// 调用了几次
    var calls: Int = 0

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
            calls: a.calls + b.calls
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
    static func parse(_ usage: [String: Any]) -> TokenUsage {
        var u = TokenUsage()
        u.calls = 1

        let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
        let inputDetails = usage["input_tokens_details"] as? [String: Any]

        u.cacheRead = (usage["cache_read_input_tokens"] as? Int)
            ?? (promptDetails?["cached_tokens"] as? Int)
            ?? (inputDetails?["cached_tokens"] as? Int)
            ?? 0
        u.cacheWrite = (usage["cache_creation_input_tokens"] as? Int)
            ?? (promptDetails?["cache_creation_tokens"] as? Int)
            ?? 0

        if let prompt = usage["prompt_tokens"] as? Int {
            // OpenAI 口径：prompt 里已经含了命中的缓存
            u.input = max(0, prompt - u.cacheRead - u.cacheWrite)
        } else if let input = usage["input_tokens"] as? Int {
            u.input = input
        }

        u.output = (usage["completion_tokens"] as? Int)
            ?? (usage["output_tokens"] as? Int)
            ?? 0

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
    case journey     // 旅行卡
    case image       // 生图
    case tts         // 朗读
    case asr         // 语音转文字
    case search      // 联网搜索
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat:       return "聊天"
        case .group:      return "群聊"
        case .call:       return "打电话"
        case .translate:  return "翻译"
        case .distill:    return "提炼"
        case .divination: return "占卜"
        case .sticker:    return "表情包"
        case .journey:    return "旅行卡"
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
        case .journey:    return "airplane"
        case .image:      return "photo.artframe"
        case .tts:        return "waveform"
        case .asr:        return "mic"
        case .search:     return "magnifyingglass"
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
