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
/// 屋子怎么投影到屏幕上。
///
/// 她说的：「我的小屋目前是 p1-17 这种角度……你也可以做成 p18-19
/// 这种平面的。」后来又说：「那个俯视图也不算是俯视，差不多就是平视，
/// 效果图上不就是一个小人正面站着吗，可以试下换成那种。
/// clawd 是正面没关系，在那个图里 clawd 并不需要转身。」
///
/// ## ⚠️ 两种投影，**一份数据**
///
/// 家具还是存 `gx / gy` 那一对格子坐标，两种画法只是把同一对坐标
/// 换算到屏幕上的方式不同。所以：
///   · 深度排序、摆放规则、拖拽、走路 **一行都不用改**——
///     它们全都只调 `point` / `tile(at:)` / `clampToFloor`
///   · 她换个画法，家具**还在原来的位置上**，不用重摆
///
/// 各存一份摆放的话，改了一边另一边就开始撒谎——
/// 这个项目里这种事已经栽过太多次了。
enum RoomProjection: String, CaseIterable, Codable, Identifiable {
    /// 等距斜俯（原来那个）
    case iso
    /// 正面平视：一面后墙 + 一条地板，人正面站着
    case flat

    var id: String { rawValue }
    var label: String { self == .iso ? "立体" : "平面" }
    var note: String {
        self == .iso ? "斜着往下看，能看见家具的顶面" : "正面平视，像一间剖开的屋子"
    }
}

struct IsoRoom {

    /// 地板几格见方。八格是试出来的：再小摆不下几件家具，
    /// 再大每一格就细得点不准了。
    /// 地板**纵深**几格。两种投影都是这个数。
    var size: Int = 8

    /// 地板**横着**几格。
    ///
    /// ⚠️ 立体屋里横竖必须一样（那是个菱形，两条边就是同一条边的两头），
    /// 所以它默认等于 `size`。
    ///
    /// 平面屋不受这个限制：那是一面正对着的墙加一块地板，
    /// 横着想多宽就多宽。她要的正是这个——
    /// 「平面视角的房间有点太小了不够放太多家具，
    /// 　改为可以拖动往最左右分别移动五格的」。
    ///
    /// ⚠️ 她挑了「两种视角各存各的位置」这条路（见 `Furniture.fx`）。
    /// 所以放宽横向**不会**把立体屋里的东西挤出界——
    /// 它们根本不共用同一对坐标。
    var cols: Int = 8
    /// 哪种投影。⚠️ **只影响换算，不影响存的数据**
    var projection: RoomProjection = .iso
    /// 一格在屏幕上多宽多高。**必须是 2:1**——
    /// 等距像素画的传统比例，用别的比例现成素材全对不上。
    var tileW: CGFloat = 40
    var tileH: CGFloat = 20
    /// 墙有多高（点）
    var wallH: CGFloat = 96
    /// 地板最上面那个尖在屏幕上的位置
    var origin: CGPoint = .zero

    /// 平面那档：**一排地砖竖着占多高**（乘 `tileH`）。
    ///
    /// ⚠️⚠️ **这个数只此一份。** 落点、反查、地砖轮廓、地板整块、
    /// 家具贴地那一条，全从它算。以前它以 `tileH / 2` 的形式抄在五个地方，
    /// 想调深浅就得五处一起改，漏一处就是「家具落在别的格子里」。
    ///
    /// 她报的：「家具推到最里面的格子，反而悬浮在上面。」
    /// 根子就是这个数太小（原来 0.5）：八排地板一共才两格宽那么深，
    /// 最里面那一排几乎贴着墙根，摆件东西上去，脚下看不见地，
    /// 整件就像挂在墙上。0.8 之后八排摊开有三格多深，最里面那排底下
    /// 还剩得出地板来。
    static let flatRowPitch: CGFloat = 1.15

    /// 平面那档：**最里那一排比最外那一排窄多少**（0…1）。
    ///
    /// 她说的：「现在这样不太像里面有空间可以放家具的样子，像一张纸。
    /// 地板墙壁不要五五分，地板应该再斜一点往里延伸。」
    ///
    /// 她说得对：原来的平面地板是个**正矩形**——每一排一样宽。
    /// 正矩形没有纵深，看上去就是一张贴在墙根的纸。
    /// 让最里那排收窄三成，地板就成了个梯形，眼睛自己会把它读成「往里去」。
    ///
    /// ⚠️ 这个数一改，**四处要一起改**：落点（`point`）、反查（`tile(at:)`）、
    /// 他能站到哪儿（`walkSpan`）、地砖和地板的形状（`tilePath` / `floorPath`）。
    /// 漏一处就是「家具落在别的格子里」或者「他走出地板外面」。
    static let flatBackNarrow: CGFloat = 0.30

    /// 横着最多能拖多远（点）。左右各这么多。
    ///
    /// 看不见的那几列一共 `cols - flatVisibleCols` 列，左右平分。
    /// 立体屋不拖，返回 0。
    var maxPan: CGFloat {
        guard projection == .flat else { return 0 }
        let hidden = max(0, cols - ClawdStore.flatVisibleCols)
        return CGFloat(hidden) / 2 * tileW
    }

    /// 第 `gy` 排在横向上还剩多宽（1 = 最外那排的宽度）。
    ///
    /// 越靠里越窄，见 `flatBackNarrow`。传进来的 `gy` 允许是
    /// −0.5 或 n−0.5 这种半格（画砖和画整块地板要用到边界）。
    func flatWide(_ gy: Double) -> CGFloat {
        let n = Double(size)
        guard n > 1 else { return 1 }
        let t = min(1.2, max(-0.2, gy / (n - 1)))
        return 1 - Self.flatBackNarrow * CGFloat(1 - t)
    }

    /// 平面那档一排多高（点）
    var rowPitch: CGFloat { tileH * Self.flatRowPitch }

    /// 横着一共几列。
    ///
    /// ⚠️ **凡是「横着数几格」的地方都得走这儿。** 立体屋横竖都是 `size`，
    /// 平面屋横着是 `cols`（36）、竖着才是 `size`（16）。
    /// 顺手写 `size` 的地方一律只铺出 16 列——她报的「平铺视角错误」
    /// 就是地砖那儿犯了这个。
    var across: Int { projection == .flat ? cols : size }

    /// 在这么大的地方里，屋子摆在哪儿、一格多大。
    ///
    /// ⚠️ **只此一份。** 画屋子的那边要用，
    /// 算「clawd 该站在凳子的哪个点上」也要用——
    /// 各算各的必然对不齐，家具和人就永远差半格。
    /// ⚠️ `as:` **没有默认值，是故意的。**
    /// 给个默认值的话，漏传的那一处会悄悄按立体算——屋子画成平面、
    /// 家具按立体落点，两边差半间屋，而且不报错。
    /// 必填的话漏一处编译就过不去。
    /// - Parameter panX: 平面屋横着拖了多远（点）。
    ///
    /// ⚠️ **拖动做在几何这一层，不是在界面上加一个 `offset`。**
    ///
    /// 加 `offset` 的话，画出来挪了，可**算出来没挪**：
    /// 她点屏幕正中，几何还以为那是没拖之前的那一格——
    /// 家具会落在别处，屋子的裁剪边界也会错位。
    /// 挪原点就没有这个问题：落点、反查、地砖、地板、墙、
    /// 他能站到哪儿，全都跟着一起走。
    static func fit(in size: CGSize, as projection: RoomProjection,
                    panX: CGFloat = 0) -> IsoRoom {
        let n = CGFloat(ClawdStore.roomSize)
        // ⚠️ 一格多大，**同时受宽和高两头管**。
        //
        // 她报的「屋子很小，而且有一部分在屏幕下面」就是只按宽算的下场：
        // 宽度够、高度不够，地板加两面墙比容器高，屋子被顶下去一截。
        //
        // 整间屋子竖着一共占：墙(4.2 格高) + 地板(n 格 × 半格高)。
        // 两头各算一次取小的，屋子就一定塞得进去。
        // ⚠️ 平面屋**按看得见几列算格子多大**，不按总列数。
        //
        // 按总列数算的话，18 列全塞进一屏，一格就细成一条——
        // 那等于把屋子横着压扁，而她要的是「屋子更宽、可以拖着看」。
        // 所以一格照 `flatVisibleCols` 列铺满一屏来定，
        // 剩下的列自然落在屏幕外，靠拖动去看（见 `IsoRoomView` 里那个横向偏移）。
        let acrossNow = projection == .flat
            ? CGFloat(ClawdStore.flatVisibleCols) : n
        let byWidth = (size.width * 0.985) / acrossNow
        // ⚠️ 这一条按**最矮的墙**算：先保证「地板 + 一堵矮墙」一定塞得下，
        // 墙具体多高留到下面再定。
        // ⚠️ 分母里那一截是**地板占几个 tileH**，两种投影不一样：
        // 立体是 n/2 + 1，平面是 n × `flatRowPitch`。
        // 抄成同一个数的话，平面那档按立体的深度去挑格子大小，
        // 地板会比算出来的深，屋子被顶出屏幕。
        let floorInTiles = projection == .flat
            ? n * IsoRoom.flatRowPitch
            : n / 2 + 1
        let byHeight = (size.height * 0.94) / (floorInTiles + 4.2)
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
        // 地板竖着占多高。**平面那档比等距的浅**：
        // 等距是「gx + gy」两个方向一起往下走，平面只有纵深那一档在走。
        let floorH = projection == .flat
            ? tileH * n * IsoRoom.flatRowPitch
            : tileH * n / 2 + tileH
        let room = size.height * 0.94 - floorH
        // 平面的墙比等距的稍高一点：它地板铺得浅，按等距那个 7 格封顶的话，
        // 屋子只占屏幕一半，上下各空一大片——那正是她当初说的「小屋太小了」。
        // ⚠️ 上限从 11 降到了 8：地板加深之后（见 `flatRowPitch`）
        // 还按 11 封顶，墙加地板比屋子还宽，看着像口井。
        // ⚠️ 平面那档从 8 降到 5。地板加深到 1.15 之后，
        // 8 格高的墙会把屋子重新压成「上下五五分」——
        // 而她要的正是地板占得多。
        let wallCap: CGFloat = projection == .flat ? 5 : 7
        let wallH = min(max(tileH * 4.2, room), tileH * wallCap)

        // 整块（墙顶到地板最下）的高度，用来把屋子**竖着摆正中**
        let whole = wallH + floorH
        let top = (size.height - whole) / 2
        return IsoRoom(size: ClawdStore.roomSize,
                       cols: projection == .flat
                           ? ClawdStore.flatCols : ClawdStore.roomSize,
                       projection: projection,
                       tileW: tileW, tileH: tileH,
                       wallH: wallH,
                       origin: CGPoint(x: size.width / 2 + panX,
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
        // ⚠️⚠️ **下面要留出他半个身子。**
        //
        // 她报的：「clawd 的活动范围不完全在屋内。」两张图都是他站在
        // 最下那一档，整个人在地板外面。
        //
        // 病根：他是用 `.position` 摆的，那个坐标是**整块的正中**，
        // 不是他的脚。最下那一排的行心已经贴着地板下沿了，
        // 正中摆在那儿，等于半个身子探到屋外。
        // 以前看不出来是因为屋子的裁剪把探出去那半截切掉了——
        // 前几天把前沿的裁剪放开之后（clawd 被切掉半个身子那次），
        // 这件事才露出来。两个症状是同一个根。
        //
        // 留 `tileW * 0.55`：他大约一格半高，半个身子就是这么多。
        let pad = Double(tileW) * 0.55
        let t = min(0.98, max(0.02, topY / h))
        let b = min(0.98, max(0.02, (botY - pad) / h))
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
        // ⚠️ 平面的地板是**矩形**，每一排一样宽——不能套菱形那条收窄。
        // 套了的话他在最里和最外那两排只能站在正中间一点点。
        // ⚠️ 平面的地板现在是**梯形**：最里那排窄、最外那排宽。
        // `t = 0` 是最上（最里）那一头，`t = 1` 是最下（最外）那一头。
        // 还按 1.0 算的话，他在最里那几排会走到地板外面去。
        let wide = projection == .flat
            ? Double(1 - Self.flatBackNarrow * CGFloat(1 - t))
            : 1 - abs(2 * t - 1)
        let n = CGFloat(projection == .flat ? self.cols : self.size)
        // 最宽处的半宽，再往里收一点点，别让他半只挂在边上
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
        if projection == .flat {
            // 平面：`gx` 横着排，`gy` 是纵深——**越靠里越往上一点**。
            //
            // 纵深一排一排往下走，一排 `rowPitch` 高。
            // ⚠️ 原来这儿写的是 `(gy - (n-1)/2) * tileH/2 + tileH*(n-1)/4`，
            // 两截前后抵消，化开就是 `gy * 一排的高度`。抵消掉的写法只是
            // 让人以为这儿有什么讲究，改的时候还得先化简一遍。
            let n = Double(cols)
            return CGPoint(x: origin.x
                            + (gx - (n - 1) / 2) * tileW * flatWide(gy),
                           y: origin.y + CGFloat(gy) * rowPitch)
        }
        return CGPoint(x: origin.x + (gx - gy) * tileW / 2,
                       y: origin.y + (gx + gy) * tileH / 2)
    }

    /// 屏幕上一个点落在哪一格。**可能落在地板外面**，调用方自己判断
    ///
    /// ⚠️ 这是 `point` 的逆。**改了那边一定要跟着改这边**——
    /// 两边对不上的话，她拖一件家具，家具会落在别处。
    func tile(at p: CGPoint) -> (gx: Double, gy: Double) {
        let dx = p.x - origin.x
        let dy = p.y - origin.y
        if projection == .flat {
            let n = Double(cols)
            // ⚠️ **先算 gy 再算 gx。** 横向的宽度是随纵深变的，
            // 不先知道在第几排，就不知道那一排一格有多宽。
            let gy = Double(dy / rowPitch)
            let w = flatWide(gy)
            return (gx: dx / (tileW * w) + (n - 1) / 2, gy: gy)
        }
        return (gx: dy / tileH + dx / tileW,
                gy: dy / tileH - dx / tileW)
    }

    /// 一格地砖从中心到**下沿**有多远。
    ///
    /// ⚠️ 家具是「底边贴着格子下沿」摆的，所以这个数不能写死成 `tileH / 2`——
    /// 平面那档的地砖只有半格高，写死的话一屋子家具会往下沉半格。
    var tileBottom: CGFloat { projection == .flat ? rowPitch / 2 : tileH / 2 }

    /// 这一格在不在地板上
    func inside(_ gx: Int, _ gy: Int) -> Bool {
        gx >= 0 && gy >= 0 && gx < cols && gy < size
    }

    /// 把落点收进地板里
    func clamp(_ gx: Int, _ gy: Int) -> (Int, Int) {
        (min(cols - 1, max(0, gx)), min(size - 1, max(0, gy)))
    }

    /// 一格地砖。等距是菱形，平面是矩形。
    func tilePath(_ gx: Int, _ gy: Int) -> Path {
        let c = point(Double(gx), Double(gy))
        if projection == .flat {
            // ⚠️ 地砖也是**梯形**：上沿（靠里）比下沿（靠外）窄。
            // 画成矩形的话，砖跟砖之间会在斜边上露出锯齿缝。
            let gyD = Double(gy)
            let up = tileW * flatWide(gyD - 0.5) / 2
            let down = tileW * flatWide(gyD + 0.5) / 2
            let top = c.y - rowPitch / 2
            let bottom = c.y + rowPitch / 2
            // ⚠️ 中心 `c.x` 已经带着这一排的收窄了，
            // 所以上下两条边都以它为中心左右摊开，不用再挪。
            var p = Path()
            p.move(to: CGPoint(x: c.x - up, y: top))
            p.addLine(to: CGPoint(x: c.x + up, y: top))
            p.addLine(to: CGPoint(x: c.x + down, y: bottom))
            p.addLine(to: CGPoint(x: c.x - down, y: bottom))
            p.closeSubpath()
            return p
        }
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
        if projection == .flat {
            let a = point(0, 0), b = point(0, n - 1)
            let w = CGFloat(cols)
            let up = tileW * w * flatWide(-0.5) / 2
            let down = tileW * w * flatWide(n - 0.5) / 2
            let top = a.y - rowPitch / 2
            let bottom = b.y + rowPitch / 2
            var p = Path()
            p.move(to: CGPoint(x: origin.x - up, y: top))
            p.addLine(to: CGPoint(x: origin.x + up, y: top))
            p.addLine(to: CGPoint(x: origin.x + down, y: bottom))
            p.addLine(to: CGPoint(x: origin.x - down, y: bottom))
            p.closeSubpath()
            return p
        }
        var p = Path()
        p.move(to: point(0, 0).offsetBy(dy: -tileH / 2))
        p.addLine(to: point(n - 1, 0).offsetBy(dx: tileW / 2))
        p.addLine(to: point(n - 1, n - 1).offsetBy(dy: tileH / 2))
        p.addLine(to: point(0, n - 1).offsetBy(dx: -tileW / 2))
        p.closeSubpath()
        return p
    }

    /// 左边那面墙（`gy = 0` 那一侧往上立起来）。
    ///
    /// ⚠️ **平面那档只有一面后墙**，就走这一个；`rightWallPath` 返回空。
    /// 这么办是为了让画屋子那边一行都不用改——它照旧画两面，
    /// 只是其中一面在平面下什么都没有。
    var leftWallPath: Path {
        let n = Double(size)
        if projection == .flat { return backWallPath }
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
        if projection == .flat { return backWallBase }
        return (point(0, 0).offsetBy(dy: -tileH / 2),
                point(0, n - 1).offsetBy(dx: -tileW / 2))
    }

    var rightWallBase: (CGPoint, CGPoint) {
        let n = Double(size)
        if projection == .flat { return backWallBase }
        return (point(0, 0).offsetBy(dy: -tileH / 2),
                point(n - 1, 0).offsetBy(dx: tileW / 2))
    }

    // MARK: 平面那档的后墙

    /// 后墙的底边：地板最里那一排的上沿，从左到右。
    private var backWallBase: (CGPoint, CGPoint) {
        let n = Double(size)
        _ = n
        // ⚠️ 后墙的宽度要跟**地板最里那条边**一样宽，
        // 不然墙比地板宽出一截，看着像地板缩在墙里面。
        let y = point(0, 0).y - rowPitch / 2
        let half = tileW * flatWide(-0.5) * CGFloat(cols) / 2
        return (CGPoint(x: origin.x - half, y: y),
                CGPoint(x: origin.x + half, y: y))
    }

    /// 后墙：一整块立起来的矩形。
    private var backWallPath: Path {
        let (a, b) = backWallBase
        return Path(CGRect(x: a.x, y: a.y - wallH,
                           width: b.x - a.x, height: wallH))
    }

    /// 右边那面墙（`gx = 0` 那一侧）
    var rightWallPath: Path {
        let n = Double(size)
        if projection == .flat { return Path() }        // 平面没有第二面墙
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

    /// 整间屋的轮廓：地板 + 两面墙拼起来。
    ///
    /// ⚠️ 用来**把家具裁进屋里**。
    ///
    /// 她指出来的：「注意靠墙的木家具，他们都有阴影，
    /// 阴影靠墙就在外面了。」——一点没错，而且是我上一版
    /// 「贴墙那排往墙里挪半格」直接带出来的：
    /// Kenney 那批图**自带一层烘死的投影**，挪到墙根之后，
    /// 那层影子就落到了墙线外面，飘在屋子外的空气里。
    ///
    /// 修法不是把家具挪回来（那她又贴不了墙了），
    /// 是**给屋子加一道边界**：超出屋子轮廓的一律裁掉。
    /// 这样影子该被墙挡住的部分自然就没了，而家具照样贴着墙。
    var roomPath: Path {
        var p = floorPath
        p.addPath(leftWallPath)
        p.addPath(rightWallPath)
        return p
    }

    /// 真拿去裁的那一块：屋子轮廓，**前面多一条裙**。
    ///
    /// 她发的图：clawd 走到最前那排，只剩一个头露在地板上，
    /// 剩下半个身子没了——看着像被小屋盖住了。
    ///
    /// 病根是 `roomPath` 拿去当裁切路径了。这道裁切本来是为了
    /// **挣到墙线外面的家具阴影**（见 `roomPath` 那段）——
    /// 那是上面两条边的事。可地板前面那两条边下面本来就是空气，
    /// 没什么可挡的，却把站在那儿的人一刀切了。
    ///
    /// 人和家具都是**站在格子上、往上长**的：脚在格子里，
    /// 身子在格子之上。所以前面补一条裙，只要比一个人高就够。
    ///
    /// ⚠️ 上面两条边（两面墙）**一点不动**。家具的烘死投影
    /// 还是该被墙吃掉那一块就吃掉。
    ///
    /// ⚠️ 只给 `clipShape` 用。可点范围还是 `roomPath`——
    /// 不然她点地板前面那片空气，会算成点在屋里。
    var clipPath: Path {
        var p = roomPath
        // 地板菱形往下平移一份，两块叠起来就是扫过的那一块。
        // 一个人站在格子上大约就这么高。
        p.addPath(floorPath, transform: CGAffineTransform(translationX: 0, y: wallH * 0.9))
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
