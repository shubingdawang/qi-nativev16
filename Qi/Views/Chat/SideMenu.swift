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
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(!isOpen)
                    .compositingGroup()
                    .clipShape(RoundedRectangle(cornerRadius: 30 * progress,
                                                style: .continuous))
                    .overlay {
                        // 推开之后给它一道边，不然跟底下那层糊成一片，
                        // 看不出来是"浮"在上面的
                        RoundedRectangle(cornerRadius: 30 * progress, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5 * progress), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: Color.black.opacity(0.30 * progress),
                            radius: 24 * progress, x: -10 * progress, y: 0)
                    .shadow(color: Color.black.opacity(0.16 * progress),
                            radius: 6 * progress, x: -2 * progress, y: 0)
                    .scaleEffect(1 - 0.10 * progress, anchor: .center)
                    .offset(x: width * progress)
                    .zIndex(1)

                // 捕捉层：只盖住聊天页那一块，点一下关上，往左拖也关上。
                if progress > 0.02 {
                    Color.black.opacity(0.001)
                        .frame(width: geo.size.width * (1 - 0.10 * progress),
                               height: geo.size.height * (1 - 0.10 * progress))
                        .contentShape(Rectangle())
                        .offset(x: width * progress + geo.size.width * 0.05 * progress)
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

// MARK: - 侧栏本体

/// 垫在最底下那一层的内容。它不管开合，只管长什么样。
struct SideMenuPanel: View {

    /// 侧栏是不是被拉开了。拉开的那一下，几行菜单一条条往上抬——
    /// 之前是整块硬生生亮出来，没有任何过程，像贴了张图上去。
    var isOpen: Bool = true
    var onSelect: (SideMenuItem) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            VStack(alignment: .leading, spacing: 3) {
                Text(app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("在这里")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .offset(y: isOpen ? 0 : -10)
            .opacity(isOpen ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.85), value: isOpen)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(SideMenuItem.all.enumerated()), id: \.element.id) { i, item in
                        row(item)
                            // 一行比一行晚一点点出来，从下往上抬。
                            // 每格 25 毫秒，十四行加起来也就三分之一秒，
                            // 快到不觉得在等，但眼睛看得出是"滑进来"的。
                            .offset(y: isOpen ? 0 : 22)
                            .opacity(isOpen ? 1 : 0)
                            .animation(
                                .spring(response: 0.38, dampingFraction: 0.86)
                                    .delay(isOpen ? Double(i) * 0.025 : 0),
                                value: isOpen)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            // 底下原来空着一大片。搁一句在一起多少天，
            // 顺手把那块空白填上——比留一整块空更像个"地方"。
            footer
                .opacity(isOpen ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(isOpen ? 0.24 : 0), value: isOpen)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 44)
    }

    // MARK: 底下那一小块

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("在一起第 \(daysTogether) 天")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            Text(Self.today.string(from: Date()))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity * 0.8)
        .padding(.horizontal, 12)
        .padding(.bottom, 40)
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
        .init(id: "library",   title: "书房", icon: Icon.diary),
        .init(id: "memo",      title: "备忘", icon: Icon.notes),
        .init(id: "mood",      title: "心情", icon: Icon.heart),
        .init(id: "footprint", title: "足迹", icon: Icon.footprint)
    ]
}
