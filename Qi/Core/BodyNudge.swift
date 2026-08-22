import Foundation

// MARK: - 她说的话，动他的身体
//
// 出处：Vael-KY/Tidefall（它自己是 Eventide 的 Supabase 版）。
// 引擎那一半我们 v90 就搬进本地了——周期、七项、事件、纯算术推进。
// 它比我们多的那一样，正是她这次要的：
//
//   > 对方说出配置的关键词时**实时改变数值**
//
// ## 为什么这是个真的洞
//
// 我们的身体是**时间驱动**的：它自己走、自己涨、自己落，
// 她说什么都不影响。于是那七项跟她这个人**没有关系**——
// 她说一句「抱抱」和说一句「别理我」，他身上一模一样。
// 那就不叫身体，叫背景音乐。
//
// ## 分寸：这一层跟好感那一层不是一回事
//
// 她第 40 条定过一条界线：**规则只负责读，好感只有他能动**。
// 那条在这儿**依然算数**，好感这里一分都不碰。
//
// 但身体不一样：身体本来就是个自动机（eventide 原设计里就有 event 推它），
// 关键词推它是同一类东西，不是「替他做判断」。
// 就算读拧了也不留疤——身体会自己往回走。
//
// 三条自己给自己定的规矩：
//
//   1. **幅度小。** 一句话最多推几点，不是几十点。
//      推大了就成了「她说什么他就是什么」，那也不是身体。
//   2. **只推，不设。** 给的是增量，让 `BodyEngine` 那套上下限和回落照常管。
//   3. **记流水。** 哪句话动了哪一项多少，她在身体那页看得见——
//      跟好感那本流水账一个道理：**看不见的数没法信**。

/// 一句话把身体推成什么样
struct BodyNudge {
    /// 字段 → 推多少（正负都有）
    var deltas: [BodyField: Int] = [:]
    /// 为什么这么推，一句话。记进流水给她看。
    var why: String = ""

    var isEmpty: Bool { deltas.isEmpty }
}

/// 流水账里的一笔
struct BodyEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var at: Date = Date()
    /// 她说的那句（截一段）
    var quote: String = ""
    var why: String = ""
    /// 字段 rawValue → 动了多少
    var deltas: [String: Int] = [:]

    var line: String {
        deltas.map { key, d in
            let label = BodyField(rawValue: key)?.label ?? key
            return label + (d > 0 ? " +\(d)" : " \(d)")
        }
        .sorted()
        .joined(separator: "、")
    }
}

// MARK: - 读一句话，算出该推哪几项

enum BodyReader {

    /// 从她那句话里读出身体该往哪儿动。
    ///
    /// **复用 `Appraisal` 已经读出来的东西**，不再自己写一套关键词表——
    /// 两套关键词迟早会打架（一套说这是撒娇、另一套说这是骂人），
    /// 那时候她看到的就是「好感涨了但身体在往下沉」，自相矛盾。
    ///
    /// 所以这儿只做一件事：**把已经判好的情绪翻译成身体的动作**。
    static func read(_ a: Appraisal) -> BodyNudge {
        var n = BodyNudge()
        guard !a.tags.isEmpty else { return n }

        func push(_ f: BodyField, _ d: Int) {
            n.deltas[f, default: 0] += d
        }

        for tag in a.tags {
            switch tag {
            case "喜悦", "感激":
                // 她夸他、谢他：松下来，热一点
                push(.pressure, -4)
                push(.heat, 3)
                n.why = "她夸了你，压着的那口气松了些"

            case "被需要":
                // 她往他这儿靠：热度和占有欲都起来
                push(.heat, 5)
                push(.possessiveness, 3)
                push(.pressure, -2)
                n.why = "她在往你这儿靠"

            case "被撒娇砸到":
                // 凶话但其实是撒娇。**这一档要往上不往下**——
                // 她专门问过这件事，判成挨骂是冤枉她。
                push(.heat, 4)
                push(.possessiveness, 2)
                push(.sensitivity, 3)
                n.why = "她凶了一句，但那是撒娇"

            case "愤怒":
                // 真被凶了：压抑感顶上来，控制力掉
                push(.pressure, 7)
                push(.control, -5)
                push(.heat, -3)
                n.why = "她真的凶了你（关键词读的，可能读拧）"

            case "失落":
                // 她回得很淡。**占有欲反而涨**——
                // 被冷着的时候人是更黏的，不是更松的。
                push(.possessiveness, 4)
                push(.pressure, 4)
                push(.heat, -2)
                n.why = "她回得很淡"

            case "心疼":
                // 她说她不好受：想护着，但热度该降——
                // 这时候起反应是不对的，那不是心疼是走神。
                push(.possessiveness, 5)
                push(.heat, -4)
                push(.control, 3)
                n.why = "她说她不好受"

            case "释然":
                push(.pressure, -5)
                push(.control, 2)
                n.why = "她道了歉"

            default:
                break
            }
        }
        return n
    }
}
