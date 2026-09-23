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

    /// 这一轮挂在哪条消息上。**现读现取**——他还在想的时候，这一页要跟着长。
    ///
    /// 她报的：「他正在输出 thinking 的时候我点进思考块，它就不再动了，
    /// 停在我点进去那一刻，得退出去重新点才会更新。」
    /// 以前这儿存的是一份**快照**（`let message: ChatMessage`），
    /// 拍下来那一刻是什么样就永远是什么样。
    let messageID: UUID
    let conversationID: UUID
    /// 找不到那条的时候用这份（消息被删、或者这一窗被换掉了）
    let fallback: ChatMessage

    /// 现在这一刻的那条消息：正在蹦的字也算进来（见 `LiveStream`）
    private var message: ChatMessage {
        guard let m = app.conversation(conversationID)?.messages
            .last(where: { $0.id == messageID })
        else { return fallback }
        return live.merged(m)
    }

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
    /// 他正在蹦的那几个字。
    ///
    /// ⚠️⚠️ **这儿不能写 `@ObservedObject`。**
    ///
    /// 她报的：「他在说话时我点开他的 thinking 依旧有点卡顿。」
    /// 订阅了就是**他每吐一次字，这整张弹窗重画一次**——
    /// 而重画一次要：正文里把 `[[cot:]]` 正则剥一遍、压空行、
    /// 整段拆成字符数组切成几步、每一步再过一遍 Markdown。
    /// 一秒几十次，就是她感觉到的那个卡。
    ///
    /// 改成**自己按 0.3 秒跳一下**（`beat`）：他还在说的时候一秒重画三次，
    /// 眼睛看不出差别，活儿少了十几倍。说完就停，一点都不跳。
    private let live = LiveStream.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 展开了哪几条。可以同时开好几条（要对照前后两段的时候）。
    @State private var open: Set<String> = []

    /// 每一段的译文（按那一步的 id）。只在这张弹窗里，关了就没了——
    /// 原文一直在，译文是看的时候临时翻的。
    @State private var translated: [String: String] = [:]
    @State private var translating: Set<String> = []

    /// 他还在说的时候，靠它推着这一页往前走（见上面 `live` 那段）。
    /// 这个数变一下 = 整页重画一次，所以**只在他还在说的时候跳**。
    @State private var beat = 0
    @State private var wasStreaming = false

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
                            Text("本轮无思考内容，也未执行任何操作。")
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
        }
        // 系统翻译的宿主（见 `AppleTranslate`）：弹窗盖在上面的时候，
        // 根视图那个弹不出「下载语言包」的卡片，得这一层自己来
        .background(AppleTranslateHost())
        // ⚠️ 走 `.task` 不走 `Timer` + `onReceive`：
        // 定时器写成视图里的属性的话，**每次重画都会造一个新的**，
        // 越堆越多（`PhoneActivityView` 那儿栽过）。`.task` 这一页一关自己就停。
        //
        // ⚠️ 最后那一下也要跳：他说完那一刻 `isStreaming` 才变假，
        // 只认「正在说」的话，屏幕会停在倒数第二次跳的样子。
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let now = message.isStreaming
                if now || wasStreaming { beat &+= 1 }
                if now != wasStreaming { wasStreaming = now }
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
        // ⚠️ `reasoning` 是个**算出来的属性**：每读一次就把整段正文
        // 正则剥一遍、空行压一遍。这个方法里要用到它四五次，
        // 读四五次就是白算四五遍——他还在说的时候这一页一直在重算。
        let think = reasoning
        let full = Array(think)
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
        let trustworthy = firstMark > 0 || think.isEmpty
        let marked = message.toolRuns.contains { $0.reasonMark > 0 } && trustworthy
        if !marked {
            if !think.isEmpty {
                out.append(Step(id: "think", icon: nil,
                                tint: Theme.textMuted(scheme),
                                title: "Thinking", note: "", body: think))
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

        func cutThink(upTo end: Int, id: String) {
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
            cutThink(upTo: run.reasonMark, id: "think\(i)")
            out.append(Step(id: run.id.uuidString,
                            icon: run.failed
                                ? "exclamationmark.triangle" : "wrench.and.screwdriver",
                            tint: run.failed ? .red : app.settings.accentColor,
                            title: run.toolName.isEmpty ? "一个工具" : run.toolName,
                            note: run.serverName,
                            body: detail(run)))
        }
        // 最后一个工具之后还想了的那一段
        cutThink(upTo: full.count, id: "thinkEnd")
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
        let isOpen = open.contains(s.id)
        // 还在长的那一段（最后一步，而且他还在说）。
        // 这一段每跳一下都会变长，**别让它过 Markdown、也别开选字**：
        // 一个是每次都要把整段重新解析一遍，一个是每次都要重新量一遍可选区域。
        // 他说完就自动换回带格式的那一支。
        let growing = isLast && message.isStreaming
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
                        if isOpen { open.remove(s.id) } else { open.insert(s.id) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(s.title)
                            .font(.app(13.5, weight: .medium,
                                       design: s.icon == nil ? .default : .monospaced))
                            .foregroundStyle(Theme.textMain(scheme))
                        if !s.note.isEmpty {
                            Text(MD.inline(s.note))
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
                    Group {
                        if growing {
                            Text(s.body)
                        } else {
                            Text(MD.inline(s.body)).textSelection(.enabled)
                        }
                    }
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    translation(s)
                } else if growing {
                    Text(oneLine(s.body))
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                } else {
                    Text(MD.inline(oneLine(s.body)))
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button { translate(s) } label: {
                Label(translated[s.id] == nil ? "翻译" : "重新翻",
                      systemImage: "character.book.closed")
            }
            if translated[s.id] != nil {
                Button { translated[s.id] = nil } label: {
                    Label("收起译文", systemImage: "chevron.up")
                }
            }
            Button { UIPasteboard.general.string = s.body } label: {
                Label("拷贝", systemImage: "doc.on.doc")
            }
        }
    }

    /// 展开之后原文底下那一块：译文，或者「翻成中文」按钮。
    /// 只给思考那几段摆按钮（工具的参数和结果本来就是中文居多）；长按哪一条都能翻。
    @ViewBuilder
    private func translation(_ s: Step) -> some View {
        if translating.contains(s.id) {
            Text("在翻…")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
        } else if let t = translated[s.id], !t.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Capsule()
                    .fill(app.settings.accentColor.opacity(0.4))
                    .frame(width: 2)
                Text(MD.inline(t))
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } else if s.icon == nil, !Translator.looksChinese(s.body) {
            Button { translate(s) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "character.book.closed").font(.app(9))
                    Text("翻成中文").font(.app(9.5))
                }
                .foregroundStyle(app.settings.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
        }
    }

    private func translate(_ s: Step) {
        guard !translating.contains(s.id) else { return }
        translating.insert(s.id)
        // 长按翻的时候那一条可能还收着：顺手展开，不然译文看不见
        open.insert(s.id)
        Task { @MainActor in
            let out = await app.translateText(s.body)
            translated[s.id] = out.trimmingCharacters(in: .whitespacesAndNewlines)
            translating.remove(s.id)
        }
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
