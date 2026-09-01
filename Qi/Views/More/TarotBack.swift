import SwiftUI

/// 牌背。
///
/// 她报的：「塔罗牌……背景的图案有点太简单了。」
/// 以前就是一块渐变加一道白边——那不是牌背，那是一块圆角矩形。
///
/// 真正的塔罗牌背有一个共同点：**一整面重复的花纹，中间一个记号。**
/// 花纹要密到看不清单个单元（远看是质地，近看才是图案），
/// 记号要小到不抢戏。这两条决定了下面的所有数值。
///
/// ⚠️ **跟着主题色走**，不写死颜色。
/// 她那次说得很明白：「我现在是绿色壁纸，除非我用家的配色，
/// 不然用这个配色很突兀。」所以这儿一个具体颜色都没有，
/// 全是 `tint` 的深浅。
///
/// ⚠️ **全是矢量，没有图片**。一副牌 78 张、扇形铺开时同屏几十张，
/// 每张贴一张位图是几十次解码；画几条线不花什么。
struct TarotBack: View {

    var tint: Color
    /// 一格花纹多大。牌小就密一点，不然一张牌上只剩两个菱形。
    var unit: CGFloat = 11
    var corner: CGFloat = 7

    var body: some View {
        ZStack {
            // 底：斜向渐变，比原来暗一点——花纹要压得住才看得见
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(
                    colors: [tint.opacity(0.62), tint.opacity(0.34)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))

            // 满面的菱形格。**用 Canvas 一次画完**——
            // 铺几十个 `Rectangle().rotationEffect` 是几十个图层，
            // 而这只是一条路径。
            Canvas { ctx, size in
                var path = Path()
                let u = unit
                // 斜着走的两组线，交出来就是菱形网
                var x = -size.height
                while x < size.width + size.height {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    path.move(to: CGPoint(x: x + size.height, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += u
                }
                ctx.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

            // 中间那个记号：一颗八角星。
            // 八角是塔罗牌背上最常见的那一个，而且八条线画完就完了。
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) * 0.19
                var star = Path()
                for k in 0..<8 {
                    let a = Double(k) * .pi / 4
                    star.move(to: c)
                    star.addLine(to: CGPoint(x: c.x + cos(a) * r,
                                             y: c.y + sin(a) * r))
                }
                ctx.stroke(star, with: .color(.white.opacity(0.55)), lineWidth: 1)
                // 外面套一圈，把八条线收住——不收的话像个爆炸
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.52, y: c.y - r * 0.52,
                                                  width: r * 1.04, height: r * 1.04)),
                           with: .color(.white.opacity(0.45)), lineWidth: 1)
            }

            // 双边框：外面一道细的，里面一道更细的。
            // 一道边看着像个按钮，两道才像张牌。
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
            RoundedRectangle(cornerRadius: corner - 2, style: .continuous)
                .strokeBorder(.white.opacity(0.32), lineWidth: 0.7)
                .padding(4)
        }
    }
}
