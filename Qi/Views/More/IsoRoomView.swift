import SwiftUI

/// 立体的小屋。
///
/// 她要的：「小屋不仅仅是一个平面，是一个立体的小屋，家具放在上面有立体感……
/// **不穿模不卡顿**。」
///
/// ## 这一版做到了什么
///
/// · 地板是 8×8 格的**等距**地砖，两面墙立起来
/// · 家具**按格子摆**，占几格由 `FurnitureCatalog.shape` 说了算
/// · **谁挡谁由 `格X + 格Y` 决定**——远的先画、近的压在上面。
///   穿模不是「修好了」，是**排序让它不可能发生**
/// · clawd **这一版还没进这个排序**，他画在所有家具上面（理由见 `drawables`）
///
/// ## 还没做（下一轮）
///
/// 家具还是现在这批**正面看的**像素图，摆进等距屋里会有点「立牌」感。
/// 换成真正的等距素材是下一步——但那是**换图**，
/// 几何、遮挡、摆放这一层不用再动。这正是先做这一层的意义。
struct IsoRoomView<Clawd: View>: View {

    @ObservedObject var store: ClawdStore
    /// 现在画的是哪一间。**只画这一间里的家具**
    var room: HomeRoom
    /// clawd 现在站在哪儿（还是老的 0…1 比例，走路那套逻辑一个字没改）
    var clawdX: Double
    var clawdY: Double
    /// 屋子地板在竖直方向占的范围，跟 `ClawdStore.floorTop/floorBottom` 是同一件事
    var floorTop: Double
    var floorBottom: Double

    var onTapFurniture: (Furniture) -> Void
    /// 他现在在这一间吗。不在就不画，也不进排序。
    var clawdHere: Bool = false
    /// clawd 本人。**由调用方给**——他的手势、朝向、走路动画都长在那边，
    /// 搬过来得连着走路那一整套一起搬，不值。
    /// 这儿只负责**把他插进正确的位置**。
    @ViewBuilder var clawd: () -> Clawd

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var dragging: UUID?
    @State private var dragCell: (gx: Int, gy: Int) = (0, 0)
    /// 正拖着的这一件此刻悬在 clawd 身上
    @State private var onClawd = false
    /// 这一块画布多大。判「拖到他身上了没有」要用——
    /// 手势拿到的是屏幕点，他的位置是 0…1 的比例，得有尺寸才换算得了
    @State private var boardSize: CGSize?

    // MARK: 摆出来

    var body: some View {
        GeometryReader { geo in
            // ⚠️ 这个局部变量**不能叫 `room`**。
            //
            // 上面那个属性 `room` 是 `HomeRoom`（现在画哪一间），
            // 这个是 `IsoRoom`（几何）。重名的话属性被遮住，
            // `store.furniture(in: room)` 会把几何当房间传进去——
            // 编译器逮住了，但这已经是这一轮里第几次
            // **同一个名字两个意思**了。所以叫 `geoRoom`。
            let geoRoom = IsoRoom.fit(in: geo.size)

            ZStack(alignment: .topLeading) {
                walls(geoRoom)
                floor(geoRoom)

                // ⚠️ 这一句就是「不穿模」的全部：**按离镜头的远近排好再画**。
                ForEach(drawables(geoRoom), id: \.key) { d in
                    if d.isClawd {
                        clawd()
                    } else if let item = d.item, let kind = d.kind {
                        piece(item, kind, geoRoom)
                    }
                }
            }
            // 拖到他身上的时候，在他脚下点一圈光——
            // **她得看得见「松手就是给他」**，不能靠猜
            .overlay(alignment: .topLeading) {
                if onClawd, let s = boardSize {
                    Circle()
                        .fill(app.settings.accentColor.opacity(0.30))
                        .frame(width: min(s.width, s.height) * 0.26,
                               height: min(s.width, s.height) * 0.26)
                        .position(x: clawdX * s.width, y: clawdY * s.height)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: onClawd)
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                boardSize = geo.size
                store.migrateRoom()
                store.migrateRooms()
            }
            .onChange(of: geo.size) { _, v in boardSize = v }
        }
    }

    // 屋子摆在哪儿、一格多大：在 `IsoRoom.fit(in:)` 里，body 直接叫它。
    // **两边得算的是同一份**——clawd 那边要把「坐到凳子上」
    // 换算成屏幕位置，各算各的必然对不齐。

    // MARK: 地和墙

    private func floor(_ geoRoom: IsoRoom) -> some View {
        // 这一格字符串里装着两种东西：**她自己那张图的文件名**，
        // 或者**内置那几档的记号**（`#wood` 这种）。
        // UUID 里不会出现井号，所以一个字符串就够分，不用加第二个字段。
        let token = store.flooring(of: room)
        let boards = RoomFinish.isBuiltIn(token) ? nil : ImageStore.cached(token)
        return ZStack(alignment: .topLeading) {
            if let boards {
                // 她自己那张地板。跟墙纸一个道理：**按菱形裁**。
                //
                // ⚠️ 图必须放在 `Color.clear` 的 **overlay** 里，
                // 不能直接当 ZStack 的一个孩子摆进去。
                //
                // 她报的「随便用一张图做地板，小屋整体往左移了」
                // 根就在这儿：`.scaledToFill()` 报回来的尺寸是
                // **盖满提议尺寸的那个尺寸**，它比提议的大。
                // ZStack 跟着变大，外面那句 `.frame(width:height:)`
                // 再把变大的内容**居中**——整间屋就歪了。
                // 而歪了之后，裁形的 Path 还在原坐标上，
                // 于是看着就像「没切割」——两个症状是同一件事。
                //
                // `Color.clear` 是个老实人：提议多大它就多大。
                // 图在它的 overlay 里溢出去不影响布局，溢的那圈被 clipShape 剪掉。
                Color.clear
                    .overlay {
                        Image(uiImage: boards)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    }
                    .clipShape(geoRoom.floorPath)
            } else {
                // ⚠️ 棋盘格那一版**也走这儿**，不再单独写一遍。
                // `RoomFinish.floor("")` 就是 `.checker`，画出来跟原来一模一样
                // （连色号都是同两个）。
                // 同一件事只留一个算法——留两个的话，改了一个另一个就开始撒谎。
                FloorFinishView(kind: RoomFinish.floor(token),
                                room: geoRoom, scheme: scheme)
            }
            // 正在拖的那一件，把它要落的几格点亮
            if let id = dragging,
               let f = store.furniture(in: room).first(where: { $0.id == id }) {
                let s = FurnitureCatalog.shape(of: f.kind)
                // 键得是「x,y」这种唯一的串。用 `\.0`（只有 x）的话，
                // 一件占两行的家具会有两格键一样，SwiftUI 只画得出一格
                ForEach(IsoRoom.cells(dragCell.gx, dragCell.gy, s.w, s.d)
                            .map { "\($0.0),\($0.1)" }, id: \.self) { key in
                    let parts = key.split(separator: ",").compactMap { Int($0) }
                    if parts.count == 2, geoRoom.inside(parts[0], parts[1]) {
                        geoRoom.tilePath(parts[0], parts[1])
                            .fill(app.settings.accentColor.opacity(0.28))
                    }
                }
            }
            geoRoom.floorPath
                .stroke(Color.black.opacity(scheme == .dark ? 0.28 : 0.10), lineWidth: 1)
        }
    }

    private func walls(_ geoRoom: IsoRoom) -> some View {
        // 跟地板一样：这个字符串要么是她那张图的文件名，要么是内置的记号
        let token = store.wallpaper(of: room)
        let paper = RoomFinish.isBuiltIn(token) ? nil : ImageStore.cached(token)
        let finish = RoomFinish.wall(token)
        return ZStack(alignment: .topLeading) {
            // 她自己那张墙纸。**必须按墙的形状裁**——
            // 直接贴一张矩形上去就是一块补丁盖在屋子上，两面墙全糊住了。
            //
            // 所以图铺满，再用 `leftWallPath` / `rightWallPath` 去 `clipShape`。
            // 两面墙裁的是同一张图的不同部位，接缝天然对得上。
            //
            // ⚠️ 右面墙要**压暗一档**。等距屋的立体感八成来自
            // 「两个面不是同一个亮度」——同一张图原样贴两面，屋子会瞬间变回一张折纸。
            if let paper {
                // ⚠️ 跟地板一样，图要藏在 `Color.clear` 的 overlay 里。
                // 直接摆进 ZStack 的话，`.scaledToFill()` 会把整个 ZStack 擑大，
                // 屋子跟着偏一边、裁形也就对不上了。
                // （她报的「小屋往左移」+「没切割」就是这一件事。）
                Color.clear
                    .overlay {
                        Image(uiImage: paper)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    }
                    .clipShape(geoRoom.leftWallPath)
                Color.clear
                    .overlay {
                        Image(uiImage: paper)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    }
                    .clipShape(geoRoom.rightWallPath)
                    .overlay {
                        geoRoom.rightWallPath.fill(Color.black.opacity(0.16))
                    }
            } else {
                // 内置那几档。`.plain` 就是原来那版纯色——
                // `WallFinishView` 碰上 `.plain` 只铺底色，什么花纹都不画，
                // 所以「什么都没选」和「选了纯色」走的是同一条路。
                //
                // ⚠️ 右面墙照旧**压暗一档**。等距屋的立体感八成来自
                // 「两个面不是同一个亮度」——花纹换了，这条不能跟着换掉。
                WallFinishView(kind: finish, base: geoRoom.leftWallBase,
                               height: geoRoom.wallH, tone: wallL, seam: seamTone)
                    .clipShape(geoRoom.leftWallPath)
                WallFinishView(kind: finish, base: geoRoom.rightWallBase,
                               height: geoRoom.wallH, tone: wallR, seam: seamTone)
                    .clipShape(geoRoom.rightWallPath)
            }
            geoRoom.leftWallPath.stroke(Color.black.opacity(0.08), lineWidth: 1)
            geoRoom.rightWallPath.stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    // 两面墙**不能同一个色**——同色的两个面拼在一起就是一张折纸，
    // 差一档明暗才有「光从一边来」的立体感
    private var wallL: Color {
        scheme == .dark ? Color(hexString: "2E2926")! : Color(hexString: "F1E9DB")!
    }
    private var wallR: Color {
        scheme == .dark ? Color(hexString: "262220")! : Color(hexString: "E3D9C7")!
    }
    /// 墙上砖缝／条纹那条线的颜色。
    /// 比墙深一档就够——深太多就成了黑线框，那是漫画不是墙
    private var seamTone: Color {
        Color.black.opacity(scheme == .dark ? 0.30 : 0.14)
    }
    // ⚠️ `floorA` / `floorB` **删掉了**，别再加回来。
    //
    // 棋盘格那两个色现在只在 `FloorFinishView.tone` 里有一份
    // （`.checker` 那一档，色号一个没改）。
    // 这儿留一份「以后说不定用得上」的副本，就是留了两个真相——
    // 哪天调了一个，另一个开始撒谎，而且谁都不会发现。

    // MARK: 谁先画

    private struct Drawable {
        let key: String
        let depth: Double
        let tall: Double
        /// clawd 那一条这两样是空的
        let item: Furniture?
        let kind: FurnitureKind?
        var isClawd: Bool { item == nil }
    }

    /// 屋里所有会挡人的东西，**按远近排好**。
    private func drawables(_ geoRoom: IsoRoom) -> [Drawable] {
        var out: [Drawable] = []

        // ⚠️ **只取这一间的**。一整个家的东西全堆进一间屋，
        // 就是她说的「桌子凳子对这个屋子来说特别大、clawd 完全不能住」。
        for f in store.furniture(in: room) {
            guard let kind = FurnitureCatalog.kind(f.kind) else { continue }
            let s = FurnitureCatalog.shape(of: f.kind)
            let cell = (f.id == dragging) ? dragCell : (gx: f.gx, gy: f.gy)
            // 一件占好几格的东西，**按它最靠近镜头的那一格算深度**——
            // 按中心算的话，一张床的床尾会被站在床尾旁边的人盖住
            // ⚠️ 拆成三步。写成一长串加减混着 `Double(...)`，
            // 编译器会在这一行上卡到超时。
            let farX: Int = cell.gx + s.w - 1
            let farY: Int = cell.gy + s.d - 1
            let depth = Double(farX + farY)
            out.append(Drawable(key: f.id.uuidString, depth: depth,
                                tall: s.tall, item: f, kind: kind))
        }

        // clawd 也进来。**这就是「他站在床后面就该被床挡住」的全部。**
        if clawdHere {
            out.append(Drawable(key: "clawd", depth: clawdDepth(
                CGPoint(x: clawdX, y: clawdY), geoRoom),
                                tall: 1, item: nil, kind: nil))
        }

        // ## clawd 进来了（上一版他永远画在最前面）
        //
        // 当初推掉的理由是「他按 0…1 走路、家具按格子摆，两套坐标」。
        // 那个理由**已经不成立了**——修「他的活动区域没跟着屋子挪」的时候，
        // `IsoRoom.walkBand` 把他的 0…1 和地板对齐了，
        // 于是 `clawdDepth` 算出来的进深跟家具是同一把尺。
        //
        // 他的手势、朝向、走路动画还留在调用方那边（搬过来不值），
        // 这儿只是**把他插进正确的位置**：
        // 站在床里侧就被床挡住，站在床外侧就压在床前面。
        //
        // ⚠️ 他的 `tall` 给 1：跟别人同一格的时候，
        // 他压在地毯上面（tall 0）、被高柜挡住（tall 2）。

        return IsoRoom.order(out, depth: { $0.depth }, height: { $0.tall }, tie: { $0.key })
    }

    /// 她那张图按这个宽度画出来会有多高
    private func mineH(_ img: UIImage, width: CGFloat) -> CGFloat {
        guard img.size.width > 0 else { return width }
        return width * img.size.height / img.size.width
    }

    /// clawd 站的那一格有多远。**下一步他进排序的时候要用**，先留着。
    ///
    /// 他还是按 0…1 的比例走路（那套逻辑一个字没改），
    /// 这儿把比例换算成地板上的进深：`floorTop` 是最里边，`floorBottom` 是最外边。
    private func clawdDepth(_ p: CGPoint, _ geoRoom: IsoRoom) -> Double {
        let span = max(0.0001, floorBottom - floorTop)
        let deep = min(1, max(0, (p.y - floorTop) / span))
        return deep * Double(geoRoom.size * 2 - 2)
    }

    // MARK: 一件家具

    private func piece(_ item: Furniture, _ kind: FurnitureKind,
                       _ geoRoom: IsoRoom) -> some View {
        let s = FurnitureCatalog.shape(of: kind.id)
        let cell = (item.id == dragging) ? dragCell : (gx: item.gx, gy: item.gy)
        // 落脚点：它盖住那几格的正中间
        let c = geoRoom.point(Double(cell.gx) + Double(s.w - 1) / 2,
                           Double(cell.gy) + Double(s.d - 1) / 2)
        // 她自己的图排第一。
        //
        // 三档：**她导的图 > 我画的等距版 > 老那张正面图**。
        // 一件一件换过去，中间任何一天她打开都不会缺东西。
        let mine = ImageStore.cached(item.imageName)
        let iso = FurnitureCatalog.isoSprite(of: kind.id)
        let sprite = iso ?? kind.sprite

        let scale: CGFloat
        let lift: CGFloat
        if iso != nil {
            // 等距图是按「一格 = 2×unit 像素」画的，所以缩放是个定值，
            // **跟这张图多大无关**——一屋子家具因此严丝合缝对在同一套地砖上。
            scale = geoRoom.tileW / CGFloat(2 * IsoArt.unit)
            // 图的中心比它**底面**的中心高 hi/2 像素（hi 是这件东西画出来多高）。
            // 不把这一截补回去，家具会整体浮在格子上方半个身位。
            let hiPx = CGFloat(sprite.height - 2)
                - CGFloat(s.w + s.d) * CGFloat(IsoArt.unit) / 2
            lift = -max(0, hiPx) / 2 * scale
        } else {
            // ⚠️ **不再额外放大。**
            //
            // 她说「新买的桌子凳子对于这个屋子来说特别大」——
            // 以前这儿乘了 1.15，一件占两格的桌子画出来比两格还宽。
            // 现在**画多宽就是它占多少格**。
            scale = geoRoom.tileW * CGFloat(max(1, s.w)) / CGFloat(max(6, sprite.width))
            // 正面图那批：底边贴着格子（地毯除外，它是摊在地上的）
            lift = s.tall > 0 ? -CGFloat(sprite.height) * scale / 2 + geoRoom.tileH / 2 : 0
        }
        let lifted = item.id == dragging

        // 她自己那张图占多宽：**按它占几格算**，不看图本身多少像素。
        // 这样她导进来的图不管多大，摆在屋里都是这件家具该有的大小。
        let mineW = geoRoom.tileW * CGFloat(s.w + s.d) / 2

        return VStack(spacing: 0) {
            if let mine {
                Image(uiImage: mine)
                    .resizable()
                    .interpolation(.none)          // 像素图**不许插值**，糊了就不是像素画了
                    .aspectRatio(contentMode: .fit)
                    .frame(width: mineW)
            } else {
                PixelSpriteView(sprite: sprite, scale: scale)
            }
        }
        // 她的图是**贴边裁过**的（导入时裁的），
        // 所以底边就是这件东西的落脚线：往上抬半张图，再压回格子上
        .offset(y: mine == nil ? lift : -mineH(mine!, width: mineW) / 2 + geoRoom.tileH / 2)
        .scaleEffect(lifted ? 1.06 : 1)
        .shadow(color: .black.opacity(lifted ? 0.28 : 0.12),
                radius: lifted ? 10 : 3, y: lifted ? 8 : 2)
        // ⚠️ 命中形状必须在 `.position` **前面**：`.position` 会把视图撑满整屋，
        // 挂在它后面的话每件家具的可点范围都是整间屋子
        // 她的图按整块矩形算命中（图里哪儿是空的我们不再逐像素查——
        // 那得每帧扫一遍位图，不值）；我画的那批还是按格子围形
        .contentShape(mine == nil
                      ? AnyShape(SpriteHitShape(sprite: sprite))
                      : AnyShape(Rectangle()))
        .position(x: c.x, y: c.y)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: lifted)
        .onTapGesture { onTapFurniture(item) }
        .gesture(dragGesture(item, s, geoRoom))
    }

    private func dragGesture(_ item: Furniture, _ s: IsoShape,
                             _ geoRoom: IsoRoom) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .onEnded { _ in
                dragging = item.id
                dragCell = (item.gx, item.gy)
                if app.settings.haptics {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(_, let drag?) = value else { return }
                // 拖到他身上了没有。**拖的过程里就得知道**——
                // 不然她一路拖过去，到松手那一刻才知道行不行
                onClawd = nearClawd(drag.location)
                let t = geoRoom.tile(at: drag.location)
                let (gx, gy) = geoRoom.clamp(Int(t.gx.rounded()), Int(t.gy.rounded()))
                if gx != dragCell.gx || gy != dragCell.gy {
                    dragCell = (gx, gy)
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
            }
            .onEnded { value in
                guard dragging == item.id else { return }
                dragging = nil
                let dropped = onClawd
                onClawd = false

                // ⚠️ **递给他。**
                //
                // 她说「我拖给 clawd 的家具他并没有搬起来，是动画还没画吗」——
                // 不是。动画一直都在（`.hauling` / `.carrying` 那两档，
                // 举过头顶的还有 `ClawdRig` 那一套真的举着）。
                // **是这个手势根本没接过**：`store.pickUp` 在整个小屋里
                // 一次都没被调用过，只有聊天页那只浮窗宠物在用。
                // 她拖过去松手，代码做的事跟拖到别处一模一样——摆到格子上。
                //
                // 现在松手落在他身上就交给他：他举起来、开始搬，
                // 走到地方自己放下（`startWalking` 里那一段本来就写好了）。
                if dropped {
                    store.pickUp(item.kind)
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    }
                    return
                }
                store.place(item.id, at: dragCell.gx, dragCell.gy)
            }
    }

    /// 这个点是不是落在 clawd 身上。
    ///
    /// 判定给得**比他本人宽一圈**：她是在拖一件家具，
    /// 手指被家具挡着看不见落点，卡太死会一直递不上。
    private func nearClawd(_ p: CGPoint) -> Bool {
        guard let s = boardSize, s.width > 1, s.height > 1 else { return false }
        let cx = clawdX * s.width
        let cy = clawdY * s.height
        let reach = min(s.width, s.height) * 0.13
        return abs(p.x - cx) < reach && abs(p.y - cy) < reach
    }
}
