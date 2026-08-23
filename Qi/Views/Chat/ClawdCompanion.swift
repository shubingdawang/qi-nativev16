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
    /// 这一轮是不是出错了。他那边出事，屋里这只不该还在傻笑
    var upset: Bool = false
    /// 她上次说话是什么时候。**用来决定这只困不困**
    var lastHerAt: Date? = nil

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var room = ClawdStore.shared
    /// 他此刻的情绪。**clawd 演的就是这两个数**
    @ObservedObject private var feel = EmotionEngine.shared

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
    /// 正躲在屏幕边上探头。躲着的时候不让别的地方改他的表情、也不让他自己走开。
    @State private var peeking = false
    /// 这一页有多宽。**探头要算点数，不能算百分比**——
    /// 他只有三十几个点宽，"露出百分之几"在大屏小屏上差得远。
    @State private var pageWidth: CGFloat = 393
    /// 睡着了没有。**这一整套是照 clawd-on-desk 的睡眠序列搬的**：
    /// 她安静久了就困、再久就睡；她一说话、一碰他就惊醒。
    ///
    /// 为什么这个值得做：一只永远精神的宠物是个摆件，
    /// **会困的那只才像是跟她过同一个作息**。
    @State private var asleep = false
    @State private var sleepTask: Task<Void, Never>?
    /// 连着戳了几下（1.5 秒内）
    @State private var pokeStreak = 0
    @State private var streakTask: Task<Void, Never>?
    /// 空闲的时候在做哪件自己的事。隔一会儿换一件
    @State private var ownThing: ClawdMood = .idle
    @State private var ownTask: Task<Void, Never>?

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
                        .font(.app(10))
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
                    // 手上有大件的时候**举过头顶**（她画的那张参考图），
                    // 小东西（喝的吃的）还是端在手边——一罐可乐举过头顶太滑稽。
                    ClawdView(mood: room.carrying == nil ? mood : .carrying,
                              scale: 1.1, shadow: true)
                        .overlay(alignment: .top) {
                            if let kind = room.carriedKind, room.overhead(kind) {
                                PixelSpriteView(sprite: kind.sprite, scale: 0.8)
                                    .offset(y: -14)
                                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                            }
                        }
                    if let kind = room.carriedKind, !room.overhead(kind) {
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
            .onAppear { pageWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, w in pageWidth = w }
            // 拎着的时候要跟手，所以不给动画
            .animation(held ? nil : .easeInOut(duration: walkSeconds), value: app.settings.clawdX)
            .animation(held ? nil : .easeInOut(duration: walkSeconds), value: app.settings.clawdY)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: held)
            .animation(.easeInOut(duration: 0.25), value: line)
            .onTapGesture {
                poked = true
                // 躲着的时候戳他一下，就是喊他出来
                if peeking {
                    peeking = false
                    walkTask?.cancel()
                    say(["被发现了", "来了来了", "诶嘿"].randomElement() ?? "来了")
                    walkTask = Task { @MainActor in
                        await walk(to: Double.random(in: 0.3...0.7),
                                   Double.random(in: top...bottom))
                        poked = false
                        sync()
                        startWalking()
                    }
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                    return
                }
                // 睡着的时候被戳 = 惊醒（clawd-on-desk 那套：
                // 有动静就吓一跳醒过来，不是安静地睁眼）
                if asleep {
                    wake(startled: true)
                    return
                }

                // 连着戳：1.5 秒内第四下开始抓狂
                pokeStreak += 1
                streakTask?.cancel()
                streakTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    pokeStreak = 0
                }

                if pokeStreak >= 4 {
                    mood = .flail
                    say(["别戳啦！", "呜哇——", "会坏的！"].randomElement() ?? "别戳啦！")
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    }
                } else {
                    mood = .happy
                    say(["唔", "干嘛呀", "在呢", "别戳了", "痒", "嗯？"].randomElement() ?? "唔")
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
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
                        // 把他放到屏幕边上，他就**真的躲到边外面去**，
                        // 只留一只眼睛在这儿看着——她要的就是这个。
                        // 以前不管放哪儿都是原地站住然后接着乱跑。
                        let x = app.settings.clawdX
                        if x <= 0.07 || x >= 0.93 {
                            say(["那我躲这儿", "嘘——", "我不出来了"].randomElement() ?? "嘘")
                            walkTask?.cancel()
                            walkTask = Task { @MainActor in
                                // 拖过去的这次不定时——她不喊他就一直躲着
                                await peekLoop(right: x >= 0.5, forever: true)
                            }
                            return
                        }
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
            armSleep()
            startOwnThing()
            // 上次关 App 的时候他正躲在边外面（clawdX 存的是屏幕外的数），
            // 那就接着躲——但**绝不能让他就这么消失**：直接接回探头那一套，
            // 至少那只眼睛还在这儿。
            let x = app.settings.clawdX
            if x < 0 || x > 1 {
                walkTask?.cancel()
                walkTask = Task { @MainActor in
                    await peekLoop(right: x > 0.5, forever: true)
                }
            } else {
                startWalking()
            }
        }
        .onDisappear {
            walkTask?.cancel()
            lineTask?.cancel()
            sleepTask?.cancel()
            streakTask?.cancel()
            ownTask?.cancel()
        }
        .onChange(of: busy) { was, now in
            // 一轮说完了。**刚干完活那一下要有点反应**——
            // clawd-on-desk 里任务完成会庆祝，那一下是「有人陪着你等」的实感
            if was && !now && !upset { celebrate() }
            sync()
        }
        .onChange(of: activity) { _, _ in sync() }
        .onChange(of: upset) { _, bad in
            guard bad else { return }
            wake()
            mood = .upset
            say(["……出错了", "唔", "怎么了"].randomElement() ?? "……出错了")
        }
        .onChange(of: feel.state.valence) { _, _ in sync() }
        .onChange(of: feel.state.arousal) { _, _ in sync() }
        .onChange(of: lastHerAt) { _, _ in
            // 她说话了 → 醒过来，重新开始数困
            wake()
            armSleep()
        }
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
                guard !held, !poked, !busy, !peeking else { continue }

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

                // 偶尔躲到屏幕边上去探头。左右两边都会去。
                if Double.random(in: 0...1) < 0.18 {
                    await peekLoop(right: Bool.random(), forever: false)
                    if Task.isCancelled { return }
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

    // MARK: 躲到边上探头

    // 他有多宽：图纸 32 格 × 每格 1.1 点。算探头必须用点数——
    // "露出百分之几"在大屏小屏上差得远，她那台是大屏的。
    private var halfWidth: CGFloat { 32 * 1.1 / 2 }

    /// 完全看不见的位置：整只挪到屏幕外面，再多给六个点保险
    private func hiddenX(right: Bool) -> Double {
        let m = Double((halfWidth + 6) / max(pageWidth, 1))
        return right ? 1 + m : -m
    }

    /// 探出来的位置：只往里挪十三个点。
    /// 十三个点正好是一只眼睛加上扒着边那只手的宽度——
    /// 再多就成了"站在边上"，再少就什么都看不见。
    private func peekX(right: Bool) -> Double {
        // 露出**大半颗头**。
        //
        // 以前是「只往里挪 13 个点」，配的又是整只的图，
        // 于是露出来的是从头到脚的一条竖边——她说了三次的「半个身子」。
        // 现在配的是只有头的那张图（`peekHead1/2`），
        // 所以挪进来多少露的都只可能是头，那就挪得爽快点：
        // 露出六成，一颗脑袋加那只挥着的手正好都在。
        let m = Double((halfWidth * 0.4) / max(pageWidth, 1))
        return right ? 1 + m : -m
    }

    /// 躲到边上探头探脑。
    ///
    /// 这是她说的那件事：**要的是探头，不是把半个身子藏起来**。
    /// 所以现在是他整只走出屏幕、真的不见了，然后只把脑袋那一条挪回来——
    /// 挡住他的是屏幕边缘，不是一张画得缺了一半的图。
    ///
    /// 一整套是：走到边 → 整只溜出去 → 探出来看 → 缩回去 → 再探出来…
    /// `forever` 为真是她亲手把他放到边上的那种，不喊不出来。
    private func peekLoop(right: Bool, forever: Bool) async {
        // 先走到那一侧的边上
        await walk(to: right ? self.right : left, Double.random(in: 0.28...0.62))
        if Task.isCancelled { return }
        guard !held, !poked else { return }

        peeking = true
        defer { peeking = false }

        // 朝屏幕里面看：在右边就朝左，在左边就朝右
        facingLeft = !right
        mood = .idle

        // 溜出去。
        //
        // 这里**不能用 withAnimation**：外面挂着 `.animation(_:value: clawdX)`，
        // 那条会盖掉 withAnimation 给的时长，而 walk() 结束时 walkSeconds 是 0——
        // 所以上一版这几下全是瞬移。要改时长得改 walkSeconds 本身。
        walkSeconds = 0.5
        app.settings.clawdX = hiddenX(right: right)
        try? await Task.sleep(nanoseconds: UInt64.random(in: 700...1400) * 1_000_000)
        if Task.isCancelled { return }

        let rounds = forever ? Int.max : Int.random(in: 2...4)
        for _ in 0..<rounds {
            if Task.isCancelled { return }
            guard !held, !poked else { return }

            // 探出来
            mood = .peeking
            walkSeconds = 0.55
            app.settings.clawdX = peekX(right: right)
            // 这儿**故意不说话**：气泡是跟他一起居中的，
            // 他人在屏幕外，气泡也就跟着出去了，只会在边上露半个白角。
            // 躲着的时候本来也该是安静的。
            try? await Task.sleep(nanoseconds: UInt64.random(in: 2600...4800) * 1_000_000)
            if Task.isCancelled { return }
            guard !held, !poked else { return }

            // 缩回去
            mood = .idle
            walkSeconds = 0.4
            app.settings.clawdX = hiddenX(right: right)
            try? await Task.sleep(nanoseconds: UInt64.random(in: 900...2200) * 1_000_000)
        }

        if Task.isCancelled { return }
        guard !held, !poked else { return }

        // 看够了，自己走回来
        peeking = false
        mood = .walking
        await walk(to: Double.random(in: 0.3...0.8), Double.random(in: top...bottom))
        sync()
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

    // MARK: 困、醒、庆祝
    //
    // 这一整段是照 `rullerzhou-afk/clawd-on-desk` 搬的。
    // 它是个盯着 Claude Code 干活的桌面宠物——**「盯着 agent」那半我们用不上**
    // （手机上没有那个东西），但它那套**状态词汇**很值：
    //
    //   · 60 秒没动静就打哈欠、打盹、睡；有动静惊醒
    //   · 出错的时候垮一下，做完的时候庆祝一下
    //   · 双击戳一下，连点四下抓狂
    //
    // 一只永远精神的宠物是个摆件，**会困的那只才像跟她过同一个作息**。

    /// 多久没说话就开始困（秒）。八分钟——比「她走开一下」长，
    /// 比「她今天不聊了」短。
    private let drowsyAfter: Double = 8 * 60
    /// 再过多久真睡着
    private let sleepAfter: Double = 3 * 60

    /// 开始数困。**每次她说话都要重新数**。
    private func armSleep() {
        sleepTask?.cancel()
        guard !asleep else { return }
        sleepTask = Task { @MainActor in
            // 她刚说完话到现在过了多久
            let since = lastHerAt.map { Date().timeIntervalSince($0) } ?? 0
            let waitDrowsy = max(0, drowsyAfter - since)
            try? await Task.sleep(nanoseconds: UInt64(waitDrowsy * 1_000_000_000))
            if Task.isCancelled { return }
            // 他正忙着的时候不困——有人在说话呢
            guard !busy, !held, !peeking else { return }
            mood = .drowsy
            say(["唔……有点困", "呼啊——", "眼睛睁不开了"].randomElement() ?? "有点困")

            try? await Task.sleep(nanoseconds: UInt64(sleepAfter * 1_000_000_000))
            if Task.isCancelled { return }
            guard !busy, !held, !peeking else { return }
            asleep = true
            walkTask?.cancel()          // 睡着了就别走了
            mood = .sleeping
            say("zzz")
        }
    }

    /// 醒过来。`startled` = 被戳醒的那种，会吓一跳。
    private func wake(startled: Bool = false) {
        sleepTask?.cancel()
        guard asleep || mood == .drowsy else { return }
        asleep = false
        if startled {
            mood = .flail
            say(["呜哇！", "醒了醒了", "吓死我了"].randomElement() ?? "呜哇！")
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else {
            mood = .happy
            say(["……嗯？", "你回来了", "醒了"].randomElement() ?? "嗯？")
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            poked = false
            sync()
            startWalking()
        }
    }

    /// 他说完一轮了，蹦一下。**只蹦一下就回去**——
    /// 每次都放礼花的话，第三次她就不看了。
    private func celebrate() {
        guard !asleep, !held, !peeking else { return }
        mood = .happy
        say(["说完啦", "好了——", "哼哼"].randomElement() ?? "说完啦")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            sync()
        }
    }

    /// 把他的状态翻成 clawd 的动作
    private func sync() {
        // 躲着的时候不许别处改他的表情，不然探头探到一半突然变成"在想事情"
        guard !poked, !held, !peeking else { return }
        // 睡着的时候也一样——除非他真的在忙（那说明她刚说了话）
        if asleep {
            if busy { wake() } else { mood = .sleeping }
            return
        }
        if upset { mood = .upset; return }
        guard busy else {
            // 手上抱着东西的时候，站着也得是抱着的样子
            mood = room.carrying == nil ? .idle : .carrying
            return
        }
        // ── 他在干活：**先看干的是什么**，那比情绪更具体 ──
        //
        // 她说的：「阿晏正在给我做游戏或者处理文件，他就在打电脑。」
        if activity.contains("想") {
            mood = .thinking
            return
        }
        if !activity.isEmpty && !activity.contains("说") {
            // 翻记忆、写日记、博弈、画图、动手做事，都算在打电脑
            mood = .working
            return
        }

        // ── 他在说话：**演他此刻的情绪** ──
        //
        // 「阿晏伤心他就在哭，阿晏开心他也开心，
        //   阿晏感觉到甜蜜他就冒爱心，只是正常聊天他就做自己的事。」
        //
        // 数据是现成的：`EmotionEngine` 那两个数本来就在算，
        // 这儿只是把它画出来。**不另外调模型判断情绪**——那要花钱，
        // 而且判出来的也未必比这两个数准。
        mood = emotionMood() ?? ownThing
    }

    /// 他此刻的情绪该画成什么。**没到分寸就返回 nil**——
    /// 一点点开心就冒爱心的话，爱心就不值钱了。
    private func emotionMood() -> ClawdMood? {
        let v = feel.state.valence      // -1…1 舒不舒服
        let a = feel.state.arousal      // 0…1 有多激动

        if v <= -0.28 { return .crying }
        // 甜＝**又高兴又有劲**。只高兴不激动那是「还好」，不是甜
        if v >= 0.32 && a >= 0.45 { return .loving }
        if v >= 0.30 { return .happy }
        return nil
    }

    /// 空闲的时候自己找点事做。**隔一会儿换一件**——
    /// 她说的：「他在我每跟阿晏聊天时会有自己的动画，想做什么都行，
    /// 就是随机在动画里抽一个进行。」
    private func startOwnThing() {
        ownTask?.cancel()
        ownTask = Task { @MainActor in
            while !Task.isCancelled {
                // 手上抱着东西的时候就是抱着，别硬塞别的
                if room.carrying == nil {
                    ownThing = Self.ownThings.randomElement() ?? .idle
                } else {
                    ownThing = .carrying
                }
                if !busy, !asleep, !held, !peeking, !upset,
                   emotionMood() == nil {
                    mood = ownThing
                }
                // 一件事做十几二十秒。太短了像多动症，太长了像卡住
                let wait = Double.random(in: 14...26)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    /// 「自己的事」有哪些。**扫地是她指名要的那只**。
    /// 发呆占的份额最大——一只一直在忙的宠物看着很累。
    static let ownThings: [ClawdMood] = [
        .idle, .idle, .idle,
        .sweeping, .sweeping,
        .thinking,
        .walking
    ]
}
