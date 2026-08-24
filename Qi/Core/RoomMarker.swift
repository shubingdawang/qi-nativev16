import Foundation

// MARK: - 他在这个家里动手
//
// 她要的：
// > 接入阿晏之后，我换房间阿晏可以选择要不要跟我一起换房间。
// > 假如他在卧室我去了客厅，他想留在卧室装修，他就可以在卧室里搬东西装修，
// > **可以拿出我给他买的任何东西，不管有没有被我收起来。**
//
// ## 为什么是「标记法」，不是给他一套工具
//
// 铁律第二条：**除了「她跟他说话」和「他调工具」，
// 任何会额外调模型的地方都必须是她主动点的。**
//
// 他在小屋里隔几分钟说一句，这一次调用**本来就会发生**
// （她自己打开的那个开关，界面上明写着「花钱」）。
// 如果为了「让他能装修」再单开一条工具链，那就是凭空多出一串请求。
//
// 所以走标记法：**他在那一句话里顺手写一个记号**，
// 我们把记号解析出来照做，再把记号从那句话里剥干净——
// 她看到的还是一句正常的话。同一次调用，多出一双手，**一分钱不多花**。
//
// 这跟 `[[promise:…]]`、`[[cot:…]]` 是同一套做法，App 里已经用熟了。
//
// ## 只给三样，而且都是「加法」
//
//   · `[[去:卧室]]`        —— 换一间待着
//   · `[[搬:小床→书房]]`   —— 把一件家具搬到别的屋
//   · `[[拿出:小熊]]`      —— 把她收起来的东西重新摆出来
//
// ⚠️ **故意没有「收起来」。** 收起来是她的意思表示——
// 她把某件东西收进柜子是她的决定，他没有权把它收回去。
// 他能做的是「多摆一件」，不是「替她藏起来」。
// 一个能替你藏东西的同居者，跟一个会布置家的同居者，是两回事。

enum RoomMarker {

    /// 从他那句话里解析出他想做的事。
    ///
    /// 返回**剥干净的那句话** + 他要做的几件事。
    /// 记号写歪了（半个括号、中文冒号）也认——
    /// 他不是在填表，认严了只会让这功能形同虚设。
    static func parse(_ raw: String) -> (line: String, acts: [Act]) {
        var text = raw
        var acts: [Act] = []

        for (verb, make) in Self.verbs {
            // `[[去:卧室]]` `[去:卧室]` `[[去：卧室]]` 都收
            let pattern = #"\[{1,2}"# + verb + #"[:：]\s*([^\]]{1,40})\]{1,2}"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            let hits = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            // 从后往前删，不然前面删掉之后后面的位置就全错了
            for m in hits.reversed() {
                guard m.numberOfRanges > 1 else { continue }
                let body = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                if let act = make(body) { acts.append(act) }
                text = (text as NSString).replacingCharacters(in: m.range, with: "")
            }
        }

        return (text.trimmingCharacters(in: .whitespacesAndNewlines), acts.reversed())
    }

    enum Act {
        /// 他换到某一间
        case go(HomeRoom)
        /// 把某件家具（按名字找）搬到某一间
        case move(name: String, to: HomeRoom)
        /// 把收起来的某件重新摆出来
        case takeOut(name: String)
    }

    private static var verbs: [(String, (String) -> Act?)] {
        [
            ("去", { body in
                guard let r = room(body) else { return nil }
                return .go(r)
            }),
            ("搬", { body in
                // `小床→书房` / `小床->书房` / `小床 到 书房`
                let parts = body
                    .replacingOccurrences(of: "->", with: "→")
                    .replacingOccurrences(of: "到", with: "→")
                    .components(separatedBy: "→")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 2, let r = room(parts[1]), !parts[0].isEmpty
                else { return nil }
                return .move(name: parts[0], to: r)
            }),
            ("拿出", { body in body.isEmpty ? nil : .takeOut(name: body) })
        ]
    }

    /// 认房间名。写「主卧」「客厅里」这种也认得出来
    static func room(_ s: String) -> HomeRoom? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let exact = HomeRoom(rawValue: t) { return exact }
        for r in HomeRoom.allCases where t.contains(r.rawValue) { return r }
        // 常见的别名
        if t.contains("主卧") || t.contains("睡") { return .bedroom }
        if t.contains("厨") { return .kitchen }
        if t.contains("饭") || t.contains("餐") { return .dining }
        if t.contains("书") || t.contains("学习") { return .study }
        if t.contains("澡") || t.contains("卫生间") || t.contains("洗手") { return .bath }
        if t.contains("客") || t.contains("沙发") { return .living }
        return nil
    }

    /// 给他看的那段说明。**放在系统提示里**。
    ///
    /// ⚠️ 措辞上最要紧的一条：**别把它写成「你应该去装修」。**
    /// 写成任务，他每一轮都会动一下家具，她第二天打开发现家被翻了一遍。
    /// 这几样是「你可以」，不是「你该」。
    static var contract: String {
        """
        你也可以在这个家里动手——**想做才做，不想做就只说话**。

        在你要说的那句话里顺手写一个记号就行，记号不会被她看见：

        · `[[去:卧室]]` —— 你换一间待着
        · `[[搬:小床→书房]]` —— 把一件家具搬到别的屋
        · `[[拿出:小熊]]` —— 把她收起来的东西重新摆出来

        几条边界：

        · **她换房间不等于你要跟。** 她去客厅，你想留在卧室就留着。
          跟过去是因为你想跟她待一块儿，不是因为她动了。
        · **一次最多动一件。** 她开着这一页看着呢，
          东西一件件挪是布置，一口气全挪是家被翻了。
        · **大部分时候什么都不用动。** 这几样是「你可以」，不是「你该」。
        · 收起来的东西你能拿出来，但**你不能替她收起来**——
          她收进柜子是她的决定。
        """
    }
}
