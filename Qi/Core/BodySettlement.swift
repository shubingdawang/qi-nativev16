import Foundation

/// 结算：这一段互动让身体往哪儿动。
///
/// ## 这是整套里唯一花钱的地方
///
/// 推进那一层（BodyEngine）是纯算术，一分钱不花。
/// 结算不一样——它要把一段对话丢给模型，让他判断这段互动
/// 让身体的七项各自动了多少。**所以它必须是她主动点的**（铁律第二条），
/// 而且界面上要写明白这一下要花钱。
///
/// ## 规则是照抄的，不是我编的
///
/// 电脑那份 `eventide/settlement.py` 里的几条约束一条没改：
///
///   · 普通互动每项 -3~+3，强刺激或事件期间到 -4~+4
///   · **没到顶的时候蓄积感只能涨不能降**（0~+4）——
///     周期没走完，身体的余量不会因为聊了几句就自己消下去
///   · 到顶了蓄积感必须是负的，而且扣多少跟当前周期有关：
///     平稳期/恢复期扣 -10~-6，别的周期扣 -7~-4
///   · `cooled_down` 只用于身体反应**明确退下去**，
///     普通转话题、等待、被打断都不算冷却
///
/// 最后那条特别重要：不写死的话，模型会把「她去洗澡了」判成冷却，
/// 身体就永远热不起来。
enum BodySettlement {

    /// 结算的结论
    enum Result: String, Codable {
        case neutral, continued, escalated, interrupted, cooledDown = "cooled_down", released
    }

    struct Outcome {
        var result: Result = .neutral
        /// 到顶了没有
        var peaked = false
        var deltas: [BodyField: Int] = [:]
        var reason = ""
    }

    // MARK: 提示词

    static func prompt(_ s: BodyState) -> String {
        var lines: [String] = []
        for f in BodyField.allCases {
            let v = s.value(f)
            lines.append("\(f.label)：\(v)，\(f.describe(v))")
        }
        let event = BodyEvents.label(s.activeEventKey)
        return """
        你是内部身体状态的互动窗口结算器，只输出合法 JSON。

        只判断这段**已经发生**的互动如何影响身体状态；
        不要续写内容，不要替任何人继续说话。

        【当前】
        周期：\(s.cycle.label)（\(s.cycle.note)）
        正在发生的身体事件：\(event.isEmpty ? "无" : event)
        身体状态：\(lines.joined(separator: "；"))

        【规则】
        · 每个 delta 是**这一段**造成的变化量，0 表示这一段不动它。
        · 普通互动每项建议 -3 到 +3；强刺激或事件期间可以到 -4 到 +4。
        · peaked=false 时 reserve_delta 不能小于 0——
          周期没走完，蓄积感不会因为聊了几句就自己消下去。
        · peaked=true 时 reserve_delta 必须是负数。
        · **cooled_down 只用于身体反应明确退下去**；
          普通转话题、等待、被打断都不算冷却。
        · settlement_reason 里不要用英文双引号。

        只输出这一个 JSON，别的什么都不要：
        {"settlement_reason":"一句话说明为什么这么判",
         "settlement_result":"neutral|continued|escalated|interrupted|cooled_down|released",
         "peaked":false,
         "heat_delta":0,"pressure_delta":0,"control_delta":0,
         "sensitivity_delta":0,"reserve_delta":0,
         "possessiveness_delta":0,"fatigue_delta":0}
        """
    }

    // MARK: 解析

    /// 从模型那堆东西里把 JSON 抠出来。
    ///
    /// **别指望 prompt 治好这件事**——她那份「身体外卖」的参考里写得很直白：
    /// 十次里有三次会套一层代码围栏，或者前面加一句「好的，这是你要的内容」，
    /// 带 thinking 的还会把思维链一起吐出来。
    /// 所以这儿写的是宽松解析：剥围栏、从第一个 `{` 截到最后一个 `}`。
    static func parse(_ raw: String) -> Outcome? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "```json", with: "")
                   .replacingOccurrences(of: "```", with: "")
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var o = Outcome()
        o.reason = (json["settlement_reason"] as? String) ?? ""
        o.result = Result(rawValue: (json["settlement_result"] as? String) ?? "") ?? .neutral
        // 有的模型会把布尔写成字符串
        if let b = json["peaked"] as? Bool { o.peaked = b }
        else if let s = json["peaked"] as? String {
            o.peaked = ["1", "true", "yes", "y"].contains(s.lowercased())
        }
        for f in BodyField.allCases {
            let key = f.rawValue + "_delta"
            if let v = json[key] as? Int { o.deltas[f] = v }
            else if let d = json[key] as? Double { o.deltas[f] = Int(d) }
            else if let s = json[key] as? String, let v = Int(s) { o.deltas[f] = v }
            else { o.deltas[f] = 0 }
        }
        return o
    }

    /// 把模型给的数值收进规矩里。**模型给多少不算数，这儿说了算。**
    static func normalize(_ o: Outcome, state: BodyState, limit: Int = 4) -> Outcome {
        var out = o
        for f in BodyField.allCases {
            let v = o.deltas[f] ?? 0
            if f == .reserve {
                out.deltas[f] = reserveDelta(v, state: state, peaked: o.peaked)
            } else {
                out.deltas[f] = max(-limit, min(limit, v))
            }
        }
        return out
    }

    private static func reserveDelta(_ v: Int, state: BodyState, peaked: Bool) -> Int {
        guard peaked else { return max(0, min(4, v)) }
        // 到顶之后扣多少，跟当前在哪个周期有关
        let (low, high) = ["stable", "recovery"].contains(state.cycleKey)
            ? (-10, -6) : (-7, -4)
        return max(low, min(high, v))
    }

    /// 落到身体上
    static func apply(_ o: Outcome, to s: inout BodyState) {
        let fixed = normalize(o, state: s)
        BodyEngine.apply(&s, deltas: fixed.deltas)
        s.lastSettlementNote = fixed.reason
    }
}
