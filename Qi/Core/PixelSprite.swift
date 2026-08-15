import SwiftUI

/// 像素精灵。
///
/// 关键决定：**不用图片文件，用文字把图画出来。**
///
/// 那个 clawd 的仓库标题写着「pure SVG + CSS keyframe animations」——
/// 也就是说它整只螃蟹是代码画的，不是图。这条路对我们太合适了：
///   · 一分钱不花，不用调任何模型
///   · 想改颜色改一个字母就行，不用重新生成
///   · 放多大都不糊，因为根本没有分辨率这回事
///   · 一件家具几百字节，几十件也就几 KB
///
/// 写法是一行一行的字符，每个字符对应调色板里一个颜色，
/// 点号是透明。看代码就能看出画的是什么，这点比一堆 png 强得多。
struct PixelSprite {
    /// 一行一行的像素，每个字符一格
    let rows: [String]
    /// 字符 → 颜色
    let palette: [Character: Color]

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    init(_ rows: [String], _ palette: [Character: Color]) {
        self.rows = rows
        self.palette = palette
    }

    func color(x: Int, y: Int) -> Color? {
        guard y < rows.count else { return nil }
        let row = Array(rows[y])
        guard x < row.count else { return nil }
        let ch = row[x]
        if ch == "." || ch == " " { return nil }
        return palette[ch]
    }
}

/// 把精灵画出来。整数倍缩放，像素才是方的。
struct PixelSpriteView: View {
    let sprite: PixelSprite
    /// 一格画多大
    var scale: CGFloat = 4
    /// 整体染个色，做剪影或者夜里的样子
    var tint: Color? = nil

    var body: some View {
        Canvas { context, _ in
            for y in 0..<sprite.height {
                for x in 0..<sprite.width {
                    guard let c = sprite.color(x: x, y: y) else { continue }
                    let rect = CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale,
                                      width: scale, height: scale)
                    context.fill(Path(rect), with: .color(tint ?? c))
                }
            }
        }
        .frame(width: CGFloat(sprite.width) * scale,
               height: CGFloat(sprite.height) * scale)
        .allowsHitTesting(false)
    }
}

// MARK: - clawd 本体

/// clawd 是只小螃蟹。
/// 几套姿势画在这儿，切着播就是动画——跟 CSS 关键帧一个道理，
/// 只是这边用 SwiftUI 的定时器换帧。
enum ClawdSprites {

    static let palette: [Character: Color] = [
        "p": Color(hexString: "C8805E")!,   // 身子，砖橘
        "d": Color(hexString: "A9664A")!,   // 暗一点，脚和边
        "k": Color(hexString: "1A1A1A")!,   // 眼睛
        "y": Color(hexString: "F0C040")!,   // 头顶那点小闪光
        "w": Color(hexString: "FFFFFF")!,   // 气泡
        "b": Color(hexString: "4A90D9")!    // 气泡里那个蓝点
    ]

    // clawd 是**螃蟹**，不是一块砖。
    //
    // 上一版把身子画成了一整块方板，左右各戳出一格当手——
    // 放大了看就是一块地砖上开了两个黑洞，谁都认不出是螃蟹。
    // 现在照螃蟹本来的样子重新排：
    //   · 顶上左右各**一只举起来的钳子**（两格宽、三格高，暗色描边）
    //   · 中间是壳，上窄下宽，眼睛是壳上挖的两个黑格
    //   · 壳底下**六条腿**，左三右三，一格宽
    // 所有帧统一 14 格宽，换帧的时候身子不会左右跳。

    /// 站着
    static let idle = PixelSprite([
        ".dd........dd.",
        "dppd......dppd",
        "dppd.pppp.dppd",
        ".ddppppppppdd.",
        "..pppppppppp..",
        "..pkkppppkkp..",
        "..pkkppppkkp..",
        "..pppppppppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 呼吸：整只往下沉一格
    static let breathe = PixelSprite([
        "..............",
        ".dd........dd.",
        "dppd......dppd",
        "dppd.pppp.dppd",
        ".ddppppppppdd.",
        "..pppppppppp..",
        "..pkkppppkkp..",
        "..pkkppppkkp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 眨眼：眼睛只剩一格高
    static let blink = PixelSprite([
        ".dd........dd.",
        "dppd......dppd",
        "dppd.pppp.dppd",
        ".ddppppppppdd.",
        "..pppppppppp..",
        "..pppppppppp..",
        "..pkkppppkkp..",
        "..pppppppppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 开心：眼睛弯成两个 ^，钳子举高
    static let happy = PixelSprite([
        "dppd......dppd",
        "dppd......dppd",
        ".dd..pppp..dd.",
        "..dppppppppd..",
        "..pppppppppp..",
        "..ppkppppkpp..",
        "..pkpkppkpkp..",
        "..pppppppppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 笑：眼睛照常，嘴角咧开一道
    static let smile = PixelSprite([
        ".dd........dd.",
        "dppd......dppd",
        "dppd.pppp.dppd",
        ".ddppppppppdd.",
        "..pppppppppp..",
        "..pkkppppkkp..",
        "..pkkppppkkp..",
        "..pppddddppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 在想事情：头顶冒小方块
    static let thinking = PixelSprite([
        ".......y......",
        "...y..........",
        ".dd........dd.",
        "dppd......dppd",
        "dppd.pppp.dppd",
        ".ddppppppppdd.",
        "..pppppppppp..",
        "..pkkppppkkp..",
        "..pkkppppkkp..",
        "..pppppppppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 想得更凶：小方块换个位置，看着像在冒
    static let thinking2 = PixelSprite([
        "...y..........",
        ".......y......",
        ".dd........dd.",
        "dppd......dppd",
        "dppd.pppp.dppd",
        ".ddppppppppdd.",
        "..pppppppppp..",
        "..pkkppppkkp..",
        "..pkkppppkkp..",
        "..pppppppppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 干活：右钳子砸下去
    static let working = PixelSprite([
        ".dd...........",
        "dppd.......dd.",
        "dppd.pppp.dppd",
        ".ddppppppppdd.",
        "..pppppppppp..",
        "..pkkppppkkp..",
        "..pkkppppkkp..",
        "..pppppppppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 换左钳子砸。两帧来回切就是在敲东西。
    static let working2 = PixelSprite([
        "...........dd.",
        ".dd.......dppd",
        "dppd.pppp.dppd",
        ".ddppppppppdd.",
        "..pppppppppp..",
        "..pkkppppkkp..",
        "..pkkppppkkp..",
        "..pppppppppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 躲到边上：只露半边身子、一只钳子和一只眼
    static let peek = PixelSprite([
        "......dd.",
        ".....dppd",
        "pppp.dppd",
        "ppppppdd.",
        "pppppppp.",
        "ppkkpppp.",
        "ppkkpppp.",
        "pppppppp.",
        "pppppppd.",
        ".d.d.d..."
    ], palette)

    /// 睡着：眼睛闭上，钳子垂下来
    static let sleep = PixelSprite([
        "..............",
        "..............",
        "dppd.pppp.dppd",
        "dddppppppppddd",
        "..pppppppppp..",
        "..pppppppppp..",
        "..pddppppddp..",
        "..pppppppppp..",
        "..pppppppppp..",
        "..dppppppppd..",
        ".d.d.d..d.d.d."
    ], palette)

    /// 头顶那个小气泡，说话的时候冒出来
    static let bubble = PixelSprite([
        ".wwwww.",
        "wwwwwww",
        "wwbwwww",
        "wwwwwww",
        ".wwwww.",
        "..ww...",
        "..w...."
    ], palette)
}

/// clawd 现在在干嘛
enum ClawdMood: String, Codable {
    case idle       // 待着
    case happy      // 被摸了
    case sleeping   // 睡了
    case peeking    // 躲在边上
    case thinking   // 他在想
    case working    // 他在动手做事
    case talking    // 他在说话

    /// 这个状态下轮播哪几帧、每帧停多久
    var frames: [(PixelSprite, Double)] {
        switch self {
        case .idle:
            // 大部分时候在呼吸，偶尔眨一下眼
            return [
                (ClawdSprites.idle, 1.4),
                (ClawdSprites.breathe, 1.1),
                (ClawdSprites.idle, 1.4),
                (ClawdSprites.blink, 0.16)
            ]
        case .happy:
            return [(ClawdSprites.happy, 0.35), (ClawdSprites.idle, 0.35)]
        case .sleeping:
            return [(ClawdSprites.sleep, 2.2), (ClawdSprites.breathe, 2.0)]
        case .peeking:
            return [(ClawdSprites.peek, 2.0), (ClawdSprites.peek, 2.0)]
        case .thinking:
            // 头顶那两个小方块交替冒，像在运算
            return [(ClawdSprites.thinking, 0.45), (ClawdSprites.thinking2, 0.45)]
        case .working:
            return [(ClawdSprites.working, 0.22), (ClawdSprites.working2, 0.22)]
        case .talking:
            return [(ClawdSprites.smile, 0.5), (ClawdSprites.idle, 0.4)]
        }
    }
}

/// 会动的 clawd
struct ClawdView: View {

    var mood: ClawdMood = .idle
    var scale: CGFloat = 4

    @State private var frame = 0
    @State private var ticker: Task<Void, Never>?

    private var sprites: [(PixelSprite, Double)] { mood.frames }

    var body: some View {
        PixelSpriteView(sprite: sprites[min(frame, sprites.count - 1)].0, scale: scale)
            .onAppear { start() }
            .onDisappear { ticker?.cancel() }
            .onChange(of: mood) { _, _ in
                frame = 0
                start()
            }
    }

    private func start() {
        ticker?.cancel()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                let hold = sprites[min(frame, sprites.count - 1)].1
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                if Task.isCancelled { return }
                frame = (frame + 1) % sprites.count
            }
        }
    }
}
