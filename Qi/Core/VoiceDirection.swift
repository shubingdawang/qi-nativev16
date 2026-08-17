import Foundation

/// 他说话的**表情**。
///
/// ## 为什么要这个
///
/// 前面做完语气那一摊之后，链路是瘸的：
/// 他听得出她怎么说（音量、语速、停顿跟她平时比），
/// 但**她听到的他永远是平的**——TTS 拿到一串字，从头念到尾一个调。
///
/// ringdonut 那份参考里管这个叫 voice direction：
/// 让他把回复写成一份**表演脚本**，句子里带上 `[轻声]`、`[叹气]`、`[笑]`
/// 这样的标签，TTS 照着演。
///
/// ## 两条必须分开的路
///
/// 同一段文字有两个去处，处理方式完全相反：
///
///   · **给她看的**：标签**必须剥干净**。她要读的是他说的话，
///     不是舞台提示。屏幕上冒出一个 `[叹气]` 立刻就出戏了
///   · **给 TTS 的**：标签**原样留着**。ElevenLabs 新一代模型认这些行内标签，
///     认不了的模型也只会把它当普通字念——所以最坏情况是多念几个字，
///     不是整段崩掉
///
/// 剥和留是两次不同的处理，别图省事只做一次。
enum VoiceDirection {

    /// 他能用的那些。**给一份清单而不是让他随便写**——
    /// 随便写的话每次标签都不一样，TTS 那边认不全，
    /// 而且她在字幕里看到的东西也不稳定。
    static let tags = [
        "轻声", "小声", "叹气", "笑", "轻笑", "顿了顿",
        "认真", "无奈", "哄", "凑近", "打哈欠", "咬牙"
    ]

    /// 教他怎么用。接在打电话那段提示词后面。
    static let hint = """

    · 你可以在句子里插入表演提示，让她**听得出你的表情**，比如：
      「[轻声]我在呢。[顿了顿]你今天是不是没吃东西。」
      能用的有：\(tags.joined(separator: "、"))。
    · 这些标签她**看不到**，只有耳朵听得出来——所以别拿它当话说，
      也别每句都挂，一段里有一两个就够了。没有情绪要演就不写。
    """

    /// 剥干净，给她看的那一份。
    ///
    /// 只剥**认识的那些**。他要是写了个 `[某某]` 不在清单里，
    /// 那多半是他真的想说这几个字（比如引了一句带方括号的东西），
    /// 无差别全剥会把正文吃掉。
    static func strip(_ text: String) -> String {
        var out = text
        for t in tags {
            out = out.replacingOccurrences(of: "[\(t)]", with: "")
            // 他可能写成中文方括号
            out = out.replacingOccurrences(of: "［\(t)］", with: "")
            out = out.replacingOccurrences(of: "【\(t)】", with: "")
        }
        // 剥完可能留下多余的空格和空行
        return out
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 给 TTS 的那一份：把各种括号统一成方括号，别的原样留着。
    static func forSpeech(_ text: String) -> String {
        var out = text
        for t in tags {
            out = out.replacingOccurrences(of: "［\(t)］", with: "[\(t)]")
            out = out.replacingOccurrences(of: "【\(t)】", with: "[\(t)]")
        }
        return out
    }

    /// 这段里他都演了些什么。显示在气泡角落，
    /// 让她**知道刚才那句是带着表情说的**——
    /// 不然配了音色的人听得出来，没配的人完全不知道有这回事。
    static func found(in text: String) -> [String] {
        tags.filter {
            text.contains("[\($0)]") || text.contains("［\($0)］")
                || text.contains("【\($0)】")
        }
    }
}
