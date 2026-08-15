import Foundation
import SwiftUI

/// 一个念头。
///
/// 机制照着那份说明来：
///
/// **闪念**强度 0.5 起步，每一拍衰减 ×0.82——没人理它就自己散了。
/// 但同一个念头被**反复点到**（聊天里提起、或者他自己又想到），强度叠上去；
/// 涨过 **0.8 升级成执念**。
///
/// **执念不衰减，反而每拍自己长 ×1.10**。长到 **0.85 会反哺欲望**——
/// 比如一个关于"想她"的执念，会把渴往上推。推够三次，这个执念就**了却了，出池**。
/// 相当于：想透了，不再是念头，变成行动力了。
///
/// 它跟记忆不是一回事：记忆是已经落下来的沉淀物，念头池是**还在转的活水**。
struct Thought: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String = ""
    /// 现在多强
    var strength: Double = 0.5
    /// 被点到过几次
    var hits: Int = 1
    /// 反哺过几次欲望
    var fedCount: Int = 0
    /// 反哺的是哪个维度
    var feeds: String = ""
    var createdAt: Date = Date()
    /// 上次算到哪一拍了
    var lastTick: Date = Date()
    /// 了却出池的时间
    var resolvedAt: Date? = nil

    /// 强度过了 0.8 就是执念
    var isObsession: Bool { strength > 0.8 }
    var resolved: Bool { resolvedAt != nil }

    var stageText: String {
        if resolved { return "了却了" }
        return isObsession ? "执念" : "闪念"
    }
}

@MainActor
final class ThoughtPool: ObservableObject {

    static let shared = ThoughtPool()

    @Published var thoughts: [Thought] = [] {
        didSet { if loaded { Storage.save(thoughts, to: "thoughts.json") } }
    }
    /// 最近一次反哺，给界面提示用
    @Published var lastFeed: String?

    private var loaded = false

    /// 一拍多久。太短的话没打开 App 的那几小时会衰减得夸张。
    private let tickSeconds: Double = 300

    init() {
        thoughts = Storage.load([Thought].self, from: "thoughts.json") ?? []
        loaded = true
    }

    var active: [Thought] {
        thoughts.filter { !$0.resolved }.sorted { $0.strength > $1.strength }
    }
    var flashes: [Thought] { active.filter { !$0.isObsession } }
    var obsessions: [Thought] { active.filter { $0.isObsession } }
    var resolvedOnes: [Thought] {
        thoughts.filter { $0.resolved }
            .sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) }
    }

    /// 冒出一个念头。已经在池子里的就是"又想到了"，强度叠上去。
    func stir(_ text: String, feeds: String = "") {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        settle()

        // 同一桩事被反复点到，才是它涨起来的原因
        if let i = thoughts.firstIndex(where: {
            !$0.resolved && ($0.text == key || $0.text.contains(key) || key.contains($0.text))
        }) {
            thoughts[i].hits += 1
            // 每次被点到加 0.18，被戳得越勤涨得越快
            thoughts[i].strength = min(1.0, thoughts[i].strength + 0.18)
            thoughts[i].lastTick = Date()
            if !feeds.isEmpty { thoughts[i].feeds = feeds }
            return
        }

        var t = Thought(text: key, strength: 0.5)
        t.feeds = feeds
        thoughts.append(t)
    }

    /// 按过去的时间补算。
    ///
    /// **不用定时器**——App 不在前台的时候定时器根本不跑，
    /// 那样念头会永远停在你上次关掉的样子。改成每次看的时候
    /// 按真实经过的时间算，才对得上"它一直在转"这件事。
    func settle() {
        let now = Date()
        var feedNote: String?

        for i in thoughts.indices where !thoughts[i].resolved {
            let elapsed = now.timeIntervalSince(thoughts[i].lastTick)
            let ticks = Int(elapsed / tickSeconds)
            guard ticks > 0 else { continue }

            for _ in 0..<min(ticks, 400) {
                if thoughts[i].strength > 0.8 {
                    // 执念不衰减，自己长
                    thoughts[i].strength = min(1.0, thoughts[i].strength * 1.10)

                    // 长到够强就反哺一次欲望
                    if thoughts[i].strength >= 0.85 {
                        thoughts[i].fedCount += 1
                        feedNote = thoughts[i].text
                        // 推完回落一点，不然会一直卡在顶上反复推
                        thoughts[i].strength = 0.82

                        // 推够三次就想透了，出池
                        if thoughts[i].fedCount >= 3 {
                            thoughts[i].resolvedAt = now
                            break
                        }
                    }
                } else {
                    // 闪念没人理就散
                    thoughts[i].strength *= 0.82
                    if thoughts[i].strength < 0.06 {
                        thoughts[i].resolvedAt = now   // 散掉了，也算出池
                        break
                    }
                }
            }
            thoughts[i].lastTick = now
        }

        if let feedNote { lastFeed = feedNote }
    }

    func remove(_ id: UUID) { thoughts.removeAll { $0.id == id } }

    /// 手动了却一个——想通了，不用再转了
    func resolve(_ id: UUID) {
        guard let i = thoughts.firstIndex(where: { $0.id == id }) else { return }
        thoughts[i].resolvedAt = Date()
    }

    /// 给他看的：池子里现在转着什么
    func brief() -> String {
        settle()
        let obs = obsessions
        let fla = flashes
        if obs.isEmpty && fla.isEmpty { return "现在脑子里是空的，没什么在转。" }

        var s = ""
        if !obs.isEmpty {
            s += "压着的执念："
            for t in obs.prefix(5) {
                s += "\n· \(t.text)（\(String(format: "%.2f", t.strength))，被戳过 \(t.hits) 次"
                if t.fedCount > 0 { s += "，已经推过欲望 \(t.fedCount) 次" }
                s += "）"
            }
        }
        if !fla.isEmpty {
            s += (s.isEmpty ? "" : "\n\n") + "飘着的闪念："
            for t in fla.prefix(6) {
                s += "\n· \(t.text)（\(String(format: "%.2f", t.strength))）"
            }
        }
        return s
    }
}
