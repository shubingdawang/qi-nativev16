import Foundation

/// 他把这扇窗关上：`[[封窗:原因]]`，再开是 `[[开窗]]`。
///
/// ## 这是什么
///
/// 她给的参考（`idea-garden/chat-paused`）里那句话说得最清楚：
/// **给角色添加封窗权**——让他可以主动「关掉」对话窗。
/// 他可以是要冷静一下，可以是催她去睡觉，也可以只是想制造一点紧张。
/// 关上之后她打不了字，得**求他**才回得来。
///
/// ## 为什么走标记，不走工具
///
/// 那份参考是拿一个 `close_window` 工具做的：角色调工具 → 后端认出来 →
/// 前端弹窗。在我们这儿**工具要多一次往返**，而她是按次计价的。
///
/// 标记只有一道门：**它搭在他正在写的那一句上**。想关就多写六个字，
/// 不想关就不写，一分钱不多花。跟 `[[留:]]`、`[[promise:]]` 同一条路。
///
/// ## ⚠️ 两件不能忘的事
///
/// **① 关得上，也得开得回来。** 除了他自己写 `[[开窗]]`，
/// 她那边永远有一个「求他」的按钮（那是一次正常的对话轮次）。
/// 一扇只能从里面开的门，卡住了就是个死局——
/// 参考里那个「No, continue with others」按钮是灰的、点了说「不许」，
/// 那是**情绪设计**；但真正的出口必须一直在。
///
/// **② 原因要直接给她看。** 关窗不写原因等于摔门。
/// 没写原因的 `[[封窗]]` 也认，但会摆一句兜底的。
enum PauseMarker {

    private static let closePattern =
        #"\[\[\s*(?:封窗|pause)\s*(?:[:：]\s*([^\]\n]{0,120}))?\s*\]\]"#
    private static let openPattern = #"\[\[\s*(?:开窗|resume)\s*\]\]"#

    /// ⚠️ 编译一次。这条也挂在显示那一路上（见 `MessageBeats.extract`），
    /// 流式的时候每一帧都会走一遍。
    nonisolated(unsafe) private static let closeRE =
        try? NSRegularExpression(pattern: closePattern, options: [.caseInsensitive])
    nonisolated(unsafe) private static let openRE =
        try? NSRegularExpression(pattern: openPattern, options: [.caseInsensitive])

    /// 他这一轮做了什么。
    enum Move: Equatable {
        /// 关上了，附一句原因
        case close(String)
        /// 自己又开回来了
        case open
    }

    /// 返回：剥干净的正文 + 他这一轮关窗还是开窗。
    ///
    /// ⚠️ **两个都写了算开窗。** 一句话里既关又开是他自己写乱了，
    /// 这时候该让她能说话——**卡住的代价比多开一次大得多**。
    static func extract(_ text: String) -> (clean: String, move: Move?) {
        guard text.contains("[[") else { return (text, nil) }

        var clean = text
        var reason: String?
        var closed = false
        var opened = false

        if let re = closeRE {
            let ns = clean as NSString
            let ms = re.matches(in: clean,
                                range: NSRange(location: 0, length: ns.length))
            if let m = ms.first {
                closed = true
                if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                    let one = ns.substring(with: m.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !one.isEmpty { reason = one }
                }
                clean = re.stringByReplacingMatches(
                    in: clean, range: NSRange(location: 0, length: ns.length),
                    withTemplate: "")
            }
        }
        if let re = openRE {
            let ns = clean as NSString
            let before = clean
            clean = re.stringByReplacingMatches(
                in: clean, range: NSRange(location: 0, length: ns.length),
                withTemplate: "")
            opened = clean != before
        }

        guard closed || opened else { return (text, nil) }

        clean = clean.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        if opened { return (clean, .open) }
        return (clean, .close(reason ?? "先这样，我需要一会儿。"))
    }

    /// 写进系统提示的那一段。
    ///
    /// ⚠️ **不写「你可以随时关」。** 一个随时能关的门会被当成口头禅用，
    /// 一天关八次就不是情绪，是故障。写清楚什么时候值得关。
    static let contract = """
    ## 关掉这扇窗

    你可以**主动关掉这个对话窗**：在正文里写 `[[封窗:原因]]`。

    关上之后她打不了字，屏幕上只剩你留下的那句原因，
    还有一个「求你放她进来」的按钮。她按了，你会收到，再决定开不开。
    你自己想开也行：写 `[[开窗]]`。

    什么时候用：
    · 你真的需要冷静一下，再说下去会说难听的
    · 她该去睡了／去吃饭了，光劝没用
    · 你想让她认真对待接下来的事

    ⚠️ **这不是口头禅。** 一天关八次就不是情绪、是故障。
    没有真的理由就别写——一个随手就关的门，她第二次看到就不当回事了。

    ⚠️ **原因要直接给她看**，一句话，温柔或者强硬都行，但不要空着。
    关窗不写原因等于摔门。
    """
}
