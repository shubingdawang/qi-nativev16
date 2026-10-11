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
    @State private var personMenu = false
    @State private var showMods = false
    @State private var soilAt: (x: Int, y: Int)?
    @State private var fishing = false
    @State private var caught: String?

    private let tile: CGFloat = 40

    private var him: String { app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                map
                    .padding(34)
            }
            .background(
                LinearGradient(colors: [Color(hexString: "A7D1E1")!, Color(hexString: "93C2D6")!],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
            .defaultScrollAnchor(.center)
            bottom
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
        .confirmationDialog(him, isPresented: $personMenu, titleVisibility: .visible) {
            ForEach(world.personActions) { a in
                Button(a.name) { doAction(a, on: nil) }
            }
            Button("算了", role: .cancel) {}
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

    // MARK: 地图

    private var map: some View {
        let w = CGFloat(world.width) * tile, h = CGFloat(world.height) * tile
        return ZStack(alignment: .topLeading) {
            GroundCanvas(ground: world.save.ground, width: world.width, height: world.height, tile: tile)
                .equatable()
            if world.farmOn { cropLayer }
            // 摆东西、铺地、拿走的时候显示淡淡的格线，方便对位置
            if mode != .walk { gridLines }
            ForEach(world.save.objects) { o in objectView(o) }
            her
            himView
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // 岛边：一圈沙滩、外沿一道浪花，底下压一层影子
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(hexString: "F3E6C6")!)
                .padding(-7)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.6), lineWidth: 1.5)
                    .padding(-9))
                .shadow(color: Color(red: 0.16, green: 0.27, blue: 0.35).opacity(0.28), radius: 18, y: 8)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard mode == .ground else { return }
                    world.setGround(groundPick, Int(v.location.x / tile), Int(v.location.y / tile))
                }
                .onEnded { v in tap(Int(v.location.x / tile), Int(v.location.y / tile), moved: v.translation != .zero) }
        )
        .animation(.easeInOut(duration: 0.45), value: world.save.herX)
        .animation(.easeInOut(duration: 0.45), value: world.save.herY)
        .animation(.easeInOut(duration: 0.55), value: world.save.himX)
        .animation(.easeInOut(duration: 0.55), value: world.save.himY)
    }

    private func tap(_ x: Int, _ y: Int, moved: Bool) {
        guard x >= 0, y >= 0, x < world.width, y < world.height else { return }
        switch mode {
        case .walk:
            guard !moved else { return }
            if x == world.save.himX && y == world.save.himY { personMenu = true; return }
            if let o = world.object(at: x, y) { menuFor = o; return }
            if world.farmOn, world.ground(x, y) == .soil { soilAt = (x, y); return }
            if world.farmOn, world.ground(x, y) == .water {
                // 点水：走到旁边的岸上钓鱼
                if let shore = shore(near: x, y) { world.walkHer(shore.0, shore.1) }
                startFishing()
                return
            }
            world.walkHer(x, y)
        case .place:
            guard !moved, let src = itemPick else { return }
            var w = 1
            if src.hasPrefix("f:"), let k = FurnitureCatalog.kind(String(src.dropFirst(2))), k.sprite.width >= 20 { w = 2 }
            world.place(src, x, y, w: w)
        case .ground:
            world.setGround(groundPick, x, y)
        case .remove:
            if let o = world.object(at: x, y) { world.remove(o.id) }
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
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(Circle().stroke(Color(hexString: "F4A7B9")!.opacity(0.6), lineWidth: 1).padding(-3))
            .background(
                Ellipse().fill(Color(red: 0.2, green: 0.25, blue: 0.15).opacity(0.2))
                    .frame(width: 24, height: 7).blur(radius: 1.5).offset(y: 19)
            )
        }
        .position(x: CGFloat(world.save.herX) * tile + tile / 2, y: CGFloat(world.save.herY) * tile + tile / 2 - 6)
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
            ClawdView(mood: world.himEmote == nil ? .idle : .happy, scale: 1.05, wornIDs: room.wornIDs)
                .frame(width: 38, height: 38)
                .background(
                    Ellipse().fill(Color(red: 0.2, green: 0.25, blue: 0.15).opacity(0.2))
                        .frame(width: 28, height: 7).blur(radius: 1.5).offset(y: 18)
                )
        }
        .position(x: CGFloat(world.save.himX) * tile + tile / 2, y: CGFloat(world.save.himY) * tile + tile / 2 - 8)
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
                    ForEach(FurnitureKind.Category.allCases.filter { $0 != .wear }) { c in
                        Button(c.rawValue) { itemFilter = c }
                            .font(.app(11.5, weight: itemFilter == c ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(itemFilter == c ? app.settings.accentColor.opacity(0.2) : Theme.softFillDeep))
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
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

/// 小岛的地面。
///
/// 草地是整片底色加大块柔和的明暗（不按格子变，看不出格子）；
/// 小路、木地板、田、水各自是**圆角连成一整块**，外面一道细描边；
/// 草叶、三叶草、花、石子按位置算出来，每次画都在同一个地方。
///
/// ⚠️ 只在地块变了的时候重画（`Equatable` 只比 `ground`），
/// 两个人走路、冒表情都不会让它跟着重算一遍。
struct GroundCanvas: View, Equatable {
    let ground: [WorldGround]
    let width: Int
    let height: Int
    let tile: CGFloat

    static func == (a: GroundCanvas, b: GroundCanvas) -> Bool {
        a.ground == b.ground && a.width == b.width && a.height == b.height && a.tile == b.tile
    }

    private func at(_ x: Int, _ y: Int) -> WorldGround? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return ground[y * width + x]
    }

    private static func noise(_ x: Int, _ y: Int, _ k: Int = 0) -> CGFloat {
        let v = sin(Double(x) * 12.9898 + Double(y) * 78.233 + Double(k) * 37.719) * 43758.5453
        return CGFloat(v - floor(v))
    }

    private static func hex(_ h: String, _ a: Double = 1) -> Color { Color(hexString: h)!.opacity(a) }

    var body: some View {
        Canvas { gc, size in
            let t = tile
            let full = CGRect(origin: .zero, size: size)
            // 草地底色
            gc.fill(Path(full), with: .color(Self.hex("C8DEAF")))
            // 大块柔和的明暗
            gc.drawLayer { layer in
                layer.clip(to: Path(full))
                layer.addFilter(.blur(radius: 30))
                for i in 0..<28 {
                    let cx = Self.noise(i, 3) * size.width, cy = Self.noise(i, 7) * size.height
                    let r = 60 + Self.noise(i, 9) * 90
                    layer.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r * 0.7, width: r * 2, height: r * 1.4)),
                               with: .color(i % 2 == 0 ? Self.hex("B9D3A0", 0.32) : Self.hex("D3E6BC", 0.36)))
                }
            }
            // 一簇一簇的草、几株三叶草
            for i in 0..<160 {
                let cx = Self.noise(i, 21) * size.width, cy = Self.noise(i, 23) * size.height
                guard let g = at(Int(cx / t), Int(cy / t)), g == .grass || g == .flowers else { continue }
                var p = Path()
                for j in 0..<3 {
                    let px = cx + CGFloat(j - 1) * 3, h: CGFloat = j == 1 ? 7 : 5
                    p.move(to: CGPoint(x: px, y: cy))
                    p.addLine(to: CGPoint(x: px + CGFloat(j - 1) * 1.5, y: cy - h))
                }
                gc.stroke(p, with: .color(Self.hex("93B87E", 0.82)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
            for i in 0..<44 {
                let cx = Self.noise(i, 31) * size.width, cy = Self.noise(i, 33) * size.height
                guard at(Int(cx / t), Int(cy / t)) == .grass else { continue }
                for (dx, dy) in [(0.0, -2.0), (2.0, 1.0), (-2.0, 1.0)] {
                    gc.fill(Path(ellipseIn: CGRect(x: cx + dx - 2, y: cy + dy - 2, width: 4, height: 4)),
                            with: .color(Self.hex("A9CB92")))
                }
            }

            // 成块的地：先画一圈描边色（往外扩一点），再画本色
            let regions: [(WorldGround, String, String)] = [
                (.path, "EDE3D0", "D4C5A9"), (.sand, "F2E5C4", "DCCBA3"), (.wood, "DFBE98", "AE875F"),
                (.soil, "A8805D", "7E5B3E"), (.water, "A9D5E6", "7DAEC4")
            ]
            for (kind, fill, rim) in regions {
                region(gc, kind, color: Self.hex(rim), inset: 2)
                region(gc, kind, color: Self.hex(fill), inset: 0)
            }

            // 每种地块自己的细节
            for y in 0..<height {
                for x in 0..<width {
                    guard let k = at(x, y) else { continue }
                    let r = CGRect(x: CGFloat(x) * t, y: CGFloat(y) * t, width: t, height: t)
                    switch k {
                    case .path, .sand:
                        for i in 0..<2 {
                            let px = r.minX + Self.noise(x, y, i + 3) * (t - 12) + 6
                            let py = r.minY + Self.noise(x, y, i + 5) * (t - 12) + 6
                            gc.fill(Path(ellipseIn: CGRect(x: px, y: py, width: 5, height: 3.5)),
                                    with: .color(Self.hex(k == .path ? "DCCFB6" : "E2D2AE")))
                        }
                    case .wood:
                        for i in 1..<3 {
                            let yy = r.minY + CGFloat(i) * t / 3
                            var p = Path()
                            p.move(to: CGPoint(x: r.minX + (at(x - 1, y) == .wood ? 0 : 3), y: yy))
                            p.addLine(to: CGPoint(x: r.maxX - (at(x + 1, y) == .wood ? 0 : 3), y: yy))
                            gc.stroke(p, with: .color(Self.hex("C69F78")), lineWidth: 1.2)
                        }
                        if (x + y) % 2 == 0 {
                            var p = Path()
                            p.move(to: CGPoint(x: r.midX, y: r.minY + 2))
                            p.addLine(to: CGPoint(x: r.midX, y: r.minY + t / 3))
                            gc.stroke(p, with: .color(Self.hex("C69F78")), lineWidth: 0.8)
                        }
                    case .soil:
                        for i in 1..<4 {
                            let yy = r.minY + CGFloat(i) * t / 4
                            let x0 = r.minX + (at(x - 1, y) == .soil ? 0 : 5)
                            let x1 = r.maxX - (at(x + 1, y) == .soil ? 0 : 5)
                            var a = Path(); a.move(to: CGPoint(x: x0, y: yy - 1)); a.addLine(to: CGPoint(x: x1, y: yy - 1))
                            gc.stroke(a, with: .color(Self.hex("8A6545")), lineWidth: 2)
                            var b = Path(); b.move(to: CGPoint(x: x0, y: yy + 1)); b.addLine(to: CGPoint(x: x1, y: yy + 1))
                            gc.stroke(b, with: .color(Self.hex("BF9775", 0.8)), lineWidth: 1)
                        }
                    case .water:
                        for i in 0..<2 {
                            let yy = r.minY + 13 + CGFloat(i) * 14
                            let xx = r.minX + 6 + CGFloat((x * 7 + i * 11) % 10)
                            var p = Path()
                            p.move(to: CGPoint(x: xx, y: yy))
                            p.addQuadCurve(to: CGPoint(x: xx + 14, y: yy), control: CGPoint(x: xx + 7, y: yy - 4))
                            gc.stroke(p, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                        }
                    case .flowers:
                        let cols = ["F4A7B9", "FFFFFF", "FBE27A", "C9B6E8"]
                        for i in 0..<4 {
                            let cx = r.minX + Self.noise(x, y, i + 11) * (t - 14) + 7
                            let cy = r.minY + Self.noise(x, y, i + 17) * (t - 14) + 7
                            let c = Self.hex(cols[(x + y + i) % cols.count])
                            for (dx, dy) in [(0.0, -2.4), (2.4, 0.0), (0.0, 2.4), (-2.4, 0.0)] {
                                gc.fill(Path(ellipseIn: CGRect(x: cx + dx - 2.2, y: cy + dy - 2.2, width: 4.4, height: 4.4)),
                                        with: .color(c))
                            }
                            gc.fill(Path(ellipseIn: CGRect(x: cx - 1.4, y: cy - 1.4, width: 2.8, height: 2.8)),
                                    with: .color(Self.hex("F2C230")))
                        }
                    case .grass:
                        break
                    }
                }
            }
        }
        .frame(width: CGFloat(width) * tile, height: CGFloat(height) * tile)
        .allowsHitTesting(false)
    }

    /// 一种地块整片画成圆润的一块：每格一个圆角块，跟同类邻居之间用矩形接上
    private func region(_ gc: GraphicsContext, _ kind: WorldGround, color: Color, inset: CGFloat) {
        let t = tile, rad: CGFloat = 13
        for y in 0..<height {
            for x in 0..<width where at(x, y) == kind {
                let r = CGRect(x: CGFloat(x) * t - inset, y: CGFloat(y) * t - inset,
                               width: t + inset * 2, height: t + inset * 2)
                gc.fill(Path(roundedRect: r, cornerRadius: rad + inset), with: .color(color))
                if at(x + 1, y) == kind {
                    gc.fill(Path(CGRect(x: CGFloat(x) * t + t / 2, y: r.minY, width: t, height: r.height)), with: .color(color))
                }
                if at(x, y + 1) == kind {
                    gc.fill(Path(CGRect(x: r.minX, y: CGFloat(y) * t + t / 2, width: r.width, height: t)), with: .color(color))
                }
                if at(x + 1, y) == kind, at(x, y + 1) == kind, at(x + 1, y + 1) == kind {
                    gc.fill(Path(CGRect(x: CGFloat(x) * t + t / 2, y: CGFloat(y) * t + t / 2, width: t, height: t)),
                            with: .color(color))
                }
            }
        }
    }
}
