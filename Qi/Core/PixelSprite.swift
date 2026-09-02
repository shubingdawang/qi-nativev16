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
        "p": Color(hexString: "F2715F")!,
        "k": Color(hexString: "000000")!,
        "u": Color(hexString: "7A2230")!,   // 嘴
        "G": Color(hexString: "0C1018")!,
        "g": Color(hexString: "23272F")!,
        "h": Color(hexString: "2F343D")!,   // 笔记本亮一档
        "v": Color(hexString: "BD93F9")!,   // 代码紫
        "i": Color(hexString: "8CE9FD")!,   // 代码青
        "j": Color(hexString: "50FA7B")!,   // 代码绿
        "l": Color(hexString: "F1FA8C")!,   // 代码黄
        "m": Color(hexString: "FF79C6")!,   // 代码粉
        "w": Color(hexString: "F8F8F2")!,
        "a": Color(hexString: "3E5C8A")!,
        "e": Color(hexString: "153F1B")!,
        "f": Color(hexString: "6FB3C9")!,
        "o": Color(hexString: "C2693F")!,
        "q": Color(hexString: "473B59")!,
        "s": Color(hexString: "6E8FC4")!,
        "x": Color(hexString: "3F7FD0")!,
        "z": Color(hexString: "6B4420")!,
        "A": Color(hexString: "4A6FA5")!,
        "B": Color(hexString: "E91E63")!,
        "C": Color(hexString: "6A5AD0")!,
        "D": Color(hexString: "F5E6C8")!,
        "E": Color(hexString: "FF1744")!,
        "F": Color(hexString: "4FB564")!,
        "H": Color(hexString: "8FD0E2")!,
        "I": Color(hexString: "C9A227")!,
        "J": Color(hexString: "FFD14A")!,
        "K": Color(hexString: "4AD5FF")!,
        "L": Color(hexString: "8A5A2A")!,
        "M": Color(hexString: "FF5C8D")!,
        "N": Color(hexString: "2E7D32")!,
        "O": Color(hexString: "4AD5FF")!,
        "P": Color(hexString: "4AD5FF")!,
        "Q": Color(hexString: "FF5C8D")!,
        "R": Color(hexString: "2E7D32")!,
        "d": Color(hexString: "C9553F")!,
        "S": Color(hexString: "E2A08E")!,
        "T": Color(hexString: "9172C1")!,
        "U": Color(hexString: "BBA07D")!,
        "V": Color(hexString: "A784DE")!,
        "W": Color(hexString: "8B9258")!,
        "X": Color(hexString: "AEC0E1")!,
        "Y": Color(hexString: "EFC7BA")!,
        "Z": Color(hexString: "3F9A52")!,
        "0": Color(hexString: "9172C1")!,
        "1": Color(hexString: "AE6B56")!,
        "2": Color(hexString: "D98B6F")!,
        "3": Color(hexString: "A784DE")!,
        "4": Color(hexString: "304D58")!,
        "5": Color(hexString: "388E3C")!,
        "6": Color(hexString: "F7314D")!,
        "7": Color(hexString: "DF886D")!,
        "8": Color(hexString: "DF886E")!,
        "9": Color(hexString: "5074A9")!,
        "y": Color(hexString: "F0C040")!,   // 头顶那点小闪光
        "b": Color(hexString: "4A90D9")!,   // 气泡里那个蓝点
        "c": Color(hexString: "8EC5FF")!,   // 眼泪
        "n": Color(hexString: "8B5E34")!,   // 扫把杆
        "t": Color(hexString: "C9A227")!,   // 扫把那撮稻草
        "r": Color(hexString: "FF9AA0")!   // 腮红
    ]

    /// 睁着眼站着。这就是图纸原样，两只手各往外长了一格。
    static let idle = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 哭：眼睛闭成一条，泪刚涌出来
    static let cry1 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 哭：那滴泪往下掉了两格
    static let cry2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppuuuuppppppppppppp....",
        "......pppppppppuuuuppppppppp........",
        "......pppppppppuuuuppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    // MARK: 扫地
    //
    // ⚠️⚠️ 这四帧是 `scripts/画扫地.py` 算出来的，**别手改**。
    // 手打 3×23 行像素，错一格就是扫把插进腿里，看图看不出来。
    //
    // ## 上一版错在哪儿
    //
    // 她报的：「聊天页的 clawd 扫地的时候是一只手上拿着棍子（扫把的柄），
    // 下面黄色的自己在左右动，根本不是扫地。做动作是要连接上身体的，
    // 不是一直让 clawd 保持直挺挺的。」
    //
    // 她说得一点没错，去数一下那两帧就看得见：
    //   · **杆（`n`）在两帧里一格都没动**——都钉在第 29..31 列那条竖线上
    //   · **稻草（`t`）从最左边瞬移到最右边**——中间隔着整个身子
    //   · **身子两帧一模一样**——一根手指头都没动
    //
    // 也就是说那根本不是一把扫把：是一根杵着不动的棍子，
    // 外加一块自己在地上左右横跳的黄色。
    //
    // ## 现在这版
    //
    //   · 杆是**一条真的斜线**，上头在手里、下头连着稻草。
    //     扫到哪儿，杆就斜到哪儿——这是「连着」的意思。
    //   · 稻草接在杆的下端，跟着杆走，不再自己动。
    //   · **身子跟着倾**（上半身左右，腿钉在地上不动）：
    //     人扫地是上半身在带，脚是不挪的。
    //   · 四帧走「左-中-右-中」一个来回，不是两帧左右跳。
    //     两帧的话眼睛只看得见「弹」，看不见「扫」。

    /// 扫地：甩到左边，身子跟着往左倾
    static let sweep1 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 扫地：扫到中间，身子直起来
    static let sweep2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 扫地：甩到右边，身子往右倾
    static let sweep3 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 扫地：收回中间。跟第二帧同一个姿势，所以一个来回是「左-中-右-中」，不是左右跳
    static let sweep4 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 甜：眯着眼笑，腮红。爱心是界面上飘的，不画进图纸
    static let sweet = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "..............................BB....",
        "..........................BBBBBBB...",
        "..........................BBpppBB...",
        "..........................BBpppBB...",
        "..........................BBpppBB...",
        "..........................BBBBBBB...",
        "...........................BBBB.....",
        "....................................",
        "....................................",
        "......ppppppppppppppppppppp.........",
        "......pppppppppppppppppppppp........",
        "......ppppppppppppppppppppp.........",
        "......pppppppppppppppppppppp.p.p....",
        "......pppEpEpppppppppEpEpppppp.p....",
        "......pppEpEppppppppBEEEpppppppp....",
        "..pppppppEEEpppppppppEEEpppppppp....",
        "..pppppppEEEpppppppppEEEpppppppp....",
        "..pppppppBBBpppppppppppppppp........",
        "..pppppppppppppppppppppppppp........",
        "..pp..pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 呼吸：整只往下沉一格，腿跟着收短一截
    static let breathe = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 眨眼：三格高的眼睛只剩最下面一格
    static let blink = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 开心：眼睛眯起来，只剩下面两格
    static let happy = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "..pppppppppppppppppppppppppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "......ppppkkppppppppppkkpppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppuuuuppppppppp........",
        "......pppppppppuuuuppppppppp........",
        "......pppppppppuuuuppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 笑：眼睛留上下两道、中间亮着，像弯起来了
    static let smile = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppuuuuppppppppppppp....",
        "......pppppppppuuuuppppppppp........",
        "......pppppppppuuuuppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 睡着：眼睛闭成一道暗色的缝
    static let sleep = PixelSprite([
        "....................................",
        ".................AAAAAA.............",
        ".............AAAAAAAAAAAA...........",
        "............AAAAAAAAAAAAAwwww.......",
        "...........AAAAAAAAAAAAAwwwwww......",
        ".........AAAAAAAAAAAAAAAwwwwww......",
        ".........AAAAAAA.....AAAwwwwww......",
        "........AAAA............wwwwww......",
        "........AA...............wwww.......",
        "........A...........................",
        ".......A............................",
        "......AAAAAAAAAAAAAAAAAAAAA.........",
        ".....AAAAAAAAAAAAAAAAAAAAAAA........",
        ".....aaaaaaaaaaaaaaaaaaaaaaa........",
        ".....aaaaaaaaaaaaaaaaaaaaaaa........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        ".wwwwwppppppppppppppppppppppwww.....",
        "wwpppppppkkkkppppppppkkkkpppppppww..",
        "wwppppppppppppppppppppppppppppppw...",
        "wwppppppppppppppppppppppppppppppww..",
        "wwppppppppppppppppppppppppppppppww..",
        "wwwwwwppppppppppppppppppppppwwwwww..",
        "wwwwwwppppppppppssppppppppppwwwwww..",
        "ssssssssssssssssssssssssssssssssssss",
        "sssssssssAAAAAaaaaaaAAAAAsssssssssss",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "qqqqqqqqaaaaaaaaaaaaaaaaaaqqqqqqqqqq",
        "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
    ], palette)

    /// 在想事情：头顶冒小方块
    static let thinking = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 想得更凶：小方块换个位置，看着像在冒
    static let thinking2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 干活：左手抬起来、右手压下去
    static let working = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pggggggggggggggggggggggggggghp....",
        "..pggGGGGGGGGGGGGGGGGGGGGGGGGggp....",
        "...ggGmmmmGGGGGhiiiiigGGGGGGGgg.....",
        "...ggGmmmmGGGGGjiiiiihGGGGGGGgg.....",
        "...ggGGGhhhhhGGGGGGpppppGGGGGgg.....",
        "...ggGGGjjjjjGGGGGGlllllGGGGGgg.....",
        "...ggGGGGGGGGGGGGGGGGGGGGGGGGgg.....",
        "...ggGvvvvvvvGlGGGGGGGGGGGGGGgg.....",
        "...ggGGGGGGGGGhGGGGGGGGGGGGGGgg.....",
        "...gggggggggggggggggggggggggggg.....",
        ".hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh....",
        ".hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh....",
        "........gggggggggggggggggg..........",
        "...................................."
    ], palette)

    /// 换只手。两帧来回切就是在忙活。
    static let working2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pggggggggggggggggggggggggggggp....",
        "..pggGGGGGGGGGGGGGGGGGGGGGGGGggp....",
        "...ggGmmmmGGGGGfiiiiihGGGGGGGgg.....",
        "...ggGmmmmGGGGGhfffffgGGGGGGGgg.....",
        "...ggGGGjjjjjjjjjjGlllllGGGGGgg.....",
        "...ggGGGjjjjjjjjjjGlllllGGGGGgg.....",
        "...ggGgggggggGhGGGGGGGGGGGGGGgg.....",
        "...ggGvvvvvvvGlGGGGGGGGGGGGGGgg.....",
        "...ggGGGGGGGGGGGGGGGGGGGGGGGGgg.....",
        "...gggggggggggggggggggggggggggg.....",
        ".hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh....",
        ".hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh....",
        "....................................",
        "...................................."
    ], palette)

    /// 走路第一步：左边那两条腿抬起来。跟 walk2 交替就是在迈步，
    /// 不是原地翻个身就瞬移过去。
    static let walk1 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 走路第二步：换右边那两条腿抬
    static let walk2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 搬东西：两只手都放低到身前，像抱着一个箱子
    static let carry = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
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
    /// 探头（一）：探出来的那一下。
    ///
    /// **这张图跟别的一样是整整 40 格宽的一只完整的他**，一格都没少。
    /// 上一版那张只画了十八格，等于把他从中间锯断——所以看着不是"探头"，
    /// 是"半个身子没了"。真正的探头得靠**屏幕边缘**去挡：
    /// 他整只站在屏幕外面，只往里挪十来个点，露出来的那一小条自然就是
    /// 一只眼睛和扒着边的那只手。
    ///
    /// 所以这张图上做了两件事，都是为了让**露出来的那一条**读得懂：
    ///   · 只留靠外那一只眼睛（另一只在屏幕外，看不见也不用画）
    ///   · 那只手抬到高处，像扒着墙沿探身子
    static let peek1 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 探头（二）：探出来之后没站住，往下缩一格、手也放下来。
    /// 跟 peek1 来回换，配上位置上那一点点进退，看着就是在探头探脑，
    /// 不是一张钉死的静态图。
    static let peek2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppppppp....",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 头顶那个小气泡，说话的时候冒出来
    // MARK: 从 gallery 扒来的

    /// 打游戏时头顶上方那台显示器。**跟身体不连，所以不在主图纸里**
    static let gameScreen = PixelSprite([
        "....................................",
        ".GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG.",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGKKGGGGGGGGGGGGGGgGGGGGGG",
        "GGGGGGGGGGGGKKGGGGGGGGGGGGGgKKGGGGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGgGGGGGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGgKKKKGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGgKKKKGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGgKKKKGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGgKKKKGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGeeeeeeeeeeeeeeeeeeeggggeeeeeeeGGG",
        "GGGeeeeeeeeeeeeeeeeeeeggggeeeeeeeGGG",
        "GGGeeeeeeeeeeeeeeeeeeeggggeeeeeeeGGG",
        "GGGeeeeeeeeeeeeeeeeeeeggggeeeeeeeGGG",
        "GGGeeeeeeeeeeeeeeeeeeeggggeeeeeeeGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        ".GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG.",
        "................GGGGG...............",
        "................GGGGG...............",
        "................GGGGG...............",
        "................GGGGG...............",
        ".........GGGGGGGGGGGGGGGGGG.........",
        "..........GGGGGGGGGGGGGGGGG........."
    ], palette)

    /// 举玫瑰（二）
    static let sweet2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "............................BB......",
        "............................BBBBBB..",
        "............................BpppBB..",
        "...........................BBpppBB..",
        "...........................BBpppBB..",
        "............................BBBBBB..",
        "..............................BBB...",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppppppppppppppppppppp.......",
        "......ppBBpppppppppppppppppp........",
        "......ppEEpEBppppppppEEpEEpppp.p....",
        "......ppEEEEBppppppppEEBEEpppp.p....",
        "..ppppppEEEEpppppppppEEEEEpppppp....",
        "..pppppppEEBppppppppppBEEppppppp....",
        "..ppppppppppppppppppppBEBppppppp....",
        "....pppppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 弹吉他（二）
    static let guitar2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "...z................................",
        ".zzoz...............................",
        "zzzpzz..............................",
        "zppppp..............................",
        "zppppp..............................",
        ".pppppz.............................",
        "..ppoozz............................",
        ".....zzzz...........................",
        "......zzzz..........................",
        "......pzzooppppppppppppppppp........",
        "......pozozzpppppppppppppppp........",
        "......pppzzzzppppppppppppppp........",
        "......pppozzozpppppppppppppp........",
        "......ppppGpzzzpppppppkkpppp........",
        "......ppppkGzzzpppppppkkpppp........",
        "......ppppkkozpzzpppppkkpppp........",
        "......ppppkkppzzzzpppoGkpppp........",
        "......ppppppppozzzoooooooppp........",
        "......pppppppppoooooooooooop........",
        "......pppppppppoooopppppooop........",
        "......pppppppppooozpppppoooo........",
        "......ppppppppoooopppppooooo........",
        "......ppppppppoooozppppooooo........",
        "........pp..ppoooozGGzoooooo........",
        "........pp..pp.ooooooooooooo........",
        "........pp..pp.oooooozzzzoo.........",
        "........pp..pp..ooooooooooo.........",
        ".................zooooooo...........",
        "...................Gzzz.............",
        "....................................",
        "...................................."
    ], palette)

    /// 弹吉他（一）
    static let guitar = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "..zzz...............................",
        ".zzpo...............................",
        "zzpppp..............................",
        "zppppp..............................",
        ".zppppz.............................",
        "..ppppzz............................",
        ".....zzzz...........................",
        "......zzzz..........................",
        "......ozzzpppppppppppppppppp........",
        "......pozpzzpppppppppppppppp........",
        "......ppozzzoppppppppppppppp........",
        "......pppozzpzpppppppppppppp........",
        "......ppppzozzzpppppppkkpppp........",
        "......ppppkzzzzpppppppkkpppp........",
        "......ppppkkzzozopppppkkpppp........",
        "......ppppkkpozzzoppppkkpppp........",
        "......ppppooppzzzzoooooopppp........",
        "......pppppppppzoooooooooopp........",
        "......pppppppppoooooooooooop........",
        "......pppppppppooozGGoooooop........",
        "......ppppppppooooGGGzoppooo........",
        "......ppppppppooooGGoppppooo........",
        "........pp..ppooooGGoppppooo........",
        "........pp..pp.ooooooppppooo........",
        "........pp..pp.ooooooppozoo.........",
        "........pp..pp.oooooozzzzoo.........",
        "................zooooooooz..........",
        "..................zoooook...........",
        "....................................",
        "...................................."
    ], palette)

    /// 打游戏（二）
    static let gaming2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        ".......pppppppppppppppppppp.........",
        "......ppppppppppppppppppppp.........",
        "......ppppppppppppppppppppp.........",
        "......ppppppppppppppppppppp.........",
        "......pppppqpppppppppqkGpppppp......",
        "...pp.pppqkGpppppppppqkGppppppp.....",
        "..ppppppppkkppppppppppkkpppppppp....",
        ".pppppppppkkppppppppppqqppppppp.....",
        "...ppppppppppppppppppppppppppp......",
        "....p.ppqhhhhhhhhhhhhhhhhhqp........",
        "......phhhhqhhhhhhhqpphhhghp........",
        "......pgggqqqhgggggppppJqhgp........",
        "......pgggqqqhgggggqppJJJghp........",
        "......pqgggqhgggggggggqJhhpp........",
        "........phhhqqgg....pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 打游戏（一）
    static let gaming = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "....p.ppppggppppppppppggpppp.p......",
        "...pppppppkkppppppppppkkppppppp.....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "...pppppppkkppppppppppkkppppppp.....",
        "...ppppppppppppppppppppppppppp......",
        "......pqhhhqqhhhhhhppphhhhqp........",
        "......pqhhhqqhhhhhhppphhhhqp........",
        "......pgggqqqqggggggqhpppggp........",
        "......phgggqhgggggggggpppghp........",
        "......ppggghhggggggggghphgpp........",
        "........pqggqqggggggqqggqp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 浇花（二）
    static let watering2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "...............................fff..",
        "..............................ffffff",
        ".............................ff.HHHH",
        "............................ffHHHHHH",
        "...........................HHHHHHHff",
        "..........................HHHHffffff",
        "...........................fffffffff",
        "...........................fffffffff",
        "......pppppppppppppppppppppfffffffff",
        "......pppppppppppppppHpppppfffffffff",
        "......pppppppppppppHHHppppppfffff...",
        "......ppppkkpppppppHHHffffff........",
        "......ppppkkppppppppHfffffff........",
        "......ppppkkppppppppppkkpppp........",
        "..ppppppppkkppppppppppfFpppppppp....",
        "..ppppppppooppppppppppfFpppppppp....",
        "..ppppppppppppppppppppmmpppppppp....",
        "......pppppppppppppppmmpmppp........",
        "......ppppppppppppFFFmppmpFF........",
        "......pppppppppppFFFFmppmFFFF.......",
        "......pppppppppppFFFFpmmpFFFF.......",
        "......pppppppppppFFFppFFfpFFF.......",
        "........pp..pp...ooooooooooooo......",
        "........pp..pp...ooooooooooooo......",
        "........pp..pp....ooooooooooo.......",
        "........pp..pp....ooooooooooo.......",
        "..................oooooooooo........",
        "..................oooooooooo........",
        "..................oooooooooo........",
        "...................................."
    ], palette)

    /// 浇花（一）
    static let watering = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        ".................................fff",
        "................................ffff",
        "...............................ff...",
        ".............................HHHHHHH",
        "............................HHHHHHHH",
        ".............................fffffff",
        "......pppppppppppppppppppppp.fffffff",
        "......ppppppppppppppHHHppppp.fffffff",
        "......ppppppppppppppHHHfpppp.fffffff",
        "......pppppppppppppppHHfffffffffffff",
        "......ppppkkpppppppppffffffff.f.....",
        "......ppppkkppppppppppkkpppff.......",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppkkppppppppppkkpppppppp....",
        "..ppppppppooppppppppppmmHppppppp....",
        "..pppppppppppppppppppmpmmFFppppp....",
        "......pppppppppppppFpmppmFFF........",
        "......ppppppppppppFFFmppmFFFF.......",
        "......pppppppppppFFFFpmmpFFFF.......",
        "......pppppppppppFFFFfFFpppp........",
        "........pp..pp..pooooooooooooo......",
        "........pp..pp...ooooooooooooo......",
        "........pp..pp....ooooooooooo.......",
        "........pp..pp....ooooooooooo.......",
        "..................oooooooooo........",
        "..................oooooooooo........",
        "..................oooooooooo........",
        "...................................."
    ], palette)

    /// 听音乐（二）
    static let listening2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        ".................g..................",
        "............ggggggggggg.............",
        ".........hggggggggggggggg...........",
        "........gggggggg..hgggggggg.........",
        "......gggggg...........ggggg........",
        ".....ggggg..............ggggg.......",
        "....ggggg.................gggg......",
        "....hgg....................gggg.....",
        "...hhhppppppppppppppp.......ggg.....",
        "..hhhhhppppppppppppppppppppp.hhh....",
        "..hCCChppppppppppppppppppppphhCCh...",
        "..hCCChppppppppppppppppppppphCCCh...",
        "..hCCChpppkkpppppppppppppppphCCCh...",
        "..hCCChpppkkppppppppppkkpppphCCCh...",
        "..hhhhppppkkppppppppppkkpppphCCCh...",
        "..phhhppppkkppppppppppkkpppphhhhh...",
        "..ppppppppppppppppppppphpppppppp....",
        ".....pppppppppppppppppppppppppppp...",
        "......pppppppppppppppppppppp.p......",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp.ppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        ".....................p..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 听音乐（一）
    static let listening = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        ".............ggggggg................",
        "..........ggggggggggggg.............",
        "........hgggggggggggggggg...........",
        ".......gggggg.......hgggggg.........",
        "......ggggg...........gggggg........",
        "....ggggg...............gggggg......",
        "...ggggg..................gggg......",
        "...gggg....................gg.......",
        "...gghppppppppppppppppppppphhhhh....",
        ".hhhhpppppppppppppppppppppphCCCh....",
        ".hhChhppppppppppppppppppppphCCCh....",
        ".hCCChppppppppppppppppppppphCCCh....",
        ".hCCChpppgkhpppppppppkkhppphCCCh....",
        ".hCCChpppkkgpppppppppgkgppphCCCh....",
        ".hCCChppphkgppppppppphkgpppphhhh....",
        ".hhhhhppphkgppppppppphkgpppppppp....",
        "..pppppppphppppppppppppppppppppp....",
        "..pppppppppppppppppppppppppp........",
        "..pppppppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppp.pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........g...........................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 画画（二）
    static let painting2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "........................o...........",
        ".......................oo...........",
        ".......................o............",
        "......................oo............",
        "......................oo............",
        "......pppppppppppppppooppppp........",
        "......pppppppppppppppooppppp........",
        "......pppppppppppppppopppppp........",
        "......ppppkkppppppppookkpppp........",
        "......ppppkkppppppppookkpppp........",
        "......ppppkkpppppppoopkkpppp.ppp....",
        "ppppppppppkkpppppppoopkkpppppppp....",
        "pJJpppppppoopppppppoppoopppppppp....",
        "JJJppppppppppppppppppppppppppppp....",
        "pJpppppppppppppppppppppppppp........",
        "kppppppppppppppppppppppppppp........",
        "kppppppppppppppppppppppppppp........",
        "opppp.pppppppppppppppppppppp........",
        "pppp..pppppppppppppppppppppp........",
        "ppp.....pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 画画（一）
    static let painting = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "...............pp..oo...............",
        "...............ppp.oo...............",
        "......pppppppppppppooppppppp........",
        "......pppppppppppppooppppppp........",
        "......pppppppppppppooppppppp........",
        "......pppppppppppppooppppppp........",
        "......ppppkkpppppppoopkkpppp........",
        "......ppppkkpppppppoopkkppppppp.....",
        "..ppppppppkkpppppppoopkkpppppppp....",
        "pJppppppppkkpppppppoopkkpppppppp....",
        "JJJppppppppppppppppoopppppppppp.....",
        "JJJppppppppppppppppooppppppp........",
        "pppppppppppppppppppooppppppp........",
        "kppppppppppppppppppooppppppp........",
        "kppppppppppppppppppppppppppp........",
        "ppppp.pppppppppppppppppppppp........",
        "pppp....pp..pp......pp..pp..........",
        "pp......pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 吃东西（二）
    static let eating2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "......pppDkkppppppppppkkpppppppp....",
        "......pppDkkppppppppppkkpppppppp....",
        "..pp..pppDpppppppppppppppppppppp....",
        ".ppppppppDDwwwwDpppppppppppppp......",
        ".ppppppDwwwwwwwwwwDpppppppppII......",
        ".pppppDwwwwwwwwwwwwxpppppIIII.......",
        "...pppxDwwwwwwwwwwxxpIIIIppp.II.....",
        "....p.pxxxxDDDDxxxxIIIppppIII.......",
        ".......xxxxxxxxxxxp.pp.III..........",
        "........xxxxxxxxxx.III..pp..........",
        "........ppxxxxxxpIIIpp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 吃东西（一）
    static let eating = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppppDppppppppppppppp........",
        "......ppppkkDpppppppppkkpppp........",
        "......ppppkkDpppppppppkkpppp........",
        "......ppppkkDpppppppppkkpppppppp....",
        "......ppppkkppppppppppkkpppppppp....",
        "......pppppppppppppppppppppppppp....",
        "..ppp.pppppDDDDpppppppppppppppp.....",
        ".pppppppwwwwwwwwwDpppppppppp.I......",
        ".pppppDwwwwwwwwwwwwppppppppIII......",
        "...pppxwwwwwwwwwwwwxpppIIIpp..I.....",
        "....p.pxxDwwwwwwDxxppIIIpppIII......",
        ".......xxxxxxxxxxxxIIp..pIII........",
        "........xxxxxxxxxx..pIIIpp..........",
        "........pxxxxxxxxp.III..pp..........",
        "........pp..pp.pIIIIpp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 看书（二）
    static let reading2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppppppkGppppppppppkGpp........",
        "......ppppppkGppppppppppkGpp........",
        "..pp..ppppppkGppppppppppkGpp..pp....",
        "..ppp.pzpDpppzzpzzpzzDDpzzzp.ppp....",
        ".ppppppzDDDDDDDDzzDDDDDDzzzpppppp...",
        ".pppppzpDDDDDpppzzpppDDDzzzpppppp...",
        "...pppzDDppppDDDzzDDDppppzzzppp.....",
        "....pppDDDDDDDDDzzDDDDDDpzzzpp......",
        "......ppzzzzzzzzzzzzzzzzzzzz........",
        "......pppppppppppppppppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 看书（一）
    static let reading = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......pppppppppppppppppppppp........",
        "......ppkkppppppppppkkpppppp........",
        "......ppkkppppppppppkkpppppp........",
        "......ppkkppppppppppkkpppppp........",
        "..pp..pozzooppppppppkkpozzzp..pp....",
        "..pppppzDDDDDDDpzzppDDDDDDzppppp....",
        ".pppppopDppDDDDDzzDDDDDppDopppppp...",
        ".pppppzDDDDDDDDDzzDDDDDDDDDzppppp...",
        "...pppoDDDDDDDppzzpDDDDDDDDzppp.....",
        ".....zoppppDDDDDzzDDDppppppoz.......",
        "......ppppppppoozzoopppppppp........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 喝咖啡（二）
    static let coffee2 = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        ".....................ppppp..........",
        ".............pDppppppppppp..........",
        "......ppppppppDppppppppppp..........",
        "....ppppppppppDpppppppppppp.........",
        "....ppppppppppppppppppzpppp.........",
        ".....ppppppppppppppppkkpppp.........",
        ".....ppppkkppppppppppkkpppp.........",
        ".....ppppkkppppppppppkkpppp.p.......",
        ".....ppppkkppppppppppkzppppppp......",
        ".....ppppkkppzzzzzzzzpwDDDppppp.....",
        "...ppppppppzzzzzzzzzzpwDDDDDppp.....",
        "...ppppppwpzzzzzzzzzDwwDDDDDDp......",
        "..pppppppwwwDDDDDDDDDDDDpppDD.......",
        ".ppppppppDDDDDDDDDDDDDDDpppDD.......",
        "...pp.pppDDDDDDDDDDDDDDDpp.DD.......",
        "......ppppDDDDDDDDDDDDDDDDDD........",
        "........ppDDDDDDDDDDDDD.DDD.........",
        "........ppDDDDD.....pp..pp..........",
        "........pp..pp......pp..............",
        "........pp..pp......................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)

    /// 喝咖啡（一）
    static let coffee = PixelSprite([
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "....................................",
        "......ppppppppppDppppppppppp........",
        "......ppppppppppDppppppppppp........",
        "......ppppppppppDppppppppppp........",
        "......ppppppppppDppppppppppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "......ppppkkppppppppppkkpppp........",
        "...pppppppppzzzzzzzzzppppppppp......",
        "...pppppppwzzzzzzzzzzzzwDDDpppp.....",
        "..ppppppppwwpzzzzzzzzDwwDDDDpppp....",
        "...pppppppDDDDDDDDDDDDDDppDDDpp.....",
        "....p.ppppDDDDDDDDDDDDDDppppDD......",
        "......ppppDDDDDDDDDDDDDDppppDD......",
        "........ppDDDDDDDDDDDDDDpp.DDw......",
        "........ppDDDDDDDDDDDDDwDDDDD.......",
        "........pp..pp......pp..DDD.........",
        "........pp..pp......pp..pp..........",
        "....................................",
        "....................................",
        "....................................",
        "...................................."
    ], palette)
    //
    // ⚠️⚠️ **这一段整段是 `scripts/照抄表情.py` 生成的，别手改。**
    // 手改一次，下次重跑就没了——而重跑是常态（换缩放、换调色板都要重跑）。
    // 要改动作，改脚本里的 `PAIRS`；要改颜色，改脚本里数调色板那一段。
    //
    // 每个动作两帧，是**从他们的 gif 里挑出差得最多的那一对**——
    // 取相邻两帧的话两张几乎一样，接进来就是一只僵在那儿的 clawd。

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

    /// 喝咖啡。从 `clawd-emotes-skill` 的 gallery 扒来的
    case coffee
    /// 看书。从 `clawd-emotes-skill` 的 gallery 扒来的
    case reading
    /// 吃东西。从 `clawd-emotes-skill` 的 gallery 扒来的
    case eating
    /// 画画。从 `clawd-emotes-skill` 的 gallery 扒来的
    case painting
    /// 听音乐。从 `clawd-emotes-skill` 的 gallery 扒来的
    case listening
    /// 浇花。从 `clawd-emotes-skill` 的 gallery 扒来的
    case watering
    /// 打游戏。从 `clawd-emotes-skill` 的 gallery 扒来的
    case gaming
    /// 弹吉他。从 `clawd-emotes-skill` 的 gallery 扒来的
    case guitar

    /// 拍照
    case photo
    /// 唱歌
    case singing
    /// 举哑铃
    case exercise
    /// 洗澡
    case shower

    // ── 节日。**按日子出，不进随机池**（见 `festiveToday`）
    /// 她生日（11 月 16 日）
    case birthday
    /// 元旦
    case newYear
    /// 春节
    case springFestival
    /// 元宵
    case lantern
    /// 端午
    case dragonBoat
    /// 七夕
    case qixi
    /// 中秋
    case midAutumn
    /// 圣诞
    case christmas
    /// 万圣夜
    case halloween

    /// 这一档直接播他们的哪个 gif（`Qi/Resources/clawd/`）。
    ///
    /// 她说的：「他怎么做的就直接拿过来就行了……你不会做就直接把他 zip 里的
    /// 文件直接 copy 到我的 app 里。」
    ///
    /// 有 gif 的就播 gif——**道具、飘着的音符爱心、动作节奏全在里面**，
    /// 一帧都不用我们重画。返回 `nil` 的那几档是我们自己的
    ///（走路、抱东西、探头、哭），他们没有对应的动画。
    var gif: String? {
        switch self {
        case .coffee:    return "clawd-coffee"
        case .reading:   return "clawd-reading"
        case .eating:    return "clawd-eating"
        case .painting:  return "clawd-painting"
        case .listening: return "clawd-listening"
        case .watering:  return "clawd-watering"
        case .gaming:    return "clawd-gaming"
        case .guitar:    return "clawd-guitar"
        case .working:   return "clawd-coding"
        case .sleeping:  return "clawd-sleeping"
        case .loving:    return "clawd-valentine"
        // ⚠️ 这个 gif **还没有**——他们 gallery 里没有扫地，
        // 是我照 skill 的规则新画的（`scripts/clawd-扫地.html`），
        // 但这台机器导不出 gif（见交接）。名字先写在这儿：
        // 文件一旦放进 `Qi/Resources/clawd/` 就自动生效，
        // 没有的话 `ClawdGif.exists` 会挡住，照旧走我们的字符画。
        case .sweeping:  return "clawd-sweeping"
        case .photo:     return "clawd-photo"
        case .singing:   return "clawd-singing"
        case .exercise:  return "clawd-exercise"
        case .shower:    return "clawd-shower"
        case .birthday:       return "clawd-birthday"
        case .newYear:        return "clawd-new-year"
        case .springFestival: return "clawd-spring"
        case .lantern:        return "clawd-lantern"
        case .dragonBoat:     return "clawd-dragon-boat"
        case .qixi:           return "clawd-qixi"
        case .midAutumn:      return "clawd-mid-autumn"
        case .christmas:      return "clawd-christmas"
        case .halloween:      return "clawd-halloween"
        default:         return nil
        }
    }

    /// 今天是节日的话，是哪一档。
    ///
    /// 她说过：「节日那些该按日子出来，不该随机抽到，
    /// 大夏天突然过年就出戏了。」
    ///
    /// ⚠️ 日子**不自己算**。农历节日在公历上年年都在挪，
    /// 项目里 `Festivals` 已经拿 iOS 自带的中国农历现算好了，直接问它。
    ///
    /// ⚠️ 结果**按天缓存**：`Festivals.all` 要把一年扫一遍，
    /// 而「他自己找点事做」十几秒就问一次，不缓存就是每十几秒扫一年。
    private static var festiveCache: (day: Date, mood: ClawdMood?)?

    static func festiveToday(_ now: Date = Date()) -> ClawdMood? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if let c = festiveCache, c.day == today { return c.mood }

        // ⚠️ **她的生日先判，压过所有公共节日。**
        //
        // 11 月 16 日是她的生日（她自己说的）。
        // 这一天万一撞上别的日子，也是她的生日更要紧——
        // 别的节日年年都有，她的生日一年就这一天，而且是**她的**。
        let cal2 = Calendar.current
        if cal2.component(.month, from: now) == 11,
           cal2.component(.day, from: now) == 16 {
            festiveCache = (today, .birthday)
            return .birthday
        }

        var hit: ClawdMood?
        for f in Festivals.all(year: cal.component(.year, from: now))
        where cal.startOfDay(for: f.date) == today {
            switch f.name {
            case "春节", "除夕": hit = .springFestival
            case "元宵":        hit = .lantern
            case "端午":        hit = .dragonBoat
            case "七夕":        hit = .qixi
            case "中秋":        hit = .midAutumn
            case "圣诞", "平安夜": hit = .christmas
            case "万圣夜":      hit = .halloween
            case "元旦":        hit = .newYear
            default: continue
            }
            break
        }
        festiveCache = (today, hit)
        return hit
    }

    /// **这一档至少要演多久**（秒）。演不满不许换下一个。
    ///
    /// 她说的：「这个表情跟阿晏的行为直接挂钩，阿晏打游戏他也打游戏、
    /// 阿晏思考他也思考。如果阿晏一秒钟切换一个行为，app 一定会崩的。
    /// 设置成一旦触发就等触发的结束再做下一个动作……
    /// 所以动画时长要安排得不快不慢。」
    ///
    /// ⚠️ **不能拿「一轮帧长」当这个数。** 打游戏两帧各 0.3 秒，
    /// 一轮才 0.6 秒——锁 0.6 秒等于没锁，他照样一秒换一个。
    /// 这个数管的是「看得出他在干嘛」需要多久，跟帧速是两件事：
    /// 帧速决定动作快慢，这个决定一件事做多久。
    ///
    /// 3.5 秒是按他们的节奏估的：打游戏一轮 0.6 秒，演五六轮；
    /// 看书一轮 2.2 秒，演一轮半。都够读出在做什么，又不至于
    /// 她说完话半天没反应。
    var hold: Double {
        switch self {
        // 过渡态：本来就是"没在干别的"，不该占着位置挡别人
        case .idle, .walking, .carrying, .hauling, .talking:
            return 1.5
        // 情绪和交互：她一说话就该立刻演，演完也不必赖着
        case .happy, .crying, .loving, .upset, .flail, .peeking:
            return 2.0
        // 睡觉／犯困：本来就是长状态
        case .sleeping, .drowsy:
            return 6.0
        // 节日：一年就这一天，让他演够一轮
        case .birthday, .newYear, .springFestival, .lantern, .dragonBoat,
             .qixi, .midAutumn, .christmas, .halloween:
            return 6.0
        // "他在做的事"——这一类才是需要演完的
        default:
            return 3.5
        }
    }

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
            // ⚠️ 0.22 → 0.34。她说「速度太快……看起来像疯癫了」。
            //
            // 参考里手臂是 0.12~0.15 秒一轮，比这还快——但它那是
            // **绕肩膀转角度**，手一直指着键盘，快只是手指在动。
            // 我们是两张整图硬切，切得越快整只越像在抽搐。
            // 换算不能照搬秒数，得照搬"看着像什么"。
            return [(ClawdSprites.working, 0.34), (ClawdSprites.working2, 0.34)]
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
            // ⚠️ 她说「玫瑰花这个完全没在动」——原来这一档里
            // 只有 `sweet` 一张图纸，换来换去都是同一张。
            return [(ClawdSprites.sweet, 1.0), (ClawdSprites.sweet2, 1.0)]
        case .photo, .singing, .exercise, .shower, .birthday,
             .newYear, .springFestival, .lantern, .dragonBoat,
             .qixi, .midAutumn, .christmas, .halloween:
            // ⚠️ 这些档**只走 gif**（见 `gif`），这儿是 gif 读不到时的兜底。
            // 她说过「你根本没有作画能力……按自己想法画出来的等同于屎」——
            // 所以不给它们画字符画了，读不到就站着，别拿我画的糊弄。
            return [
                (ClawdSprites.idle, 1.4),
                (ClawdSprites.breathe, 1.1),
                (ClawdSprites.idle, 1.4),
                (ClawdSprites.blink, 0.16)
            ]
        case .sweeping:
            // 一个来回：左 → 中 → 右 → 中。
            // 中间那两帧短一点——扫把甩过中段本来就快，
            // 四帧等长会显得像节拍器。
            return [(ClawdSprites.sweep1, 0.22), (ClawdSprites.sweep2, 0.16),
                    (ClawdSprites.sweep3, 0.22), (ClawdSprites.sweep4, 0.16)]
        case .coffee:
            return [(ClawdSprites.coffee, 0.5), (ClawdSprites.coffee2, 0.5)]
        case .reading:
            return [(ClawdSprites.reading, 1.2), (ClawdSprites.reading2, 1.0)]
        case .eating:
            return [(ClawdSprites.eating, 0.42), (ClawdSprites.eating2, 0.42)]
        case .painting:
            return [(ClawdSprites.painting, 0.45), (ClawdSprites.painting2, 0.45)]
        case .listening:
            return [(ClawdSprites.listening, 0.4), (ClawdSprites.listening2, 0.4)]
        case .watering:
            return [(ClawdSprites.watering, 0.6), (ClawdSprites.watering2, 0.6)]
        case .gaming:
            return [(ClawdSprites.gaming, 0.3), (ClawdSprites.gaming2, 0.3)]
        case .guitar:
            return [(ClawdSprites.guitar, 0.32), (ClawdSprites.guitar2, 0.32)]
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
    /// **身上穿戴的那件**（帽子、眼镜、围巾…）。
    ///
    /// ⚠️ 小屋里那只走的是这个 `ClawdView`，不是聊天页那个 `ClawdRigView`。
    /// 两边**都要传**——只给一边的话，她在小屋给他戴上帽子，
    /// 切到聊天页帽子就没了，看着像刚才那一下没生效。
    var worn: PixelSprite?
    var wornID: String = ""
    /// **两只手摆起来**（欢呼 / 招手）。
    ///
    /// 她要的「随着情绪联动」里最要紧的一件。做法见 `ClawdRig.plan`
    /// 的 `.cheer` 那一档：手是身侧那块不变形的疙瘩，只是绕肩膀来回转。
    ///
    /// ⚠️ 小屋和聊天页那只走的是这个 `ClawdView`（画整张图，没有能转的手），
    /// 而能转手的是 `ClawdRigView`——所以以前不管情绪怎么变，
    /// 他的手**永远是垂着的两块**。这个开关就是把那条路接上。
    var pose: CarryPose = .none

    @State private var frame = 0
    @State private var ticker: Task<Void, Never>?
    /// 爱心飘起来没有
    @State private var hearts = false

    private var sprites: [(PixelSprite, Double)] { mood.frames }

    /// 睡着和呼吸那两帧整只往下沉了一格，影子跟着淡一点、扁一点
    private var settled: Bool { mood == .sleeping }

    /// 手摆起来的那一版身子。
    ///
    /// 身子照常放帧（眨眼、呼吸都还在），**只把两只手抠掉换成会转的**。
    ///
    /// ⚠️ 用 `TimelineView(.animation)` 取时间，**不要拿 `@State` 计时**。
    /// 这只 clawd 在小屋、聊天页、输入框上同时活着，
    /// 每秒六十次改状态的话整棵树跟着重画。
    /// 干活时飘起来的数据粒子。五颗，各自错开，从电脑后面升到头顶以上。
    ///
    /// ⚠️ 起点要在**电脑后面**（屏幕顶在第 13 行，离底 14 格），
    /// 终点要**飘过他的头**（头顶在第 4 行，离底 23 格）。
    /// 第一版只升到离底 4..13 格——整段埋在屏幕那片灰里，等于没画。
    ///
    /// ⚠️ 走 `TimelineView` 取时间，不拿 `@State` 计时——
    /// 这只 clawd 同时活在小屋、聊天页、输入框上。
    private var dataBits: some View {
        TimelineView(.animation) { ctx in
            let now = ctx.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                ForEach(0..<5, id: \.self) { i in
                    // 每颗自己的周期和起点，错开才像"冒出来"不像"齐步走"
                    let period = 1.1 + Double(i) * 0.17
                    let t = (now / period).truncatingRemainder(dividingBy: 1)
                    let fromX = [-9.0, -4.0, 1.0, 6.0, 10.0][i]
                    Rectangle()
                        .fill(Color(hexString: "40C4FF") ?? .cyan)
                        .frame(width: scale * 1.2, height: scale * 1.2)
                        .offset(x: (fromX + t * 3) * scale,
                                y: -(8 + t * 17) * scale)
                        .opacity(t < 0.15 ? 0 : (1 - t) * 0.8)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 头顶上方那台显示器（打游戏时）。
    ///
    /// ⚠️ **那个 -30 是算出来的，别调手感。**
    ///
    /// 显示器那张图纸盖住 svg y -13..2，主图纸盖住 -1..17，
    /// 两张共用横向范围（-1..17），所以左右天然对齐，只需要往上挪。
    ///
    ///     主图纸第 0 行 = svg -1
    ///     svg -1 落在显示器图纸的第 (−1+13)×2 = 24 行
    ///     显示器图纸 30 行高，底对齐时往上推 30 格，
    ///     它的第 24 行正好压在主图纸第 0 行上
    ///
    /// 改了任何一张图纸的范围，这个数要跟着重算。
    private var gameScreen: some View {
        ZStack(alignment: .bottom) {
            PixelSpriteView(sprite: ClawdSprites.gameScreen, scale: scale)
                .offset(y: -30 * scale)
        }
        .allowsHitTesting(false)
    }

    /// 头顶飘出来的音符。跟 `dataBits` 一个路子：
    /// 各飘各的、错开周期、边飘边淡，齐步走就假了。
    private var musicNotes: some View {
        TimelineView(.animation) { ctx in
            let now = ctx.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                ForEach(0..<3, id: \.self) { i in
                    let period = 2.0 + Double(i) * 0.45
                    let t = (now / period).truncatingRemainder(dividingBy: 1)
                    // 左右各一串，中间一串——从耳机上方冒出来
                    let fromX = [-8.0, 0.0, 7.0][i]
                    Text(i == 1 ? "♫" : "♪")
                        .font(.system(size: scale * 5, weight: .bold))
                        .foregroundStyle(Color(hexString: "8B7BD8") ?? .purple)
                        .offset(x: (fromX + sin(t * 6) * 1.5) * scale,
                                y: -(10 + t * 16) * scale)
                        .opacity(t < 0.12 ? 0 : (1 - t) * 0.9)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var waving: some View {
        let body = sprites[min(frame, sprites.count - 1)].0
        let cols = CGFloat(body.width), rows = CGFloat(body.height)
        return TimelineView(.animation) { ctx in
            // 0.62 秒一个来回。官方那套表情摆手是 0.55s，
            // 慢一点点更像"高兴"而不是"抽筋"
            let beat = (ctx.date.timeIntervalSinceReferenceDate / 0.62)
                .truncatingRemainder(dividingBy: 1)
            let plan = ClawdRig.plan(pose: pose, beat: beat, itemW: 0, itemH: 0)
            ZStack(alignment: .topLeading) {
                // ⚠️⚠️ **手在下、身子在上**，跟 `ClawdRigView` 一样。
                // 手有一半是埋在身子里的（`ClawdRig.arm` 那段注释说了为什么），
                // 顺序反了那半截就糊在他脸上。
                ClawdArmView(onLeft: true, angle: plan.leftArm, scale: scale)
                ClawdArmView(onLeft: false, angle: plan.rightArm, scale: scale)
                PixelSpriteView(sprite: ClawdRig.stripArms(body), scale: scale)
            }
            .frame(width: cols * scale, height: rows * scale, alignment: .topLeading)
        }
    }

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

            if let g = mood.gif, ClawdGif.exists(g), pose == .none, worn == nil {
                // ⚠️ **播 gif 的时候，我们自己那套一件都不叠。**
                //
                // 道具、飘着的音符和爱心、动作的快慢，人家的 gif 里全都有。
                // 再叠一层我们画的音符或者数据粒子，就是两份重影。
                //
                // ⚠️ 尺寸和位置是算出来的，别调手感：
                // 他们的 viewBox 是 45×45 个单位，我们的图纸是 18 个单位宽，
                // 所以 gif 要画成 `90×scale`（= 45 单位 × 2 格/单位 × scale），
                // 这样**一个 SVG 单位在两边一样大**，切换动作时他不会忽大忽小。
                // 底对齐之后他的脚比我们的图纸低 6 格，抬回去。
                Color.clear
                    .frame(width: 36 * scale, height: 36 * scale)
                    .overlay(alignment: .bottom) {
                        ClawdGifView(name: g, size: 90 * scale)
                            .frame(width: 90 * scale, height: 90 * scale)
                            .offset(y: -6 * scale)
                            .allowsHitTesting(false)
                    }
            } else if pose == .none {
                PixelSpriteView(sprite: sprites[min(frame, sprites.count - 1)].0, scale: scale)
            } else {
                waving
            }

            // 身上戴的那件，贴在对应的位置上（见 `ClawdRig.wearAt`）
            if let worn {
                PixelSpriteView(sprite: worn, scale: scale)
                    .offset(x: ClawdRig.wearAt(wornID, itemW: CGFloat(worn.width),
                                               itemH: CGFloat(worn.height)).x * scale,
                            y: ClawdRig.wearAt(wornID, itemW: CGFloat(worn.width),
                                               itemH: CGFloat(worn.height)).y * scale)
            }

            // 甜的时候头顶飘爱心。
            //
            // **不画进图纸**：图纸只有 32×23，身子占满了，
            // 心画进去只能替掉身上的豆子，看着像破了个洞。
            // 飘在外面才是「冒出来的」。

            // 干活时从电脑后面往上飘的数据粒子。
            //
            // 抄的 `clawd-on-desk` 那份 `clawd-working-typing.svg`：
            // 一串 `#40C4FF` 的小方块，各自错开延迟往上飘、边飘边淡。
            //
            // ⚠️ 这不是装饰。**电脑只说明他坐在那儿，粒子才说明他正在动。**
            if mood == .working, mood.gif == nil {
                dataBits
            }

            // 打游戏时头顶上方那台显示器。
            //
            // 她说的：「打游戏依旧没有游戏屏幕。」
            //
            // ⚠️ **它不在主图纸里，是单独一张。** 量过所有 24 个动画，
            // 只有这台显示器飘到了躯干顶上方十二个多单位，别的道具最高才
            // 1.6，全在框里。为它一个把画布拉高到装得下，整只 clawd 就得
            // 缩成一小块，二十多张图陪着一张受罪。
            //
            // 所以跟爱心、音符、数据粒子一个待遇：浮在图纸外面画。
            // 它本来就跟身体不连——`only_body` 把它从主图纸里擦掉，
            // `solo_prop` 单独扒一张（见 `scripts/照抄表情.py`）。
            // ⚠️ 打游戏走 gif 了（屏幕就在人家画面里），这儿不再另画一台。
            if mood == .gaming, mood.gif == nil {
                gameScreen
            }

            // 听音乐时头顶飘出来的音符。
            //
            // 她说的：「听音乐没有音符吗，不太像听音乐。」
            // ——耳机戴上了，可光戴着耳机跟发呆没区别，
            // **是音符说明他在听**，就像数据粒子说明他在敲键盘。
            //
            // ⚠️ 音符**不进图纸**。他们原图里音符飘到躯干顶上方 25 个单位，
            // 硬塞进图纸的话身子会被压得只剩一点点（量过：图纸留 6.6 单位
            // 就够装下所有握在手里的东西了）。所以跟爱心、数据粒子一样，
            // 单独浮在图纸外面画。
            //
            // 符号照他们的来（`anatomy.md` 的粒子那节写的就是 `<text>♪`）。
            // ⚠️ 听音乐走 gif 了（音符就在人家画面里），别再叠一份。
            if mood == .listening, mood.gif == nil {
                musicNotes
            }

            if mood == .loving, mood.gif == nil {
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
