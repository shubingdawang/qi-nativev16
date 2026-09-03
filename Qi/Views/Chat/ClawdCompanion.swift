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
    /// 这一档是什么时候开始演的（配 `ClawdMood.hold` 用）
    @State private var moodAt = Date()
    /// 排队等着的下一个动作。**当前这个演完才轮到它。**
    @State private var pending: ClawdMood?
    /// 到点叫号的那个闹钟（见 `settleMood`）
    @State private var pendTask: Task<Void, Never>?
    @State private var poked = false
    @State private var held = false
    @State private var facingLeft = false
    @State private var walkSeconds: Double = 2.6
    @State private var walkTask: Task<Void, Never>?

    /// 他此刻站在哪儿（屏幕比例）。
    ///
    /// ⚠️ **走路的每一步写这个，不写 `app.settings`。**
    /// `settings` 是 `AppState` 上的 `@Published`，
    /// 改一次全 App 重新求值一遍；而走一趟要改八十次。
    /// 她说的「没回话的时候也卡」就是这儿——clawd 恰恰是
    /// 安静的时候才起来走。
    ///
    /// 全局那两个只在**停下来**的时候写一次，
    /// 它是「关了 App 再打开他还站在原地」用的；
    /// 走路中间那四十个位置一个都不用记。
    @State private var liveX: Double = .nan
    @State private var liveY: Double = .nan

    /// 现在该画在哪儿。还没对齐过就用存下来的那个。
    private var posX: Double { liveX.isNaN ? app.settings.clawdX : liveX }
    private var posY: Double { liveY.isNaN ? app.settings.clawdY : liveY }

    /// 停下来了，把位置记住。
    private func settle() {
        if !liveX.isNaN { app.settings.clawdX = liveX }
        if !liveY.isNaN { app.settings.clawdY = liveY }
    }
    @State private var line: String?
    @State private var lineTask: Task<Void, Never>?
    /// 手上那件东西**此刻怎么拿**。空手就是 `.none`
    @State private var carryPose: CarryPose = .none
    /// 动作进度 0…1。喝、摇晃这类靠它一帧一帧推
    @State private var rigBeat: Double = 0
    /// 推 `rigBeat` 的那根针。**没在做动作的时候它是停的**——
    /// 不然一整天挂在那儿空转，白烧电
    @State private var rigTicker: Task<Void, Never>?
    /// 手上这件是不是他自己掏出来的。
    /// 是的话喝完会自己收起来；她塞给他的（在小屋搬起来的）就一直拿着。
    @State private var tookOutMyself = false
    /// 正躲在屏幕边上探头。躲着的时候不让别的地方改他的表情、也不让他自己走开。
    @State private var peeking = false
    /// 探头时身体往屏幕里倾多少度（见 `ClawdRigView.tilt`）
    @State private var peekTilt: Double = 0
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
    /// 手指按下去那一刻。用来分「戳」和「拎起来」
    @State private var pressAt: Date?
    @State private var liftTask: Task<Void, Never>?
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
                // ⚠️ 这里整段换掉了。
                //
                // 以前是：物件缩到 0.8、往他头顶上一放，他的手一动不动——
                // **他没有在举，他只是头上顶着个东西**（她的原话）。
                //
                // 现在走骨架（`ClawdRigView`）：身子和两只手是分开的，
                // 姿势只描述「手转到哪儿、东西摆在哪儿」。
                // 举大件就是**双手抬过头顶**、东西压在两手中间，不缩小；
                // 拿小东西就是一只手伸出去、东西挨着手边；
                // 喝和摇晃是**真的在动**（`beat` 驱动），不是配一句台词。
                ClawdRigView(mood: room.carrying == nil ? mood : .carrying,
                             item: room.carriedKind?.sprite,
                             // 身上穿戴的那件。**以前这一项根本没传**——
                             // 帽子买了、穿上了、存进 `ClawdStore.wearing` 了，
                             // 然后就再也没出现过（`wornKind` 全项目零处引用）。
                             // 她报了两次，第二次是「穿衣服也是像图上这样，
                             // 不是一成不变的一个纸片」。
                             worn: room.wornKind?.sprite,
                             wornID: room.wearing ?? "",
                             pose: carryPose,
                             // 探头时身体绕脚底往屏幕里倾（见 `ClawdRigView.tilt`）
                             tilt: peekTilt,
                             // ⚠️ 1.1 × 1.5 = 1.65。换图纸那次欠的账：图纸从 54 格缩到 36 格（3 格/单位 → 2 格/单位），躯干跟着从 33 格变成 22 格，**scale 没跟着调，他在所有地方都缩了三分之一**。22 × s_new = 33 × s_old → 每一处 scale 都要 ×1.5 才回到原来那么大。
                             scale: 1.65,
                             beat: rigBeat,
                             shadow: true)
                    // 倾斜得有个过渡。外面那条 `.animation(value: clawdX)`
                    // 只管横向位置，管不到 tilt——不加这句探头就是硬切一下。
                    .animation(.easeOut(duration: 0.45), value: peekTilt)
                    .scaleEffect(held ? 1.2 : 1)
                    .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
                    .shadow(color: .black.opacity(held ? 0.26 : 0), radius: 10, y: 8)
                    // 这一条是长按拖不动的根源：PixelSpriteView 里那块 Canvas
                    // 自己写着 allowsHitTesting(false)，所以它整个不接触摸，
                    // 外面挂多少手势都落不到实处。补一块实心的感应区上去，
                    // 顺便放大一圈——它只有三十几个点宽，按准太难了。
                    .contentShape(Rectangle().inset(by: -14))
            }
            .position(x: posX * geo.size.width,
                      y: posY * geo.size.height)
            .onAppear { pageWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, w in pageWidth = w }
            // 拎着的时候要跟手，所以不给动画
            .animation(held ? nil : .easeInOut(duration: walkSeconds), value: posX)
            .animation(held ? nil : .easeInOut(duration: walkSeconds), value: posY)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: held)
            .animation(.easeInOut(duration: 0.25), value: line)
            // ⚠️ **一个手势管两件事**：轻点是戳，按住 0.28 秒是拎起来。
            //
            // 以前是 `.onTapGesture` + `.highPriorityGesture(长按序列)` 并存，
            // 高优先级那个把点击吃了（她报的第 1 条）。
            // 两个手势抢同一块地方，赢的那个不一定是她想要的那个——
            // 所以干脆只留一个，由它自己分。
            //
            // 还得是 highPriority：聊天页整页挂着一个拉侧栏的拖拽，
            // 普通 gesture 会被它压住。
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if pressAt == nil {
                            pressAt = Date()
                            liftTask?.cancel()
                            liftTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 280_000_000)
                                guard pressAt != nil, !held else { return }
                                lift()
                            }
                        }
                        guard held else { return }
                        // 拖的每一帧也只写本地，松手才落全局（理由同 `liveX`）
                        liveX = min(right, max(left, value.location.x / geo.size.width))
                        liveY = min(bottom, max(top, value.location.y / geo.size.height))
                    }
                    .onEnded { value in
                        // 松手了，把拖到的位置记住（拖的过程只写了本地）
                        settle()
                        liftTask?.cancel()
                        let quick = Date().timeIntervalSince(pressAt ?? Date()) < 0.28
                        let still = abs(value.translation.width) < 12
                            && abs(value.translation.height) < 12
                        pressAt = nil
                        if held {
                            drop()
                        } else if quick && still {
                            pokeTap()
                        }
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
            let x = posX
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
            pendTask?.cancel()
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
            moodAt = Date()
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
                // ⚠️ 走路和「自己找点事做」是**两条独立的循环**，
                // 原来 8…18 秒配上那边的 14…26 秒，两条一叠，
                // 平均六七秒他就动一下——她说的「动作太频繁」是这么来的。
                // 两边一起放慢，走位比换动作更显眼，所以放得更开。
                try? await Task.sleep(nanoseconds: UInt64.random(in: 20...45) * 1_000_000_000)
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
                    moodAt = Date()
                    // 这件东西该怎么拿：大件双手举，小件一只手端着
                    carryPose = ClawdRig.poses(for: pick).first ?? .hold
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
                        // 能摇的（红酒）先晃两下再喝。
                        // 她点名要的：「假如是红酒可以喝也可以摇晃酒杯」——
                        // 摇是个**动作**，不是一句台词。
                        if ClawdRig.poses(for: pick).contains(.swirl),
                           Double.random(in: 0...1) < 0.5 {
                            await swirl()
                            if Task.isCancelled { return }
                        }
                        await sip()
                    }

                    // 喝完收起来
                    if tookOutMyself, !held {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            room.carrying = nil
                        }
                        tookOutMyself = false
                        carryPose = .none
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

    // 他有多宽：图纸 36 格 × 每格 1.1 点。算探头必须用点数——
    // "露出百分之几"在大屏小屏上差得远，她那台是大屏的。
    //
    // ⚠️ **32 → 36**：图纸换成 2 格/单位之后是 36 格宽，这儿漏改过。
    // 又是那条老毛病——「改一个尺寸，跟它有关系的全部要重算」。
    private var halfWidth: CGFloat { 36 * 1.1 / 2 }

    /// 完全看不见的位置：整只挪到屏幕外面，再多给六个点保险
    private func hiddenX(right: Bool) -> Double {
        let m = Double((halfWidth + 6) / max(pageWidth, 1))
        return right ? 1 + m : -m
    }

    /// 探出来的位置：只往里挪十三个点。
    /// 十三个点正好是一只眼睛加上扒着边那只手的宽度——
    /// 再多就成了"站在边上"，再少就什么都看不见。
    /// 探出来的位置：**露出他的六成**。
    ///
    /// ⚠️ 这个数改过两次，两次都改错了方向，记一下为什么：
    ///
    /// · 第一版「只往里挪 13 个点」，配整只的图 → 露出一条从头到脚的竖边
    /// · 第二版换成只有头的图、还把露出的宽度收得更小 →
    ///   **她看到的是四格颜色**（她的原话：「只剩下四格了，
    ///   并不是字面意义上的探头」）
    ///
    /// 两次都错在同一件事上：**把「藏起来」当成了目的**。
    /// 探头的重点不是藏得好，是**一眼认得出是他**——
    /// 认不出是谁的那四格，只是一条色边。
    ///
    /// 她画了一张给我看：一只完整的 clawd，被屏幕边切掉一截。
    /// 所以现在按「露出多少个点」来算，露六成，头、眼睛、扶着墙那只手、
    /// 腿都在里面。
    private var peekVisible: CGFloat { halfWidth * 2 * 0.6 }

    private func peekX(right: Bool) -> Double {
        // 他占 [center − halfWidth, center + halfWidth]。
        // 想让屏幕里剩下 `peekVisible` 那么宽，中心就该落在
        // 「边界 ± (halfWidth − 露出的宽度)」上。
        let m = Double((halfWidth - peekVisible) / max(pageWidth, 1))
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
        // ⚠️ 倾斜要跟着一起收。不清零的话他走回屏幕中间还歪着身子。
        defer { peeking = false; peekTilt = 0 }

        // 朝屏幕里面看：在右边就朝左，在左边就朝右
        facingLeft = !right
        mood = .idle
        moodAt = Date()

        // 溜出去。
        //
        // 这里**不能用 withAnimation**：外面挂着 `.animation(_:value: clawdX)`，
        // 那条会盖掉 withAnimation 给的时长，而 walk() 结束时 walkSeconds 是 0——
        // 所以上一版这几下全是瞬移。要改时长得改 walkSeconds 本身。
        walkSeconds = 0.5
        liveX = hiddenX(right: right); settle()
        try? await Task.sleep(nanoseconds: UInt64.random(in: 700...1400) * 1_000_000)
        if Task.isCancelled { return }

        let rounds = forever ? Int.max : Int.random(in: 2...4)
        for _ in 0..<rounds {
            if Task.isCancelled { return }
            guard !held, !poked else { return }

            // 探出来
            mood = .peeking
            moodAt = Date()
            walkSeconds = 0.55
            liveX = peekX(right: right); settle()
            // **探头的动作是「倾」，不是「挪」。**
            // 她说 app 上这个是平移的、不对——`anatomy.md` 那张
            // transform-origin 表里没有一处平移，全是绕自己的支点转。
            // 位置只负责「他躲在边上」，探出去的姿态靠身体绕脚底倾过去。
            //
            // 在右边就往左倾（负角度＝逆时针，顶部朝左），在左边反过来。
            peekTilt = right ? -14 : 14
            // 这儿**故意不说话**：气泡是跟他一起居中的，
            // 他人在屏幕外，气泡也就跟着出去了，只会在边上露半个白角。
            // 躲着的时候本来也该是安静的。
            try? await Task.sleep(nanoseconds: UInt64.random(in: 2600...4800) * 1_000_000)
            if Task.isCancelled { return }
            guard !held, !poked else { return }

            // 缩回去
            mood = .idle
            moodAt = Date()
            walkSeconds = 0.4
            peekTilt = 0                 // 先站直，再缩回去
            liveX = hiddenX(right: right); settle()
            try? await Task.sleep(nanoseconds: UInt64.random(in: 900...2200) * 1_000_000)
        }

        if Task.isCancelled { return }
        guard !held, !poked else { return }

        // 看够了，自己走回来
        peeking = false
        mood = .walking
        moodAt = Date()
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
        let fromX = posX
        let fromY = posY
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
            liveX = fromX + dx * eased
            // 每一步上下颠一点点，走路的那个起伏
            let bob = (i % 2 == 0 ? 0.0 : -0.004)
            liveY = fromY + dy * eased + bob
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        liveY = ty
        // ⚠️ 走完了才把位置记进全局，**一趟只写这一次**。
        // 中间那四十步一步都不写——那是她说的「没回话的时候卡」的病根。
        settle()
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

    /// 喝一口。
    ///
    /// **这是一个真的动作**：手抬到嘴边、杯子跟着仰、喝完放下来。
    /// 一口 1.6 秒，`beat` 从 0 走到 1，姿势表里那条 `sin` 曲线
    /// 负责让它先快后慢——匀速抬手看着像机械臂。
    private func sip() async {
        let before = mood
        carryPose = .sip
        mood = .happy
        moodAt = Date()
        await runBeat(seconds: 1.6)
        carryPose = .hold
        mood = before == .happy ? .carrying : before
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    /// 晃两下酒杯。
    ///
    /// 她点名要的：「假如是红酒可以喝也可以摇晃酒杯」。
    /// 摇是**手腕小幅往复**，杯子跟着划一个小圈，杯口始终朝上——
    /// 倾角一大就成了泼酒。
    private func swirl() async {
        carryPose = .swirl
        await runBeat(seconds: 2.4, loops: 2)
        carryPose = .hold
    }

    /// 把 `rigBeat` 从 0 推到 1（可以来回几圈）。
    ///
    /// 20 帧一秒。再快人眼也看不出，再慢就一顿一顿的。
    /// **做完就把针停掉**——这一层不该在他站着发呆的时候还在跑。
    private func runBeat(seconds: Double, loops: Int = 1) async {
        rigTicker?.cancel()
        let steps = Int(seconds * 20)
        guard steps > 0 else { return }
        for round in 0..<max(1, loops) {
            _ = round
            for i in 0...steps {
                if Task.isCancelled { rigBeat = 0; return }
                rigBeat = Double(i) / Double(steps)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        rigBeat = 0
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

    /// 多久没说话就开始困（秒）。
    ///
    /// ⚠️⚠️ 八分钟改成四十分钟，**而且只在该睡的钟点才算**。
    ///
    /// 她报的：「现在说的最多的话就是困了，大白天也说困。」
    ///
    /// 一点没错，而且原因很直白：**这一整段只看「她多久没说话」，
    /// 一个小时都没看过**。下午两点她八分钟没打字，他就打哈欠。
    /// 而八分钟在白天根本不算「安静」——她可能只是在开会、在洗碗、
    /// 在看这条消息想怎么回。
    ///
    /// 困是**跟作息绑在一起**的，不是跟「有没有人理我」绑在一起。
    /// 一只白天犯困的宠物不像跟她过同一个作息，像坏了。
    private let drowsyAfter: Double = 40 * 60
    /// 再过多久真睡着
    private let sleepAfter: Double = 8 * 60

    /// 这会儿是该困的钟点吗。
    ///
    /// 23 点到早上 7 点。这之外再安静也只是「她今天忙」，不是「夜深了」。
    ///
    /// ⚠️ 白天的长时间安静**不是没有反应**——他会去做自己的事
    /// （扫地、发呆、走两步，见 `ownThings`）。
    /// 那才是「她不在的时候他也存在」，而不是「她不在他就昏过去」。
    private var bedtimeNow: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 23 || h < 7
    }

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
            // ⚠️ **不到钟点就不困。** 白天再安静也只是她忙，
            // 那时候他该去做自己的事，不该打哈欠（见 `bedtimeNow`）。
            guard bedtimeNow else { return }
            mood = .drowsy
            moodAt = Date()
            say(["唔……有点困", "呼啊——", "眼睛睁不开了"].randomElement() ?? "有点困")

            try? await Task.sleep(nanoseconds: UInt64(sleepAfter * 1_000_000_000))
            if Task.isCancelled { return }
            guard !busy, !held, !peeking else { return }
            asleep = true
            walkTask?.cancel()          // 睡着了就别走了
            mood = .sleeping
            moodAt = Date()
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
            moodAt = Date()
            say(["呜哇！", "醒了醒了", "吓死我了"].randomElement() ?? "呜哇！")
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else {
            mood = .happy
            moodAt = Date()
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
        moodAt = Date()
        say(["说完啦", "好了——", "哼哼"].randomElement() ?? "说完啦")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            sync()
        }
    }

    /// 把他的状态翻成 clawd 的动作
    private func sync() {
        // 手上那件东西该怎么拿——**每次同步都对一遍**。
        //
        // 不这么写的话，她在小屋里直接把床塞给他（那条路不经过这儿的掏东西那段），
        // 姿势会停在 `.none` 上：东西在手上，手却垂着。
        // 正在喝／正在摇的时候不动它，不然一口喝到一半手会掉下去。
        if carryPose != .sip, carryPose != .swirl {
            if let kind = room.carriedKind {
                carryPose = ClawdRig.poses(for: kind).first ?? .hold
            } else {
                carryPose = .none
            }
        }

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
            settleMood(room.carrying == nil ? .idle : .carrying)
            return
        }
        // ── 他在干活：**先看干的是什么**，那比情绪更具体 ──
        //
        // 她说的：「阿晏正在给我做游戏或者处理文件，他就在打电脑。」
        if activity.contains("想") {
            settleMood(.thinking)
            return
        }
        if !activity.isEmpty && !activity.contains("说") {
            // 翻记忆、写日记、博弈、画图、动手做事，都算在打电脑
            settleMood(.working)
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
        settleMood(emotionMood() ?? ownThing)
    }

    /// 换一个动作，**但要等当前这个演完**。

    /// 她说的：「一旦触发，就等触发的结束再做下一个动作。
    /// 比如阿晏正打游戏，触发打游戏的动画；下一秒阿晏思考，
    /// 打游戏的动画没好，就还是打游戏；如果打游戏动画好了，
    /// 就正常触发思考。」
    ///
    /// ⚠️ **根子在 `sync()` 挂着 `.onChange(of: activity)`。**
    /// 我干什么，它就立刻改一次他的表情——我一秒钟换一个动作，
    /// 他就一秒钟换一张脸，既看不出在做什么，也白白重画几十次。
    ///
    /// ⚠️ **不是所有切换都排队。** 戳他、拎起来、她说话让他醒——
    /// 这些是她**当下的动作**，必须立刻有反应，排队就成了没反应。
    /// 排队的只有「环境驱动」那几档：他在忙什么、他什么情绪、
    /// 以及闲着时自己找的事。那几档晚个两三秒没人看得出来。
    @MainActor
    private func settleMood(_ next: ClawdMood) {
        if next == mood {
            pending = nil
            return
        }
        let played = Date().timeIntervalSince(moodAt)
        if played < mood.hold {
            // 还没演完，排着——**并且给它上个闹钟**。
            //
            // ⚠️ 光排队不叫号等于把动作吞了：`sync()` 是被
            // 「我在忙什么」「她情绪变了」这些事件推着走的，
            // 我要是停下来不动了，就再没人来看一眼队里还有谁。
            // 他会一直演着打游戏，我早就不打了。
            //
            // 用一次性延时而不是每秒轮询：他同时活在小屋、聊天页、
            // 输入框上，多一个常驻的定时器就多一份重画。
            pending = next
            pendTask?.cancel()
            let wait = mood.hold - played
            pendTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, let queued = pending else { return }
                settleMood(queued)
            }
            return
        }
        pendTask?.cancel()
        mood = next
        moodAt = Date()
        pending = nil
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
                    ownThing = Self.todaysThings().randomElement() ?? .idle
                } else {
                    ownThing = .carrying
                }
                if !busy, !asleep, !held, !peeking, !upset,
                   emotionMood() == nil {
                    settleMood(ownThing)
                }
                // 一件事做半分钟到一分钟。原来是 14…26 秒，跟走路那条循环
                // 一叠就太密了（见 `startWalking` 里的注释）。
                let wait = Double.random(in: 30...60)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    /// 「自己的事」有哪些。**扫地是她指名要的那只**。
    /// 发呆占的份额最大——一只一直在忙的宠物看着很累。
    static let ownThings: [ClawdMood] = [
        .idle, .idle, .idle, .idle, .idle,
        .sweeping, .sweeping,
        .thinking,
        .walking,
        // 从他们 gallery 扒来的那八件（见 `scripts/照抄表情.py`）
        .coffee, .reading, .eating, .painting,
        .listening, .watering, .gaming, .guitar,
        .photo, .singing, .exercise, .shower
    ]

    /// 今天他可以做哪些事。
    ///
    /// ⚠️ **节日不进那张固定的池子。**
    /// 她说过：「节日那些该按日子出来，不该随机抽到，
    /// 大夏天突然过年就出戏了。」
    ///
    /// 所以节日是**当天临时加进来的**，而且给的份额大——
    /// 一年就这一天，他该老想着这件事；过了今天自己就没了。
    private static func todaysThings() -> [ClawdMood] {
        guard let f = ClawdMood.festiveToday() else { return ownThings }
        return ownThings + Array(repeating: f, count: 8)
    }

    /// 戳他一下。
    ///
    /// ⚠️ 以前这是 `.onTapGesture`，跟底下那个 `highPriorityGesture`
    /// （长按拎起来）挂在**同一个视图**上。高优先级的那个会把点击整个吃掉——
    /// 她说的「点 clawd 无反应，连续点也没反应」就是这么来的：
    /// 手指一抬，长按还没到 0.28 秒，序列手势失败，
    /// 而点击又轮不到自己上场，于是什么都没发生。
    ///
    /// 现在两件事合成**一个**手势（见 body 里那个 DragGesture），
    /// 按下去多久、动没动，由它自己分：快而不动 = 戳，按住不放 = 拎起来。
    @MainActor
    private func pokeTap() {
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
                moodAt = Date()
                say(["别戳啦！", "呜哇——", "会坏的！"].randomElement() ?? "别戳啦！")
                if app.settings.haptics {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            } else {
                mood = .happy
                moodAt = Date()
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

    /// 拎起来
    @MainActor
    private func lift() {
        held = true
        // 拎着的时候，聊天页那个「从左边缘拉出侧边栏」的手势让路
        ClawdStore.clawdHeld = true
        walkTask?.cancel()
        mood = .happy
        moodAt = Date()
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        say(["诶——", "放我下来", "飞起来了"].randomElement() ?? "诶")
    }

    /// 放下
    @MainActor
    private func drop() {
        held = false
        ClawdStore.clawdHeld = false
        // 把他放到屏幕边上，他就**真的躲到边外面去**，
        // 只留一只眼睛在这儿看着——她要的就是这个。
        // 以前不管放哪儿都是原地站住然后接着乱跑。
        let x = posX
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
}
