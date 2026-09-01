import SwiftUI

// MARK: - 会动手的 clawd
//
// 她说的：
// > clawd 举起东西希望不再是一个缩小的家具在他头上，而是他真正举着
// >（举重物时双手抬过头顶举着）和拿着（跟扫把一样拿在手上）。
// > 假如是饮料可以喝，假如是红酒可以喝也可以摇晃酒杯。
// > **喝和摇晃都是动作，不只是简简单单说一句「我在摇晃酒杯」。**
//
// 以前是这么糊弄的：物件缩到 0.8 倍，往他头顶上一放。
// 他的手一动不动——**他没有在举，他只是头上顶着个东西。**
//
// ## 为什么不是「每个动作画一套帧」
//
// 一件物品四个动作、几十件物品，那是上千帧手绘。画不完，
// 而且加一件新家具就得再画四套，这条路从第二件东西开始就断了。
//
// 所以走**骨架**这条路：把他拆成「身子 + 两只手」，
// 手是能单独转、单独挪的。姿势只描述「手转到哪儿、东西放在哪儿」，
// 于是**一套骨架配上一句「这东西该怎么拿」，就能长出所有动作**，
// 加新家具不用再画一帧。
//
// ⚠️ 拆的时候身子一格没动：手本来就长在身子外面
// （图纸 40 格里，身子占第 8..31 格，手是 4..7 和 32..35，
//   最外面各留 4 格空——举手的时候手要往外张，得有地方张）。
// 把那两块从身子那张图里抠掉、单独画，剪影跟原来一模一样。

/// 手上那件东西**怎么拿**。
///
/// 这是「一件物品」和「一套动作」之间的全部约定——
/// 新加一件家具只要说清楚它属于哪一档，动作就自己有了。
enum CarryPose: String, Codable, Sendable {
    /// 空着手
    case none
    /// 欢呼：两只手绕肩膀来回摆
    case cheer
    /// 招手：一只手摆，另一只垂着
    case wave
    /// 拿在手上（扫把、书、一罐可乐）。一只手，东西挨着手边
    case hold
    /// 双手抬过头顶举着（床、柜子这类大件）
    case lift
    /// 举到嘴边喝
    case sip
    /// 摇晃（酒杯）。手腕小幅往复
    case swirl
}

/// 一副能动的 clawd。
///
/// `beat` 是动作进度（0…1，来回摆）：喝到哪一口、酒杯晃到哪一边，
/// 全靠它驱动。不传就是静止的姿势。
struct ClawdRigView: View {

    var mood: ClawdMood = .idle
    /// 手上那件东西。空着就是没拿
    var item: PixelSprite?
    /// **身上穿戴的那件**（帽子、眼镜、围巾…）。跟手上那件是两个槽。
    var worn: PixelSprite?
    /// 那件穿戴是什么（决定贴在身上哪儿，见 `ClawdRig.wearAt`）
    var wornID: String = ""
    var pose: CarryPose = .none
    /// 一格画多大
    var scale: CGFloat = 4
    /// 动作进度 0…1。喝、摇这类靠它
    var beat: Double = 0
    var shadow: Bool = false

    @State private var frame = 0
    @State private var ticker: Task<Void, Never>?

    private var frames: [(PixelSprite, Double)] { mood.frames }
    private var body0: PixelSprite {
        // ⚠️ 弯腿要在**抠掉手之后**做：`stripArms` 认的是列，`bendLegs` 动的是行，
        // 反过来做也对，但两个都做完才是这一帧真正的身子。
        ClawdRig.bendLegs(ClawdRig.stripArms(frames[min(frame, frames.count - 1)].0),
                          by: plan.squat)
    }

    /// 图纸一共多宽多高（格）
    private var cols: CGFloat { CGFloat(frames[0].0.width) }
    private var rows: CGFloat { CGFloat(frames[0].0.height) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ⚠️⚠️ **手在下、身子在上。顺序反了就前功尽弃。**
            //
            // 手加长到 8 格、里面 4 格埋进身子，靠的就是**身子盖住它**。
            // 要是手画在身子上面，埋进去的那 4 格会直接糊在他脸上
            // （眼睛在第 9..11 行，手在第 10..14 行，正好撞上）。
            // 举东西的时候手是**整条画好的**（`armUp`），不转角度；
            // 平时才用会转的那只。见 `ClawdRig.armUp` 那段注释。
            if plan.armsUp {
                armUp(onLeft: true)
                armUp(onLeft: false)
            } else {
                arm(.left)
                arm(.right)
            }

            // 身子（图纸上原来那两块手已经抠掉了，见 `stripArms`）
            PixelSpriteView(sprite: body0, scale: scale)

            // 身上穿戴的那件（帽子、眼镜、围巾、背包、靴子…）。
            //
            // ⚠️ **画在手之后、手上那件之前**：
            // 帽子该压在身子和手上面，但他举起来的床该压在帽子上面——
            // 不然一张床会从帽檐底下钻出来。
            if let worn {
                PixelSpriteView(sprite: worn, scale: scale)
                    .offset(x: ClawdRig.wearAt(wornID, itemW: CGFloat(worn.width),
                                               itemH: CGFloat(worn.height)).x * scale,
                            y: ClawdRig.wearAt(wornID, itemW: CGFloat(worn.width),
                                               itemH: CGFloat(worn.height)).y * scale)
            }

            // 举重物会出汗。抄的参考里那两滴 `.bb-sweat`：
            // 从身子两侧的肩膀那儿甩出去，往外、往下、边飞边淡。
            //
            // ⚠️ 她问「举重物的汗呢」——这不是装饰。
            // 一个姿势要读得出"费劲"，光有动作不够；
            // 汗是**唯一一处能看出"重"的东西**，
            // 别的都只能看出"在动"。
            if plan.armsUp {
                sweat
            }

            // 手上那件东西。**不缩小**——她说的就是这个：
            // 缩小的东西看着是「顶在头上的挂件」，不是「他举着的家具」。
            if let item {
                PixelSpriteView(sprite: item, scale: scale)
                    .rotationEffect(.degrees(plan.itemTilt), anchor: .bottom)
                    .offset(x: plan.itemAt.x * scale, y: plan.itemAt.y * scale)
            }
        }
        .frame(width: cols * scale, height: rows * scale, alignment: .topLeading)
        .background(alignment: .bottom) {
            if shadow {
                Ellipse()
                    .fill(RadialGradient(colors: [.black.opacity(0.22), .black.opacity(0)],
                                         center: .center, startRadius: 0,
                                         endRadius: cols * scale * 0.5))
                    .frame(width: cols * scale * 0.9, height: scale * 2.4)
                    .offset(y: scale * 1.2)
            }
        }
        .onAppear { start() }
        .onDisappear { ticker?.cancel() }
        .onChange(of: mood) { _, _ in frame = 0; start() }
    }

    // MARK: 手

    private enum Side { case left, right }

    private func arm(_ side: Side) -> some View {
        ClawdArmView(onLeft: side == .left,
                     angle: side == .left ? plan.leftArm : plan.rightArm,
                     scale: scale)
    }

    /// 举过头顶的那只手臂。
    ///
    /// 举重物甩出来的汗。两滴，一左一右，错开半个周期。
    ///
    /// ⚠️ 走 `beat` 取进度，不另开计时器——这只 clawd 同时活在
    /// 小屋、聊天页、输入框上，多一个每秒六十次的状态就多一份重画。
    private var sweat: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { i in
                // 两滴错开半个周期，别一起蹦
                let t = (beat + (i == 0 ? 0 : 0.5))
                    .truncatingRemainder(dividingBy: 1)
                let side: CGFloat = i == 0 ? -1 : 1
                let fromX = i == 0
                    ? CGFloat(ClawdRig.bodyLeft) - 1
                    : CGFloat(ClawdRig.bodyRight) + 1
                Circle()
                    .fill(Color(hexString: "7EC8FF") ?? .cyan)
                    .frame(width: scale * 1.2, height: scale * 1.6)
                    .offset(x: (fromX + side * CGFloat(t) * 3) * scale,
                            y: (CGFloat(ClawdRig.bodyTop) + 3
                                + CGFloat(t) * 5) * scale)
                    // 飞出去的过程里淡掉；`t` 很小的时候还没甩出来
                    .opacity(t < 0.1 ? 0 : (1 - t) * 0.85)
            }
        }
        .allowsHitTesting(false)
    }

    /// **长度固定，整条跟着身子沉浮**——人的胳膊不会伸缩。
    private func armUp(onLeft: Bool) -> some View {
        PixelSpriteView(sprite: ClawdRig.armUp, scale: scale)
            .offset(x: ClawdRig.armUpX(onLeft: onLeft) * scale,
                    y: ClawdRig.armUpTop(squat: plan.squat) * scale)
    }

    // MARK: 这一刻该摆成什么样

    private var plan: ClawdRig.Plan {
        ClawdRig.plan(pose: pose, beat: beat,
                      itemW: CGFloat(item?.width ?? 0),
                      itemH: CGFloat(item?.height ?? 0))
    }

    private func start() {
        ticker?.cancel()
        guard frames.count > 1 else { return }
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                let hold = frames[min(frame, frames.count - 1)].1
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                if Task.isCancelled { return }
                frame = (frame + 1) % frames.count
            }
        }
    }
}

/// 一只会转的手。
///
/// ⚠️ **`ClawdRigView` 和 `ClawdView` 共用这一个。**
/// 两边各写一份的话，肩膀位置迟早对不上——
/// 而肩膀差一格，手看着就像长在肚子上。
struct ClawdArmView: View {

    let onLeft: Bool
    /// 抬多少度（0 = 垂着）
    let angle: Double
    let scale: CGFloat

    var body: some View {
        // 肩膀在图纸上的位置：身子左边缘 / 右边缘那一格，手臂那五行
        let shoulderX: CGFloat = onLeft
            ? CGFloat(ClawdRig.bodyLeft)
            : CGFloat(ClawdRig.bodyRight + 1)
        // 手往外只露 `armOut` 格，剩下的往身子里塞——所以左上角
        // 从肩膀往外退 `armOut`，而不是退整条手臂的长度。
        let left = shoulderX - CGFloat(ClawdRig.armOut)
        PixelSpriteView(sprite: ClawdRig.arm, scale: scale)
            // ⚠️ 支点是**手臂的正中心**，不是内侧边。
            //
            // 手一共 8 格长、外面只露 4 格，所以正中心正好落在肩膀那条线上
            // （`armOut / width = 4/8 = 0.5`）。
            // **改了 `armOut` 或者手的长度，这个 `.center` 就不再对了**——
            // 得跟着改成 `UnitPoint(x: armOut / arm.width, y: 0.5)`，
            // 否则整条手会绕着一个错的点甩出去。
            //
            // ⚠️⚠️ **符号：左手 `+`、右手 `-`。别凭感觉写。**
            //
            // SwiftUI 的正角度是**顺时针**（y 轴朝下）。
            // 左手在支点左边 `(-1, 0)`，顺时针转 90° → `(0, -1)`，往**上**；
            // 右手在支点右边 `(+1, 0)`，顺时针转 90° → `(0, +1)`，往**下**。
            // 所以要让两只手都抬起来，左手取正、右手取负。
            //
            // 这儿原来写反了，两只手一直是**往下甩**的。
            // `plan` 里的约定是「正数 = 抬起来」（`.lift` 举过头顶 = 72），
            // 所以举家具、喝东西、摇杯子那几档也一起反了很久。
            // 她一句话点破：「你挥手往里挥的吗。」
            .rotationEffect(.degrees(onLeft ? angle : -angle), anchor: .center)
            .offset(x: left * scale, y: CGFloat(ClawdRig.armRow) * scale)
    }
}

enum ClawdRig {

    /// 身子在图纸上占第几格到第几格。手长在这两格外面。
    ///
    /// ⚠️⚠️ **4 → 8 / 27 → 31**：图纸从 32 格加宽到 40 格
    /// （左右各补了四列空），每一格原样往右挪了四列。
    ///
    /// 为什么加宽：身子两边原来各只剩 4 格，手臂只能贴着身子竖起来，
    /// **旁边没有一丝空气**——不管画多细都是「粘在头上的两根柱子」。
    /// 她图纸上那些举手的，手跟身子之间都是有空隙、往外张开的。
    ///
    /// `midX`、`stripArms`、`wearAt`、`plan` 全是从这两个数算出来的，
    /// 所以改这两个就够——**但漏改，手和穿戴就会长在错的地方。**
    static let bodyLeft = 8
    static let bodyRight = 31
    /// 手臂从第几行起。
    ///
    /// ⚠️⚠️ **6 → 10**：图纸从 23 行加高到 27 行（顶上补了四行空），
    /// 每一格原样往下挪了四行，所以肩膀也跟着挪。
    /// **漏改这一个，手就会长在肚子上。**
    static let armRow = 10

    /// 一只手。**8 格长**：外面露 4 格，里面还有 4 格**埋在身子里**。
    ///
    /// ## 为什么要埋这 4 格
    ///
    /// 她指出来的：「他手挥动时有一块镂空……正常生物手臂会不和身体连接吗。」
    /// ——一点没错，而且是个硬伤不是审美问题：
    ///
    /// 手臂是个**矩形绕内侧边的中点转**。一转，那条内侧边就不再贴着
    /// 身子的竖边了，根部当场豁开一个**楔形的洞**。
    /// 转得越高洞越大：手 5 格高，转到 75° 时缺口有 `2.5 × sin75° ≈ 2.4` 格。
    ///
    /// 修法是标准的那一种：**把关节埋起来**。
    /// 手加长到 8 格，多出来的 4 格塞进身子里，
    /// 再把手画在**身子底下**（见 `ClawdRigView` / `ClawdView` 的图层顺序）。
    /// 这样转到任何角度，根部那块永远被身子自己盖着，洞露不出来。
    /// 埋 4 格是算过的：最深只需要 2.4 格，留了余量。
    ///
    /// ⚠️ **露在外面那 4 格必须跟 `ClawdSprites.idle` 里那块一模一样**
    /// （4 格宽、5 格高、第 10..14 行）。她说过「手臂太细而且位置靠上」——
    /// 根子就是这儿曾经只写了两行。改之前先把 `idle` 的
    /// 第 4..7 列和第 32..35 列打出来对一遍，**别照着感觉调。**
    static let arm = PixelSprite([
        "pppppppp",
        "pppppppp",
        "pppppppp",
        "pppppppp",
        "pppppppp"
    ], ClawdSprites.palette)

    /// 手露在身子外面几格（剩下的埋进去）
    static let armOut = 4

    /// **举过头顶的那只手臂。手绘、不转角度，而且是「伸长」出来的。**
    ///
    /// 为什么不转：转一个 4×5 的长方块，像素落不到格子上，边就是糊的。
    /// 官方那套表情能一路转角度，是因为**它的手是 2×2 接近正方形**的一小团，
    /// 转到哪儿都还是一小团；我们的手一拉长，转出来是一片斜板。
    ///
    /// ⚠️⚠️ **为什么要按高度现生成，而不是一张固定的图整条上移**
    ///
    /// 上一版是固定一张图往上平移的。她指出来：
    /// 「举杠铃动的是手臂，不是手。你的手变高了——
    ///   难道正常人举哑铃手会变高吗。」
    ///
    /// 一整条往上飘，等于**手臂根部脱开了肩膀**：肩膀跟着手一起升，
    /// 那不是在举，是整条胳膊在往上浮。
    /// 真实的是**肩膀钉住不动，手臂伸长**——所以这儿按当前高度
    /// 现算长度：底端永远压在 `armUpBottom`，只有顶端跟着手往上跑。
    ///
    /// 顶上那行 `k` 是**握把**——抄的参考里压在手臂顶上那块深色
    /// （`<rect ... fill="#333"/>`）。没有它手和手臂一整条同色，
    /// 看不出"握住"，东西像浮在手上面。
    static let armUp = PixelSprite(
        ["kkkk"] + Array(repeating: "pppp", count: 11), ClawdSprites.palette)

    /// 手举起来时，**手掌高出头顶几格**。固定值。
    static let armUpAboveHead = 3

    /// 举起来的手有多宽（格）
    static let armUpWide = 4
    /// 手根部往身子里盖几格。**这就是「连着」**——
    /// 不靠转角度去凑，所以永远不会豁开她说的那个镂空。
    static let armUpOverlap = 2
    /// 身子顶在第几行
    static let bodyTop = 4
    /// 腿从第几行开始（`idle` 第 21 行起就有断口了）
    static let legTop = 21

    /// 弯腿：腿缩短 `n` 格，**整个上半身跟着往下沉**，脚底钉在原地。
    ///
    /// ⚠️⚠️ **弯的是腿，不是身子。**
    /// 她指出来的：「正常人举杠铃不会是身体变短的，而是腿。」
    /// 从躯干里抽行的话，等于他上半身缩了一截——人不是那么使劲的。
    ///
    /// ⚠️ 也不能整只往下挪：脚跟着走，那是往下掉，不是在蹲。
    ///
    /// 做法是从**腿中间**抽掉 `n` 行、顶上补 `n` 行空：
    /// 躯干一格不变形，脚底还在最后一行。
    static func bendLegs(_ s: PixelSprite, by n: Int) -> PixelSprite {
        guard n > 0, s.rows.count > legTop + n else { return s }
        var rows = s.rows
        // 从腿中间抽（不是从底下砍——从底下砍脚就往上跑了）
        let at = legTop + 2
        rows.removeSubrange((at - n + 1)...at)
        let blank = String(repeating: ".", count: s.width)
        return PixelSprite(Array(repeating: blank, count: n) + rows, s.palette)
    }

    /// 举起来那只手的**左上角**在第几列。**钉死在肩膀上。**
    ///
    /// ⚠️⚠️ 我上一版让它**跟着东西的宽度走**，想让手去够到床。
    /// 床窄，手就被挪进身子里——她一眼看穿：
    /// 「你手长头顶啊」「你再说一遍这是肩膀吗大哥」。
    ///
    /// **肩膀是身子的肩膀，不是随东西移动的一个点。**
    /// 手永远在身子最外侧那几列；东西不够宽，就**把东西画大**
    /// 去够手（床已经画到 22 格了），不是让手去迁就东西。
    static func armUpX(onLeft: Bool) -> CGFloat {
        onLeft
            ? CGFloat(bodyLeft + armUpOverlap - armUpWide)
            : CGFloat(bodyRight + 1 - armUpOverlap)
    }

    /// 举起来那只手的**手尖**在第几行（也就是东西搁在哪儿）。
    ///
    /// ⚠️⚠️⚠️ **手臂长度是固定的。这儿只跟着 `squat` 走，没有别的变量。**
    ///
    /// 她的原话：「手是保持不变的啊，手臂变长能动吗，
    /// 手臂跟着身体一起，因为人的长度是固定的啊。」
    ///
    /// 我在这一处连着错了两版，一版比一版离谱：
    ///  · 第一版：手不动、身子沉，两边加起来正好抵消——什么都没动
    ///  · 第二版：让手臂**能伸缩**——等于给他装了两根液压杆
    ///
    /// 正确的只有一种：**举重物时唯一在动的是腿。**
    /// 腿一弯，肩膀、手臂、手、床整个跟着往下沉；腿一蹬，整个跟着起来。
    /// 手臂自始至终一格没变，因为人的胳膊不会伸缩。
    ///
    /// 所以这儿 `= bodyTop + squat - armUpAboveHead`：
    /// 手掌永远高出头顶固定的几格，头沉多少它沉多少。
    static func armUpTop(squat: Int) -> CGFloat {
        CGFloat(bodyTop + squat - armUpAboveHead)
    }

    /// 把手从身子那张图里抠掉。
    ///
    /// **只清身子边界外的列**（0..3 和 28..31），
    /// 身子本身一格不动——所以换任何一帧都不会歪。
    ///
    /// ⚠️ **只清身子色那几格**（`p`）。以前是不管什么一律抹成透明，
    /// 结果把扫地那两帧伸在身子外面的扫把杆（`n`）和稻草（`t`）
    /// 一起抹没了——他举着空气扫地。
    /// 抠的是「手」，不是「身子外面的所有东西」。
    static func stripArms(_ s: PixelSprite) -> PixelSprite {
        let rows = s.rows.map { row -> String in
            var chars = Array(row)
            for x in chars.indices where x < bodyLeft || x > bodyRight {
                if chars[x] == "p" { chars[x] = "." }
            }
            return String(chars)
        }
        return PixelSprite(rows, s.palette)
    }

    /// 一个姿势要摆成什么样。
    struct Plan {
        /// 手臂抬多少度（0 = 垂着，正数 = 往上抬）
        var leftArm: Double = 0
        var rightArm: Double = 0
        /// 手上那件东西摆在哪儿（图纸格，相对左上角）
        var itemAt: CGPoint = .zero
        /// 东西歪多少度
        var itemTilt: Double = 0

        /// **手举过头顶**（不转角度，换成整条画好的 `armUp`）。
        ///
        /// 她带回来那份参考里最要紧的一句：
        /// 「bar + plates + both arms live in a single group that
        ///  translates as one piece (**no per-arm rotation,
        ///  so no detached-hand risk**)」——
        /// 手和东西是**一个整体一起平移**，一根手臂都没转。
        /// 我们「床跟手对不齐」「根部镂空」，根子就是各转各的。
        var armsUp = false
        /// **腿弯几格**。
        ///
        /// ⚠️ 弯的是腿，不是身子。她的原话：
        /// 「正常人举杠铃不会是身体变短的，而是腿。」
        var squat: Int = 0
    }

    /// 姿势表。
    ///
    /// 这儿是**这一整套动作的全部数据**——加一个新姿势就在这儿加一档，
    /// 不用去碰任何一个视图。
    static func plan(pose: CarryPose, beat: Double,
                     itemW: CGFloat, itemH: CGFloat) -> Plan {
        var p = Plan()
        // 图纸中线，用来把东西摆正
        let midX = CGFloat(bodyLeft + bodyRight + 1) / 2
        // 手转的支点在肩膀那一端的**正中间**，也就是这一行。
        // 底下那几档「东西摆在哪儿」都是照着手的位置调出来的，
        // 所以写成「肩膀中线 ± 几格」，而不是「手臂第一行 ± 几格」——
        // ⚠️ 手臂加高（2 格 → 5 格）那一次，中线跟着往下挪了一格，
        // 而当时那几行写的是 `armRow`，于是他手上的东西全都悬空了一格。
        // 认支点，别认上边缘。
        let handY = CGFloat(armRow) + CGFloat(arm.height - 1) / 2

        switch pose {
        case .none:
            return p

        case .cheer, .wave:
            // 欢呼 / 招手。
            //
            // ⚠️⚠️ **手臂一格都不重画。**
            //
            // 这是照着官方那套表情（`clawd-emotes`）的规矩来的：
            // 手就是身侧那一小块，**永远不变形**，
            // 「举手」= 把它绕肩膀转 35°…75°，来回摆。
            // 没有小臂、没有肘、没有手掌。
            // 它那儿庆生就是 35°↔75°、新年 50°↔70°，全是这么做的。
            //
            // 我在这上面翻了四次车：一直在雕一条静态的胳膊
            // （加长、收腕、加手掌、拐个肘），
            // 她的评价一次比一次难听，最后那版
            // 「像头上装了两个杠铃」——都对。
            //
            // **读出「在欢呼」的是动作，不是轮廓。**
            // 一块不变形的疙瘩，摆起来就是手；
            // 雕得再细，不动也还是个疙瘩。
            let t = abs(beat * 2 - 1)               // 0→1→0 的三角波
            p.rightArm = 35 + 40 * t
            p.leftArm = pose == .cheer ? p.rightArm : 0

        case .hold:
            // 一只手往前伸一点，东西挨着手边、**落在地上那条线上**。
            // 扫把、可乐都是这一档。
            p.rightArm = 18
            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 1.5,
                               y: handY + 1.5 - itemH * 0.55)
            p.itemTilt = -8

        case .lift:
            // 双手抬过头顶（搬床、搬柜子）。**东西不缩小**——
            // 缩小的东西看着是顶在头上的挂件，不是他举着的家具。
            //
            // ⚠️⚠️ **这一档不转角度了。**
            //
            // 原来是把手转到 72°，东西的位置另外写死——两套算法各算各的，
            // 所以床跟手永远差那么一点，手根部还豁着一个洞。
            // 参考里的做法是反过来的：**手和东西是一个整体一起平移**，
            // 位置只有一个来源，对不齐这件事从根上不成立。
            //
            // 动作分两半，而且**是反着的**（这一条是她指出来的）：
            //   · 手 + 床往上顶
            //   · 同时**腿弯下去**、眼睛眯起来
            // 两边同方向动就只是整只在飘；反向对抗才读得出「在使劲」。
            // ⚠️ **只有一个变量：腿弯几格。**
            // 手臂、手、床全跟着身子走，因为人的胳膊长度是固定的。
            let t = (sin(beat * .pi * 2) + 1) / 2       // 0→1→0，一个来回
            p.armsUp = true
            p.squat = Int((t * 2).rounded())            // 腿弯两格，蹬起来再放下
            let top = armUpTop(squat: p.squat)
            // 床就搁在手尖上——**同一个数算出来的**，不可能对不齐
            p.itemAt = CGPoint(x: midX - itemW / 2, y: top - itemH)

        case .sip:
            // 举到嘴边喝。beat 0→1 是「凑近 → 仰头灌 → 放下」，
            // 所以用一条先快后慢的曲线，不是匀速——匀速看着像机械臂。
            let t = sin(beat * .pi)                      // 0→1→0
            p.rightArm = 40 + 25 * t
            p.itemAt = CGPoint(x: midX + 1.5 - itemW / 2,
                               y: handY - 2 - 2.5 * t)
            p.itemTilt = -20 - 45 * t

        case .swirl:
            // 摇酒杯。手腕小幅往复，杯子跟着划一个小圈——
            // **杯口始终朝上**（倾角很小），不然就是在泼酒了。
            let a = beat * .pi * 2
            p.rightArm = 34 + sin(a) * 8
            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 0.5 + cos(a) * 0.8 - itemW / 2,
                               y: handY - 1.5 + sin(a) * 0.6 - itemH * 0.3)
            p.itemTilt = sin(a) * 12
        }
        return p
    }

    // MARK: 穿在身上

    /// 一件穿戴该贴在他身上**哪个位置**（图纸格，相对左上角）。
    ///
    /// ## 为什么以前没有这个
    ///
    /// 她报过两次。第一次：「clawd 的穿戴比如贝雷帽被当成家具放在房间里，
    /// 实际上应该给他直接穿上。」——那次加了 `ClawdStore.wearing` 这个槽，
    /// 存是存下了。
    ///
    /// 可**没有任何一个视图去读它**。她这次说「穿衣服也是像图上这样，
    /// 不是一成不变的一个纸片」——去查了一下，`wornKind` 全项目零处引用：
    /// 帽子买了、穿上了、存下来了，**然后就再也没出现过**。
    ///
    /// ⚠️ 记一句：**存下来不等于画出来。** 加一个字段很容易，
    /// 而「谁去读它」是另一件必须单独做完的事。
    ///
    /// ## 怎么定位
    ///
    /// 图纸 **40 格宽、27 格高**（见 `ClawdSprites`；
    /// 顶上四行、左右各四列都是留给举手的空）：
    /// 身子 8..31 列，脸在第 9..12 行，脚在最底下几行。
    /// 所以帽子在头顶偏上、眼镜压在眼睛那一行、围巾在下巴底下、
    /// 靴子贴着脚、背包挂在身后偏一侧。
    static func wearAt(_ id: String, itemW: CGFloat, itemH: CGFloat) -> CGPoint {
        let midX = CGFloat(bodyLeft + bodyRight + 1) / 2
        switch id {
        case "hat", "beret":
            // 扣在头顶：横着居中，竖着**压住最上那一行**，别浮在头顶上方
            return CGPoint(x: midX - itemW / 2, y: 4 - itemH + 3)
        case "glasses":
            // 眼睛在第 5..7 行，镜框压在那一片上
            return CGPoint(x: midX - itemW / 2, y: 9)
        case "bowtie":
            return CGPoint(x: midX - itemW / 2, y: 15)
        case "scarf":
            // 围巾绕在脖子那一圈——比领结低一点、宽一点
            return CGPoint(x: midX - itemW / 2, y: 14)
        case "bag":
            // 背包**挂在身后偏一侧**，露出一半才看得出是背着的
            return CGPoint(x: CGFloat(bodyRight) - itemW * 0.55, y: 13)
        case "boots":
            // 贴着脚。图纸 23 行高，脚在最底下
            return CGPoint(x: midX - itemW / 2, y: 27 - itemH)
        default:
            return CGPoint(x: midX - itemW / 2, y: 12)
        }
    }

    /// 一件东西**该怎么拿**。
    ///
    /// 这是唯一需要为新家具填的一项：说清楚它是「拿着」还是「举着」、
    /// 能不能喝、能不能摇。动作本身不用再画。
    static func poses(for kind: FurnitureKind) -> [CarryPose] {
        let id = kind.id
        // 喝的
        if id.contains("wine") || id.contains("酒") {
            return [.hold, .sip, .swirl]
        }
        if id.contains("cola") || id.contains("coffee") || id.contains("tea")
            || id.contains("milk") || id.contains("drink") || id.contains("水") {
            return [.hold, .sip]
        }
        // 大件：举得动，但喝不了
        if kind.sprite.width >= 16 { return [.lift] }
        return [.hold]
    }
}
