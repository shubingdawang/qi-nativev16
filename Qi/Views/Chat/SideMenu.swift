import SwiftUI

// MARK: - 外壳

/// claude.ai 那种侧栏：**侧栏不盖在聊天上面，而是垫在下面**。
/// 往右一拉，整个聊天页往右挪、缩小一点、四角变圆，
/// 像一张卡片被推开，露出底下一直都在的那一层。
///
/// 用法是把整页包起来：
/// ```
/// ZStack { ...聊天页... }
///     .sideMenuShell(isOpen: $sideOpen) { item in ... }
/// ```
struct SideMenuShell<Content: View>: View {

    @Binding var isOpen: Bool
    var onSelect: (SideMenuItem) -> Void
    @ViewBuilder var content: Content

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 关的时候手指往左带了多少（负数）
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.80, 320)
            let raw = isOpen ? (width + drag) / width : 0
            let progress = min(1, max(0, raw))

            ZStack(alignment: .leading) {

                // 底下这一层：侧栏。它一直都在，只是平时被聊天页压着。
                SideMenuPanel(isOpen: isOpen, onSelect: { item in
                    onSelect(item)
                    close()
                })
                .frame(width: width, height: geo.size.height)
                // 侧栏要顶到屏幕最上最下，不然上下各留一条白边，
                // 看着像贴了张比屏幕小一圈的纸
                .ignoresSafeArea()
                .opacity(progress)
                .allowsHitTesting(isOpen)
                .zIndex(0)

                // 上面这一层：聊天页本体。
                //
                // **开着的时候整块不接手势**（allowsHitTesting(false)）。
                // 之前是在它上面盖一层透明的捕捉层，结果连底下侧栏的点击
                // 和滚动一起吃掉了，侧栏看得见点不动。现在改成直接让它失效，
                // 再单独放一层只盖住它自己的捕捉层。
                // 下沉要够狠才看得出来是"推开了一张卡片"。
                // 上一版只缩了 10%、盖了一层几乎看不见的暗，
                // 结果推开之后跟没推一样。现在三件事一起加：
                // 缩到 84%、圆角给到 36、**页面本身压一层暗**——
                // 最后这条是关键，光靠外面的阴影是压不下去的。
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(!isOpen)
                    .overlay {
                        // 压一层暗是为了"沉下去"，不是为了把聊天页关灯。
                        // 0.34 太重了，推开之后那半边黑得很突兀。
                        Color.black.opacity(0.16 * progress)
                            .allowsHitTesting(false)
                    }
                    .compositingGroup()
                    .clipShape(RoundedRectangle(cornerRadius: 36 * progress,
                                                style: .continuous))
                    .overlay {
                        // 推开之后给它一道边，不然跟底下那层糊成一片，
                        // 看不出来是"浮"在上面的
                        RoundedRectangle(cornerRadius: 36 * progress, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28 * progress), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: Color.black.opacity(0.45 * progress),
                            radius: 30 * progress, x: -12 * progress, y: 0)
                    .shadow(color: Color.black.opacity(0.22 * progress),
                            radius: 8 * progress, x: -3 * progress, y: 0)
                    .scaleEffect(1 - 0.16 * progress, anchor: .center)
                    .offset(x: width * progress)
                    .zIndex(1)

                // 捕捉层：只盖住聊天页那一块，点一下关上，往左拖也关上。
                if progress > 0.02 {
                    // 这块盖的是被推开那张卡片，尺寸得跟着上面的缩放一起改，
                    // 不然点空白处关不掉、或者点到侧栏上反而被它吃掉
                    Color.black.opacity(0.001)
                        .frame(width: geo.size.width * (1 - 0.16 * progress),
                               height: geo.size.height * (1 - 0.16 * progress))
                        .contentShape(Rectangle())
                        .offset(x: width * progress + geo.size.width * 0.08 * progress)
                        .onTapGesture { close() }
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    if v.translation.width < 0 { drag = v.translation.width }
                                }
                                .onEnded { v in
                                    if v.translation.width < -width * 0.28
                                        || v.predictedEndTranslation.width < -width * 0.6 {
                                        close()
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            drag = 0
                                        }
                                    }
                                }
                        )
                        .zIndex(2)
                }
            }
            .background {
                // 这里**不能铺纯色**。铺了就把底下的壁纸盖死，
                // 推开之后侧栏那半边突然变成一块白板，跟聊天页接不上。
                // 只压一层很淡的暗，让壁纸照样透上来，
                // 下沉感交给聊天页那两道阴影去撑。
                if progress > 0.01 {
                    Color.black.opacity((scheme == .dark ? 0.20 : 0.06) * progress)
                        .ignoresSafeArea()
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isOpen)
        }
        // 整页铺满，上下不留白条。聊天页里那几处 padding 已经把
        // 状态栏和 home indicator 的位置让出来了。
        //
        // **只能忽略 container，不能连键盘一起忽略。**
        // 不加参数的 .ignoresSafeArea() 等于 regions: .all，键盘那块
        // 也算在内——外壳一旦把它吃掉，里面的输入框就不知道键盘弹起来了，
        // 打的字全被挡在键盘底下。这就是之前看不见自己在打什么的原因。
        .ignoresSafeArea(.container)
    }

    private func close() {
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isOpen = false
            drag = 0
        }
    }
}

extension View {
    func sideMenuShell(isOpen: Binding<Bool>,
                       onSelect: @escaping (SideMenuItem) -> Void) -> some View {
        SideMenuShell(isOpen: isOpen, onSelect: onSelect) {
            self
        }
    }
}

/// 侧栏翻到哪儿了。
///
/// 放成静态量而不是 @State，是因为她要的是这个行为：
/// **App 没被划掉就一直记着上次翻到的地方，划掉重开才回到居中。**
/// @State 会随着 View 销毁而没，@SceneStorage 又会跨启动留着，
/// 都不对；一个活在进程里的静态量正好。
@MainActor
enum SideMenuScroll {
    static var lastID: String?
}

// MARK: - 侧栏本体

/// 垫在最底下那一层的内容。它不管开合，只管长什么样。
struct SideMenuPanel: View {

    /// 侧栏是不是被拉开了。拉开的那一下，几行菜单一条条往上抬——
    /// 之前是整块硬生生亮出来，没有任何过程，像贴了张图上去。
    var isOpen: Bool = true
    var onSelect: (SideMenuItem) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    /// 现在停在哪一项上
    @State private var scrolledID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            header
                .offset(y: isOpen ? 0 : -12)
                .opacity(isOpen ? 1 : 0)
                .animation(.spring(response: 0.34, dampingFraction: 0.85), value: isOpen)

            // 菜单本体。滚起来是**半个转盘**的样子：
            // 越靠近竖直中线的那几项越大、越实、越往右探；
            // 上下两头缩小、变淡、往左收回去，像绕着一根轴转过去了。
            //
            // 做法是 .visualEffect ——它只改画出来的样子，不参与排版，
            // 所以每一帧跟着滚动位置重算也不会把布局搅乱。
            GeometryReader { geo in
                let mid = geo.size.height / 2

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(SideMenuItem.all.enumerated()), id: \.element.id) { i, item in
                            row(item)
                                .id(item.id)
                                .visualEffect { content, proxy in
                                    // 这一行的中心离竖直中线有多远，0 是正中，1 是到边
                                    let y = proxy.frame(in: .named("wheel")).midY
                                    let d = min(1, abs(y - mid) / mid)
                                    return content
                                        .scaleEffect(1 - d * 0.30, anchor: .leading)
                                        // 往左收一点点就行。收太多整栏都贴在屏幕边上，
                                        // 右边空一大片，看着像没排满。
                                        .offset(x: -d * d * 16)
                                        .opacity(1 - d * 0.68)
                                        .blur(radius: d * d * 1.8)
                                }
                                // 拉开侧栏的那一下，一行比一行晚一点点抬上来
                                .offset(y: isOpen ? 0 : 26)
                                .opacity(isOpen ? 1 : 0)
                                .animation(
                                    .spring(response: 0.42, dampingFraction: 0.82)
                                        .delay(isOpen ? Double(i) * 0.03 : 0),
                                    value: isOpen)
                        }
                    }
                    // 整栏往右让开一截，别贴着屏幕边
                    .padding(.leading, 44)
                    .padding(.trailing, 10)
                    .scrollTargetLayout()
                }
                .coordinateSpace(name: "wheel")
                // 上下各留半屏的余量，最上和最下那一项也能转到正中间来。
                //
                // 上一版为了"不留空白"把内容高度钉死成正好一屏
                // （minHeight: geo.size.height），结果内容跟容器一样高，
                // ScrollView 认为没有可滚的东西，整栏就滚不动了。
                .contentMargins(.vertical, geo.size.height * 0.34, for: .scrollContent)
                .scrollPosition(id: $scrolledID, anchor: .center)
                .onAppear {
                    // 第一次打开落在正中间那一项；之后停在上次翻到的地方。
                    // 位置记在一个静态量里——App 还活着就一直在，
                    // 被划掉重开才回到居中。
                    if SideMenuScroll.lastID == nil {
                        SideMenuScroll.lastID =
                            SideMenuItem.all[SideMenuItem.all.count / 2].id
                    }
                    scrolledID = SideMenuScroll.lastID
                }
                .onChange(of: scrolledID) { _, id in
                    if let id { SideMenuScroll.lastID = id }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 44)
    }

    // MARK: 顶上那一块

    /// 名字、在一起多少天、今天几号，全挪到最上面来。
    /// 原来「在一起第 N 天」挂在最底下，那是整栏最不容易看见的位置。
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            HStack(spacing: 6) {
                Text("在一起第 \(daysTogether) 天")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSoft(scheme))
                Circle()
                    .fill(Theme.textMuted(scheme).opacity(0.5))
                    .frame(width: 3, height: 3)
                Text(Self.today.string(from: Date()))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .padding(.leading, 44)
        .padding(.trailing, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var daysTogether: Int {
        let from = Calendar.current.startOfDay(for: app.settings.togetherSince)
        let to = Calendar.current.startOfDay(for: Date())
        let d = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
        return max(1, d + 1)
    }

    nonisolated(unsafe) static let today: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f
    }()

    // MARK: 一行

    private func row(_ item: SideMenuItem) -> some View {
        Button {
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onSelect(item)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .frame(width: 24)
                Text(item.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(SideMenuRowStyle())
    }
}

/// 按下去轻轻陷一下
struct SideMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 菜单项

struct SideMenuItem: Identifiable, Hashable {
    var id: String
    var title: String
    var icon: String

    static let all: [SideMenuItem] = [
        .init(id: "sticker",   title: "相册", icon: Icon.gallery),
        .init(id: "favorite",  title: "收藏", icon: Icon.star),
        .init(id: "games",     title: "游戏", icon: Icon.games),
        .init(id: "thoughts",  title: "念头池", icon: "drop"),
        .init(id: "call",      title: "通话", icon: "phone"),
        .init(id: "fortune",   title: "占卜", icon: "sparkles"),
        .init(id: "clawd",     title: "clawd", icon: "pawprint"),
        .init(id: "phone",     title: "手机", icon: "iphone"),
        .init(id: "music",     title: "音乐", icon: "music.note"),
        .init(id: "pixel",     title: "像素", icon: Icon.sticker),
        .init(id: "clawdart",  title: "表情工坊", icon: "paintbrush.pointed"),
        .init(id: "library",   title: "书房", icon: Icon.diary),
        .init(id: "memo",      title: "备忘", icon: Icon.notes),
        .init(id: "promise",   title: "承诺", icon: "hand.raised"),
        .init(id: "mood",      title: "心情", icon: Icon.heart),
        .init(id: "hobby",     title: "爱好", icon: "heart.text.square"),
        .init(id: "footprint", title: "足迹", icon: Icon.footprint)
    ]
}
