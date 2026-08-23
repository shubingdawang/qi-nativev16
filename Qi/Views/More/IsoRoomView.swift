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
struct IsoRoomView: View {

    @ObservedObject var store: ClawdStore
    /// clawd 现在站在哪儿（还是老的 0…1 比例，走路那套逻辑一个字没改）
    var clawdX: Double
    var clawdY: Double
    /// 屋子地板在竖直方向占的范围，跟 `ClawdStore.floorTop/floorBottom` 是同一件事
    var floorTop: Double
    var floorBottom: Double

    var onTapFurniture: (Furniture) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var dragging: UUID?
    @State private var dragCell: (gx: Int, gy: Int) = (0, 0)

    // MARK: 摆出来

    var body: some View {
        GeometryReader { geo in
            let room = geometry(in: geo.size)

            ZStack(alignment: .topLeading) {
                walls(room)
                floor(room)

                // ⚠️ 这一句就是「不穿模」的全部：**按离镜头的远近排好再画**。
                ForEach(drawables(room), id: \.key) { d in
                    piece(d.item, d.kind, room)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { store.migrateRoom() }
        }
    }

    /// 屋子摆在哪儿、一格多大。
    ///
    /// 地板宽度按屋子宽的九成算，**留一点边**——顶到边上的话
    /// 最外圈那几格永远有一半在屏幕外，她放不进去东西。
    private func geometry(in size: CGSize) -> IsoRoom {
        let n = CGFloat(ClawdStore.roomSize)
        let tileW = (size.width * 0.92) / n
        let tileH = tileW / 2
        return IsoRoom(size: ClawdStore.roomSize,
                       tileW: tileW, tileH: tileH,
                       wallH: tileH * 4.2,
                       // 地板最上面那个尖：横着居中，竖着让整块地板落在下半屏
                       origin: CGPoint(x: size.width / 2,
                                       y: size.height - tileH * n / 2 - tileH * 1.2))
    }

    // MARK: 地和墙

    private func floor(_ room: IsoRoom) -> some View {
        ZStack(alignment: .topLeading) {
            // 一格一格画，**深浅交替**——不这么画的话地板是一整块色，
            // 立体感全靠两面墙撑着，一眼看过去还是平的
            ForEach(0..<(room.size * room.size), id: \.self) { i in
                let gx = i / room.size, gy = i % room.size
                room.tilePath(gx, gy)
                    .fill((gx + gy) % 2 == 0 ? floorA : floorB)
            }
            // 正在拖的那一件，把它要落的几格点亮
            if let id = dragging,
               let f = store.owned.first(where: { $0.id == id }) {
                let s = FurnitureCatalog.shape(of: f.kind)
                // 键得是「x,y」这种唯一的串。用 `\.0`（只有 x）的话，
                // 一件占两行的家具会有两格键一样，SwiftUI 只画得出一格
                ForEach(IsoRoom.cells(dragCell.gx, dragCell.gy, s.w, s.d)
                            .map { "\($0.0),\($0.1)" }, id: \.self) { key in
                    let parts = key.split(separator: ",").compactMap { Int($0) }
                    if parts.count == 2, room.inside(parts[0], parts[1]) {
                        room.tilePath(parts[0], parts[1])
                            .fill(app.settings.accentColor.opacity(0.28))
                    }
                }
            }
            room.floorPath
                .stroke(Color.black.opacity(scheme == .dark ? 0.28 : 0.10), lineWidth: 1)
        }
    }

    private func walls(_ room: IsoRoom) -> some View {
        ZStack(alignment: .topLeading) {
            room.leftWallPath.fill(wallL)
            room.rightWallPath.fill(wallR)
            room.leftWallPath.stroke(Color.black.opacity(0.08), lineWidth: 1)
            room.rightWallPath.stroke(Color.black.opacity(0.08), lineWidth: 1)
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
    private var floorA: Color {
        scheme == .dark ? Color(hexString: "3B322A")! : Color(hexString: "D7C6A9")!
    }
    private var floorB: Color {
        scheme == .dark ? Color(hexString: "352D26")! : Color(hexString: "CFBD9E")!
    }

    // MARK: 谁先画

    private struct Drawable {
        let key: String
        let depth: Double
        let tall: Double
        let item: Furniture
        let kind: FurnitureKind
    }

    /// 屋里所有会挡人的东西，**按远近排好**。
    private func drawables(_ room: IsoRoom) -> [Drawable] {
        var out: [Drawable] = []

        for f in store.owned where !f.hidden && !f.carried {
            guard let kind = FurnitureCatalog.kind(f.kind) else { continue }
            let s = FurnitureCatalog.shape(of: f.kind)
            let cell = (f.id == dragging) ? dragCell : (gx: f.gx, gy: f.gy)
            // 一件占好几格的东西，**按它最靠近镜头的那一格算深度**——
            // 按中心算的话，一张床的床尾会被站在床尾旁边的人盖住
            let depth = Double(cell.gx + s.w - 1 + cell.gy + s.d - 1)
            out.append(Drawable(key: f.id.uuidString, depth: depth,
                                tall: s.tall, item: f, kind: kind))
        }

        // ⚠️ **clawd 这一版还没进这个排序**，他画在所有家具上面。
        //
        // 让他也进来是下一小步：他还是按 0…1 的比例走路（那套逻辑一个字没改），
        // 要进排序就得把他的比例换算成地板进深，
        // 而他的手势、朝向、走路动画都挂在调用方那边——
        // 这一刀得连着走路那套一起改，不该跟「屋子立起来」混在一轮里。
        //
        // 现在的样子：**家具之间的遮挡是对的**（这是主要的那一半），
        // 他永远在前面——那不是穿模，是很多像素游戏里主角的常规画法。

        return IsoRoom.order(out, depth: { $0.depth }, height: { $0.tall }, tie: { $0.key })
    }

    /// clawd 站的那一格有多远。**下一步他进排序的时候要用**，先留着。
    ///
    /// 他还是按 0…1 的比例走路（那套逻辑一个字没改），
    /// 这儿把比例换算成地板上的进深：`floorTop` 是最里边，`floorBottom` 是最外边。
    private func clawdDepth(_ p: CGPoint, _ room: IsoRoom) -> Double {
        let span = max(0.0001, floorBottom - floorTop)
        let deep = min(1, max(0, (p.y - floorTop) / span))
        return deep * Double(room.size * 2 - 2)
    }

    // MARK: 一件家具

    private func piece(_ item: Furniture, _ kind: FurnitureKind,
                       _ room: IsoRoom) -> some View {
        let s = FurnitureCatalog.shape(of: kind.id)
        let cell = (item.id == dragging) ? dragCell : (gx: item.gx, gy: item.gy)
        // 落脚点：它盖住那几格的正中间
        let c = room.point(Double(cell.gx) + Double(s.w - 1) / 2,
                           Double(cell.gy) + Double(s.d - 1) / 2)
        let scale = room.tileW / CGFloat(max(6, kind.sprite.width)) * CGFloat(max(1, s.w)) * 1.15
        let lifted = item.id == dragging

        return VStack(spacing: 0) {
            PixelSpriteView(sprite: kind.sprite, scale: scale)
        }
        // 地毯这类是**摊在地上**的，别的东西该站在格子上（往上抬半格）
        .offset(y: s.tall > 0 ? -CGFloat(kind.sprite.height) * scale / 2 + room.tileH / 2 : 0)
        .scaleEffect(lifted ? 1.06 : 1)
        .shadow(color: .black.opacity(lifted ? 0.28 : 0.12),
                radius: lifted ? 10 : 3, y: lifted ? 8 : 2)
        // ⚠️ 命中形状必须在 `.position` **前面**：`.position` 会把视图撑满整屋，
        // 挂在它后面的话每件家具的可点范围都是整间屋子
        .contentShape(SpriteHitShape(sprite: kind.sprite))
        .position(x: c.x, y: c.y)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: lifted)
        .onTapGesture { onTapFurniture(item) }
        .gesture(dragGesture(item, s, room))
    }

    private func dragGesture(_ item: Furniture, _ s: IsoShape,
                             _ room: IsoRoom) -> some Gesture {
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
                let t = room.tile(at: drag.location)
                let (gx, gy) = room.clamp(Int(t.gx.rounded()), Int(t.gy.rounded()))
                if gx != dragCell.gx || gy != dragCell.gy {
                    dragCell = (gx, gy)
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
            }
            .onEnded { _ in
                guard dragging == item.id else { return }
                dragging = nil
                store.place(item.id, at: dragCell.gx, dragCell.gy)
            }
    }
}
