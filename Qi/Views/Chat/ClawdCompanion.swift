import SwiftUI

/// 在聊天页上溜达的那只 clawd。
///
/// **它不接模型，一分钱不花。** 它只是看着阿晏在干嘛，然后做对应的动作：
/// 他在想 → 头顶冒小方块；他在调工具 → 埋头干活；他在说话 → 笑；
/// 都没在忙 → 站着呼吸、偶尔眨眼。
///
/// 以前它是钉在输入框正上方的一格，只能待在那儿。现在整页都是它的地盘：
/// 自己走来走去，长按能拎起来放到任意位置，放下继续走。
/// 位置记在设置里，关掉 App 再进来它还在原地。
struct ClawdRoamer: View {

    /// 他现在在干嘛，由外面传进来
    var busy: Bool = false
    var activity: String = ""

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var mood: ClawdMood = .idle
    @State private var poked = false
    @State private var held = false
    @State private var facingLeft = false
    @State private var walkSeconds: Double = 2.6
    @State private var walkTask: Task<Void, Never>?
    @State private var line: String?
    @State private var lineTask: Task<Void, Never>?

    /// 能走的范围。上面留给顶栏那条，下面留给输入框，
    /// 走进去就被盖住了，白走。
    private let top: Double = 0.16
    private let bottom: Double = 0.74
    private let left: Double = 0.10
    private let right: Double = 0.90

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .center, spacing: 3) {
                if let line, !line.isEmpty {
                    Text(line)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(scheme == .dark
                                      ? Color.white.opacity(0.16)
                                      : Color.white.opacity(0.90))
                        )
                        .fixedSize()
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                ClawdView(mood: mood, scale: 1.1, shadow: true)
                    .scaleEffect(held ? 1.2 : 1)
                    .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
                    .shadow(color: .black.opacity(held ? 0.26 : 0), radius: 10, y: 8)
            }
            .position(x: app.settings.clawdX * geo.size.width,
                      y: app.settings.clawdY * geo.size.height)
            // 拎着的时候要跟手，所以不给动画
            .animation(held ? nil : .easeInOut(duration: walkSeconds), value: app.settings.clawdX)
            .animation(held ? nil : .easeInOut(duration: walkSeconds), value: app.settings.clawdY)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: held)
            .animation(.easeInOut(duration: 0.25), value: line)
            .onTapGesture {
                poked = true
                mood = .happy
                say(["唔", "干嘛呀", "在呢", "别戳了", "痒", "嗯？"].randomElement() ?? "唔")
                if app.settings.haptics {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    poked = false
                    sync()
                }
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        held = true
                        walkTask?.cancel()
                        mood = .happy
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        say(["诶——", "放我下来", "飞起来了"].randomElement() ?? "诶")
                    }
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        if case .second(_, let drag?) = value {
                            app.settings.clawdX = min(right, max(left, drag.location.x / geo.size.width))
                            app.settings.clawdY = min(bottom, max(top, drag.location.y / geo.size.height))
                        }
                    }
                    .onEnded { _ in
                        guard held else { return }
                        held = false
                        say(["就这儿吧", "好", "这儿也行"].randomElement() ?? "好")
                        sync()
                        startWalking()
                    }
            )
        }
        // 整层不接触摸，只有它自己那一小块接——
        // 不然它会把底下的气泡、按钮全挡住
        .allowsHitTesting(true)
        .onAppear {
            sync()
            startWalking()
        }
        .onDisappear {
            walkTask?.cancel()
            lineTask?.cancel()
        }
        .onChange(of: busy) { _, _ in sync() }
        .onChange(of: activity) { _, _ in sync() }
    }

    // MARK: 自己走

    /// 隔一会儿自己挪个位置。他在忙的时候不走——
    /// 正在想事情、正在干活的那只应该杵在那儿，不是满屏乱跑。
    private func startWalking() {
        walkTask?.cancel()
        walkTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 8...18) * 1_000_000_000)
                if Task.isCancelled { return }
                guard !held, !poked, !busy else { continue }

                let tx = Double.random(in: left...right)
                let ty = Double.random(in: top...bottom)
                let dx = tx - app.settings.clawdX
                let dy = ty - app.settings.clawdY
                let dist = (dx * dx + dy * dy).squareRoot()

                facingLeft = dx < 0
                walkSeconds = 1.8 + dist * 3.0
                mood = .working              // 走路那几帧腿在倒腾
                app.settings.clawdX = tx
                app.settings.clawdY = ty

                try? await Task.sleep(nanoseconds: UInt64(walkSeconds * 1_000_000_000))
                if Task.isCancelled { return }
                sync()
            }
        }
    }

    private func say(_ text: String) {
        lineTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { line = text }
        lineTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) { line = nil }
        }
    }

    /// 把他的状态翻成 clawd 的动作
    private func sync() {
        guard !poked, !held else { return }
        guard busy else {
            mood = .idle
            return
        }
        // 活动那句话里带什么词，就做什么动作
        if activity.contains("想") {
            mood = .thinking
        } else if activity.contains("说") {
            mood = .talking
        } else if activity.isEmpty {
            mood = .thinking
        } else {
            // 翻记忆、写日记、博弈、动手做事，都算在干活
            mood = .working
        }
    }
}
