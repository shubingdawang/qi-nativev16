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
            // 一格一格地画会在格与格之间留下发白的细线：
            // scale 不是整数的时候每个小方块的边落在半个像素上，
            // 抗锯齿把边缘画成半透明，两块挨着就透出一道缝——
            // 身上那些"线"就是这么来的。
            //
            // 所以**同一行里颜色一样的连续几格并成一条**再画，
            // 竖着再多铺出半个像素让上下两行压住彼此。
            // 这样整块身子是一片实心的，一条缝都没有。
            for y in 0..<sprite.height {
                var x = 0
                while x < sprite.width {
                    guard let c = sprite.color(x: x, y: y) else {
                        x += 1
                        continue
                    }
                    var run = 1
                    while x + run < sprite.width,
                          let next = sprite.color(x: x + run, y: y),
                          next == c {
                        run += 1
                    }
                    let rect = CGRect(x: CGFloat(x) * scale,
                                      y: CGFloat(y) * scale,
                                      width: CGFloat(run) * scale + 0.5,
                                      height: scale + 0.5)
                    context.fill(Path(rect), with: .color(tint ?? c))
                    x += run
                }
            }
        }
        .frame(width: CGFloat(sprite.width) * scale,
               height: CGFloat(sprite.height) * scale)
        .allowsHitTesting(false)
    }
}

// MARK: - clawd 本体

/// clawd 是 Claude 那只吉祥物。
///
/// 这一版**照饼饼给的豆画图纸一格一格抄下来的**，不是我自己想的：
/// 图纸 32 列 25 行，用到的是第 2~31 列、第 2~24 行，一共 510 颗豆——
/// 身子色 492 颗、眼睛黑色 18 颗，抄完对得上，说明没抄错。
///
///   · 身子    第 2~18 行 × 第 5~28 列，一整块
///   · 两只手  第 8~12 行，左边第 2~4 列、右边第 29~31 列
///   · 四条腿  第 19~24 行，第 5-7、10-12、21-23、26-28 列
///     （中间空一大段，所以是两条在左、两条在右）
///   · 眼睛    第 7~9 行，第 8-10 列和第 23-25 列，两个三格见方的黑块
///
/// 别的姿势都是在这张图上改眼睛或者挪手挪出来的，身子一格没动，
/// 所以换帧的时候它不会歪、不会跳。
enum ClawdSprites {

    static let palette: [Character: Color] = [
        "p": Color(hexString: "F2715F")!,   // 身子，图纸上那个珊瑚红
        "d": Color(hexString: "C9553F")!,   // 暗一档，闭着的眼睛用
        "k": Color(hexString: "000000")!,   // 眼睛，图纸上是纯黑
        "y": Color(hexString: "F0C040")!,   // 头顶那点小闪光
        "w": Color(hexString: "FFFFFF")!,   // 气泡
        "b": Color(hexString: "4A90D9")!    // 气泡里那个蓝点
    ]

    /// 睁着眼站着。这就是图纸原样，两只手各往外长了一格。
    static let idle = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 呼吸：整只往下沉一格，腿跟着收短一截
    static let breathe = PixelSprite([
        "................................",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 眨眼：三格高的眼睛只剩最下面一格
    static let blink = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "pppppppppppppppppppppppppppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 开心：眼睛眯起来，只剩下面两格
    static let happy = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 笑：眼睛留上下两道、中间亮着，像弯起来了
    static let smile = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "pppppppppppppppppppppppppppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 睡着：眼睛闭成一道暗色的缝
    static let sleep = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "pppppppppppppppppppppppppppppppp",
        "pppppppdddppppppppppppdddppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 在想事情：头顶冒小方块
    static let thinking = PixelSprite([
        ".......y........................",
        "..................y.............",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 想得更凶：小方块换个位置，看着像在冒
    static let thinking2 = PixelSprite([
        "..................y.............",
        ".......y........................",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 干活：左手抬起来、右手压下去
    static let working = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "pppppppkkkppppppppppppkkkppp....",
        "pppppppkkkppppppppppppkkkppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 换只手。两帧来回切就是在忙活。
    static let working2 = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppppppp",
        "....pppkkkppppppppppppkkkppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppp....",
        "pppppppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ], palette)

    /// 躲到边上：只露左半边身子和一只手
    static let peek = PixelSprite([
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....pppkkkpppppppp",
        "pppppppkkkpppppppp",
        "pppppppkkkpppppppp",
        "pppppppppppppppppp",
        "pppppppppppppppppp",
        "pppppppppppppppppp",
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....pppppppppppppp",
        "....ppp..ppp......",
        "....ppp..ppp......",
        "....ppp..ppp......",
        "....ppp..ppp......",
        "....ppp..ppp......",
        "....ppp..ppp......"
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
    /// 脚底下那团影子。摆在房间里要有，不然它像浮在半空；
    /// 输入框上蹲的那只太小，加了反而脏。
    var shadow: Bool = false

    @State private var frame = 0
    @State private var ticker: Task<Void, Never>?

    private var sprites: [(PixelSprite, Double)] { mood.frames }

    /// 睡着和呼吸那两帧整只往下沉了一格，影子跟着淡一点、扁一点
    private var settled: Bool { mood == .sleeping }

    var body: some View {
        ZStack(alignment: .bottom) {
            if shadow {
                let w = CGFloat(sprites[0].0.width) * scale
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [.black.opacity(settled ? 0.30 : 0.22), .black.opacity(0)],
                            center: .center, startRadius: 0, endRadius: w * 0.32)
                    )
                    .frame(width: w * 0.66, height: w * 0.15)
                    .offset(y: w * 0.05)
                    .blur(radius: 1.5)
                    .allowsHitTesting(false)
            }

            PixelSpriteView(sprite: sprites[min(frame, sprites.count - 1)].0, scale: scale)
        }
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
