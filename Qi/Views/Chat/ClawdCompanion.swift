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
    @ObservedObject private var room = ClawdStore.shared

    @State private var mood: ClawdMood = .idle
    @State private var poked = false
    @State private var held = false
    @State private var facingLeft = false
    @State private var walkSeconds: Double = 2.6
    @State private var walkTask: Task<Void, Never>?
    @State private var line: String?
    @State private var lineTask: Task<Void, Never>?
    /// 喝东西时罐子抬起来多高
    @State private var sipLift: CGFloat = 0
    /// 手上这件是不是他自己掏出来的。
    /// 是的话喝完会自己收起来；她塞给他的（在小屋搬起来的）就一直拿着。
    @State private var tookOutMyself = false

    /// 能走的范围。上面留给顶栏那条，下面留给输入框，
    /// 走进去就被盖住了，白走。
    private let top: Double = 0.16
    private let bottom: Double = 0.74
    // 左右放到 0.02 / 0.98：她要能把他直接拖到屏幕边上去。
    // 原来卡在 0.10/0.90，怎么拖都差一截，看着像拖不动。
    private let left: Double = 0.02
    private let right: Double = 0.98

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

                // 手上那件东西。举在身子旁边，跟着一起走。
                // 它读的是 ClawdStore.carrying——**小屋和聊天页共用同一个**，
                // 所以在小屋搬起箱子，切过来这边他手上也抱着。
                HStack(alignment: .bottom, spacing: 1) {
                    ClawdView(mood: mood, scale: 1.1, shadow: true)
                    if let kind = room.carriedKind {
                        PixelSpriteView(sprite: kind.sprite, scale: 1.0)
                            // sipLift 是喝的时候把罐子举到嘴边那一下。
                            // 平时是 0，喝的时候抬起来、往身子里侧靠一点。
                            .offset(x: sipLift == 0 ? 0 : -7, y: -6 - sipLift)
                            .rotationEffect(.degrees(sipLift == 0 ? 0 : -22),
                                            anchor: .bottomLeading)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                    .scaleEffect(held ? 1.2 : 1)
                    .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
                    .shadow(color: .black.opacity(held ? 0.26 : 0), radius: 10, y: 8)
                    // 这一条是长按拖不动的根源：PixelSpriteView 里那块 Canvas
                    // 自己写着 allowsHitTesting(false)，所以它整个不接触摸，
                    // 外面挂多少手势都落不到实处。补一块实心的感应区上去，
                    // 顺便放大一圈——它只有三十几个点宽，按准太难了。
                    .contentShape(Rectangle().inset(by: -14))
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
            // 用 highPriority：聊天页整页还挂着一个拉侧栏的拖拽手势，
            // 普通 gesture 会被它压住
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.28)
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

                // 自己去掏点东西出来喝。
                //
                // 只掏**她真的买过**的（ClawdStore.owned），而且只掏吃的喝的——
                // 抱着书架满屏跑不像话。掏出来之后边走边喝几口，喝完自己收起来。
                //
                // 她在小屋里塞给他的那件不走这条路：tookOutMyself 记着这件是不是
                // 他自己拿的，只有自己拿的才会自己收。她给的他就一直拿着。
                if room.carrying == nil, Double.random(in: 0...1) < 0.24,
                   let pick = snackOnHand() {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        room.pickUp(pick.id)
                    }
                    tookOutMyself = true
                    mood = .carrying
                    say(takeOutLine(pick))
                    try? await Task.sleep(nanoseconds: 1_200_000_000)

                    // 边走边喝：走一段、喝一口，来回两三趟
                    for _ in 0..<Int.random(in: 2...3) {
                        if Task.isCancelled { return }
                        guard !held, !poked else { break }
                        await walk(to: Double.random(in: left...right),
                                   Double.random(in: top...bottom))
                        if Task.isCancelled { return }
                        guard !held, !poked else { break }
                        await sip()
                    }

                    // 喝完收起来
                    if tookOutMyself, !held {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            room.carrying = nil
                        }
                        tookOutMyself = false
                        say(finishLine(pick))
                    }
                    sync()
                    continue
                }

                // 偶尔躲到屏幕边上去探头。
                //
                // 以前是直接瞬移到 0.97 然后换成 peek 帧——半个身子在屏幕外，
                // 看着像被裁掉了，不像在探头。现在改成有来有回：
                // 先走到边上 → 整只缩出去（藏起来）→ 停一会儿 →
                // **慢慢探出来一点点**，露出半边身子和一只眼 → 看够了再走回来。
                if Double.random(in: 0...1) < 0.18 {
                    await walk(to: right, Double.random(in: 0.3...0.6))
                    if Task.isCancelled { return }
                    guard !held, !poked else { continue }

                    // 缩出去。1.06 是完全看不见的位置。
                    facingLeft = false
                    mood = .idle
                    withAnimation(.easeIn(duration: 0.5)) {
                        app.settings.clawdX = 1.06
                    }
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    if Task.isCancelled { return }

                    // 探头：只探出一点点，配 peek 那半边身子的帧
                    mood = .peeking
                    withAnimation(.easeOut(duration: 0.7)) {
                        app.settings.clawdX = 0.965
                    }
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 6...14) * 1_000_000_000)
                    if Task.isCancelled { return }
                    guard !held, !poked else { continue }

                    // 看够了，走回来
                    mood = .walking
                    await walk(to: Double.random(in: 0.3...0.8), Double.random(in: top...bottom))
                    sync()
                    continue
                }

                let tx = Double.random(in: left...right)
                let ty = Double.random(in: top...bottom)
                await walk(to: tx, ty)
                if Task.isCancelled { return }
                sync()
            }
        }
    }

    /// 真的走过去，一步一步。
    ///
    /// 以前是一个 easeInOut 把位置从 A 插值到 B——身子平移过去，
    /// 腿一动不动，看着就是"翻个身然后瞬移"。
    /// 现在拆成很多小步：每步只挪一点点，配合 walk1/walk2 两帧换脚，
    /// 再加一个上下一像素的颠簸。距离越远步数越多，走得就越久。
    private func walk(to tx: Double, _ ty: Double) async {
        let fromX = app.settings.clawdX
        let fromY = app.settings.clawdY
        let dx = tx - fromX
        let dy = ty - fromY
        let dist = (dx * dx + dy * dy).squareRoot()

        facingLeft = dx < 0
        // 一步走屏幕的 2.5%，最少 6 步最多 40 步
        let steps = max(6, min(40, Int(dist / 0.025)))
        // 每步之间不给动画，靠步数本身做出连续感——
        // 给了动画反而会跟下一步的动画打架，走出橡皮筋效果
        walkSeconds = 0

        mood = room.carrying == nil ? .walking : .hauling

        for i in 1...steps {
            if Task.isCancelled { return }
            if held || poked { return }
            let t = Double(i) / Double(steps)
            // 起步和收步稍微慢一点，中间快——真人走路就是这样
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            app.settings.clawdX = fromX + dx * eased
            // 每一步上下颠一点点，走路的那个起伏
            let bob = (i % 2 == 0 ? 0.0 : -0.004)
            app.settings.clawdY = fromY + dy * eased + bob
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        app.settings.clawdY = ty
    }

    // MARK: 掏东西吃喝

    /// 她买过的、能拿着走的吃喝里随便挑一样。没买过就返回 nil，他就不掏。
    private func snackOnHand() -> FurnitureKind? {
        room.owned
            .filter { !$0.hidden }
            .compactMap { FurnitureCatalog.kind($0.kind) }
            .filter { $0.category == .drink || $0.category == .food }
            .randomElement()
    }

    /// 喝一口：罐子抬到嘴边，停一下，放下来。
    /// 抬起的时候顺手把表情换成眯眼的那帧，看着像在享受。
    private func sip() async {
        let before = mood
        withAnimation(.easeOut(duration: 0.35)) { sipLift = 9 }
        mood = .happy
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeIn(duration: 0.3)) { sipLift = 0 }
        mood = before == .happy ? .carrying : before
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    private func takeOutLine(_ k: FurnitureKind) -> String {
        let drink = k.category == .drink
        return (drink
            ? ["渴了", "喝口\(k.name)", "开一罐", "润润嗓子"]
            : ["饿了", "吃点\(k.name)", "垫一口"]).randomElement() ?? "渴了"
    }

    private func finishLine(_ k: FurnitureKind) -> String {
        let drink = k.category == .drink
        return (drink
            ? ["喝完了", "舒服", "嗝——", "解渴"]
            : ["吃完了", "饱了", "好吃"]).randomElement() ?? "喝完了"
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
            // 手上抱着东西的时候，站着也得是抱着的样子
            mood = room.carrying == nil ? .idle : .carrying
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
