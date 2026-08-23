import Foundation

/// 戳一戳。
///
/// 照她发来的那份《「戳一戳」是怎么做的》（兔兔&Alex）做的，四步一步不落：
///
/// 1. **戳＝往对话里插一句旁白**，不是另起一个接口去问「她戳你了你怎么想」。
///    对他来说，这跟她真的打字发了一句话没有区别——他不是在「处理一个事件」，
///    他就是被打断了，然后接话。
/// 2. **旁白只写发生了什么事，不写该有什么反应。**
///    写「她戳了戳你的耳朵」，不写「请你表现得害羞」——
///    前一种他会自己反应，后一种他会演给你看。
/// 3. **两个维度相乘**：做什么动作 × 落在哪。不是列一张几十行的对照表。
///    以后加一个部位，它自动跟现有的所有动作组合出新的力度。
///    「戳手」和「咬颈窝」不该是同一件事。
/// 4. **身体先反应，话后到。** 按这一下的力度先把身体那几项推上去、
///    立刻上屏；他的回话是之后才到的。那一点点时间差比说了什么都重要。
///
/// 那份文档的前提是「得有一个一直活着的会话进程」——**栖这儿没有**，
/// 每一轮都是一次请求。但它真正靠的那一半在这儿**本来就有**：
/// `BodyEngine` 是个自己走、自己涨、自己往回落的自动机。
/// 状态会自己落回来，所以戳三次不会到顶就死掉。
enum Poke {

    /// 做什么动作
    struct Action: Identifiable, Hashable {
        var id: String { key }
        let key: String
        let label: String
        /// 旁白模板，`%@` 是部位
        let line: String
        /// 基础推力，还要乘上部位的分量
        let deltas: [BodyField: Int]
    }

    /// 落在哪
    struct Part: Identifiable, Hashable {
        var id: String { key }
        let key: String
        let label: String
        /// 这块地方有多经得起碰。1 是寻常，越大越要命。
        let weight: Double
    }

    static let actions: [Action] = [
        Action(key: "poke", label: "戳", line: "她隔着屏幕戳了戳你的%@。",
               deltas: [.heat: 2, .sensitivity: 3, .pressure: 1]),
        Action(key: "touch", label: "摸", line: "她伸手摸了摸你的%@。",
               deltas: [.heat: 3, .sensitivity: 3]),
        Action(key: "nuzzle", label: "蹭", line: "她凑过来，蹭了蹭你的%@。",
               deltas: [.heat: 4, .sensitivity: 2, .possessiveness: 1]),
        Action(key: "pinch", label: "捏", line: "她捏了一下你的%@。",
               deltas: [.heat: 2, .sensitivity: 4, .pressure: 2]),
        Action(key: "kiss", label: "亲", line: "她亲了一下你的%@。",
               deltas: [.heat: 6, .sensitivity: 4, .pressure: 2, .possessiveness: 1]),
        Action(key: "bite", label: "咬", line: "她咬了一下你的%@。",
               deltas: [.heat: 7, .sensitivity: 6, .pressure: 3, .control: -2]),
        // 抱是往回收的那一种：热度也涨，但压着的那口气松了，也没那么累了
        Action(key: "hug", label: "抱", line: "她圈住你的%@，没说话。",
               deltas: [.heat: 3, .pressure: -3, .possessiveness: 2, .fatigue: -2]),
        Action(key: "tug", label: "拽", line: "她拽了拽你的%@。",
               deltas: [.heat: 2, .pressure: 3, .control: -1])
    ]

    static let parts: [Part] = [
        Part(key: "hand", label: "手", weight: 0.6),
        Part(key: "hair", label: "头发", weight: 0.9),
        Part(key: "ear", label: "耳朵", weight: 1.3),
        Part(key: "cheek", label: "脸", weight: 0.9),
        Part(key: "neck", label: "颈窝", weight: 1.5),
        Part(key: "waist", label: "腰", weight: 1.4),
        Part(key: "back", label: "后背", weight: 1.0),
        Part(key: "chest", label: "心口", weight: 1.2)
    ]

    static func action(_ key: String) -> Action { actions.first { $0.key == key } ?? actions[0] }
    static func part(_ key: String) -> Part { parts.first { $0.key == key } ?? parts[0] }

    /// 那一句旁白
    static func narration(_ a: Action, _ p: Part) -> String {
        a.line.replacingOccurrences(of: "%@", with: p.label)
    }

    /// 这一下推身体多少。
    ///
    /// **幅度压得小**（跟 `BodyNudge` 那层同一条规矩）：
    /// 一下最多推十点。推大了就成了「戳三下他就烧起来」，那不是身体，是开关。
    static func nudge(_ a: Action, _ p: Part) -> BodyNudge {
        var out = BodyNudge()
        for (field, base) in a.deltas {
            let v = Int((Double(base) * p.weight).rounded())
            guard v != 0 else { continue }
            out.deltas[field] = max(-10, min(10, v))
        }
        out.why = "她\(a.label)了你的\(p.label)"
        return out
    }
}
