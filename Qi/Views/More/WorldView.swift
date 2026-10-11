import SwiftUI

/// 小岛：一格一格铺地、摆东西，两个人在上面走、一起做事。
struct WorldView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var world = WorldStore.shared
    @ObservedObject private var room = ClawdStore.shared
    @ObservedObject private var pieces = PieceStore.shared

    enum Mode: String, CaseIterable, Identifiable {
        case walk, place, ground, remove
        var id: String { rawValue }
        var label: String {
            switch self {
            case .walk: return "走走"
            case .place: return "摆东西"
            case .ground: return "铺地"
            case .remove: return "拿走"
            }
        }
        var icon: String {
            switch self {
            case .walk: return "figure.walk"
            case .place: return "square.on.square"
            case .ground: return "square.grid.3x3.fill"
            case .remove: return "trash"
            }
        }
    }

    @State private var mode: Mode = .walk
    @State private var groundPick: WorldGround = .wood
    @State private var itemPick: String?
    @State private var itemFilter: FurnitureKind.Category = .furniture
    @State private var menuFor: WorldObject?
    @State private var decorMenu: WorldDecor?
    @State private var decorPick: WorldDecorKind?
    @State private var sceneryTab = false
    @State private var personMenu = false
    @State private var showMods = false
    @State private var soilAt: (x: Int, y: Int)?
    @State private var fishing = false
    @State private var caught: String?

    /// 一格 48 点 = 素材里 16 像素放大三倍
    private let tile: CGFloat = 48
    /// 岛外面留多宽的海（放大缩小、拖到边上都还是海）
    private let seaPad: CGFloat = 48 * 10

    // 两个人在画面上的位置：存档里是「要去哪一格」，这里一步一步走过去
    @StateObject private var herWalk = IslandWalker(WorldStore.shared.save.herX, WorldStore.shared.save.herY, step: 0.2)
    @StateObject private var himWalk = IslandWalker(WorldStore.shared.save.himX, WorldStore.shared.save.himY, step: 0.24)

    // 镜头：两指捏合缩放、单指拖动
    @State private var zoom: CGFloat = 0.8
    @State private var zoomStart: CGFloat?
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var framed = false

    private var him: String { app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName }

    var body: some View {
        VStack(spacing: 0) {
            island
            bottom
        }
        .onChange(of: world.save.herX * 1000 + world.save.herY) { _, _ in
            herWalk.walk(to: world.save.herX, world.save.herY) { world.route(from: $0, to: $1) }
        }
        .onChange(of: world.save.himX * 1000 + world.save.himY) { _, _ in
            himWalk.walk(to: world.save.himX, world.save.himY) { world.route(from: $0, to: $1) }
        }
        .navigationTitle("小岛")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMods = true } label: { Image(systemName: "puzzlepiece.extension") }
            }
        }
        .sheet(isPresented: $showMods) { modsSheet.presentationDetents([.medium, .large]) }
        .confirmationDialog(menuFor.map { world.name(of: $0) } ?? "", isPresented: Binding(
            get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }), titleVisibility: .visible) {
            if let o = menuFor {
                ForEach(world.actions(for: o)) { a in
                    Button(a.name) { doAction(a, on: o) }
                }
                Button("走过去") { world.walkHer(o.x, min(o.y + 1, world.height - 1)) }
            }
            Button("算了", role: .cancel) { menuFor = nil }
        }
        .confirmationDialog(soilTitle, isPresented: Binding(get: { soilAt != nil }, set: { if !$0 { soilAt = nil } }),
                            titleVisibility: .visible) {
            if let at = soilAt {
                if let c = world.crop(at.x, at.y) {
                    if WorldFarm.stage(c) == 3 {
                        Button("收") { world.harvest(at.x, at.y, byHer: true) }
                    }
                    Button("浇水") { world.water(at.x, at.y, byHer: true) }
                } else {
                    ForEach(WorldFarm.seeds) { s in
                        Button("种\(s.name)（约 \(Int(s.hours)) 小时熟）") { world.plant(s, at.x, at.y, byHer: true) }
                    }
                }
            }
            Button("算了", role: .cancel) { soilAt = nil }
        }
        .alert(caught.map { "钓到了\($0)" } ?? "", isPresented: Binding(get: { caught != nil }, set: { if !$0 { caught = nil } })) {
            Button("放进篮子") { caught = nil }
        }
        .confirmationDialog(decorMenu.flatMap { WorldDecorKind.resolve($0.kind)?.label } ?? "",
                            isPresented: Binding(get: { decorMenu != nil }, set: { if !$0 { decorMenu = nil } }),
                            titleVisibility: .visible) {
            if let d = decorMenu {
                ForEach(world.actions(forDecor: d)) { a in
                    Button(a.name) {
                        let line = world.perform(a, onDecor: d, byHer: true)
                        app.tellHim("小岛上，" + line)
                        decorMenu = nil
                    }
                }
            }
            Button("算了", role: .cancel) { decorMenu = nil }
        }
        .confirmationDialog(him, isPresented: $personMenu, titleVisibility: .visible) {
            ForEach(world.personActions) { a in
                Button(a.name) { doAction(a, on: nil) }
            }
            Button("算了", role: .cancel) {}
        }
    }

    /// 晚上亮着的：每座房子的门窗
    private var nightLights: [CGPoint] {
        let sc = tile / CGFloat(IslandArt.px)
        return world.decor.compactMap { d -> CGPoint? in
            guard let k = WorldDecorKind.resolve(d.kind), k.isHouse else { return nil }
            let s = IslandArt.size(of: k.sprite)
            return CGPoint(x: CGFloat(d.x) * tile + s.width * sc / 2, y: CGFloat(d.y + 1) * tile - 14 * sc)
        }
    }

    /// 海：素材里的水铺满
    @ViewBuilder
    private var sea: some View {
        if let img = IslandArt.sea {
            Image(uiImage: img).resizable(resizingMode: .tile)
        } else {
            Color(hexString: "6FC3D6")!
        }
    }

    private var soilTitle: String {
        guard let at = soilAt else { return "" }
        guard let c = world.crop(at.x, at.y), let s = WorldFarm.seed(c.kind) else { return "一块空田" }
        return s.name + "：" + ["刚种下", "发芽了", "长叶了", "熟了"][WorldFarm.stage(c)] + (c.waters > 0 ? " · 浇过 \(c.waters) 次水" : "")
    }

    private func doAction(_ a: WorldAction, on o: WorldObject?) {
        let line = world.perform(a, on: o, byHer: true)
        // 告诉他，他在聊天里接着演
        app.tellHim("小岛上，" + line)
        menuFor = nil
    }

    // MARK: 镜头

    private var island: some View {
        GeometryReader { geo in
            let content = CGSize(width: CGFloat(world.width) * tile + seaPad * 2,
                                 height: CGFloat(world.height) * tile + seaPad * 2)
            map
                .padding(seaPad)
                .background(sea)
                .frame(width: content.width, height: content.height)
                .scaleEffect(zoom)
                .offset(pan)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture(geo.size, content).simultaneously(with: zoomGesture(geo.size, content)))
                .simultaneousGesture(SpatialTapGesture().onEnded { v in
                    if let c = cell(at: v.location, geo.size, content) { tap(c.0, c.1, moved: false) }
                })
                .onAppear {
                    guard !framed else { return }
                    framed = true
                    look(at: herWalk.pos, geo.size, content)
                }
        }
        .background(sea.ignoresSafeArea())
    }

    /// 屏幕上的点 → 岛上第几格
    private func cell(at p: CGPoint, _ screen: CGSize, _ content: CGSize) -> (Int, Int)? {
        let mx = (p.x - screen.width / 2 - pan.width) / zoom + content.width / 2 - seaPad
        let my = (p.y - screen.height / 2 - pan.height) / zoom + content.height / 2 - seaPad
        let x = Int(floor(mx / tile)), y = Int(floor(my / tile))
        guard x >= 0, y >= 0, x < world.width, y < world.height else { return nil }
        return (x, y)
    }

    private func minZoom(_ screen: CGSize, _ content: CGSize) -> CGFloat {
        max(0.3, screen.width / content.width, screen.height / content.height)
    }

    /// 拖到哪儿都不露出海外面
    private func clamp(_ p: CGSize, _ screen: CGSize, _ content: CGSize, _ z: CGFloat) -> CGSize {
        let mx = max(0, (content.width * z - screen.width) / 2), my = max(0, (content.height * z - screen.height) / 2)
        return CGSize(width: min(mx, max(-mx, p.width)), height: min(my, max(-my, p.height)))
    }

    /// 镜头对准某一格
    private func look(at t: CGPoint, _ screen: CGSize, _ content: CGSize) {
        let px = seaPad + t.x * tile + tile / 2 - content.width / 2
        let py = seaPad + t.y * tile + tile / 2 - content.height / 2
        pan = clamp(CGSize(width: -px * zoom, height: -py * zoom), screen, content, zoom)
        panStart = pan
    }

    private func dragGesture(_ screen: CGSize, _ content: CGSize) -> some Gesture {
        DragGesture(minimumDistance: mode == .ground ? 0 : 6)
            .onChanged { v in
                guard zoomStart == nil else { return }
                if mode == .ground {
                    // 铺地：手指划过的格子都铺上
                    if let c = cell(at: v.location, screen, content) { world.setGround(groundPick, c.0, c.1) }
                    return
                }
                pan = clamp(CGSize(width: panStart.width + v.translation.width, height: panStart.height + v.translation.height),
                            screen, content, zoom)
            }
            .onEnded { _ in panStart = pan }
    }

    private func zoomGesture(_ screen: CGSize, _ content: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomStart == nil { zoomStart = zoom; panStart = pan }
                guard let z0 = zoomStart else { return }
                let z = min(2.2, max(minZoom(screen, content), z0 * v.magnification))
                // 以屏幕中间为准缩放
                pan = clamp(CGSize(width: panStart.width * z / z0, height: panStart.height * z / z0), screen, content, z)
                zoom = z
            }
            .onEnded { _ in
                zoomStart = nil
                panStart = pan
            }
    }

    // MARK: 地图

    private var map: some View {
        let w = CGFloat(world.width) * tile, h = CGFloat(world.height) * tile
        return ZStack(alignment: .topLeading) {
            IslandGround(ground: world.save.ground, width: world.width, height: world.height, tile: tile)
                .equatable()
            if world.farmOn { cropLayer }
            // 摆东西、铺地、拿走的时候显示淡淡的格线，方便对位置
            if mode != .walk { gridLines }
            // 景、摆的东西、两个人按脚下那一行排前后：站在树下面一行的人挡住树，站在树后面的被树挡住
            ZStack(alignment: .topLeading) {
                ForEach(world.decor) { d in
                    decorView(d).zIndex(Double(d.y) + 0.5)
                }
                ForEach(world.save.objects) { o in
                    objectView(o).zIndex(Double(o.y) + 0.6)
                }
                her.zIndex(Double(herWalk.pos.y) + 0.7)
                himView.zIndex(Double(himWalk.pos.y) + 0.75)
            }
            .frame(width: w, height: h, alignment: .topLeading)
            AmbientLayer(width: world.width, height: world.height, tile: tile,
                         night: WorldStore.isNight, lights: nightLights)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    private func tap(_ x: Int, _ y: Int, moved: Bool) {
        guard x >= 0, y >= 0, x < world.width, y < world.height else { return }
        switch mode {
        case .walk:
            guard !moved else { return }
            if x == world.save.himX && y == world.save.himY { personMenu = true; return }
            if let o = world.object(at: x, y) { menuFor = o; return }
            if let d = world.decor(at: x, y, base: true), !world.actions(forDecor: d).isEmpty { decorMenu = d; return }
            if world.farmOn, world.ground(x, y) == .soil { soilAt = (x, y); return }
            if world.farmOn, world.ground(x, y).isWater {
                // 点水：走到旁边的岸上钓鱼
                if let shore = shore(near: x, y) { world.walkHer(shore.0, shore.1) }
                startFishing()
                return
            }
            world.walkHer(x, y)
        case .place:
            guard !moved else { return }
            if sceneryTab {
                if let k = decorPick { world.addDecor(k.rawValue, x, y) }
                return
            }
            guard let src = itemPick else { return }
            var w = 1
            if src.hasPrefix("f:"), let k = FurnitureCatalog.kind(String(src.dropFirst(2))), k.sprite.width >= 20 { w = 2 }
            world.place(src, x, y, w: w)
        case .ground:
            world.setGround(groundPick, x, y)
        case .remove:
            if let o = world.object(at: x, y) { world.remove(o.id) }
            else if let d = world.decor(at: x, y) { world.removeDecor(d.id) }
        }
    }

    private func shore(near x: Int, _ y: Int) -> (Int, Int)? {
        for (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
            let nx = x + dx, ny = y + dy
            if nx >= 0, ny >= 0, nx < world.width, ny < world.height, !world.ground(nx, ny).blocked { return (nx, ny) }
        }
        return nil
    }

    private func startFishing() {
        guard !fishing else { return }
        fishing = true
        world.flash("fish")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64.random(in: 1_500_000_000...3_500_000_000))
            let got = world.fish(byHer: true)
            caught = got
            fishing = false
            // 钓到稀罕的才告诉他
            if ["锦鲤", "珍珠", "漂流瓶", "一朵睡莲"].contains(got) { app.tellHim("小岛上，她在水边钓到了\(got)。") }
        }
    }

    /// 庄稼：种子 → 芽 → 叶 → 结果。每分钟刷一次
    private var cropLayer: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            Canvas { gc, _ in
                for (key, c) in world.save.crops {
                    let xy = key.split(separator: ",").compactMap { Int($0) }
                    guard xy.count == 2, let s = WorldFarm.seed(c.kind) else { continue }
                    let cx = CGFloat(xy[0]) * tile + tile / 2, base = CGFloat(xy[1]) * tile + tile - 8
                    let leaf = Color(hexString: "6FA35C")!
                    switch WorldFarm.stage(c, now: ctx.date) {
                    case 0:
                        for dx in [-6.0, 0, 6] {
                            gc.fill(Path(ellipseIn: CGRect(x: cx + dx - 1.5, y: base - 3, width: 3, height: 3)),
                                    with: .color(Color(hexString: "5E3A26")!))
                        }
                    case 1:
                        var p = Path()
                        p.move(to: CGPoint(x: cx, y: base)); p.addLine(to: CGPoint(x: cx, y: base - 8))
                        gc.stroke(p, with: .color(leaf), lineWidth: 1.6)
                        gc.fill(Path(ellipseIn: CGRect(x: cx - 6, y: base - 12, width: 6, height: 4)), with: .color(leaf))
                        gc.fill(Path(ellipseIn: CGRect(x: cx, y: base - 12, width: 6, height: 4)), with: .color(leaf))
                    default:
                        var p = Path()
                        p.move(to: CGPoint(x: cx, y: base)); p.addLine(to: CGPoint(x: cx, y: base - 18))
                        gc.stroke(p, with: .color(leaf), lineWidth: 2)
                        for (dx, dy) in [(-9.0, -10.0), (3.0, -14.0), (-7.0, -20.0)] {
                            gc.fill(Path(ellipseIn: CGRect(x: cx + dx, y: base + dy, width: 8, height: 5)), with: .color(leaf))
                        }
                        if WorldFarm.stage(c, now: ctx.date) == 3 {
                            let fruit = Color(hexString: s.color)!
                            for (dx, dy) in [(-6.0, -24.0), (2.0, -27.0), (-2.0, -19.0)] {
                                gc.fill(Path(ellipseIn: CGRect(x: cx + dx, y: base + dy, width: 7, height: 7)), with: .color(fruit))
                            }
                        }
                    }
                    if c.lastWatered.map({ ctx.date.timeIntervalSince($0) < 1800 }) == true {
                        gc.fill(Path(ellipseIn: CGRect(x: cx + 9, y: base - 6, width: 4, height: 5)),
                                with: .color(Color(hexString: "6FB4D2")!))
                    }
                }
            }
        }
        .frame(width: CGFloat(world.width) * tile, height: CGFloat(world.height) * tile)
        .allowsHitTesting(false)
    }

    /// 一样景：图的左下角对着那一格的左下角
    @ViewBuilder
    private func decorView(_ d: WorldDecor) -> some View {
        if let k = WorldDecorKind.resolve(d.kind) {
            let sc = tile / CGFloat(IslandArt.px)
            let s = IslandArt.size(of: k.sprite)
            IslandSprite(key: k.sprite, scale: sc)
                .position(x: CGFloat(d.x) * tile + s.width * sc / 2,
                          y: CGFloat(d.y + 1) * tile - s.height * sc / 2)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func objectImage(_ source: String) -> some View {
        if source.hasPrefix("f:"), let k = FurnitureCatalog.kind(String(source.dropFirst(2))) {
            if let img = FurnitureCatalog.artImage(of: k.id, flat: true) {
                Image(uiImage: img).resizable().interpolation(.none).scaledToFit()
            } else {
                PixelSpriteView(sprite: k.sprite, scale: 1.4)
            }
        } else if source.hasPrefix("p:"), let id = UUID(uuidString: String(source.dropFirst(2))),
                  let p = pieces.pieces.first(where: { $0.id == id }),
                  let img = ImageStore.thumb(p.imageName, maxPixel: 240) {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary)
        }
    }

    private func objectView(_ o: WorldObject) -> some View {
        let w = CGFloat(o.w) * tile
        return ZStack(alignment: .bottom) {
            // 脚下一团软影子
            Ellipse()
                .fill(Color(red: 0.2, green: 0.25, blue: 0.15).opacity(0.18))
                .frame(width: w * 0.8, height: tile * 0.28)
                .blur(radius: 2)
                .offset(y: tile * 0.08)
            objectImage(o.source)
                .frame(width: w * 0.95, height: tile * 1.5, alignment: .bottom)
        }
        .frame(width: w, height: tile * 1.6, alignment: .bottom)
        .position(x: CGFloat(o.x) * tile + w / 2, y: CGFloat(o.y) * tile + tile - tile * 0.8)
        .allowsHitTesting(false)
    }

    private var gridLines: some View {
        Canvas { gc, size in
            var p = Path()
            for x in 1..<world.width {
                p.move(to: CGPoint(x: CGFloat(x) * tile, y: 0)); p.addLine(to: CGPoint(x: CGFloat(x) * tile, y: size.height))
            }
            for y in 1..<world.height {
                p.move(to: CGPoint(x: 0, y: CGFloat(y) * tile)); p.addLine(to: CGPoint(x: size.width, y: CGFloat(y) * tile))
            }
            gc.stroke(p, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
        }
        .frame(width: CGFloat(world.width) * tile, height: CGFloat(world.height) * tile)
        .allowsHitTesting(false)
    }

    private var her: some View {
        VStack(spacing: 2) {
            emote(world.herEmote)
            Group {
                if let n = app.settings.userAvatarName, let img = ImageStore.thumb(n, maxPixel: 120) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color(hexString: "F4A7B9")!
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(Circle().stroke(Color(hexString: "F4A7B9")!.opacity(0.6), lineWidth: 1).padding(-3))
            .background(
                Ellipse().fill(Color(red: 0.2, green: 0.25, blue: 0.15).opacity(0.2))
                    .frame(width: 26, height: 7).blur(radius: 1.5).offset(y: 21)
            )
        }
        .offset(y: herWalk.moving ? -2 : 0)
        .position(x: herWalk.pos.x * tile + tile / 2, y: herWalk.pos.y * tile + tile / 2 - 6)
        .allowsHitTesting(false)
    }

    private var himView: some View {
        VStack(spacing: 2) {
            if let s = world.himSay {
                Text(s)
                    .font(.app(10.5))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.92)))
                    .foregroundStyle(Color(hexString: "4B3C43")!)
                    .fixedSize()
            } else {
                emote(world.himEmote)
            }
            ClawdView(mood: world.himEmote == nil ? .idle : .happy, scale: 1.2, wornIDs: room.wornIDs)
                .frame(width: 44, height: 44)
                .background(
                    Ellipse().fill(Color(red: 0.2, green: 0.25, blue: 0.15).opacity(0.2))
                        .frame(width: 30, height: 7).blur(radius: 1.5).offset(y: 21)
                )
        }
        .offset(y: himWalk.moving ? -2 : 0)
        .position(x: himWalk.pos.x * tile + tile / 2, y: himWalk.pos.y * tile + tile / 2 - 8)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func emote(_ name: String?) -> some View {
        if let name {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hexString: "E8758F")!)
                .padding(6)
                .background(Circle().fill(.white.opacity(0.95)))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    // MARK: 底下

    private var bottom: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Mode.allCases) { m in
                    Button { mode = m } label: {
                        VStack(spacing: 3) {
                            Image(systemName: m.icon).font(.app(15))
                            Text(m.label).font(.app(10))
                        }
                        .foregroundStyle(mode == m ? app.settings.accentColor : Theme.textSoft(scheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(mode == m ? app.settings.accentColor.opacity(0.16) : Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            switch mode {
            case .walk:
                Text("点空地走过去；点东西看能一起做什么；点\(him)对他做点什么；点田种菜浇水，点水钓鱼。")
                    .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                    .padding(.horizontal, 16)
            case .remove:
                Text("点一件东西把它拿走。")
                    .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
            case .ground:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WorldGround.allCases) { g in
                            Button { groundPick = g } label: {
                                VStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 6).fill(g.color).frame(width: 34, height: 26)
                                        .overlay(RoundedRectangle(cornerRadius: 6)
                                            .stroke(app.settings.accentColor, lineWidth: groundPick == g ? 2 : 0))
                                    Text(g.label).font(.app(10))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            case .place:
                itemPicker
            }
        }
        .padding(.top, 10)
        .padding(.bottom, Layout.tabBarExpanded)
        .background(.ultraThinMaterial)
    }

    private var itemPicker: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("风景") { sceneryTab = true }
                        .font(.app(11.5, weight: sceneryTab ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(sceneryTab ? app.settings.accentColor.opacity(0.2) : Theme.softFillDeep))
                        .buttonStyle(.plain)
                    ForEach(FurnitureKind.Category.allCases.filter { $0 != .wear }) { c in
                        Button(c.rawValue) { itemFilter = c; sceneryTab = false }
                            .font(.app(11.5, weight: !sceneryTab && itemFilter == c ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(!sceneryTab && itemFilter == c ? app.settings.accentColor.opacity(0.2) : Theme.softFillDeep))
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            if sceneryTab {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WorldDecorKind.allCases) { k in
                            Button { decorPick = k } label: {
                                VStack(spacing: 3) {
                                    let s = IslandArt.size(of: k.sprite)
                                    IslandSprite(key: k.sprite, scale: 40 / max(s.width, s.height))
                                        .frame(width: 40, height: 40)
                                    Text(k.label).font(.app(9.5)).lineLimit(1).frame(width: 52)
                                }
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(decorPick == k ? app.settings.accentColor.opacity(0.18) : Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 她自己的家具素材（拼豆、导入的图）排最前面
                    ForEach(pieces.pieces) { p in
                        itemCell("p:" + p.id.uuidString, name: p.name.isEmpty ? "我的" : p.name)
                    }
                    ForEach(FurnitureCatalog.all.filter { $0.category == itemFilter }) { k in
                        itemCell("f:" + k.id, name: k.name)
                    }
                }
                .padding(.horizontal, 16)
            }
            }
        }
    }

    private func itemCell(_ src: String, name: String) -> some View {
        Button { itemPick = src } label: {
            VStack(spacing: 3) {
                objectImage(src).frame(width: 40, height: 40)
                Text(name).font(.app(9.5)).lineLimit(1).frame(width: 52)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(itemPick == src ? app.settings.accentColor.opacity(0.18) : Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    // MARK: 模组

    private var modsSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WorldMods.all) { m in
                        Toggle(isOn: Binding(get: { world.modOn(m) }, set: { _ in world.toggleMod(m) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(.app(14, weight: .medium))
                                Text(m.summary).font(.app(11.5)).foregroundStyle(.secondary)
                            }
                        }
                        .tint(app.settings.accentColor)
                    }
                } footer: {
                    Text("打开的模组决定岛上能一起做哪些事。\(him)那边也一样能用。")
                }
                if !world.save.basket.isEmpty {
                    Section("篮子") {
                        Text(world.basketText).font(.app(12.5))
                    }
                }
                if !world.save.events.isEmpty {
                    Section("最近") {
                        ForEach(Array(world.save.events.suffix(12).reversed().enumerated()), id: \.offset) { _, e in
                            Text(e.text).font(.app(12.5))
                        }
                    }
                }
            }
            .navigationTitle("模组")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 小岛的地面：素材拼好的一张小图（一格 16 像素）放大，不插值。
///
/// ⚠️ 只在地块变了的时候重新拼（`Equatable` 只比 `ground`），
/// 两个人走路、冒表情都不会让它跟着重算一遍。
struct IslandGround: View, Equatable {
    let ground: [WorldGround]
    let width: Int
    let height: Int
    let tile: CGFloat

    static func == (a: IslandGround, b: IslandGround) -> Bool {
        a.ground == b.ground && a.width == b.width && a.height == b.height && a.tile == b.tile
    }

    var body: some View {
        Image(uiImage: IslandArt.ground(ground, width: width, height: height))
            .resizable()
            .interpolation(.none)
            .frame(width: CGFloat(width) * tile, height: CGFloat(height) * tile)
            .allowsHitTesting(false)
    }
}

/// 岛上一个人走路：存档里改了「在哪一格」，这里沿着路线一格一格走过去（绕开水和树）
@MainActor
final class IslandWalker: ObservableObject {
    enum Facing { case down, left, right, up }

    /// 画面上在哪（格子坐标，走在半路是小数）
    @Published private(set) var pos: CGPoint
    @Published private(set) var facing: Facing = .down
    @Published private(set) var moving = false

    private var at: (Int, Int)
    private let step: Double
    private var task: Task<Void, Never>?

    init(_ x: Int, _ y: Int, step: Double) {
        pos = CGPoint(x: x, y: y)
        at = (x, y)
        self.step = step
    }

    func walk(to x: Int, _ y: Int, route: ((Int, Int), (Int, Int)) -> [(Int, Int)]?) {
        guard (x, y) != at else { return }
        task?.cancel()
        // 走不到（隔着水）就直接过去
        let steps = route(at, (x, y)) ?? [(x, y)]
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.moving = true
            for s in steps {
                if Task.isCancelled { return }
                let dx = s.0 - self.at.0, dy = s.1 - self.at.1
                self.facing = dx < 0 ? .left : dx > 0 ? .right : dy < 0 ? .up : .down
                self.at = s
                withAnimation(.linear(duration: self.step)) { self.pos = CGPoint(x: s.0, y: s.1) }
                try? await Task.sleep(nanoseconds: UInt64(self.step * 1_000_000_000))
            }
            if !Task.isCancelled { self.moving = false }
        }
    }
}
