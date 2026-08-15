import SwiftUI

struct RootView: View {

    @EnvironmentObject var app: AppState
    @ObservedObject private var notifier = Notifier.shared
    @State private var selection = 0
    @State private var navOpen = false

    var body: some View {
        ZStack {
            WallpaperBackground()

            Group {
                switch selection {
                case 0: ChatView(space: .chat, title: "絮语")
                case 1: WorkshopView()
                case 2: NotesView()
                default: SettingsView()
                }
            }

            NavDrawerBar(selection: $selection, isOpen: $navOpen,
                         canAutoHide: selection <= 1)
        }
        .onAppear {
            // 札记、设置这些页面导航常驻，不然翻着翻着就出不去了
            if selection > 1 { navOpen = true }
        }
        .onChange(of: selection) { _, v in
            if v > 1 {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { navOpen = true }
            }
        }
        // 从横幅点进来的，直接翻到他说话的那个窗口
        .onChange(of: notifier.openConversationID) { _, id in
            guard let id else { return }
            selection = 0
            app.setActive(id, for: .chat)
            notifier.openConversationID = nil
        }


    }
}

// MARK: - 抽屉式导航条

/// 底部这条导航是抽屉：平时往右收进去，只在屏幕右边留一个小把手，
/// 需要换页面时把它拉出来。聊天的时候不占地方。
struct NavDrawerBar: View {

    @Binding var selection: Int
    @Binding var isOpen: Bool
    /// 只有絮语和工坊会自己收起来；别的页面一直挂着
    var canAutoHide: Bool = true

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var dragX: CGFloat = 0
    @State private var handleDragY: CGFloat = 0
    @State private var idleTask: Task<Void, Never>?

    private let items: [(String, String)] = [
        ("絮语", Icon.chat),
        ("工坊", Icon.workshop),
        ("札记", Icon.notes),
        ("设置", Icon.settings)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {

                if isOpen {
                    bar
                        .padding(.horizontal, 14)
                        .offset(x: max(0, dragX))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    if v.translation.width > 0 { dragX = v.translation.width }
                                    postpone()
                                }
                                .onEnded { v in
                                    if v.translation.width > 70 || v.predictedEndTranslation.width > 140 {
                                        toggle(false)
                                    }
                                    dragX = 0
                                }
                        )
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 34)
                }

                if !isOpen {
                    handle
                        .position(
                            // 减掉的这一截要算上把手左边那圈留白，
                            // 不然条本身会顶到屏幕边上被切掉半根
                            x: geo.size.width - 20,
                            y: handleCenterY(in: geo.size.height)
                        )
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isOpen)
        }
        .ignoresSafeArea(edges: .bottom)
        // 只要它是开着的，就一直有一个三秒的倒计时在跑。
        //
        // 之前只在"点了它"的时候才起倒计时，所以从设置页（常驻不收）
        // 切回絮语的时候，条已经是开着的、又没人点它，
        // 倒计时根本没起过——那条就一直挂在那儿不走了。
        .onChange(of: isOpen) { _, open in
            if open { postpone() } else { idleTask?.cancel() }
        }
        .onChange(of: canAutoHide) { _, can in
            // 切到札记、设置这些页面时，把已经在倒计时的那个任务掐掉，
            // 不然刚展开又被上一页留下的计时收回去；
            // 反过来切回絮语、工坊，就得把倒计时重新起上
            if can {
                if isOpen { postpone() }
            } else {
                idleTask?.cancel()
            }
        }
        .onAppear {
            if isOpen { postpone() }
        }
    }

    /// 把手停在屏幕右侧的哪个高度
    private func handleCenterY(in height: CGFloat) -> CGFloat {
        let base = height * app.settings.handleY
        return min(max(70, base + handleDragY), height - 70)
    }

    private func toggle(_ open: Bool) {
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { isOpen = open }
        if open { postpone() } else { idleTask?.cancel() }
    }

    /// 三秒没人碰就自己收回去，免得一直贴在底部误触到系统的切换手势。
    /// 只在絮语和工坊这么干——札记、设置那些页面要是也收，
    /// 翻内容的时候很容易就出不去了。
    private func postpone() {
        idleTask?.cancel()
        guard canAutoHide else { return }
        idleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { isOpen = false }
        }
    }

    // 收起时贴在右边缘的那根小白条。点一下就出来，不用滑——
    // 在能上下滚的页面上，横滑很难滑准。
    //
    // 以前是个 26 宽的方块，里面还竖着一道主题色的杠，
    // 又厚又抢眼。现在就是一根圆角小白条：材质跟着设置里的玻璃走，
    // 玻璃换成通透它就跟着变通透，不再是单独一件东西。
    private var handle: some View {
        Button {
            toggle(true)
        } label: {
            // **这里不能用 GlassSurface。**
            // material 是要去采样背后那块画面的，拖着它走的时候
            // 采样跟不上位移，屏幕上就拖出一道虚影（就是那个"重影"）。
            // 这么细一根条本来也糊不出什么东西来，
            // 所以直接画一根实心的白条：不采样，就不会有影。
            // 颜色还是跟着玻璃设置走——哪套玻璃就哪个白。
            Capsule(style: .continuous)
                .fill(.white.opacity(handleWhite))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(handleWhite * 0.5), lineWidth: 0.5)
                }
                .frame(width: 5.5, height: 44)
                .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.14),
                        radius: 5, x: -1, y: 1)
                // 条本身很细，四周留出富余，手指按偏一点也能中
                .padding(.leading, 22)
                .padding(.trailing, 3)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onEnded { v in
                    // 上下拖是换位置，不影响点击
                    if abs(v.translation.height) > 20, let h = currentScreenHeight {
                        let newY = (h * app.settings.handleY + v.translation.height) / h
                        app.settings.handleY = min(0.9, max(0.1, newY))
                    }
                    handleDragY = 0
                }
                .onChanged { v in
                    if abs(v.translation.height) > 10 { handleDragY = v.translation.height }
                }
        )
    }

    /// 那根条有多白。三套玻璃各给一个值，换玻璃它跟着变。
    private var handleWhite: Double {
        let base: Double
        switch app.settings.glassStyle {
        case .frosted: base = scheme == .dark ? 0.42 : 0.92
        case .clear:   base = scheme == .dark ? 0.30 : 0.70
        case .blur:    base = scheme == .dark ? 0.36 : 0.82
        }
        return base * min(1, app.settings.glassOpacity + 0.3)
    }

    private var currentScreenHeight: CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.height
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                    selection = i
                    postpone()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].1)
                            .font(.system(size: 17, weight: .regular))
                        Text(items[i].0)
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(selection == i
                                     ? Theme.textMain(scheme)
                                     : Theme.textMuted(scheme).opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        // 选中的那个底下垫一小块。**要跟外面那根条同形状**——
                        // 外面是胶囊，里面塞个方角圆矩形，四个角就顶出来了。
                        if selection == i {
                            Capsule(style: .continuous)
                                .fill(Theme.textMain(scheme).opacity(0.07))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        // 网页版那根条：整根近乎白、圆到底、投影浅，
        // 像一片贴在屏幕上的纸，不是一块沉下去的面板。
        // 跟别处一样走 GlassSurface，这样设置里的玻璃浓度也管得着它。
        // 半径给得比高度大，画出来就是胶囊。
        .background {
            GlassSurface(radius: 30, strength: app.settings.glassOpacity, extra: 0.2)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.10),
                radius: 14, x: 0, y: 5)
    }
}

/// 页面底部要给导航条留的距离。导航条收起时不占地方，所以留一点点就够。
enum Layout {
    static let tabBarSpace: CGFloat = 10
    /// 展开状态下导航条大概这么高，札记、设置这些常驻页面用这个
    static let tabBarExpanded: CGFloat = 76
    /// 思考链、工具调用这类附属卡片统一这么宽。
    /// 它们跟说了多长的话没关系，宽度就该是定的——
    /// 只有说的话才按文字长短自己撑开。
    static let sideCardWidth: CGFloat = 258
}

// MARK: - 壁纸背景层

struct WallpaperBackground: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.pageBackground(scheme)

                if let name = app.settings.wallpaperName,
                   let image = ImageStore.load(name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    if scheme == .dark {
                        Color.black.opacity(0.30)
                    }
                    if app.settings.wallpaperDim > 0.01 {
                        Color.black.opacity(app.settings.wallpaperDim)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}
