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

    /// 拖零件的时候，**直接改网页里那个属性，不重载整页**。
    ///
    /// ⚠️ 这一条是这个功能能不能用的关键。
    ///
    /// 走 `svg` 那条路的话，手指每动一个点就重写一次字符串、
    /// 触发一次 `loadHTMLString`——**整页重载**：动画从头开始、
    /// 画面闪一下、还卡。拖一次等于重载上百次。
    ///
    /// 所以拖的过程只喂一句 JS 改 transform（几乎不花什么），
    /// **松手那一下才写回 `svg`**（那时候重载一次是应该的，
    /// 因为要落到那份唯一的账上）。
    func nudge(_ id: String, _ transform: String) {
        // 单引号，别用双引号——外面这串本身就是双引号包的
        let js = "var e=document.getElementById('\(id)');"
            + "if(e){e.setAttribute('transform','\(transform)');}"
        web?.evaluateJavaScript(js, completionHandler: nil)
    }

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
    /// 预览放大多少、挪到哪儿。
    ///
    /// ⚠️ **它们得挂在这一层，不能挂在预览那个子 View 里。**
    /// 她说「放大缩小功能应该是持续的……我把他放多大
    /// 他就保持在我操作的地方，不管是零件还是画都是」——
    /// 挂在子 View 里的话，切一下页签它就重建了，缩放归零。
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    /// 正在拖的那一下（松手才并进 `pan`）
    @State private var panLive: CGSize = .zero
    /// 捏之前的倍率。没它的话每捏一下都从 1× 重新算，
    /// 手指一落下去画面就弹回去了
    @State private var zoomBase: CGFloat = 1

    /// 改之前的样子，给「撤销」用。
    ///
    /// 她的原话：「点击回到原样是直接变回一个画好的 clawd，
    /// 那我画好的其他东西就会直接变成 clawd 了……
    /// 这部分应该再出一个撤回功能。」
    ///
    /// ⚠️ **一个能一键抹掉她半小时成果、而且没法撤销的按钮，
    /// 比没有这个按钮更坏。** 按下去之前她不知道会发生什么，
    /// 按下去之后来不及后悔。
    @State private var history: [(svg: String, css: String)] = []
    /// 「一行字」那件现在要填的字
    @State private var words = ""
    /// 画布本身。**住在这一层**，切页签不会丢（见 `ClawdGridEditor.doc`）
    @State private var doodle = ClawdDoodle()
    /// 现在选中的那件零件。空 = 没选
    @State private var picked: String = ""
    /// 拖的过程中那个临时位移（松手才写回 svg）
    @State private var nudgeLive: CGSize = .zero
    /// 拖大小滑块的过程中的值。
    ///
    /// ⚠️ **没它不行。** 滑块的 `get` 是从 `svg` 里读的，
    /// 而拖的过程中我们故意不写 `svg`（写一次就重载一次整页）——
    /// 于是滑块读到的永远是旧值，**手指拖不动那个圆点**。
    @State private var scaleLive: Double?
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

    /// 改之前先把现在这份存下来。
    ///
    /// ⚠️ **每一个会改 svg/css 的按钮都要先叫它。**
    /// 漏一个，那一步就撤不回来——而她发现的时候
    /// 已经来不及了。
    ///
    /// 只留二十步：再多就是拿内存装一些永远不会回去的状态。
    private func remember() {
        history.append((svg, css))
        if history.count > 20 { history.removeFirst() }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        svg = last.svg
        css = last.css
    }

    private func rerender() {
        canvas.html = ClawdSVG.page(svg: svg, css: css)
    }

    // MARK: 上半屏：预览

    private var preview: some View {
        VStack(spacing: 6) {
            ZStack {
                // 棋盘格，让人一眼看出背景是透明的
                TransparencyGrid()
                // ⚠️ 缩放只作用在**画布**上，不动棋盘格——
                // 棋盘格是“背景是透的”这件事的标记，
                // 跟着一起放大就成了画面的一部分。
                ClawdCanvasView(canvas: canvas)
                    .scaleEffect(zoom)
                    .offset(x: pan.width + panLive.width,
                            y: pan.height + panLive.height)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { panLive = $0.translation }
                    .onEnded { _ in
                        pan.width += panLive.width
                        pan.height += panLive.height
                        panLive = .zero
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { zoom = min(6, max(0.4, $0.magnification * zoomBase)) }
                    .onEnded { _ in zoomBase = zoom }
            )

            zoomBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 缩放那一条。
    ///
    /// 两根手指捏也行，但**滑块得有**——
    /// 小格子那一档里捕捉捉不准，她报过「无法精准定位」。
    private var zoomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.magnifyingglass")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
            Slider(value: $zoom, in: 0.4...6)
                .onChange(of: zoom) { _, v in zoomBase = v }
            Text(String(format: "%.1f×", zoom))
                .font(.app(10, design: .monospaced))
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(width: 34, alignment: .trailing)
            Button("归位") {
                zoom = 1; zoomBase = 1; pan = .zero; panLive = .zero
            }
            .font(.app(11))
            .buttonStyle(.plain)
            .foregroundStyle(app.settings.accentColor)
        }
    }

    // MARK: 摆位置

    /// 放上去的零件能挪、能缩、能删。
    ///
    /// 她报的最后一件：零件的坐标是**照 clawd 的身子定死的**
    /// （腮红在 x=50,y=92，因为那儿正好是他的脸颊）。
    /// 她画的不一定是 clawd——画一朵花、一杯奶茶，
    /// 腮红照样落在「clawd 脸颊」那个位置上。
    @ViewBuilder
    private var placeSection: some View {
        let list = ClawdSVG.placedList(in: svg)
        if !list.isEmpty {
            section("摆位置") {
                VStack(alignment: .leading, spacing: 10) {
                    // 放了哪几件。点一下选中它
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)],
                              spacing: 8) {
                        ForEach(list) { item in
                            Button {
                                // 换选的时候把临时值清掉，
                                // 不清的话上一件的大小会带到这一件上
                                scaleLive = nil
                                picked = (picked == item.id) ? "" : item.id
                            } label: {
                                Text(item.name)
                                    .font(.app(12))
                                    .foregroundStyle(picked == item.id
                                                     ? Color.white
                                                     : Theme.textMain(scheme))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10,
                                                                 style: .continuous)
                                        .fill(picked == item.id
                                              ? app.settings.accentColor.opacity(0.85)
                                              : Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !picked.isEmpty {
                        movePad
                    } else {
                        Text("点一件选中它，才能挪位置、改大小。")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
            }
        }
    }

    /// 拖盘 + 大小 + 删掉
    private var movePad: some View {
        let t = ClawdSVG.transformOf(picked, in: svg)
        return VStack(alignment: .leading, spacing: 9) {
            // 拖这块挪它。
            //
            // ⚠️ 不做成「在预览上直接拖那件东西」：
            // 预览那块的拖动已经是「挪画布」了，
            // 两个手势撞在一起她永远弄不清自己在挪哪一个。
            // 单独一块板子，手指放上去就只有一种意思。
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.softFillDeep)
                VStack(spacing: 3) {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.app(15))
                        .foregroundStyle(app.settings.accentColor)
                    Text("拖这儿挪它")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text(String(format: "x %.0f　y %.0f", t.dx, t.dy))
                        .font(.app(10, design: .monospaced))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .frame(height: 84)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { g in
                        nudgeLive = g.translation
                        // 拖的时候只嗂一句 JS，**不重载整页**
                        canvas.nudge(picked, ClawdSVG.transformText(
                            dx: t.dx + g.translation.width,
                            dy: t.dy + g.translation.height,
                            scale: t.scale))
                    }
                    .onEnded { g in
                        nudgeLive = .zero
                        remember()
                        svg = ClawdSVG.move(picked,
                                            dx: t.dx + g.translation.width,
                                            dy: t.dy + g.translation.height,
                                            scale: t.scale, in: svg)
                    }
            )

            HStack(spacing: 8) {
                Text("大小")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMain(scheme))
                Slider(value: Binding(
                    get: { scaleLive ?? t.scale },
                    set: { v in
                        scaleLive = v
                        // 拖的时候只嗂 JS，不写 svg
                        canvas.nudge(picked, ClawdSVG.transformText(
                            dx: t.dx, dy: t.dy, scale: v))
                    }
                ), in: 0.2...3, onEditingChanged: { editing in
                    // ⚠️ **松手那一下必须写回 `svg`。**
                    // 不写的话它只存在于网页里，
                    // 切一下页签、或者随便改点别的触发重载，就没了。
                    guard !editing, let v = scaleLive else { return }
                    remember()
                    svg = ClawdSVG.move(picked, dx: t.dx, dy: t.dy, scale: v, in: svg)
                    scaleLive = nil
                })
                Text(String(format: "%.2f×", scaleLive ?? t.scale))
                    .font(.app(10, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(width: 42, alignment: .trailing)
            }

            HStack(spacing: 8) {
                tapChip("归位") {
                    remember()
                    svg = ClawdSVG.move(picked, dx: 0, dy: 0, scale: 1, in: svg)
                }
                tapChip("删掉这件") {
                    remember()
                    svg = ClawdSVG.removePlaced(picked, from: svg)
                    picked = ""
                }
                Spacer(minLength: 0)
            }
        }
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
            ClawdGridEditor(doc: $doodle) { drawn, withBody in
                // 画布那边一改也得存一步——
                // 不存的话「撤销」会跳过她刚画的那一笔
                remember()
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
                                remember()
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
                                remember()
                                if !p.svg.isEmpty {
                                    // 包一层才挪得动（见 `ClawdSVG.placed`）
                                    let id = ClawdSVG.nextPlacedID(in: svg)
                                    svg = ClawdSVG.insert(
                                        ClawdSVG.placed(p.svg, name: p.name, id: id),
                                        into: svg)
                                    // 放完直接选中它：她刚放上去那一秒
                                    // 想做的事就是把它挪到对的地方
                                    picked = id
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
                                remember()
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

                placeSection

                section("说一句话") {
                    HStack(spacing: 8) {
                        TextField("写你想让他说的", text: $words)
                            .textFieldStyle(.plain)
                            .font(.app(14))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 11,
                                                         style: .continuous)
                                .fill(Theme.softFillDeep))
                        tapChip("放上去") {
                            let t = words.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            remember()
                            let part = ClawdSVG.sayPart(t)
                            let id = ClawdSVG.nextPlacedID(in: svg)
                            svg = ClawdSVG.insert(
                                ClawdSVG.placed(part.svg, name: "一行字", id: id),
                                into: svg)
                            picked = id
                            // ⚠️ 空行走常量，别在这儿直接写转义 —— 第十四次了
                            let gap = "\n\n"
                            if !css.contains(".say") { css += gap + part.css }
                        }
                    }
                }

                section("重来") {
                    HStack(spacing: 8) {
                        // ⚠️ **撤销排在最前面。**
                        // 旁边就是一个能把她半小时成果一键抹掉的按钮，
                        // 那就得让「抹错了怎么办」就在手边。
                        tapChip(history.isEmpty ? "没得撤了" : "撤销") {
                            undo()
                        }
                        .opacity(history.isEmpty ? 0.45 : 1)
                        tapChip("回到原样") {
                            remember()
                            svg = ClawdSVG.skeleton
                            css = ClawdSVG.baseCSS
                        }
                        tapChip("去掉所有动画") {
                            remember()
                            css = ClawdSVG.baseCSS
                                .components(separatedBy: "/* 整只呼吸")
                                .first ?? ClawdSVG.baseCSS
                        }
                        Spacer(minLength: 0)
                    }
                }

                Text("零件会插入当前的图形与样式，插入后可在「图形」「样式」两页继续编辑。三处共用同一份内容。")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
    }

    private func code(_ text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MD.inline(hint))
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
                        Text("存入表情库后可正常发送，模型也可在对话中选用。")
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))

                        field("叫什么", text: $name, hint: "比如：探头")
                        field("画面写什么", text: $desc,
                              hint: "写画面内容和动作，不是写它好不好看")

                        Text("画面描述为必填项。模型不读取图像本身，仅依据该描述判断使用时机。")
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
