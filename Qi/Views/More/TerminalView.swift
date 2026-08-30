import SwiftUI

/// 终端那一页。
///
/// 一条一条摆着：几点几分 · 哪一类 · 一句话 · 底下一行细节。
/// **等宽字**——这一页是拿来对齐着看的，不是拿来读的。
///
/// 上面一排是筛子（请求／工具／用量／唤醒／出错），
/// 出错那一档单独一个色，因为她八成是为了它才点进来的。
struct TerminalView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var console = Console.shared

    /// 选中的筛子。空 = 全都要。
    @State private var tab = 0
    @State private var picked: Set<Console.Kind> = []
    /// 命令那一栏
    @State private var cmd = ""
    @State private var shellLines: [ShellBridge.Line] = []
    @State private var running = false
    @State private var shellNote: String?
    @State private var toBottom = true
    @State private var copied = false

    private var shown: [Console.Line] {
        picked.isEmpty ? console.lines : console.lines.filter { picked.contains($0.kind) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 两栏。**日志和命令是两回事**：
            // 日志是 App 自己干了什么（只读），
            // 命令是她去动那台电脑（可写）。
            // 混在一页里的话，她满屏日志里找不到自己刚跑的那条。
            Picker("", selection: $tab) {
                Text("日志").tag(0)
                Text("命令").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if tab == 1 {
                shellTab
            } else {
            filters

            if shown.isEmpty {
                EmptyNote(icon: "terminal",
                          title: console.lines.isEmpty ? "还什么都没发生" : "这一档是空的",
                          hint: console.lines.isEmpty
                              ? "发起一次对话或触发一次工具调用后，此处会记录运行日志。\n日志仅存于本机，不上传，也不进入模型的上下文。"
                              : "切换其他分类查看。")
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(shown) { row($0) }
                            Color.clear.frame(height: 1).id("底")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: console.lines.count) { _, _ in
                        guard toBottom else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("底", anchor: .bottom) }
                    }
                    .onAppear { proxy.scrollTo("底", anchor: .bottom) }
                }
            }
            }
        }
        .background { WallpaperBackground() }
        .navigationTitle("终端")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = console.plainText(picked.isEmpty ? nil : picked)
                        copied = true
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Label("复制这些", systemImage: "doc.on.doc")
                    }
                    Toggle(isOn: $toBottom) {
                        Label("跟着滚到底", systemImage: "arrow.down.to.line")
                    }
                    Divider()
                    Button(role: .destructive) {
                        console.clear()
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("复制好了", isPresented: $copied) {
            Button("好") { copied = false }
        } message: {
            Text("可直接复制导出。内容不含密钥，也不含完整聊天记录。")
        }
    }

    // MARK: 筛子

    // MARK: 命令那一栏

    /// 在电脑上跑一条命令，输出流回来。
    ///
    /// ⚠️ 这一栏动的是**那台电脑**，不是这个 App。
    /// 所以顶上那句话要说清楚在哪儿跑——不写的话她会以为是手机本地的。
    @ViewBuilder
    private var shellTab: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if shellLines.isEmpty {
                            Text("在电脑上跑命令，输出显示在这里。\n"
                                 + "目录是桥所在的那个项目；桥的窗口关了就连不上。")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.top, 24)
                        }
                        ForEach(shellLines) { l in
                            Text(l.text)
                                .font(.system(size: 11, design: .monospaced))
                                // 出错的那几行单独一个色——她多半是为了它才看的
                                .foregroundStyle(l.kind == "err" ? .orange
                                                 : (l.kind == "start"
                                                    ? app.settings.accentColor
                                                    : Theme.textSoft(scheme)))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("shellBottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: shellLines.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("shellBottom", anchor: .bottom)
                    }
                }
            }

            if let shellNote {
                Text(shellNote)
                    .font(.app(11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme))
                TextField("git status", text: $cmd)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { send() }
                if running {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.app(19))
                            .foregroundStyle(cmd.trimmingCharacters(in: .whitespaces).isEmpty
                                             ? Theme.textMuted(scheme)
                                             : app.settings.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(cmd.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.softFillDeep))
            .padding(.horizontal, 12)
            .padding(.bottom, Layout.tabBarSpace + 12)
        }
    }

    private func send() {
        let line = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !running else { return }
        guard let p = ShellBridge.find(in: app.providers) else {
            shellNote = ShellBridge.ShellError.noBridge.errorDescription
            return
        }
        cmd = ""
        shellNote = nil
        running = true
        Task { @MainActor in
            do {
                try await ShellBridge.run(line, provider: p) { l in
                    shellLines.append(l)
                    // 太长就砍前面。**留 500 行**——
                    // 一次 build 的输出能有上千行，全留着这一页会越翻越卡。
                    if shellLines.count > 500 {
                        shellLines.removeFirst(shellLines.count - 500)
                    }
                }
            } catch {
                shellNote = error.localizedDescription
            }
            running = false
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(nil, "全部", count: console.lines.count)
                ForEach(Console.Kind.allCases, id: \.self) { k in
                    let n = console.lines.filter { $0.kind == k }.count
                    if n > 0 { chip(k, k.rawValue, count: n) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private func chip(_ kind: Console.Kind?, _ label: String, count: Int) -> some View {
        let on = kind == nil ? picked.isEmpty : picked.contains(kind!)
        let tint = kind == .warn ? StatusTone.remind.color : app.settings.accentColor
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                guard let kind else { picked.removeAll(); return }
                if picked.contains(kind) { picked.remove(kind) } else { picked.insert(kind) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.app(11.5, weight: on ? .semibold : .regular))
                Text("\(count)").font(.app(9.5, design: .monospaced)).opacity(0.75)
            }
            .foregroundStyle(on ? .white : Theme.textSoft(scheme))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(on ? tint.opacity(0.85) : Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    // MARK: 一行

    private func row(_ line: Console.Line) -> some View {
        let tint = line.kind == .warn ? StatusTone.remind.color : Theme.textMuted(scheme)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Self.clock.string(from: line.at))
                    .font(.app(10, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                Image(systemName: line.kind.icon)
                    .font(.app(9))
                    .foregroundStyle(tint)
                Text(line.title)
                    .font(.app(12, design: .monospaced))
                    .foregroundStyle(line.kind == .warn
                                     ? StatusTone.remind.color
                                     : Theme.textMain(scheme))
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            if !line.detail.isEmpty {
                Text(line.detail)
                    .font(.app(10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .padding(.leading, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = line.title
                    + (line.detail.isEmpty ? "" : "\n" + line.detail)
            } label: {
                Label("复制这一条", systemImage: "doc.on.doc")
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
