import SwiftUI

/// 「他刚才干了什么」那张弹窗。
///
/// ## 长什么样
///
/// 她指着 claude.ai 定的：**一个点是 Thinking，一条线连到工具，
/// 用完工具还有 thinking 就再一个点、再一条线。**
/// 左边一条竖线串到底，每一步一个记号。
///
/// ⚠️ **里面不要框。** 之前每一条都套了一张玻璃卡片，
/// 一屏三张卡就是三个边框、三层背景——那是「一堆卡片」，不是「一条线」。
/// 时间线要的是**连续**，卡片天生把它切断。
///
/// ## 三层
///
///   ① 气泡上只留他自己起的那个名字（`[[cot:…]]`）
///   ② 点开 —— 这张弹窗，一条条列出来，各带一行摘要
///   ③ 再点某一条 —— 才看那一条的全文
///
/// ⚠️ 第二层**只给一行摘要**，这是整件事的关键。
/// 第二层要是也铺全文，那只是把「顶掉半屏聊天」换成了「顶掉半屏弹窗」。
///
/// ⚠️ 第一条叫 **Thinking**，不叫「想了想」。
/// 她定的：「想了想改成 thinking，这个不是他自己想的。」
/// 意思是——那一行是**我们**贴的标签，不是他写的字；
/// 用中文写会跟他自己起的那个名字混在一起，看着像也是他写的。
struct ProcessSheet: View {

    let message: ChatMessage

    /// 思考正文，`[[cot:]]` 剥掉、多余空行压掉。
    ///
    /// ⚠️ 这件事**自己在这儿算**，不从气泡那边当参数递进来。
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

    /// 开多高。
    ///
    /// 她定的：「一开始只要大概比三分之一屏高一点，
    /// 我按着标题往上滑再是现在的高度。」
    /// 所以两档：先 0.4，她想看全的时候自己拉满。
    @State private var height: PresentationDetent = .fraction(0.4)

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let all = steps
                        ForEach(Array(all.enumerated()), id: \.element.id) { i, s in
                            row(s, isLast: i == all.count - 1)
                        }
                        if all.isEmpty {
                            Text("这一轮他什么都没想、也什么都没做。")
                                .font(.app(12))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 16)
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
        .presentationDetents([.fraction(0.4), .large], selection: $height)
        .presentationDragIndicator(.visible)
    }

    // MARK: 一步一步

    /// 时间线上的一步
    struct Step: Identifiable {
        let id: String
        /// 左边那个记号。`nil` = 画一个实心圆点（thinking 那种）
        let icon: String?
        let tint: Color
        let title: String
        /// 标题右边那点小字（工具是哪台服务器给的）
        let note: String
        let body: String
    }

    /// 把这一轮拆成一条线上的几步，**按真实的先后**。
    ///
    /// 她要的：「一个点是 thinking 再一条线连接工具，
    /// 用完工具还有 thinking 就再一个点一条线。」
    ///
    /// 靠的是每个工具身上那个 `reasonMark`——它记着这个工具开动的时候
    /// 思考已经写了多少字。按这几个数把思考切成几段，
    /// 段和工具交替摆出来，就是当时真实的顺序。
    ///
    /// ⚠️ 老消息的 `reasonMark` 全是 0：切出来前面几段都是空的，
    /// 整段思考落在最后一刀之后——**看起来跟以前一模一样**。
    /// 不用迁移，也不会让旧记录忽然变样。
    private var steps: [Step] {
        var out: [Step] = []
        let full = Array(reasoning)
        var cut = 0

        // ⚠️ 老消息**一条都没标过**（`reasonMark` 全是 0）。
        // 照下面那套切的话，每一刀都切在 0，整段思考会落到最后一个工具之后——
        // 变成「先动手，后思考」，跟以前显示的正好反过来，而且那是假的。
        // 没标过就照老样子：想在前，动手在后。
        //
        // ⚠️ 还有一种「标了，但标的是假的」：
        // 有的中转站**把思考攒到一轮的最后才吐**（她的那个就是）。
        // 那第一次动工具的时候 `reasoning` 还是空的，标下来就是 0；
        // 要是这一轮动了好几次手、后面几次标到了数，
        // `contains { > 0 }` 就为真，于是照下面那套切——
        // 第一刀切在 0，思考整段落到工具后面。
        // 她报的「点进去会先出现工具，最后才出现 thinking」就是这个。
        //
        // 所以再加一条：**他想了，可第一次动手却标着 0 —— 那这几个数不能信。**
        // 真的先动手再想的话，那一刀本来就该在 0，
        // 但那种情况下「想在前、动手在后」也只是把顺序说得保守一点，
        // 不会把不存在的思考塞到中间去。
        let firstMark = message.toolRuns.first?.reasonMark ?? 0
        let trustworthy = firstMark > 0 || reasoning.isEmpty
        let marked = message.toolRuns.contains { $0.reasonMark > 0 } && trustworthy
        if !marked {
            if !reasoning.isEmpty {
                out.append(Step(id: "think", icon: nil,
                                tint: Theme.textMuted(scheme),
                                title: "Thinking", note: "", body: reasoning))
            }
            for run in message.toolRuns {
                out.append(Step(id: run.id.uuidString,
                                icon: run.failed
                                    ? "exclamationmark.triangle" : "wrench.and.screwdriver",
                                tint: run.failed ? .red : app.settings.accentColor,
                                title: run.toolName.isEmpty ? "一个工具" : run.toolName,
                                note: run.serverName,
                                body: detail(run)))
            }
            return out
        }

        func think(upTo end: Int, id: String) {
            let to = max(cut, min(end, full.count))
            guard to > cut else { return }
            let piece = String(full[cut..<to]).trimmingCharacters(in: .whitespacesAndNewlines)
            cut = to
            guard !piece.isEmpty else { return }
            out.append(Step(id: id, icon: nil,
                            tint: Theme.textMuted(scheme),
                            title: "Thinking", note: "", body: piece))
        }

        for (i, run) in message.toolRuns.enumerated() {
            // ⚠️ `reasonMark` 量的是**没剥 [[cot:]] 之前**的长度，
            // 而这儿的 `reasoning` 已经剥过了，会短一截。
            // 所以只当成「大概到这儿」用，越界的一律夹回范围内——
            // 切歪一点点比切崩了强。
            think(upTo: run.reasonMark, id: "think\(i)")
            out.append(Step(id: run.id.uuidString,
                            icon: run.failed
                                ? "exclamationmark.triangle" : "wrench.and.screwdriver",
                            tint: run.failed ? .red : app.settings.accentColor,
                            title: run.toolName.isEmpty ? "一个工具" : run.toolName,
                            note: run.serverName,
                            body: detail(run)))
        }
        // 最后一个工具之后还想了的那一段
        think(upTo: full.count, id: "thinkEnd")
        return out
    }

    /// 弹窗标题用他自己起的那个名字。
    /// 没起才退回「想了几秒 · 动了几下手」——那句话跟他在想什么毫无关系，
    /// 所以提示词里那条已经改成**必写**了。
    private var title: String {
        if !message.cotTitle.isEmpty { return message.cotTitle }
        var bits: [String] = []
        if let s = message.reasoningSeconds, s > 0 {
            bits.append(String(format: "想了 %.1fs", s))
        }
        if !message.toolRuns.isEmpty { bits.append("动了 \(message.toolRuns.count) 下手") }
        return bits.isEmpty ? "他刚才干了什么" : bits.joined(separator: " · ")
    }

    // MARK: 一条

    /// 一步。左边记号 + 一条竖线往下接，右边标题和摘要。
    ///
    /// ⚠️ **没有卡片背景**。整条线靠左边那根竖线连起来，
    /// 一加边框就断成一张张卡了。
    @ViewBuilder
    private func row(_ s: Step, isLast: Bool) -> some View {
        let isOpen = open == s.id
        HStack(alignment: .top, spacing: 11) {
            // 左边一栏：记号 + 往下那根线
            VStack(spacing: 0) {
                Group {
                    if let icon = s.icon {
                        Image(systemName: icon)
                            .font(.app(11))
                            .foregroundStyle(s.tint)
                    } else {
                        // thinking 那种就是一个实心点，跟 claude.ai 一样
                        Circle()
                            .fill(s.tint.opacity(0.8))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(width: 18, height: 18)
                // 最后一步底下不画线——线是「还有下一步」的意思
                if !isLast {
                    Rectangle()
                        .fill(Theme.textMuted(scheme).opacity(0.25))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        open = isOpen ? nil : s.id
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(s.title)
                            .font(.app(13.5, weight: .medium,
                                       design: s.icon == nil ? .default : .monospaced))
                            .foregroundStyle(Theme.textMain(scheme))
                        if !s.note.isEmpty {
                            Text(s.note)
                                .font(.app(9.5))
                                .foregroundStyle(Theme.textMuted(scheme))
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

                // ⚠️ 收着的时候**只给一行**。
                // 第二层要是也铺全文，那只是把「顶掉半屏聊天」
                // 换成了「顶掉半屏弹窗」。
                if isOpen {
                    // 展开之后**给全的**，不掐行数。
                    // 她定过：「不是把行高固定，是根据字数来画」——
                    // 她特地点开这一条，就没有再截断她的道理。
                    Text(MD.inline(s.body))
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(oneLine(s.body))
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
