import SwiftUI
import WebKit

/// clawd 表情工坊。
///
/// 她要的是「**我也能直接用 SVG 和 CSS 做 clawd 的表情包**」——
/// 所以这一页不是一堆做好的贴纸让她挑，是一块她自己能动手的画布：
///
///   · 上面实时预览，改一个字下面立刻变
///   · 换脸、加零件都是点一下就插进代码里，**不用从空白开始写**
///   · 想写就直接改代码，两边是同一份东西
///   · 存下来直接进表情库，跟别的表情一样能发
///
/// 预览和导出走的是**同一份 HTML**，所见即所得。

// MARK: - 画布

/// 拿 WKWebView 当画布。
/// 用它是因为 SVG 的动画（CSS keyframes）SwiftUI 画不出来，
/// 而她要的正是「能动的」表情包。
@MainActor
final class ClawdCanvas: ObservableObject {

    /// 当前渲染的那份 HTML
    @Published var html = ""

    fileprivate weak var web: WKWebView?

    /// 把画布现在的样子拍成 PNG。
    /// 背景是透明的，所以拍出来带 alpha，贴到聊天里不会有一块白底。
    func snapshot() async -> Data? {
        guard let web else { return nil }
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        // 这个 SDK 的 takeSnapshot **只有回调版**，没有自动桥接出来的 async。
        // 拿 continuation 包一层：回调本身就标了 @MainActor @Sendable，
        // 从里面 resume 是安全的，Data 也是 Sendable。
        return await withCheckedContinuation { cont in
            web.takeSnapshot(with: config) { image, _ in
                cont.resume(returning: image?.pngData())
            }
        }
    }
}

struct ClawdCanvasView: UIViewRepresentable {

    @ObservedObject var canvas: ClawdCanvas

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        // 透明背景，不然拍出来是一块白板
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        canvas.web = web
        web.loadHTMLString(canvas.html, baseURL: nil)
        context.coordinator.last = canvas.html
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // 内容没变就别重载——每次重载动画都会从头开始，
        // 她打字的时候会看到一只不停重启的 clawd
        guard context.coordinator.last != canvas.html else { return }
        context.coordinator.last = canvas.html
        canvas.web = web
        web.loadHTMLString(canvas.html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var last: String?
    }
}

// MARK: - 工坊

struct ClawdStudioView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @StateObject private var canvas = ClawdCanvas()

    @State private var svg = ClawdSVG.skeleton
    @State private var css = ClawdSVG.baseCSS
    /// 0 画（摆积木，不碰代码）· 1 零件 · 2 图形（SVG）· 3 样式（CSS）
    @State private var tab = 0
    @State private var saving = false
    @State private var name = ""
    @State private var desc = ""
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            preview
            picker
            Divider().opacity(0.15)
            editor
        }
        .navigationTitle("clawd 表情工坊")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    name = ""; desc = ""; saving = true
                } label: {
                    Text("保存到表情库").font(.app(14))
                }
            }
        }
        .onAppear { rerender() }
        .onChange(of: svg) { _, _ in rerender() }
        .onChange(of: css) { _, _ in rerender() }
        .sheet(isPresented: $saving) { saveSheet }
        .alert("提示", isPresented: Binding(get: { notice != nil },
                                          set: { if !$0 { notice = nil } })) {
            Button("好") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func rerender() {
        canvas.html = ClawdSVG.page(svg: svg, css: css)
    }

    // MARK: 上半屏：预览

    private var preview: some View {
        ZStack {
            // 棋盘格，让人一眼看出背景是透明的
            TransparencyGrid()
            ClawdCanvasView(canvas: canvas)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var picker: some View {
        Picker("", selection: $tab) {
            Text("画").tag(0)
            Text("零件").tag(1)
            Text("图形").tag(2)
            Text("样式").tag(3)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 下半屏

    @ViewBuilder
    private var editor: some View {
        switch tab {
        case 0:
            // 摆积木：**一个字的代码都不用看**。
            // 她说改代码这条路她走不了，所以这个排第一，默认就是它。
            ClawdGridEditor { drawn, withBody in
                // 装在身上：整块塞进骨架的 #face 里，它会跟身子一起呼吸。
                // 不装身上：只有她画的那一张，同一个 viewBox，
                // 导出和存进表情库那条路一个字都不用改。
                svg = withBody
                    ? ClawdSVG.replaceFace(in: ClawdSVG.skeleton, with: drawn)
                    : ClawdSVG.bare(drawn)
            }
        case 1: kit
        case 2: code($svg, hint: "这是 SVG。clawd 的身子、手、腿、脸都在这儿。")
        default: code($css, hint: "这是 CSS。颜色、动画都在这儿。")
        }
    }

    /// 零件面板：点一下就插进代码里，不用从空白开始写
    private var kit: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                section("换一张脸") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)],
                              spacing: 8) {
                        ForEach(ClawdSVG.faces) { f in
                            tapChip(f.name) {
                                svg = ClawdSVG.replaceFace(in: svg, with: f.svg)
                            }
                        }
                    }
                }

                section("加个零件") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                              spacing: 8) {
                        ForEach(ClawdSVG.parts) { p in
                            tapChip(p.name) {
                                if !p.svg.isEmpty {
                                    svg = ClawdSVG.insert(p.svg, into: svg)
                                }
                                if !p.css.isEmpty, !css.contains(p.css) {
                                    css += "\n\n" + p.css
                                }
                            }
                        }
                    }
                }

                section("换个颜色") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: 8)],
                              spacing: 8) {
                        ForEach(["F2715F", "E4A672", "7FB3D5", "8FBF8F",
                                 "C58BC0", "8A8378", "4A4038"], id: \.self) { hex in
                            Button {
                                recolor(to: hex)
                            } label: {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color(hexString: hex) ?? .gray)
                                    .frame(height: 34)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                section("重来") {
                    HStack(spacing: 8) {
                        tapChip("回到原样") {
                            svg = ClawdSVG.skeleton
                            css = ClawdSVG.baseCSS
                        }
                        tapChip("去掉所有动画") {
                            css = ClawdSVG.baseCSS
                                .components(separatedBy: "/* 整只呼吸")
                                .first ?? ClawdSVG.baseCSS
                        }
                        Spacer(minLength: 0)
                    }
                }

                Text("零件是往代码里插东西，插完可以去「图形」「样式」两页接着改。两边是同一份，改哪边都行。")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
    }

    private func code(_ text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hint)
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.horizontal, 16)
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .font(.app(12, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.softFillDeep))
                .padding(.horizontal, 16)
                .padding(.bottom, Layout.tabBarExpanded + 10)
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            content()
        }
    }

    private func tapChip(_ t: String, run: @escaping () -> Void) -> some View {
        Button {
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            run()
        } label: {
            Text(t)
                .font(.app(12))
                .foregroundStyle(Theme.textMain(scheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    /// 换身子的颜色。只动 CSS 里那个变量，不碰图形。
    private func recolor(to hex: String) {
        var out: [String] = []
        for line in css.components(separatedBy: "\n") {
            if line.contains("--body:") {
                out.append("  --body: #\(hex);")
            } else {
                out.append(line)
            }
        }
        css = out.joined(separator: "\n")
    }

    // MARK: 存进表情库

    private var saveSheet: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("存进表情库之后，它跟别的表情一样能发，他也能挑着用。")
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))

                        field("叫什么", text: $name, hint: "比如：探头")
                        field("画面写什么", text: $desc,
                              hint: "写画面内容和动作，不是写它好不好看")

                        Text("画面描述是必填的——他看不见图，只能读这段字。写清楚了他才知道什么时候该发它。")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))

                        Button {
                            saveToLibrary()
                        } label: {
                            Text("存下")
                                .font(.app(15, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill((Color(hexString: "4A4038") ?? .black)
                                        .opacity(canSave ? 1 : 0.35)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("保存到表情库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { saving = false }
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !desc.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            TextField(hint, text: text)
                .font(.app(15))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 11).fill(Theme.softFillDeep))
        }
    }

    private func saveToLibrary() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let about = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            guard let data = await canvas.snapshot() else {
                notice = "画面还没准备好，等一下再试。"
                return
            }
            // 存成 PNG。**动画只会留下按下那一刻的那一帧**——
            // 这是静态图的物理限制，不是没做完；
            // 要动图得逐帧合成，那是另一件事。
            guard var s = StickerStore.shared.add(data: data, ext: "png",
                                                  owner: "user") else {
                notice = "存不下，空间可能满了。"
                return
            }
            s.name = title
            s.description = about
            StickerStore.shared.update(s)
            saving = false
            notice = "存好了，在表情库里。（动的那些只留下了按下这一刻的样子）"
        }
    }
}

// MARK: - 棋盘格

/// 透明背景的那种灰白方格。摆一层在预览底下，
/// 她才看得出来这张图**是没有底色的**。
///
/// 名字不叫 Checkerboard 是因为 PixelStudioView 里已经有一个同名的
/// `Shape` 了——两个都是顶层类型，重名直接编译不过。
struct TransparencyGrid: View {
    var side: CGFloat = 10
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let light = scheme == .dark
                ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
            let dark = scheme == .dark
                ? Color.white.opacity(0.02) : Color.black.opacity(0.015)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : side
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: side, height: side)),
                             with: .color(light))
                    x += side * 2
                }
                y += side
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}
