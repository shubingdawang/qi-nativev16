import SwiftUI

// MARK: - 立体小屋的地基
//
// 她要的：
// > clawd 的小屋不仅仅是一个平面，是一个立体的小屋，家具放在上面有立体感，
// > clawd 可以自己装修自己的小家……**不穿模不卡顿**。
//
// ## 为什么先做这一层，而不是先画好看的家具
//
// 「不穿模」不是画出来的，也不是事后一条条调出来的——
// **它是排序排出来的。**
//
// 等距房间里，两件东西谁挡谁，只取决于谁离镜头近。
// 离镜头的远近在等距投影里有一个准确的数：**格X + 格Y**。
// 按这个数从小到大画，远的先画、近的压在上面，
// 于是**穿模这件事从根上就不会发生**——不是「修好了」，是「不可能发生」。
//
// 反过来，如果先画一堆漂亮家具再想办法让它们别叠错，
// 那就是一辈子在打补丁。所以这一层必须在素材之前。
//
// ## 这一份只管几何，不碰界面
//
// 格子↔屏幕怎么换算、一件家具占几格、这一格能不能放、
// 谁该画在谁前面——全在这儿。画成什么样是 `IsoRoomView` 的事。
// 分开的好处很实在：**换素材不动几何，改几何不动素材。**

/// 等距房间的几何。
///
/// 地板是 `size × size` 格。格子坐标 `(gx, gy)`：
/// `gx` 往右后方增大，`gy` 往左后方增大——也就是屏幕上的「往里走」。
struct IsoRoom {

    /// 地板几格见方。八格是试出来的：再小摆不下几件家具，
    /// 再大每一格就细得点不准了。
    var size: Int = 8
    /// 一格在屏幕上多宽多高。**必须是 2:1**——
    /// 等距像素画的传统比例，用别的比例现成素材全对不上。
    var tileW: CGFloat = 40
    var tileH: CGFloat = 20
    /// 墙有多高（点）
    var wallH: CGFloat = 96
    /// 地板最上面那个尖在屏幕上的位置
    var origin: CGPoint = .zero

    /// 在这么大的地方里，屋子摆在哪儿、一格多大。
    ///
    /// ⚠️ **只此一份。** 画屋子的那边要用，
    /// 算「clawd 该站在凳子的哪个点上」也要用——
    /// 各算各的必然对不齐，家具和人就永远差半格。
    static func fit(in size: CGSize) -> IsoRoom {
        let n = CGFloat(ClawdStore.roomSize)
        // ⚠️ 一格多大，**同时受宽和高两头管**。
        //
        // 她报的「屋子很小，而且有一部分在屏幕下面」就是只按宽算的下场：
        // 宽度够、高度不够，地板加两面墙比容器高，屋子被顶下去一截。
        //
        // 整间屋子竖着一共占：墙(4.2 格高) + 地板(n 格 × 半格高)。
        // 两头各算一次取小的，屋子就一定塞得进去。
        let byWidth = (size.width * 0.985) / n
        // ⚠️ 这一条按**最矮的墙**算：先保证「地板 + 一堵矮墙」一定塞得下，
        // 墙具体多高留到下面再定。
        let byHeight = (size.height * 0.94) / (n / 2 + 4.2 + 1)
        let tileW = min(byWidth, byHeight)
        let tileH = tileW / 2

        // ⚠️⚠️ **剩下的竖向空间全给墙。**
        //
        // 她报的：「clawd 的小屋太小了。」
        //
        // 去量一下就明白了：地板的宽度**已经顶到容器的 94%**，
        // 再宽就出屏幕了——横着没有余地。
        // 可整间屋子（墙 4.2 格 + 地板）竖着只占了屏幕高度的**三分之一**，
        // 上下各空着一大片。屋子不是画小了，是**摆在一片空地当中**，
        // 所以看着小。
        //
        // 所以不再把墙写死成 4.2 格：地板按宽度定好之后，
        // **竖着还剩多少就给墙多少**。屋子从此是撑满这一屏的，
        // 而地板一格也没变小。
        //
        // 上限 7 格：她说「小屋有点太高了」——9 格那版墙占了整屋的六成，
        // 家具缩在井底一小块。7 格之后墙和地大致对半，看着才像一间屋。
        // 下限还是 4.2 格——横屏或者小窗口的时候剩不下地方，
        // 至少得是间屋子的样子。
        let floorH = tileH * n / 2 + tileH
        let room = size.height * 0.94 - floorH
        let wallH = min(max(tileH * 4.2, room), tileH * 7)

        // 整块（墙顶到地板最下）的高度，用来把屋子**竖着摆正中**
        let whole = wallH + floorH
        let top = (size.height - whole) / 2
        return IsoRoom(size: ClawdStore.roomSize,
                       tileW: tileW, tileH: tileH,
                       wallH: wallH,
                       origin: CGPoint(x: size.width / 2,
                                       y: top + wallH + tileH / 2))
    }

    // MARK: clawd 能站在哪儿
    //
    // 他走路那一套用的是「占容器的百分之几」（0…1），
    // 跟这儿的格子坐标是两套东西。以前两边各写各的常数，
    // 结果就是她报的：**「房间虽然整体往上挪了，但是 clawd 的活动区域
    // 并没有往上挪」**——屋子归 `fit` 算，他归两个写死的数，当然对不齐。
    //
    // 下面这两个把地板的形状翻译成他那套 0…1，**只此一份**。

    /// 地板在这块地方里**竖着**占哪一段（0…1）。
    ///
    /// 上下各留一点余量：他是「整只居中」摆上去的，
    /// 贴着最上那个尖站会有半个身子探进墙里。
    func walkBand(in size: CGSize) -> (top: Double, bottom: Double) {
        guard size.height > 1 else { return (0.62, 0.9) }
        let n = Double(self.size)
        let topY = Double(point(0, 0).y)
        let botY = Double(point(n - 1, n - 1).y)
        let h = Double(size.height)
        let t = min(0.98, max(0.02, topY / h))
        let b = min(0.98, max(0.02, botY / h))
        // 上边多让出一点——最上那个角太窄，站上去两边都悬空
        return (min(t + 0.03, b), b)
    }

    /// 在竖直位置 `y`（0…1）上，地板**横着**到哪儿（0…1）。
    ///
    /// 地板是个菱形，不是矩形：越靠近上下两个尖，能站的地方越窄。
    /// 以前横着一律 clamp 到 0.12…0.88，所以他在最上和最下那一截
    /// 会走到地板外面的空气里去。
    func walkSpan(atY y: Double, in size: CGSize) -> (lo: Double, hi: Double) {
        guard size.width > 1 else { return (0.12, 0.88) }
        let (top, bottom) = walkBand(in: size)
        let span = max(0.0001, bottom - top)
        // 0 = 最上那个尖，1 = 最下那个尖；中间最宽
        let t = min(1, max(0, (y - top) / span))
        let wide = 1 - abs(2 * t - 1)                 // 三角形，中间是 1
        let n = CGFloat(self.size)
        // 菱形最宽处的半宽，再往里收一点点，别让他半只挂在边上
        let halfMax = tileW * n / 2 - tileW * 0.35
        let half = halfMax * CGFloat(wide)
        let cx = origin.x
        let lo = (cx - half) / size.width
        let hi = (cx + half) / size.width
        guard hi > lo else { return (0.5, 0.5) }
        return (Double(lo), Double(hi))
    }

    /// 把一个点夹回地板里。走路、拖拽都从这儿过。
    func clampToFloor(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let (top, bottom) = walkBand(in: size)
        let y = min(bottom, max(top, Double(p.y)))
        let (lo, hi) = walkSpan(atY: y, in: size)
        return CGPoint(x: min(hi, max(lo, Double(p.x))), y: y)
    }

    // MARK: 格子 ↔ 屏幕

    /// 一格的**中心**在屏幕上的位置
    func point(_ gx: Double, _ gy: Double) -> CGPoint {
        CGPoint(x: origin.x + (gx - gy) * tileW / 2,
                y: origin.y + (gx + gy) * tileH / 2)
    }

    /// 屏幕上一个点落在哪一格。**可能落在地板外面**，调用方自己判断
    func tile(at p: CGPoint) -> (gx: Double, gy: Double) {
        let dx = p.x - origin.x
        let dy = p.y - origin.y
        return (gx: dy / tileH + dx / tileW,
                gy: dy / tileH - dx / tileW)
    }

    /// 这一格在不在地板上
    func inside(_ gx: Int, _ gy: Int) -> Bool {
        gx >= 0 && gy >= 0 && gx < size && gy < size
    }

    /// 把落点收进地板里
    func clamp(_ gx: Int, _ gy: Int) -> (Int, Int) {
        (min(size - 1, max(0, gx)), min(size - 1, max(0, gy)))
    }

    /// 一格地砖的四个角（菱形）
    func tilePath(_ gx: Int, _ gy: Int) -> Path {
        let c = point(Double(gx), Double(gy))
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - tileH / 2))
        p.addLine(to: CGPoint(x: c.x + tileW / 2, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + tileH / 2))
        p.addLine(to: CGPoint(x: c.x - tileW / 2, y: c.y))
        p.closeSubpath()
        return p
    }

    /// 地板整块的轮廓
    var floorPath: Path {
        let n = Double(size)
        var p = Path()
        p.move(to: point(0, 0).offsetBy(dy: -tileH / 2))
        p.addLine(to: point(n - 1, 0).offsetBy(dx: tileW / 2))
        p.addLine(to: point(n - 1, n - 1).offsetBy(dy: tileH / 2))
        p.addLine(to: point(0, n - 1).offsetBy(dx: -tileW / 2))
        p.closeSubpath()
        return p
    }

    /// 左边那面墙（`gy = 0` 那一侧往上立起来）
    var leftWallPath: Path {
        let n = Double(size)
        let a = point(0, 0).offsetBy(dy: -tileH / 2)
        let b = point(0, n - 1).offsetBy(dx: -tileW / 2)
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: b.offsetBy(dy: -wallH))
        p.addLine(to: a.offsetBy(dy: -wallH))
        p.closeSubpath()
        return p
    }

    /// 两面墙的**底边**：从哪一点到哪一点。
    ///
    /// 内置墙面（`RoomFinish`）要拿它算砖缝和条纹的位置。
    ///
    /// ⚠️ 画墙上的花纹**不能在屏幕的横竖方向上画**。
    /// 等距屋的「水平」是斜的（斜率正好 ±½，因为 `tileH = tileW / 2`），
    /// 拿屏幕的水平线去画砖缝，砖墙会横穿过整间屋，看着像贴了张纸。
    /// 照着这条底边走，缝天然就是斜的、跟墙一个方向。
    var leftWallBase: (CGPoint, CGPoint) {
        let n = Double(size)
        return (point(0, 0).offsetBy(dy: -tileH / 2),
                point(0, n - 1).offsetBy(dx: -tileW / 2))
    }

    var rightWallBase: (CGPoint, CGPoint) {
        let n = Double(size)
        return (point(0, 0).offsetBy(dy: -tileH / 2),
                point(n - 1, 0).offsetBy(dx: tileW / 2))
    }

    /// 右边那面墙（`gx = 0` 那一侧）
    var rightWallPath: Path {
        let n = Double(size)
        let a = point(0, 0).offsetBy(dy: -tileH / 2)
        let b = point(n - 1, 0).offsetBy(dx: tileW / 2)
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: b.offsetBy(dy: -wallH))
        p.addLine(to: a.offsetBy(dy: -wallH))
        p.closeSubpath()
        return p
    }

    // MARK: 谁挡谁

    /// 画的先后。**这一个数就是「不穿模」的全部秘密。**
    ///
    /// 等距投影里，离镜头的远近只跟 `gx + gy` 有关。
    /// 从小到大画：远的先落笔、近的压在上面。
    ///
    /// 两件东西恰好一样远的时候（比如挨着的两把椅子），
    /// 拿**高度**当第二把尺子：矮的先画。
    /// 都一样就按 id 定死——**不能靠不稳定的顺序**，
    /// 那会让两件家具每次重画都换一次前后，看着像在打架。
    static func order<T>(_ items: [T],
                         depth: (T) -> Double,
                         height: (T) -> Double,
                         tie: (T) -> String) -> [T] {
        items.sorted { a, b in
            let da = depth(a), db = depth(b)
            if abs(da - db) > 0.0001 { return da < db }
            let ha = height(a), hb = height(b)
            if abs(ha - hb) > 0.0001 { return ha < hb }
            return tie(a) < tie(b)
        }
    }

    // MARK: 放得下放不下

    /// 一件占 `w × d` 格的东西，落在 `(gx, gy)` 会盖住哪几格
    static func cells(_ gx: Int, _ gy: Int, _ w: Int, _ d: Int) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for i in 0..<max(1, w) {
            for j in 0..<max(1, d) {
                out.append((gx + i, gy + j))
            }
        }
        return out
    }

    /// 这一件放得下吗。
    ///
    /// 两条：**不能出地板**、**不能压在别人身上**。
    /// 就这两条——不写更多规则了，规则一多她摆个东西要试半天。
    func canPlace(_ gx: Int, _ gy: Int, w: Int, d: Int,
                  taken: Set<String>) -> Bool {
        for (x, y) in Self.cells(gx, gy, w, d) {
            guard inside(x, y) else { return false }
            if taken.contains("\(x),\(y)") { return false }
        }
        return true
    }

    /// 放不下的时候，往外找最近一处放得下的地方。
    ///
    /// **不能一句「放不下」就把东西弹回去**——她拖了半天，
    /// 结果东西跳回原位，那比放歪还气人。
    /// 从落点开始一圈圈往外找，找到就放那儿。
    func nearestFree(_ gx: Int, _ gy: Int, w: Int, d: Int,
                     taken: Set<String>) -> (Int, Int)? {
        if canPlace(gx, gy, w: w, d: d, taken: taken) { return (gx, gy) }
        for r in 1...size {
            for dx in -r...r {
                for dy in -r...r where abs(dx) == r || abs(dy) == r {
                    let x = gx + dx, y = gy + dy
                    if canPlace(x, y, w: w, d: d, taken: taken) { return (x, y) }
                }
            }
        }
        return nil
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}

// MARK: - 一件东西在屋里占多大

/// 家具的立体信息。
///
/// ⚠️ 这是**每加一件家具唯一要填的东西**：占几格、站着多高、
/// 该贴墙还是摆地上、clawd 能对它做什么。
/// 填完了，摆放、遮挡、互动就都有了——不用为它写一行代码。
struct IsoShape {
    /// 占地几格（宽 × 进深）
    var w: Int = 1
    var d: Int = 1
    /// 立起来多高（格）。只影响谁挡谁的第二把尺子和影子大小
    var tall: Double = 1
    /// 贴墙的（画、空调、窗）。贴墙的不占地板
    var onWall: Bool = false
    /// 有没有一个能放东西的台面（桌子有，床没有）。
    /// 阿晏「把饮料放在哪张桌子上」靠的就是这一条
    var surface: Bool = false
    /// clawd 能对它做什么。名字是动作名，不是台词
    var actions: [String] = []
}
