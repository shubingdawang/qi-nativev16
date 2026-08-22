import SwiftUI

/// 一个够用的 Markdown 显示控件。
/// 把文字按 ``` 拆成"普通段落"和"代码块"两种：
/// 普通段落交给系统自带的 Markdown 解析（粗体、斜体、链接、行内代码都支持）；
/// 代码块单独用等宽字体渲染，并且可以横向滚动、右上角能一键复制。
struct MarkdownText: View {

    let text: String
    var fontSize: Double = 16
    /// 要不要把宽度撑满。
    ///
    /// 聊天气泡里要 **false**：气泡该跟着字数长长短短，
    /// 一句「嗯」也顶出一整行的宽度看着很怪（她原话：「有点怪怪的」）。
    /// 别的地方（笔记、卡片正文）撑满是对的，所以默认还是 true。
    var fillWidth: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let body):
                    Text(attributed(body))
                        .font(.system(size: fontSize))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
                case .code(let language, let body):
                    CodeBlockView(language: language, code: body, fontSize: fontSize)
                }
            }
        }
    }

    // MARK: 拆分

    private enum Segment {
        case text(String)
        case code(String, String)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var isCode = false
        var language = ""
        var buffer: [String] = []

        func flush() {
            let joined = buffer.joined(separator: "\n")
            buffer.removeAll()
            if isCode {
                result.append(.code(language, joined))
            } else if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.text(joined))
            }
        }

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flush()
                if !isCode {
                    language = line.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "```", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                isCode.toggle()
                continue
            }
            buffer.append(line)
        }
        flush()

        if result.isEmpty { result.append(.text(text)) }
        return result
    }

    private func attributed(_ raw: String) -> AttributedString {
        // 系统那套 inline markdown **不认 `~~删除线~~`**，
        // 所以先自己把它挑出来，剩下的再交给系统。
        // 记忆改过之后显示的就是 `~~记错的~~ 改对的`，
        // 画不出删除线的话那行读起来是两句自相矛盾的话。
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

    private func plain(_ raw: String) -> AttributedString {
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
