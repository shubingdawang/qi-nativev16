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
                    .padding(24)
            }
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
            groundLayer
            if world.farmOn { cropLayer }
            ForEach(world.save.objects) { o in objectView(o) }
            her
            himView
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
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

    /// 地面：底色 + 每种地块自己的小纹理（固定的，不会每次重画都变）
    private var groundLayer: some View {
        Canvas { gc, _ in
            for y in 0..<world.height {
                for x in 0..<world.width {
                    let g = world.ground(x, y)
                    let r = CGRect(x: CGFloat(x) * tile, y: CGFloat(y) * tile, width: tile, height: tile)
                    gc.fill(Path(r), with: .color(g.color))
                    let seed = (x * 73 + y * 151) % 97
                    switch g {
                    case .grass, .flowers:
                        for k in 0..<3 {
                            let px = r.minX + CGFloat((seed * (k + 3)) % 32) + 4
                            let py = r.minY + CGFloat((seed * (k + 7)) % 30) + 6
                            var p = Path()
                            p.move(to: CGPoint(x: px, y: py))
                            p.addLine(to: CGPoint(x: px - 1.5, y: py - 4))
                            p.move(to: CGPoint(x: px, y: py))
                            p.addLine(to: CGPoint(x: px + 1.5, y: py - 4))
                            gc.stroke(p, with: .color(Color(hexString: "8FB57A")!.opacity(0.7)), lineWidth: 1)
                        }
                        if g == .flowers {
                            let cols = ["F4A7B9", "FBE27A", "FFFFFF", "C9B6E8"]
                            for k in 0..<3 {
                                let px = r.minX + CGFloat((seed * (k + 5)) % 30) + 5
                                let py = r.minY + CGFloat((seed * (k + 2)) % 28) + 6
                                gc.fill(Path(ellipseIn: CGRect(x: px, y: py, width: 5, height: 5)),
                                        with: .color(Color(hexString: cols[(seed + k) % cols.count])!))
                            }
                        }
                    case .water:
                        for k in 0..<2 {
                            let py = r.minY + 12 + CGFloat(k) * 14
                            var p = Path()
                            p.move(to: CGPoint(x: r.minX + 6, y: py))
                            p.addQuadCurve(to: CGPoint(x: r.minX + 20, y: py), control: CGPoint(x: r.minX + 13, y: py - 4))
                            p.addQuadCurve(to: CGPoint(x: r.minX + 34, y: py), control: CGPoint(x: r.minX + 27, y: py + 4))
                            gc.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: 1.2)
                        }
                    case .wood:
                        for k in 1..<3 {
                            var p = Path()
                            p.move(to: CGPoint(x: r.minX, y: r.minY + CGFloat(k) * tile / 3))
                            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + CGFloat(k) * tile / 3))
                            gc.stroke(p, with: .color(Color(hexString: "B8916A")!.opacity(0.6)), lineWidth: 1)
                        }
                    case .soil:
                        for k in 1..<4 {
                            var p = Path()
                            p.move(to: CGPoint(x: r.minX + 3, y: r.minY + CGFloat(k) * tile / 4))
                            p.addLine(to: CGPoint(x: r.maxX - 3, y: r.minY + CGFloat(k) * tile / 4))
                            gc.stroke(p, with: .color(Color(hexString: "86603F")!.opacity(0.7)), lineWidth: 1.4)
                        }
                    case .path, .sand:
                        for k in 0..<3 {
                            let px = r.minX + CGFloat((seed * (k + 4)) % 32) + 4
                            let py = r.minY + CGFloat((seed * (k + 9)) % 32) + 4
                            gc.fill(Path(ellipseIn: CGRect(x: px, y: py, width: 3, height: 2.4)),
                                    with: .color(Color(hexString: "CBBBA0")!.opacity(0.8)))
                        }
                    }
                }
            }
        }
        .frame(width: CGFloat(world.width) * tile, height: CGFloat(world.height) * tile)
        .allowsHitTesting(false)
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
        return objectImage(o.source)
            .frame(width: w * 0.95, height: tile * 1.5, alignment: .bottom)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
            .position(x: CGFloat(o.x) * tile + w / 2, y: CGFloat(o.y) * tile + tile - tile * 0.75)
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
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
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
                .padding(5)
                .background(Circle().fill(.white.opacity(0.92)))
                .transition(.scale.combined(with: .opacity))
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
