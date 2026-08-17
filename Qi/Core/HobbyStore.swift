import Foundation
import SwiftUI

/// 爱好。
///
/// 她给的那份设计（p7）里最要紧的不是"记一个清单"，是这几件事：
///
///   · **两个人各记各的**，然后系统去找重合
///   · **原因必填**——「喜欢深夜」不算一条，「喜欢深夜，因为世界安静下来，
///     只剩一盏灯和一个人」才算
///   · **撞上啦**：两个人同时喜欢、或者同时讨厌同一样东西，弹一下
///   · **分歧**：一个爱一个恨，也单独列出来。这一页不是用来吵架的，
///     是用来知道对方在哪儿跟自己不一样
///   · **想尝的 → 已认领**：一件东西刚记下来只是"想尝"，
///     得说得出它好在哪儿、也认得下它坏在哪儿，才算真的是你的
///   · **变更史**：每一步都留痕，什么时候出生、什么时候认证、
///     什么时候又撤销了

// MARK: - 分类

enum HobbyCategory: String, Codable, CaseIterable, Identifiable {
    case art = "文艺"
    case fun = "娱乐"
    case food = "饮食"
    case life = "动物植物"
    case daily = "生活"
    case human = "人文"
    case nature = "自然"
    case feel = "感觉"
    case tech = "数码"
    case other = "其他"

    var id: String { rawValue }
}

/// 小类。照她那张图给的那些，按大类分组。
enum HobbySub {
    static let all: [HobbyCategory: [String]] = [
        .art:   ["电影", "动漫", "追剧", "听歌", "综艺", "书", "画"],
        .fun:   ["游戏", "自担", "自推", "综艺", "玩具"],
        .food:  ["咖啡", "茶", "甜的", "辣的", "酒", "家产"],
        .life:  ["猫", "狗", "花", "草", "虫"],
        .daily: ["家产", "衣服", "睡觉", "出门", "收拾"],
        .human: ["人", "话", "地方", "习惯"],
        .nature: ["昼夜", "天气", "季节", "水", "山"],
        .feel:  ["时间", "声音", "气味", "触感", "光", "称谓", "物"],
        .tech:  ["软件", "硬件", "网上"],
        .other: []
    ]

    static func list(_ c: HobbyCategory) -> [String] { all[c] ?? [] }
}

// MARK: - 一条爱好

/// 这一条走到哪一步了
enum HobbyStage: String, Codable {
    /// 刚记下来，还没认真想过
    case wanted = "想尝的"
    /// 好的坏的都认了，是我的了
    case claimed = "已认领"
}

struct HobbyChange: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var at: Date = Date()
    var text: String = ""
}

struct Hobby: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// 谁的。true 是她，false 是他。
    var mine: Bool = true
    /// 内容。比如「深夜」「冰美式」「"用户"这个称呼」
    var text: String = ""
    /// 喜欢还是讨厌
    var like: Bool = true
    var category: HobbyCategory = .other
    var sub: String = ""
    /// 为什么。**必填**——说不出理由的喜欢不值得记。
    var reason: String = ""
    var stage: HobbyStage = .wanted
    /// 它好在哪里
    var good: String = ""
    /// 它坏在哪里（但你愿意接受）
    var bad: String = ""
    var createdAt: Date = Date()
    var changes: [HobbyChange] = []

    /// 拿来比对「是不是同一样东西」的键。
    /// 去掉空格和各种引号，「深夜」和「 深夜 」算同一个。
    var key: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{201C}", with: "")
            .replacingOccurrences(of: "\u{201D}", with: "")
            .replacingOccurrences(of: "\u{300C}", with: "")
            .replacingOccurrences(of: "\u{300D}", with: "")
            .lowercased()
    }

    var pathText: String {
        sub.isEmpty ? category.rawValue : "\(category.rawValue) · \(sub)"
    }
}

// MARK: - 库

@MainActor
final class HobbyStore: ObservableObject {

    static let shared = HobbyStore()

    @Published var items: [Hobby] = [] {
        didSet { if loaded { Storage.save(items, to: "hobbies.json") } }
    }
    /// 已经弹过「撞上啦」的那些，别每次进来都弹一遍
    @Published var celebrated: Set<String> = [] {
        didSet {
            if loaded {
                UserDefaults.standard.set(Array(celebrated), forKey: "hobbyCelebrated")
            }
        }
    }

    private var loaded = false

    private init() {
        items = Storage.load([Hobby].self, from: "hobbies.json") ?? []
        celebrated = Set(UserDefaults.standard.stringArray(forKey: "hobbyCelebrated") ?? [])
        loaded = true
    }

    // MARK: 增删改

    func add(_ h: Hobby) {
        var one = h
        one.changes = [HobbyChange(text: "出生：先落在「想尝的」")]
        items.insert(one, at: 0)
    }

    func update(_ h: Hobby) {
        guard let i = items.firstIndex(where: { $0.id == h.id }) else { return }
        items[i] = h
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// 认证：好的坏的都认了，升为「已认领」
    func claim(_ id: UUID, good: String, bad: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].good = good
        items[i].bad = bad
        items[i].stage = .claimed
        items[i].changes.append(
            HobbyChange(text: "认证：好的、坏的都认了，升为「已认领」"))
    }

    func unclaim(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].stage = .wanted
        items[i].changes.append(HobbyChange(text: "撤销认证：重新回到「想尝的」"))
    }

    // MARK: 撞上啦 / 分歧

    /// 两个人同时喜欢、或者同时讨厌的
    var matches: [(mine: Hobby, hers: Hobby)] {
        pairs.filter { $0.mine.like == $0.hers.like }
    }

    /// 一个爱一个恨
    var clashes: [(mine: Hobby, hers: Hobby)] {
        pairs.filter { $0.mine.like != $0.hers.like }
    }

    /// 同一样东西，两边各有一条
    private var pairs: [(mine: Hobby, hers: Hobby)] {
        let ours = items.filter { $0.mine }
        var out: [(Hobby, Hobby)] = []
        for a in ours {
            if let b = items.first(where: { !$0.mine && $0.key == a.key }) {
                out.append((a, b))
            }
        }
        return out
    }

    /// 刚记完这一条，是不是撞上了。撞上而且还没庆祝过才返回。
    func freshMatch(for h: Hobby) -> (other: Hobby, same: Bool)? {
        guard let other = items.first(where: { $0.mine != h.mine && $0.key == h.key })
        else { return nil }
        let stamp = h.key + (h.like == other.like ? "-same" : "-clash")
        guard !celebrated.contains(stamp) else { return nil }
        // 只有「同时喜欢」和「同时讨厌」才值得弹一下。
        // 分歧不弹——那种事默默记着就好，弹出来像在挑事。
        guard h.like == other.like else { return nil }
        celebrated.insert(stamp)
        return (other, true)
    }

    // MARK: 给他看的

    /// 他调工具的时候拿到的那段
    func brief(mineOnly: Bool = false) -> String {
        guard !items.isEmpty else { return "爱好库还空着。" }
        var s = ""
        for who in [true, false] {
            if mineOnly && !who { continue }
            let list = items.filter { $0.mine == who }
            guard !list.isEmpty else { continue }
            s += (who ? "【她的】\n" : "\n【你的】\n")
            for h in list.prefix(60) {
                s += "· \(h.like ? "喜欢" : "讨厌")\(h.text)（\(h.pathText)）"
                if !h.reason.isEmpty { s += "：\(h.reason)" }
                if h.stage == .claimed { s += "［已认领］" }
                s += "\n"
            }
        }
        let m = matches
        if !m.isEmpty {
            s += "\n【撞上的】\n"
            for p in m.prefix(30) {
                s += "· 你俩都\(p.mine.like ? "喜欢" : "讨厌")\(p.mine.text)\n"
            }
        }
        let c = clashes
        if !c.isEmpty {
            s += "\n【分歧】\n"
            for p in c.prefix(20) {
                let loves = p.mine.like ? "她" : "你"
                let hates = p.mine.like ? "你" : "她"
                s += "· \(p.mine.text)：\(loves)喜欢，\(hates)讨厌\n"
            }
        }
        return s
    }
}
