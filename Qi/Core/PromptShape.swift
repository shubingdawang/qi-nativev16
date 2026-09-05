import Foundation

// MARK: - 这一份都花在哪儿

/// 真发出去的那一份请求，分块量一遍。
///
/// ## 为什么要有它
///
/// 她问过好几次：「token 依旧是 12w 多」「是注入太多了吗」。
/// 我每次都只能凭着读代码猜——猜是最没用的回答，因为**只有量过才知道**。
///
/// ⚠️⚠️ **它读的是真的要发出去的那个数组**，不是照着 `buildAPIMessages`
/// 再拼一遍。这一点是这份东西唯一的价值：照着拼一遍就是第二份真相，
/// 那边改了这边不改，它就开始撒谎，而撒谎的仪表比没有仪表更糟。
///
/// ## 字数不是 token
///
/// 真正的 token 数只有对面知道（每次回来的 `usage` 里有）。这儿给的是
/// **估的**，用来看「哪一块占大头」——这个用途上估得准不准无所谓，
/// 谁比谁大三倍是看得出来的。中文一个字大约一个 token，
/// 英文数字标点大约四个字符一个。
enum TokenGuess {

    static func of(_ s: String) -> Int {
        var cjk = 0, other = 0
        for u in s.unicodeScalars {
            switch u.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF,     // 汉字
                 0x3000...0x303F, 0xFF00...0xFFEF,     // 中文标点、全角
                 0x3040...0x30FF, 0xAC00...0xD7AF:     // 假名、谚文
                cjk += 1
            default:
                other += 1
            }
        }
        return cjk + other / 4
    }

    /// 一张图大约多少。
    ///
    /// Anthropic 那边是 `宽 × 高 / 750`。我们发出去之前统一缩到长边 1280，
    /// 竖屏截图大约 590×1280 ≈ 1000。**这个数是估的**，
    /// 但一张图抵一千个字这件事本身就是要说给她听的重点。
    static let perImage = 1000
}

/// 一块。
struct PromptBlock: Identifiable {
    var id = UUID()
    var name: String
    var tokens: Int
    /// 在不在缓存断点前面（前面的只在第一次全价，之后便宜很多）
    var cached: Bool
    /// 一句人话，说清楚这块是什么、能不能砍
    var note: String
}

/// 一整份请求量下来的样子
struct PromptShape {
    var at = Date()
    var blocks: [PromptBlock] = []
    /// 工具表里最大的那几件，用来回答「关掉几个能省多少」
    var fattestTools: [(name: String, tokens: Int)] = []
    var toolCount = 0
    var imageCount = 0
    var messageCount = 0

    var total: Int { blocks.reduce(0) { $0 + $1.tokens } }
    var cachedTotal: Int { blocks.filter { $0.cached }.reduce(0) { $0 + $1.tokens } }

    /// 量一份**真要发出去**的请求。
    static func measure(tools: [[String: Any]],
                        messages: [ChatAPI.OutgoingMessage]) -> PromptShape {
        var out = PromptShape()
        out.toolCount = tools.count
        out.messageCount = messages.count

        // ── 工具表
        var toolTotal = 0
        var each: [(String, Int)] = []
        for t in tools {
            let n = (try? JSONSerialization.data(withJSONObject: t))?.count ?? 0
            // 工具表几乎全是英文标识符和 JSON 括号，按四个字符一个 token 估
            let guess = n / 4
            toolTotal += guess
            let name = ((t["function"] as? [String: Any])?["name"] as? String) ?? "?"
            each.append((name, guess))
        }
        out.fattestTools = Array(each.sorted { $0.1 > $1.1 }.prefix(8))
            .map { (name: $0.0, tokens: $0.1) }
        if toolTotal > 0 {
            out.blocks.append(.init(
                name: "工具表",
                tokens: toolTotal, cached: true,
                note: "\(tools.count) 件工具的名字、说明和参数表。"
                    + "它排在最前面，**进缓存**，所以一整窗只算一次全价。"
                    + "但它照样占着上下文——用不上的可以在 MCP 那一页关掉。"))
        }

        // ── 系统提示：稳定的一半 / 每轮在变的一半
        var stable = 0, dynamic = 0
        for m in messages where m.role == "system" {
            stable += TokenGuess.of(m.stablePrefix)
            dynamic += TokenGuess.of(m.text)
        }
        if stable > 0 {
            out.blocks.append(.init(
                name: "身份·规矩·能力·表情目录",
                tokens: stable, cached: true,
                note: "他是谁、说好的规矩、几段能力说明、表情包目录、"
                    + "还有这一窗压过的浓缩件。**进缓存**，一整窗只算一次全价。"))
        }
        if dynamic > 0 {
            out.blocks.append(.init(
                name: "每轮都在变的那些",
                tokens: dynamic, cached: false,
                note: "身体、心跳、好感、念头池、此刻、节日、月相、"
                    + "她在听什么在读什么……**每一轮都重算**，因为它们每一轮都在变。"
                    + "这一块是真正每次都要重新付钱的地方。"))
        }

        // ── 历史
        var history = 0
        var images = 0
        for m in messages where m.role != "system" {
            history += TokenGuess.of(m.text)
            history += TokenGuess.of(m.stablePrefix)
            images += m.imageDataURLs.count
            for c in m.toolCalls { history += TokenGuess.of(c.arguments) + 8 }
        }
        out.imageCount = images
        if history > 0 {
            out.blocks.append(.init(
                name: "聊天记录",
                tokens: history, cached: true,
                note: "这一窗还没被压缩掉的那些话，连工具调用的参数和返回值一起。"
                    + "除了最新的一两条，其余**进缓存**。"
                    + "嫌它长就把「滚雪球压缩」的条数调小一点。"))
        }
        if images > 0 {
            out.blocks.append(.init(
                name: "图片",
                tokens: images * TokenGuess.perImage, cached: true,
                note: "\(images) 张真图，**一张大约抵一千个字**。"
                    + "再往前的图已经退成一行文字说明了（就是那句「[图：…]」），"
                    + "所以这个数不会一直涨。"))
        }
        return out
    }
}
