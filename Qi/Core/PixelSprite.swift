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

    // ⚠️ **这三样是「造的时候算一次」，不是「用的时候现算」。**
    //
    // 她说「太卡了太卡了」，根子有一半在这儿。上一版 `color(x:y:)` 里
    // 写的是 `let row = Array(rows[y])`——**查一个像素，就把那一整行
    // 字符串重新拆成一个数组**。Swift 的 String 不能按下标取字符，
    // 所以那句话看着无害，实际是一次遍历 + 一次堆分配。
    //
    // 一件等距家具一百来列、八十来行，画一帧要查将近一万次；
    // 屋里摆十件，他还在走路（每一帧都重画）——
    // **一秒钟几百万次数组分配**，手机不卡才怪。
    //
    // 现在开局就把整张图摊成 `[Color?]` 的一维数组，
    // 之后每次查像素就是一次下标寻址，不分配、不遍历。
    // 画出来一模一样，代价差了三四个数量级。
    private let grid: [Color?]
    private let w: Int
    private let h: Int

    var width: Int { w }
    var height: Int { h }

    init(_ rows: [String], _ palette: [Character: Color]) {
        self.rows = rows
        self.palette = palette
        let hh = rows.count
        let ww = rows.map(\.count).max() ?? 0
        self.w = ww
        self.h = hh
        var g = [Color?](repeating: nil, count: max(0, ww * hh))
        for (y, row) in rows.enumerated() {
            // 这一行遍历一次就够了——**整个 App 生命周期里就这一次**
            for (x, ch) in row.enumerated() {
                guard x < ww else { break }
                guard ch != ".", ch != " " else { continue }
                g[y * ww + x] = palette[ch]
            }
        }
        self.grid = g
    }

    func color(x: Int, y: Int) -> Color? {
        guard x >= 0, y >= 0, x < w, y < h else { return nil }
        return grid[y * w + x]
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
        "b": Color(hexString: "4A90D9")!,   // 气泡里那个蓝点
        "c": Color(hexString: "8EC5FF")!,   // 眼泪
        "n": Color(hexString: "8B5E34")!,   // 扫把杆
        "t": Color(hexString: "C9A227")!,   // 扫把那撮稻草
        "r": Color(hexString: "FF9AA0")!    // 腮红
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

    /// 哭：眼睛闭成一条，泪刚涌出来
    static let cry1 = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "ppppppppcppppppppppppppcpppppppp",
        "ppppppppcppppppppppppppcpppppppp",
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

    /// 哭：那滴泪往下掉了两格
    static let cry2 = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "ppppppppcppppppppppppppcpppppppp",
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

    /// 扫地：扫头在左边
    static let sweep1 = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp..n.",
        "....pppppppppppppppppppppppp..n.",
        "....pppkkkppppppppppppkkkppp..n.",
        "pppppppkkkppppppppppppkkkpppppnp",
        "pppppppkkkppppppppppppkkkpppppnp",
        "ppppppppppppppppppppppppppppppnp",
        "ppppppppppppppppppppppppppppppnp",
        "ppppppppppppppppppppppppppppppnp",
        "....pppppppppppppppppppppppp..n.",
        "....pppppppppppppppppppppppp..n.",
        "....pppppppppppppppppppppppp.nn.",
        "....pppppppppppppppppppppppp.nn.",
        "....pppppppppppppppppppppppp.nn.",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "..ttppp..ppp........ppp..ppp....",
        ".tttttp..ppp........ppp..ppp....",
        "tttttttt.ppp........ppp..ppp...."
    ], palette)

    /// 扫地：扫头甩到右边。
    ///
    /// ⚠️ **两帧的差别要足够大。** 她报的：
    /// 「扫把很小很小，跟他本体不符合，太小导致动的幅度根本看不见，
    ///   我一直观察才发现扫把有在左右晃动，没有真的在扫地的感觉。」
    /// 以前扫头只有 4×2 格、两帧只差一格——那不叫扫地，叫抖了一下。
    /// 现在扫头横跨八格，一帧甩到左下、一帧甩到右下，隔着屏幕也看得出在扫。
    static let sweep2 = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp..n.",
        "....pppppppppppppppppppppppp..n.",
        "....pppkkkppppppppppppkkkppp..n.",
        "pppppppkkkppppppppppppkkkpppppnp",
        "pppppppkkkppppppppppppkkkpppppnp",
        "ppppppppppppppppppppppppppppppnp",
        "ppppppppppppppppppppppppppppppnp",
        "ppppppppppppppppppppppppppppppnp",
        "....pppppppppppppppppppppppp..n.",
        "....pppppppppppppppppppppppp..n.",
        "....pppppppppppppppppppppppp.nn.",
        "....pppppppppppppppppppppppp.nn.",
        "....pppppppppppppppppppppppp.nn.",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppptt..",
        "....ppp..ppp........ppp..pttttt.",
        "....ppp..ppp........ppp.tttttttt"
    ], palette)

    /// 甜：眯着眼笑，腮红。爱心是界面上飘的，不画进图纸
    static let sweet = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "pppppppdddppppppppppppdddppppppp",
        "pppppppppppppppppppppppppppppppp",
        "ppppprrpppppppppppppppppprrppppp",
        "ppppprrpppppppppppppppppprrppppp",
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

    /// 走路第一步：左边那两条腿抬起来。跟 walk2 交替就是在迈步，
    /// 不是原地翻个身就瞬移过去。
    static let walk1 = PixelSprite([
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
        ".........ppp.............ppp....",
        ".........ppp.............ppp...."
    ], palette)

    /// 走路第二步：换右边那两条腿抬
    static let walk2 = PixelSprite([
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
        "....ppp.............ppp.........",
        "....ppp.............ppp........."
    ], palette)

    /// 搬东西：两只手都放低到身前，像抱着一个箱子
    static let carry = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "....pppkkkppppppppppppkkkppp....",
        "....pppkkkppppppppppppkkkppp....",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
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

    // MARK: 探头（这一版：只画头）
    //
    // 她说了第三次：「聊天页探头这个之前的窗已经修过两三次了，
    // 都是半个身子藏在屏幕里，并不是探头。探头是指只探出头来，
    // 手可以挥动或者做其他动作。」
    //
    // 前两版都在调「往里挪多少点」——**那条路走不通**。
    // 他整只站在屏幕外、横着挪回来，露出来的必然是「从头到脚的一条竖边」，
    // 也就是半个身子。挪多挪少只是那条边宽窄的区别。
    //
    // 只探出头，得**从图上就只画头**：下面这两张里没有身子也没有腿，
    // 只有一颗脑袋和一只扒着边／挥着的手。这样露出来的就只可能是头。
    // 空格是透明的，所以身子不是被挡住——是根本不存在。

    /// 探头（一）：扒着边看
    static let peekHead1 = PixelSprite([
        "................................",
        "................................",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "....pppkkkppppppppppppkkkppp....",
        "....pppkkkppppppppppppkkkppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppp....",
        "..pppp..........................",
        "................................",
        "................................"
    ], palette)

    /// 探头（二）：手抬起来挥
    static let peekHead2 = PixelSprite([
        "..pppp..........................",
        "..pppp..........................",
        "..pppppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "....pppkkkppppppppppppkkkppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "................................",
        "................................",
        "................................",
        "................................"
    ], palette)

    /// 探头（一）：探出来的那一下。
    ///
    /// **这张图跟别的一样是整整 32 格宽的一只完整的他**，一格都没少。
    /// 上一版那张只画了十八格，等于把他从中间锯断——所以看着不是"探头"，
    /// 是"半个身子没了"。真正的探头得靠**屏幕边缘**去挡：
    /// 他整只站在屏幕外面，只往里挪十来个点，露出来的那一小条自然就是
    /// 一只眼睛和扒着边的那只手。
    ///
    /// 所以这张图上做了两件事，都是为了让**露出来的那一条**读得懂：
    ///   · 只留靠外那一只眼睛（另一只在屏幕外，看不见也不用画）
    ///   · 那只手抬到高处，像扒着墙沿探身子
    static let peek1 = PixelSprite([
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "pppppppppppppppppppppppppppp....",
        "pppppppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkpppppppppppppppppp....",
        "....pppkkkpppppppppppppppppp....",
        "....pppkkkpppppppppppppppppp....",
        "....pppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppppppp",
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

    /// 探头（二）：探出来之后没站住，往下缩一格、手也放下来。
    /// 跟 peek1 来回换，配上位置上那一点点进退，看着就是在探头探脑，
    /// 不是一张钉死的静态图。
    static let peek2 = PixelSprite([
        "................................",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkpppppppppppppppppp....",
        "pppppppkkkpppppppppppppppppppppp",
        "pppppppkkkpppppppppppppppppppppp",
        "....pppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppppppp",
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
        "................................"
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
    case walking    // 正在走路（迈步，不是瞬移）
    case carrying   // 手上抱着东西站着
    case hauling    // 抱着东西在走
    /// 这一轮出错了，垮一下。
    /// 出处：clawd-on-desk 的 12 个状态里那个 error——
    /// **他那边出事，屋里这只不该还在傻笑。**
    case upset
    /// 被连着戳了好几下，甩手抗议
    case flail

    /// 犯困到睡着之间那一段。clawd-on-desk 的睡眠序列是
    /// 打哈欠 → 打盹 → 瘫 → 睡；我们的帧没那么多，
    /// 走「困」这一档（慢慢眨、越眨越久）再进 sleeping。
    case drowsy

    // MARK: 跟着阿晏的那三档
    //
    // 她说的：「当阿晏跟我在聊天时，他可以表达阿晏所表达的——
    // 阿晏伤心他就在哭，阿晏在做游戏或者处理文件他就在打电脑，
    // 阿晏只是正常聊天他就做自己的事，阿晏开心他也开心，
    // 阿晏感觉到甜蜜他就冒爱心。」
    //
    // 数据是现成的：`EmotionEngine` 那两个数（valence 舒不舒服、
    // arousal 有多激动）本来就在算，这儿只是**把它画出来**。

    /// 他难过。眼睛闭成一条，泪一滴一滴掉
    case crying
    /// 他甜。眯着眼笑、腮红，头顶飘爱心
    case loving
    /// 扫地。**「做自己的事」里的一种**——
    /// 她指名要的那只扫地的 clawd 就是这个
    case sweeping

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
        case .walking:
            // 0.16 秒换一次脚。再慢就看着像在滑，再快腿会糊成一团。
            return [(ClawdSprites.walk1, 0.16), (ClawdSprites.walk2, 0.16)]
        case .carrying:
            return [(ClawdSprites.carry, 1.2), (ClawdSprites.idle, 0.9)]
        case .hauling:
            // 抱着东西走：手一直端着，所以只有腿在换
            return [(ClawdSprites.walk1, 0.19), (ClawdSprites.carry, 0.19)]
        case .sleeping:
            return [(ClawdSprites.sleep, 2.2), (ClawdSprites.breathe, 2.0)]
        case .peeking:
            // ⚠️ **换回整只**（`peek1`/`peek2`）。
            //
            // 上一版改成了「只有头的那两张」，又把露出来的宽度
            // 撑到很小，于是她看到的是四格颜色——
            // 她的原话：「现在的 clawd 在侧边探头只剩下四格了，
            // 并不是字面意义上的探头。」
            //
            // 她还画了一张给我看：**一只完整的 clawd，被屏幕边切掉一截**。
            // 那才是探头——认得出是他，才叫探头；
            // 认不出是谁的那四格，只是一条色边。
            //
            // 两帧手的位置不同，看着就是扶着墙在挥。
            return [(ClawdSprites.peek1, 0.9), (ClawdSprites.peek2, 0.7)]
        case .thinking:
            // 头顶那两个小方块交替冒，像在运算
            return [(ClawdSprites.thinking, 0.45), (ClawdSprites.thinking2, 0.45)]
        case .working:
            return [(ClawdSprites.working, 0.22), (ClawdSprites.working2, 0.22)]
        case .talking:
            return [(ClawdSprites.smile, 0.5), (ClawdSprites.idle, 0.4)]
        case .upset:
            // 垮着。眨眼那帧当「闭眼低头」用，停久一点
            return [(ClawdSprites.blink, 1.2), (ClawdSprites.idle, 0.5)]
        case .flail:
            // 抓狂：两只手甩得飞快。借走路那两帧，把时间压到最短
            return [(ClawdSprites.walk1, 0.07), (ClawdSprites.walk2, 0.07)]
        case .drowsy:
            // 越眨越久，最后就睡过去了
            return [(ClawdSprites.idle, 1.0), (ClawdSprites.blink, 0.55),
                    (ClawdSprites.breathe, 1.6), (ClawdSprites.blink, 0.9)]
        case .crying:
            // 一滴泪涌出来、往下掉，再一滴。**慢**——
            // 哭得太快看着像抽搐，不像难过
            return [(ClawdSprites.cry1, 0.8), (ClawdSprites.cry2, 0.7)]
        case .loving:
            return [(ClawdSprites.sweet, 1.1), (ClawdSprites.happy, 0.5)]
        case .sweeping:
            return [(ClawdSprites.sweep1, 0.4), (ClawdSprites.sweep2, 0.4)]
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
    /// 爱心飘起来没有
    @State private var hearts = false

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

            // 甜的时候头顶飘爱心。
            //
            // **不画进图纸**：图纸只有 32×23，身子占满了，
            // 心画进去只能替掉身上的豆子，看着像破了个洞。
            // 飘在外面才是「冒出来的」。
            if mood == .loving {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        JournalStickerShape(kind: "heart")
                            .fill(Color(hexString: "FF6B81") ?? .pink)
                            .frame(width: scale * 3.5, height: scale * 3.5)
                            .offset(x: CGFloat(i - 1) * scale * 5,
                                    y: hearts ? -scale * 11 : -scale * 5)
                            .opacity(hearts ? 0 : 0.9)
                            .animation(
                                .easeOut(duration: 1.6)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.5),
                                value: hearts)
                    }
                }
                .allowsHitTesting(false)
                .onAppear { hearts = true }
                .onDisappear { hearts = false }
            }
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

/// 精灵**画出来的那些格子**围成的形状。
///
/// 拿来当 `.contentShape` 用：这样只有真的画了东西的地方才接触摸，
/// 透明的边角不再抢点击。
///
/// 为什么需要它（她报的第 9 条）：
/// > 我并不能自由拖动 clawd 小屋里的家具，当床和小桌同时在时，
/// > 我不管是点击小桌还是长按小桌，都只能移动床。
///
/// 家具是一张张矩形的精灵图，**透明的地方也算在矩形里**。
/// 一张床的图很大，四角都是空的；小桌摆在床的空角上，
/// 看着没挨着，实际整个盖在床的矩形里面。
/// 谁画在上面谁接管那一整块矩形，于是永远是床赢。
///
/// 按格子围形之后，床的空角不再接触摸，点小桌就是点小桌。
struct SpriteHitShape: Shape {

    let sprite: PixelSprite

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = max(sprite.width, 1), h = max(sprite.height, 1)
        let cw = rect.width / CGFloat(w)
        let ch = rect.height / CGFloat(h)
        for y in 0..<h {
            var x = 0
            while x < w {
                guard sprite.color(x: x, y: y) != nil else { x += 1; continue }
                // 同一行里连着的几格并成一条，省下大量子路径
                var run = 1
                while x + run < w, sprite.color(x: x + run, y: y) != nil { run += 1 }
                p.addRect(CGRect(x: rect.minX + CGFloat(x) * cw,
                                 y: rect.minY + CGFloat(y) * ch,
                                 width: cw * CGFloat(run),
                                 height: ch))
                x += run
            }
        }
        return p
    }
}
