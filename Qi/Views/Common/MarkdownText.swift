import SwiftUI

/// 一个够用的 Markdown 显示控件。
///
/// ## 这一版补了什么（她报的第 8 条：「整个 app 并没有做 markdown 渲染」）
///
/// 上一版**只解析行内**（粗体、斜体、行内代码、链接）加代码块。
/// 也就是说他写 `## 小标题`、`- 一条`、`> 引一句`、`---`，
/// 她看到的就是这几个符号本身杵在那儿。他越认真排版，她看到的越乱。
///
/// 现在按**块**拆：标题 / 列表 / 有序列表 / 引用 / 分割线 / 代码块 / 普通段落，
/// 每一种各画各的；行内那套照旧在每块里跑。
///
/// 标题用宋体（跟全 App 的标题一套，见 `Look.swift`）——
/// 他写的小标题和界面上的小标题长一个样，读起来才是一件东西。
///
/// ⚠️ **表格没做。** 手机屏太窄，硬画出来只能横滚，
/// 不如让它照原样显示——那还看得出是一张表。
struct MarkdownText: View {

    let text: String
    var fontSize: Double = 16
    /// 要不要把宽度撑满。
    ///
    /// 聊天气泡里要 **false**：气泡该跟着字数长长短短，
    /// 一句「嗯」也顶出一整行的宽度看着很怪（她原话：「有点怪怪的」）。
    /// 别的地方（笔记、卡片正文）撑满是对的，所以默认还是 true。
    var fillWidth: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                block(segment)
            }
        }
    }

    @ViewBuilder
    private func block(_ segment: Segment) -> some View {
        switch segment {

        case .text(let body):
            Text(attributed(body))
                .font(.system(size: fontSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)

        case .heading(let level, let body):
            // 一级 19、二级 17、三级往下 15。再小就跟正文分不开了
            let size = level <= 1 ? fontSize + 3 : (level == 2 ? fontSize + 1 : fontSize)
            Text(attributed(body))
                .heading(size, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
                .padding(.top, 2)

        case .bullet(let depth, let body):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                // 点不用 SF Symbol：那玩意儿的基线跟文字对不齐，
                // 一个圆点画出来就行
                Circle()
                    .fill(Theme.textMuted(scheme))
                    .frame(width: 4, height: 4)
                    .offset(y: -1)
                Text(attributed(body))
                    .font(.system(size: fontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 14)
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)

        case .ordered(let number, let body):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(number + ".")
                    .font(.system(size: fontSize * 0.92, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme))
                Text(attributed(body))
                    .font(.system(size: fontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)

        case .quote(let body):
            HStack(alignment: .top, spacing: 9) {
                // 引用是一道竖线，不是一个框。框会把它变成"另一张卡"，
                // 而它其实还是这段话的一部分
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.textMuted(scheme).opacity(0.45))
                    .frame(width: 2.5)
                Text(attributed(body))
                    .font(.system(size: fontSize * 0.96))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)

        case .rule:
            Hairline().padding(.vertical, 3)

        case .code(let language, let body):
            CodeBlockView(language: language, code: body, fontSize: fontSize)
        }
    }

    // MARK: 拆分

    private enum Segment {
        case text(String)
        case heading(Int, String)
        case bullet(Int, String)
        case ordered(String, String)
        case quote(String)
        case rule
        case code(String, String)
    }

    /// 一行是不是列表项：`- ` `* ` `• ` 都算，前面的缩进算层级
    private static func bulletBody(_ line: String) -> (depth: Int, body: String)? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let t = line.trimmingCharacters(in: .whitespaces)
        for mark in ["- ", "* ", "• ", "· "] where t.hasPrefix(mark) {
            return (min(indent / 2, 3), String(t.dropFirst(mark.count)))
        }
        // `---` 是分割线不是列表，`-` 后面必须有字
        return nil
    }

    /// `1. 正文` / `12) 正文`
    private static func orderedBody(_ line: String) -> (number: String, body: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        let digits = t.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = t.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix("） ") || rest.hasPrefix(") ") else { return nil }
        return (String(digits), String(rest.dropFirst(2)))
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var isCode = false
        var language = ""
        var buffer: [String] = []

        /// 攒着的普通行倒出来
        func flushText() {
            let joined = buffer.joined(separator: "\n")
            buffer.removeAll()
            guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(.text(joined))
        }

        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)

            // 代码块的围栏。**在代码块里面什么都不解析**——
            // 里面的 # 和 - 是代码，不是标题和列表
            if t.hasPrefix("```") {
                if isCode {
                    result.append(.code(language, buffer.joined(separator: "\n")))
                    buffer.removeAll()
                    isCode = false
                } else {
                    flushText()
                    language = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    isCode = true
                }
                continue
            }
            if isCode { buffer.append(line); continue }

            // 分割线：--- *** ___
            if t.count >= 3, t.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) {
                flushText()
                result.append(.rule)
                continue
            }

            // 标题
            if t.hasPrefix("#") {
                let hashes = t.prefix { $0 == "#" }.count
                let body = t.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                if hashes <= 6 && !body.isEmpty {
                    flushText()
                    result.append(.heading(hashes, body))
                    continue
                }
            }

            // 引用
            if t.hasPrefix("> ") || t == ">" {
                flushText()
                result.append(.quote(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if let b = Self.bulletBody(line) {
                flushText()
                result.append(.bullet(b.depth, b.body))
                continue
            }

            if let o = Self.orderedBody(line) {
                flushText()
                result.append(.ordered(o.number, o.body))
                continue
            }

            buffer.append(line)
        }

        if isCode {
            // 围栏没闭合（还在流式输出的那半截）。**照代码块显示**，
            // 别把没写完的代码当正文抖出来
            result.append(.code(language, buffer.joined(separator: "\n")))
        } else {
            flushText()
        }

        if result.isEmpty { result.append(.text(text)) }
        return result
    }

    private func attributed(_ raw: String) -> AttributedString {
        MD.inline(raw)
    }
}

/// 行内那一套，拎出来单独放。
///
/// 为什么要拎出来：**App 自己写的说明里也全是 `**重点**`**，
/// 而 SwiftUI 只对写死的字面量解析 markdown——
/// 一旦那句话是拼出来的（`"前半" + "后半"`）或者带插值，
/// 那两对星号就原样显示给她看了（她截图里「图、文件、语音、表情\*\*都会一起等\*\*」
/// 就是这么来的）。这些地方现在一律走 `Text(MD.inline(…))`。
enum MD {

    static func inline(_ raw: String) -> AttributedString {
        // 批注：`⟪原句⟫→改的` —— 原句**红色下划线**。
        //
        // ⚠️ 是下划线不是删除线（她纠正过：「之前说的删除线是口误了」）。
        // 划掉是「这个不算了」，而批注是「这个念作那个」——
        // 原文没错，只是旁边补一句。两件事不能用同一个记号。
        //
        // 记号本身（`⟪⟫`）不显示出来，只留里面的字 + 箭头 + 改的那半。
        if raw.contains(Annotated.open) {
            var out = AttributedString()
            var rest = Substring(raw)
            while let a = rest.range(of: Annotated.open),
                  let b = rest.range(of: Annotated.close,
                                     range: a.upperBound..<rest.endIndex) {
                out += inline(String(rest[rest.startIndex..<a.lowerBound]))
                var marked = AttributedString(String(rest[a.upperBound..<b.lowerBound]))
                marked.underlineStyle = .single
                marked.foregroundColor = .red
                out += marked
                rest = rest[b.upperBound...]
            }
            // 剩下的那截（箭头 + 改的那半 + 后面的正文）照常解析
            out += inline(String(rest))
            return out
        }
        // 系统那套 inline markdown **不认 `~~删除线~~`**，
        // 所以先自己把它挑出来，剩下的再交给系统。
        // 记忆改过之后显示的就是 `~~记错的~~ 改对的`，
        // 画不出删除线的话那行读起来是两句自相矛盾的话。
        //
        // ⚠️ 这一档留着，**它跟批注不是一回事**：
        // 这是「他记错了、后来改对了」，原文真的作废——那才该划掉。
        if raw.contains("~~") {
            var out = AttributedString()
            var rest = Substring(raw)
            while let a = rest.range(of: "~~"),
                  let b = rest.range(of: "~~", range: a.upperBound..<rest.endIndex) {
                out += plain(String(rest[rest.startIndex..<a.lowerBound]))
                var struck = AttributedString(String(rest[a.upperBound..<b.lowerBound]))
                struck.strikethroughStyle = .single
                struck.foregroundColor = .red.opacity(0.75)
                out += struck
                rest = rest[b.upperBound...]
            }
            out += plain(String(rest))
            return out
        }
        return plain(raw)
    }

    private static func plain(_ raw: String) -> AttributedString {
        // 保留原有换行，只解析行内格式
        if let parsed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return parsed
        }
        return AttributedString(raw)
    }
}

struct CodeBlockView: View {

    let language: String
    let code: String
    var fontSize: Double = 16

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "代码" : language)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Text(copied ? "已复制" : "复制")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: max(11, fontSize - 2), design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.softFillDeep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}
