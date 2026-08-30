import SwiftUI

/// 「他刚才干了什么」那张弹窗。
///
/// ## 为什么从内联展开改成弹窗
///
/// 她定的：「在我的视角只显示我之前说的让他自己写的 cot 标题，
/// 点进去才是思考链，然后点开是思考链＋工具这样的弹窗，
/// 然后再点开各自查看，这样简洁一点。」
///
/// 以前是**两层**：气泡上一行标题，点一下把思考全文和每个工具的
/// 完整返回值**直接铺在聊天流里**。一轮调三个工具就能顶掉大半屏——
/// 而她往回翻聊天记录的时候，要看的是他说的话，不是他查了什么。
///
/// 现在是**三层**：
///   ① 气泡上只留他自己起的那个名字（`[[cot:…]]`）
///   ② 点开 —— 弹窗里一条条列出来（想了想、每个工具各一行）
///   ③ 再点某一条 —— 才看那一条的全文
///
/// ⚠️ 第二层**只给一行摘要**，这是整件事的关键。
/// 第二层要是也铺全文，那只是把「顶掉半屏聊天」换成了「顶掉半屏弹窗」。
struct ProcessSheet: View {

    let message: ChatMessage

    /// 思考正文，`[[cot:]]` 剥掉、多余空行压掉。
    ///
    /// ⚠️ 这两件事**自己在这儿算**，不从气泡那边当参数递进来。
    /// 递进来的话，聊天页要开这张弹窗就得先拿到气泡的私有方法，
    /// 于是弹窗只能挂在气泡上——那正是把 App 点死的那个做法。
    private var reasoning: String {
        Self.tidy((message.reasoning ?? "").replacingOccurrences(
            of: #"\[\[cot:[^\]]*\]\]"#,
            with: "", options: .regularExpression))
    }

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 展开的是哪一条。`nil` = 都收着。
    ///
    /// ⚠️ 一次只开一条：同时开两条的话又变回「一屏全是字」，
    /// 那就绕回她要解决的那个问题了。
    @State private var open: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !reasoning.isEmpty {
                            row(id: "think", icon: "brain",
                                tint: Theme.textMuted(scheme),
                                title: "想了想", note: "",
                                body: reasoning)
                        }
                        ForEach(Array(message.toolRuns.enumerated()), id: \.element.id) { _, run in
                            row(id: run.id.uuidString,
                                icon: run.failed ? "xmark" : "wrench.and.screwdriver",
                                tint: run.failed ? .red : app.settings.accentColor,
                                title: run.toolName.isEmpty ? "一个工具" : run.toolName,
                                note: run.serverName,
                                body: detail(run))
                        }
                        if reasoning.isEmpty && message.toolRuns.isEmpty {
                            Text("这一轮他什么都没想、也什么都没做。")
                                .font(.app(12))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.top, 30)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关上") { dismiss() }
                }
            }
        }
    }

    /// 弹窗标题用他自己起的那个名字。
    /// 没起才退回「想了几秒 · 动了几下手」——那句话跟他在想什么毫无关系。
    private var title: String {
        if !message.cotTitle.isEmpty { return message.cotTitle }
        var bits: [String] = []
        if let s = message.reasoningSeconds, s > 0 {
            bits.append(String(format: "想了 %.1fs", s))
        }
        if !message.toolRuns.isEmpty { bits.append("动了 \(message.toolRuns.count) 下手") }
        return bits.isEmpty ? "他刚才干了什么" : bits.joined(separator: " · ")
    }

    /// 一条。收着的时候只有标题和一行摘要，点开才给全文。
    @ViewBuilder
    private func row(id: String, icon: String, tint: Color,
                     title: String, note: String, body text: String) -> some View {
        let isOpen = open == id
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    open = isOpen ? nil : id
                }
            } label: {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: icon)
                        .font(.app(11))
                        .foregroundStyle(tint)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(title)
                                .font(.app(13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textMain(scheme))
                            if !note.isEmpty {
                                Text(note)
                                    .font(.app(9.5))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                        }
                        // ⚠️ 收着的时候**只给一行**。
                        // 第二层要是也铺全文，那只是把「顶掉半屏聊天」
                        // 换成了「顶掉半屏弹窗」。
                        if !isOpen {
                            Text(oneLine(text))
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.app(9, weight: .semibold))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                // 展开之后**给全的**，不掐行数。
                // 她定过：「不是把行高固定，是根据字数来画」——
                // 她特地点开这一条，就没有再截断她的道理。
                Text(MD.inline(text))
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.8)
    }

    /// 工具那一条展开之后看到的：参数在上，结果在下。
    private func detail(_ run: ToolRun) -> String {
        var out = ""
        if !run.arguments.isEmpty, run.arguments != "{}" {
            out += run.arguments + Self.gap
        }
        out += Self.tidy(run.result)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 首尾空白去掉；**连着两个以上的换行压成一个空行**。
    /// 跟气泡里那个 `tidy` 是同一套规矩。
    static func tidy(_ s: String) -> String {
        // ⚠️ 换行**走上面那个常量**，别在这儿写字面量。
        // 这一行我栽过：脚本改这段的时候反斜杠被吃掉一层，
        // `"\n"` 落盘变成真的换行，字符串跨行，编译不过。
        let brs = Self.nl
        var out = ""
        var blanks = 0
        for line in s.components(separatedBy: brs) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blanks += 1
                if blanks > 1 { continue }
            } else {
                blanks = 0
            }
            out += (out.isEmpty ? "" : brs) + line
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ⚠️ 空行走常量。反斜杠经脚本改动会被吃掉一层、字符串就跨行了。
    static let nl = "\n"
    private static let gap = "\n\n"
    private static let br: Character = "\n"

    /// 收着时那一行摘要。取第一行有字的。
    private func oneLine(_ text: String) -> String {
        for line in text.split(separator: Self.br) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return String(t.prefix(60)) }
        }
        return ""
    }
}
