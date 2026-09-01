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
        ClawdRig.stripArms(frames[min(frame, frames.count - 1)].0)
    }

    /// 图纸一共多宽多高（格）
    private var cols: CGFloat { CGFloat(frames[0].0.width) }
    private var rows: CGFloat { CGFloat(frames[0].0.height) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 身子（手已经抠掉了）
            PixelSpriteView(sprite: body0, scale: scale)

            // 两只手
            arm(.left)
            arm(.right)

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
        PixelSpriteView(sprite: ClawdRig.arm, scale: scale)
            // 转的支点在肩膀那一端，不是手臂中间——
            // 从中间转的话整条手臂会从身子里穿出去
            .rotationEffect(.degrees(onLeft ? -angle : angle),
                            anchor: onLeft ? .trailing : .leading)
            .offset(x: (onLeft ? shoulderX - CGFloat(ClawdRig.arm.width) : shoulderX) * scale,
                    y: CGFloat(ClawdRig.armRow) * scale)
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

    /// 一只手。就是原来长在身子外面那一小块，抠出来单独画。
    ///
    /// ⚠️ **必须跟 `ClawdSprites.idle` 里那块一模一样：4 格宽、5 格高、
    /// 从第 10 行到第 14 行**（加高之后的行号）。 她说「手臂太细而且位置有点靠上」——
    /// 根子就是这儿只写了两行：身子那张图上的手是 6~10 行整整五格，
    /// 抠掉之后补上来的却是贴在第 6 行的两格。
    /// 于是手瘦了六成、整条往上提了一格半。
    ///
    /// 改这里之前先跑一遍：把 `idle` 的第 0..3 列和第 28..31 列打出来，
    /// 是 `p` 的那几行就是手该占的行。**别照着感觉调。**
    static let arm = PixelSprite([
        "pppp",
        "pppp",
        "pppp",
        "pppp",
        "pppp"
    ], ClawdSprites.palette)

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
            // 双手抬过头顶。**东西压在两只手中间的正上方**，
            // 不缩小——这是她要的「真正举着」。
            //
            // 手抬到 72 度：再高手臂就转到身子里去了，
            // 再低看着像在推，不像在举。
            let strain = sin(beat * .pi * 2) * 0.35     // 举久了会抖一下
            p.leftArm = 72 + strain
            p.rightArm = 72 + strain
            p.itemAt = CGPoint(x: midX - itemW / 2,
                               y: -itemH - 1.2 + strain * 0.15)

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
