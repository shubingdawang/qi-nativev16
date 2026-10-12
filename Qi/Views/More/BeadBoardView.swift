import SwiftUI
import PhotosUI

// MARK: - 拼豆板列表（侧栏「拼豆」）

struct BeadListView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = BeadStore.shared

    @State private var editing: BeadProject?
    @State private var newSize = 32
    @State private var creating = false
    @State private var pickedRef: PhotosPickerItem?
    @State private var cropNew: CropJob?
    @State private var keyword = ""
    @State private var newName = ""
    @State private var renamingItem: BeadProject?
    @State private var renameText = ""

    private var shownProjects: [BeadProject] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return store.projects }
        return store.projects.filter { $0.name.localizedCaseInsensitiveContains(k) }
    }

    /// 新板起名：她填了用她的，没填就「拼豆 N」
    private func named(_ p: BeadProject) -> BeadProject {
        var p = p
        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { p.name = n; store.save(p) }
        newName = ""
        return p
    }

    /// 用裁好的图建一块新板
    private func startWith(_ img: UIImage) {
        cropNew = nil
        let name = ImageStore.save(ImageStore.downscale(img, maxSide: 1600)) ?? ""
        var p = store.create(size: newSize, refImage: name)
        p.fitToReference(img)
        store.save(p)
        p = named(p)
        creating = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editing = p }
    }
    @State private var importPick: PhotosPickerItem?
    @State private var placing: PlacingImage?
    @State private var deleting: BeadProject?
    @ObservedObject private var wears = CustomWearStore.shared
    @ObservedObject private var room = ClawdStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button { creating = true } label: {
                        Label("新的拼豆板", systemImage: "circle.grid.3x3")
                            .font(.app(14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(app.settings.accentColor.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                    PhotosPicker(selection: $importPick, matching: .images) {
                        Label("直接导入图片", systemImage: "square.and.arrow.down")
                            .font(.app(14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }

                if store.projects.count > 3 || !keyword.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: Icon.search).font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                        TextField("按名字找", text: $keyword).font(.app(13)).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.softFillDeep))
                }

                if store.projects.isEmpty {
                    Text("新建一块板，可以垫一张参考图照着拼；也能直接导入图片，放大缩小旋转后存到家具素材或表情包。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                if !wears.items.isEmpty {
                    Text("我做的衣服").heading(14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(wears.items) { w in
                                let on = room.isWearing(w.id)
                                VStack(spacing: 6) {
                                    ZStack {
                                        PixelSpriteView(sprite: ClawdSprites.idle, scale: 2)
                                            .frame(width: 72, height: 72, alignment: .topLeading)
                                            .opacity(0.35)
                                        if let img = wears.image(w.id) {
                                            Image(uiImage: img).resizable().frame(width: 72, height: 72)
                                        }
                                    }
                                    .frame(width: 72, height: 72)
                                    Text(w.name).font(.app(11)).lineLimit(1)
                                    Button(on ? "脱下" : "穿上") { room.wear(w.id) }
                                        .font(.app(11.5, weight: .medium))
                                        .foregroundStyle(on ? Theme.textMuted(scheme) : app.settings.accentColor)
                                }
                                .padding(8)
                                .frame(width: 92)
                                .glassCard(padding: 0)
                                .contextMenu {
                                    Button(role: .destructive) { wears.delete(w.id) } label: {
                                        Label("删除", systemImage: Icon.trash)
                                    }
                                }
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(shownProjects) { p in
                        Button { editing = p } label: {
                            VStack(spacing: 6) {
                                BeadThumb(project: p)
                                    .aspectRatio(1, contentMode: .fit)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.softFillDeep))
                                Text(p.name).font(.app(12.5)).lineLimit(1)
                                Text("\(p.w)×\(p.h) · \(p.filled) 颗")
                                    .font(.app(10.5))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            .padding(10)
                            .glassCard(padding: 0)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { renameText = p.name; renamingItem = p } label: {
                                Label("改名", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deleting = p } label: {
                                Label("删除", systemImage: Icon.trash)
                            }
                        }
                    }
                }
                if shownProjects.isEmpty && !keyword.isEmpty {
                    Text("没有叫「\(keyword)」的板").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationTitle("拼豆")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { createSheet.presentationDetents([.medium]) }
        .fullScreenCover(item: $editing) { p in BeadEditorView(projectID: p.id) }
        .fullScreenCover(item: $placing) { p in ImportPlacementView(image: p.image, source: "导入的图片") }
        .onChange(of: importPick) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    placing = PlacingImage(image: img)
                }
                importPick = nil
            }
        }
        .alert("改名", isPresented: Binding(get: { renamingItem != nil },
                                          set: { if !$0 { renamingItem = nil } })) {
            TextField("名字", text: $renameText)
            Button("取消", role: .cancel) { renamingItem = nil }
            Button("好") {
                if var p = renamingItem {
                    let n = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !n.isEmpty { p.name = n; store.save(p) }
                }
                renamingItem = nil
            }
        }
        .confirmationDialog("删除这块拼豆板？", isPresented: Binding(get: { deleting != nil },
                                                             set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let d = deleting { store.delete(d.id) }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    private var createSheet: some View {
        VStack(spacing: 18) {
            Text("新的拼豆板").font(.app(16, weight: .semibold)).padding(.top, 22)
            TextField("起个名字（可以不填）", text: $newName)
                .font(.app(14))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                .padding(.horizontal, 20)
            Picker("大小", selection: $newSize) {
                ForEach([16, 24, 32, 48, 64], id: \.self) { n in Text("\(n)×\(n)").tag(n) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            HStack(spacing: 12) {
                Button {
                    let p = named(store.create(size: newSize))
                    creating = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editing = p }
                } label: {
                    Text("空白开始").font(.app(14, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.softFillDeep))
                }
                .buttonStyle(.plain)
                PhotosPicker(selection: $pickedRef, matching: .images) {
                    Text("垫一张参考图").font(.app(14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(app.settings.accentColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            Text("参考图垫在豆子下面，可以调透明度、挪位置、放大旋转，也能一键照着铺满豆子。")
                .font(.app(11.5))
                .foregroundStyle(Theme.textMuted(scheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .onChange(of: pickedRef) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    cropNew = CropJob(image: img)
                }
                pickedRef = nil
            }
        }
        // 挑完图先裁一下，裁好了再建板
        .fullScreenCover(item: $cropNew) { job in
            ImageCropView(image: job.image, done: { startWith($0) }, cancel: { startWith(job.image) })
        }
    }
}

struct PlacingImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 列表里的小图
struct BeadThumb: View {
    let project: BeadProject
    var body: some View {
        Canvas { gc, sz in
            let w = project.w, h = project.h
            let cell = min(sz.width / CGFloat(w), sz.height / CGFloat(h))
            let ox = (sz.width - cell * CGFloat(w)) / 2, oy = (sz.height - cell * CGFloat(h)) / 2
            for i in 0..<project.cells.count {
                let hex = project.cells[i]
                guard !hex.isEmpty, let c = UIColor(beadHex: hex) else { continue }
                let r = CGRect(x: ox + CGFloat(i % w) * cell, y: oy + CGFloat(i / w) * cell, width: cell, height: cell)
                gc.fill(Path(r.insetBy(dx: -0.3, dy: -0.3)), with: .color(Color(c)))
            }
        }
    }
}

// MARK: - 编辑

struct BeadEditorView: View {

    let projectID: UUID

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    enum Tool: String, CaseIterable, Identifiable {
        case pen, eraser, fill, picker, hand, reference
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pen: return "pencil.tip"
            case .eraser: return "eraser"
            case .fill: return "drop"
            case .picker: return "eyedropper"
            case .hand: return "hand.draw"
            case .reference: return "photo"
            }
        }
        var label: String {
            switch self {
            case .pen: return "放豆"
            case .eraser: return "拿走"
            case .fill: return "填满"
            case .picker: return "取色"
            case .hand: return "移动"
            case .reference: return "参考图"
            }
        }
    }

    @State private var p = BeadProject(size: 32)
    @State private var loaded = false
    @State private var tool: Tool = .pen
    @State private var color = "F4A7B9"
    @State private var custom = Color.pink
    @State private var undo: [[String]] = []
    @State private var redo: [[String]] = []
    @State private var strokeStarted = false

    // 板子的放大和平移（移动工具）
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    // 参考图手势的起点
    @State private var refBase: (s: Double, r: Double, x: Double, y: Double)?

    @State private var refUIImage: UIImage?
    @State private var exporting = false
    @State private var renaming = false
    @State private var tracing = false
    @State private var refPick: PhotosPickerItem?
    @State private var cropRef: CropJob?

    /// 裁好的参考图换上去
    private func useRef(_ img: UIImage) {
        cropRef = nil
        guard let name = ImageStore.save(ImageStore.downscale(img, maxSide: 1600)) else { return }
        if !p.refImage.isEmpty { ImageStore.delete(p.refImage) }
        p.refImage = name
        p.refScale = 1; p.refRotation = 0; p.refX = 0; p.refY = 0; p.refShown = true
        refUIImage = ImageStore.cached(name)
        // 板上还空着：板子直接改成跟底图一样的格数，底图铺满
        if p.filled == 0 { notice = p.fitToReference(img) } else { p.refFill = false }
        BeadStore.shared.save(p)
    }

    /// 「对齐底图」：板子改成底图的格数、底图铺满（已经放的豆子留着）
    private func alignToReference() {
        guard let img = refUIImage else { return }
        pushUndo()
        notice = p.fitToReference(img)
    }
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                let cell = min((geo.size.width - 24) / CGFloat(p.w), (geo.size.height - 12) / CGFloat(p.h))
                board(cell: cell)
                    .frame(width: cell * CGFloat(p.w), height: cell * CGFloat(p.h))
                    .scaleEffect(zoom)
                    .offset(pan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(handGesture, including: tool == .hand ? .all : .subviews)
                    .clipped()
            }
            controls
        }
        .background(WallpaperBackground())
        .onAppear(perform: load)
        .onDisappear { BeadStore.shared.save(p) }
        .fullScreenCover(isPresented: $exporting) { BeadExportView(project: p) }
        .alert("改名", isPresented: $renaming) {
            TextField("名字", text: $p.name)
            Button("好") { BeadStore.shared.save(p) }
        }
        .onChange(of: refPick) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    cropRef = CropJob(image: img)
                }
                refPick = nil
            }
        }
        .fullScreenCover(item: $cropRef) { job in
            ImageCropView(image: job.image, done: { useRef($0) }, cancel: { useRef(job.image) })
        }
    }

    private func load() {
        guard !loaded, let saved = BeadStore.shared.project(projectID) else { return }
        p = saved
        loaded = true
        if !p.refImage.isEmpty { refUIImage = ImageStore.cached(p.refImage) }
    }

    // MARK: 顶上

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { BeadStore.shared.save(p); dismiss() } label: {
                Image(systemName: "chevron.down").font(.app(15, weight: .medium))
            }
            Button { renaming = true } label: {
                Text(p.name).font(.app(15, weight: .semibold)).lineLimit(1)
            }
            Spacer()
            Button { stepUndo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(undo.isEmpty)
            Button { stepRedo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(redo.isEmpty)
            Button { BeadStore.shared.save(p); exporting = true } label: {
                Text("导出").font(.app(14, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(app.settings.accentColor.opacity(0.22)))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMain(scheme))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 板

    private func board(cell: CGFloat) -> some View {
        let n = p.w
        let bw = cell * CGFloat(p.w), bh = cell * CGFloat(p.h)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hexString: "F7F5F2")!)
            if let img = refUIImage, p.refShown {
                Canvas { ctx, sz in
                    var gc = ctx
                    gc.opacity = p.refOpacity
                    gc.withCGContext { cg in
                        UIGraphicsPushContext(cg)
                        BeadStore.drawReference(img, in: sz, project: p)
                        UIGraphicsPopContext()
                    }
                }
                .allowsHitTesting(false)
            }
            Canvas { gc, sz in
                for i in 0..<p.cells.count {
                    let r = CGRect(x: CGFloat(i % n) * cell, y: CGFloat(i / n) * cell, width: cell, height: cell)
                    let hex = p.cells[i]
                    if hex.isEmpty {
                        // 空着的地方是板上的小钉
                        let d = max(1.2, cell * 0.16)
                        gc.fill(Path(ellipseIn: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)),
                                with: .color(Color.black.opacity(0.12)))
                    } else if let c = UIColor(beadHex: hex) {
                        // 方形像素：一整格一个色块，格与格之间**不留缝**——拼出来就是一张像素图。
                        // 往外多铺一丝，免得两格接缝处抗锯齿出一道浅线
                        gc.fill(Path(r.insetBy(dx: -0.3, dy: -0.3)), with: .color(Color(c)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .contentShape(Rectangle())
        .gesture(drawGesture(cell: cell), including: (tool == .hand || tool == .reference) ? .subviews : .all)
        .simultaneousGesture(refDrag(width: bw, height: bh), including: tool == .reference ? .all : .subviews)
        .simultaneousGesture(refZoom, including: tool == .reference ? .all : .subviews)
        .simultaneousGesture(refTurn, including: tool == .reference ? .all : .subviews)
    }

    private func cellIndex(_ pt: CGPoint, cell: CGFloat) -> Int? {
        let col = Int(pt.x / cell), row = Int(pt.y / cell)
        guard col >= 0, row >= 0, col < p.w, row < p.h else { return nil }
        return row * p.w + col
    }

    private func drawGesture(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard let i = cellIndex(v.location, cell: cell) else { return }
                if !strokeStarted {
                    strokeStarted = true
                    pushUndo()
                }
                switch tool {
                case .pen: if p.cells[i] != color { p.cells[i] = color }
                case .eraser: if !p.cells[i].isEmpty { p.cells[i] = "" }
                case .fill: if v.translation == .zero { flood(from: i) }
                case .picker:
                    if !p.cells[i].isEmpty { color = p.cells[i] }
                    else if let c = sampleReference(i) { color = c }
                default: break
                }
            }
            .onEnded { _ in
                strokeStarted = false
                if tool == .picker { tool = .pen }
            }
    }

    private func flood(from start: Int) {
        let n = p.w, rowsN = p.h
        let target = p.cells[start]
        guard target != color else { return }
        var stack = [start]
        var seen = Set<Int>()
        while let i = stack.popLast() {
            guard !seen.contains(i), p.cells[i] == target else { continue }
            seen.insert(i)
            p.cells[i] = color
            let r = i / n, c = i % n
            if c > 0 { stack.append(i - 1) }
            if c < n - 1 { stack.append(i + 1) }
            if r > 0 { stack.append(i - n) }
            if r < rowsN - 1 { stack.append(i + n) }
        }
    }

    /// 取色：格子上没豆子就取参考图在这一格的颜色
    private func sampleReference(_ i: Int) -> String? {
        guard let img = refUIImage else { return nil }
        let traced = BeadStore.trace(p, image: img, exact: true)
        return traced[i].isEmpty ? nil : traced[i]
    }

    private var handGesture: some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { v in pan = CGSize(width: panBase.width + v.translation.width,
                                               height: panBase.height + v.translation.height) }
                .onEnded { _ in panBase = pan },
            MagnifyGesture()
                .onChanged { v in zoom = min(6, max(1, zoomBase * v.magnification)) }
                .onEnded { _ in
                    zoomBase = zoom
                    if zoom <= 1.01 { withAnimation { pan = .zero; panBase = .zero } }
                }
        )
    }

    // 参考图：拖动挪位置、两指放大、两指旋转
    private func refDrag(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if refBase == nil { refBase = (p.refScale, p.refRotation, p.refX, p.refY) }
                guard let b = refBase else { return }
                p.refX = b.x + Double(v.translation.width / width)
                p.refY = b.y + Double(v.translation.height / height)
            }
            .onEnded { _ in refBase = nil }
    }

    private var refZoom: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if refBase == nil { refBase = (p.refScale, p.refRotation, p.refX, p.refY) }
                guard let b = refBase else { return }
                p.refScale = min(8, max(0.1, b.s * Double(v.magnification)))
            }
            .onEnded { _ in refBase = nil }
    }

    private var refTurn: some Gesture {
        RotateGesture()
            .onChanged { v in
                if refBase == nil { refBase = (p.refScale, p.refRotation, p.refX, p.refY) }
                guard let b = refBase else { return }
                p.refRotation = b.r + v.rotation.degrees
            }
            .onEnded { _ in refBase = nil }
    }

    private func pushUndo() {
        undo.append(p.cells)
        if undo.count > 60 { undo.removeFirst() }
        redo.removeAll()
    }

    private func stepUndo() {
        guard let last = undo.popLast() else { return }
        redo.append(p.cells)
        p.cells = last
    }

    private func stepRedo() {
        guard let next = redo.popLast() else { return }
        undo.append(p.cells)
        p.cells = next
    }

    // MARK: 底下

    private var controls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tool.allCases) { t in
                        Button { tool = t } label: {
                            VStack(spacing: 3) {
                                Image(systemName: t.icon).font(.app(15))
                                Text(t.label).font(.app(10))
                            }
                            .foregroundStyle(tool == t ? app.settings.accentColor : Theme.textSoft(scheme))
                            .frame(width: 52, height: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(tool == t ? app.settings.accentColor.opacity(0.16) : Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            if tool == .reference || tool == .hand {
                referenceRow
            } else {
                paletteRow
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
    }

    private var paletteRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ColorPicker("", selection: $custom, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30, height: 30)
                    .onChange(of: custom) { _, c in color = UIColor(c).beadHex; if tool != .fill { tool = .pen } }
                ForEach(BeadStore.palette, id: \.self) { hex in
                    Button {
                        color = hex
                        if tool == .eraser || tool == .picker { tool = .pen }
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex)!)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.6))
                            .overlay(Circle().stroke(app.settings.accentColor, lineWidth: color == hex ? 2.4 : 0)
                                .padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
        }
    }

    private var referenceRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $refPick, matching: .images) {
                    Label(refUIImage == nil ? "垫一张图" : "换一张", systemImage: "photo.badge.plus")
                        .font(.app(12.5))
                }
                if refUIImage != nil {
                    Toggle("显示", isOn: $p.refShown).font(.app(12.5)).fixedSize()
                    Spacer()
                    Button {
                        p.refScale = 1; p.refRotation = 0; p.refX = 0; p.refY = 0
                    } label: { Text("摆正").font(.app(12.5)) }
                    Button { alignToReference() } label: {
                        Label("对齐底图", systemImage: "grid").font(.app(12.5))
                    }
                }
                Spacer(minLength: 0)
            }
            if refUIImage != nil {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled").font(.app(12))
                    Slider(value: $p.refOpacity, in: 0.05...1)
                    Menu {
                        Button("照着铺（换成色板里的颜色）") { traceAll(exact: false) }
                        Button("照着铺（用原图的颜色）") { traceAll(exact: true) }
                    } label: {
                        Label("一键铺豆", systemImage: "wand.and.stars")
                            .font(.app(12.5, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(app.settings.accentColor.opacity(0.2)))
                    }
                }
                Text(notice ?? (tool == .reference ? "在板上拖动挪参考图，两指放大、旋转。「对齐底图」：板子改成底图的格数，一格对一格。" : "拖动挪板子，两指放大。"))
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.textSoft(scheme))
        .padding(.horizontal, 16)
    }

    private func traceAll(exact: Bool) {
        guard let img = refUIImage else { return }
        pushUndo()
        p.cells = BeadStore.trace(p, image: img, exact: exact)
        tool = .pen
    }
}

// MARK: - 导出

struct BeadExportView: View {
    let project: BeadProject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var look: BeadStore.Look = .pixel
    @State private var placing: PlacingImage?
    @State private var cutting: CutJob?
    @State private var animating: PlacingImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("样子", selection: $look) {
                    ForEach(BeadStore.Look.allCases) { l in Text(l.label).tag(l) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                Image(uiImage: BeadStore.render(project, look: look))
                    .resizable()
                    .interpolation(look == .pixel ? .none : .high)
                    .scaledToFit()
                    .padding(20)
                    .background(CheckerBoard().clipShape(RoundedRectangle(cornerRadius: 14)))
                    .padding(.horizontal, 24)
                Button {
                    placing = PlacingImage(image: BeadStore.render(project, look: look, cellPx: 24))
                } label: {
                    Text("下一步：摆好再存").font(.app(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Capsule().fill(Color.accentColor))
                }
                .padding(.horizontal, 24)
                HStack(spacing: 10) {
                    Button {
                        cutting = CutJob(cut: OutfitCutter(w: project.w, h: project.h, cells: project.cells))
                    } label: {
                        Label("做成 clawd 的衣服", systemImage: "tshirt").font(.app(13.5, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Capsule().fill(Theme.softFillDeep))
                    }
                    Button {
                        animating = PlacingImage(image: BeadStore.render(project, look: .pixel, cellPx: 8))
                    } label: {
                        Label("做成动图", systemImage: "sparkles").font(.app(13.5, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Capsule().fill(Theme.softFillDeep))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                Text("「做成 clawd 的衣服」：画的是穿着衣服的 clawd 就行，会自动抠掉他自己的身子，穿上后跟着他所有动作走。")
                    .font(.app(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                Spacer()
            }
            .padding(.top, 16)
            .fullScreenCover(item: $cutting) { job in
                OutfitCutView(cut: job.cut, name: project.name)
            }
            .fullScreenCover(item: $animating) { a in GifMakerView(image: a.image, name: project.name) }
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
            .fullScreenCover(item: $placing) { p in ImportPlacementView(image: p.image, source: project.name) }
        }
    }
}

// MARK: - 导入中心：摆好、选去处、存

struct ImportPlacementView: View {
    let image: UIImage
    var source: String = ""

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    enum Dest: String, CaseIterable, Identifiable {
        case furniture, sticker, clothes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .furniture: return "家具素材"
            case .sticker: return "表情包"
            case .clothes: return "衣服"
            }
        }
        var icon: String {
            switch self {
            case .furniture: return "sofa"
            case .sticker: return "face.smiling"
            case .clothes: return "tshirt"
            }
        }
    }

    @State private var dest: Dest = .furniture
    @State private var wearSlot: ClawdRig.WearSlot = .head
    @State private var wearName = ""
    @State private var wearNow = true
    @State private var scale: CGFloat = 1
    @State private var scaleBase: CGFloat = 1
    @State private var turn: Angle = .zero
    @State private var turnBase: Angle = .zero
    @State private var offset: CGSize = .zero
    @State private var offsetBase: CGSize = .zero
    @State private var done: String?
    @State private var autoCut: CutJob?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("存到", selection: $dest) {
                    ForEach(Dest.allCases) { d in Label(d.label, systemImage: d.icon).tag(d) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    ZStack {
                        CheckerBoard()
                        // 做衣服时垫一只 clawd：框就是它那张 36 格的图纸，摆到身上哪儿就穿在哪儿
                        if dest == .clothes {
                            PixelSpriteView(sprite: ClawdSprites.idle, scale: side / CGFloat(ClawdRig.canvas))
                                .frame(width: side, height: side, alignment: .topLeading)
                                .opacity(0.55)
                        }
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .scaleEffect(scale)
                            .rotationEffect(turn)
                            .offset(offset)
                    }
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(app.settings.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            SimultaneousGesture(
                                DragGesture()
                                    .onChanged { v in offset = CGSize(width: offsetBase.width + v.translation.width,
                                                                      height: offsetBase.height + v.translation.height) }
                                    .onEnded { _ in offsetBase = offset },
                                MagnifyGesture()
                                    .onChanged { v in scale = min(8, max(0.1, scaleBase * v.magnification)) }
                                    .onEnded { _ in scaleBase = scale }),
                            RotateGesture()
                                .onChanged { v in turn = turnBase + v.rotation }
                                .onEnded { _ in turnBase = turn })
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { frameSide = side }
                    .onChange(of: side) { _, s in frameSide = s }
                }
                .padding(.horizontal, 20)

                HStack(spacing: 10) {
                    stepper("缩小", "minus.magnifyingglass") { scale = max(0.1, scale / 1.15); scaleBase = scale }
                    stepper("放大", "plus.magnifyingglass") { scale = min(8, scale * 1.15); scaleBase = scale }
                    stepper("左转", "rotate.left") { turn -= .degrees(15); turnBase = turn }
                    stepper("右转", "rotate.right") { turn += .degrees(15); turnBase = turn }
                    stepper("复原", "arrow.counterclockwise") {
                        scale = 1; scaleBase = 1; turn = .zero; turnBase = .zero; offset = .zero; offsetBase = .zero
                    }
                }

                if dest == .clothes {
                    VStack(spacing: 8) {
                        Picker("穿在", selection: $wearSlot) {
                            ForEach(0..<CustomWearStore.slots.count, id: \.self) { i in
                                Text(CustomWearStore.slots[i].1).tag(CustomWearStore.slots[i].0)
                            }
                        }
                        .pickerStyle(.segmented)
                        Button {
                            if let g = OutfitCutter.grid(from: image) {
                                autoCut = CutJob(cut: OutfitCutter(w: g.w, h: g.h, cells: g.cells))
                            }
                        } label: {
                            Label("画的是穿着衣服的 clawd？自动抠出衣服", systemImage: "scissors")
                                .font(.app(12.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(app.settings.accentColor)
                        HStack {
                            TextField("名字，如：小草帽", text: $wearName)
                                .font(.app(13))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.softFillDeep))
                            Toggle("存好就穿上", isOn: $wearNow).font(.app(12)).fixedSize()
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Text(dest == .clothes ? "把图摆到 clawd 身上想穿的位置；同一个位置一次只穿一件。"
                                      : "虚线框里的部分会被存下来；两指可以放大、旋转，拖动挪位置。")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))

                Button(action: commit) {
                    Text("存到\(dest.label)").font(.app(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Capsule().fill(app.settings.accentColor))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .padding(.top, 10)
            .fullScreenCover(item: $autoCut) { job in OutfitCutView(cut: job.cut, name: source) }
            .navigationTitle("摆好再存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
            .alert(done ?? "", isPresented: Binding(get: { done != nil }, set: { if !$0 { done = nil } })) {
                Button("好") { dismiss() }
            }
        }
    }

    @State private var frameSide: CGFloat = 300

    private func stepper(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.app(15))
                Text(label).font(.app(10))
            }
            .foregroundStyle(Theme.textSoft(scheme))
            .frame(width: 54, height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    /// 按框里看到的样子画一张出来（透明底）
    private func rendered(px: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let k = px / max(frameSide, 1)
        return UIGraphicsImageRenderer(size: CGSize(width: px, height: px), format: format).image { ctx in
            let g = ctx.cgContext
            let iw = image.size.width, ih = image.size.height
            let fit = min(px / iw, px / ih)
            let w = iw * fit, h = ih * fit
            g.translateBy(x: px / 2 + offset.width * k, y: px / 2 + offset.height * k)
            g.rotate(by: CGFloat(turn.radians))
            g.scaleBy(x: scale, y: scale)
            image.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        }
    }

    private func commit() {
        switch dest {
        case .furniture:
            let img = rendered(px: 768)
            if PieceStore.shared.add(img, name: source) != nil {
                done = "已存到家具素材，在 clawd 小屋给家具换图时可以挑它。"
            } else {
                done = "没存上，再试一次。"
            }
        case .sticker:
            let img = rendered(px: 512)
            if let data = img.pngData(), var s = StickerStore.shared.add(data: data, ext: "png", owner: "user") {
                if !source.isEmpty { s.name = source; StickerStore.shared.update(s) }
                done = "已存到表情包。"
            } else {
                done = "没存上，再试一次。"
            }
        case .clothes:
            let img = rendered(px: CGFloat(ClawdRig.canvas) * 16)
            let name = wearName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let item = CustomWearStore.shared.add(img, slot: wearSlot, name: name.isEmpty ? source : name) {
                if wearNow, !ClawdStore.shared.isWearing(item.id) { ClawdStore.shared.wear(item.id) }
                done = wearNow ? "做好了，clawd 已经穿上。" : "已存进「我做的衣服」。"
            } else {
                done = "没存上，再试一次。"
            }
        }
    }
}

/// 要抠的那套衣服
struct CutJob: Identifiable {
    let id = UUID()
    let cut: OutfitCutter
}

/// 要裁的那张图
struct CropJob: Identifiable {
    let id = UUID()
    let image: UIImage
}

extension BeadProject {
    /// 板子按底图定格数，底图铺满。返回一句告诉她改成了什么
    @discardableResult
    mutating func fitToReference(_ img: UIImage) -> String {
        refScale = 1; refRotation = 0; refX = 0; refY = 0
        refFill = true
        if let g = BeadGrid.detect(img) {
            resize(g.cols, g.rows)
            return "认出底图是 \(g.cols)×\(g.rows) 格，板子改成一样的，一格对一格。"
        }
        // 认不出格子：宽不变，行数按图的长宽比来，底图正好铺满
        let ih = img.size.height, iw = img.size.width
        let nh = iw > 0 ? max(4, min(128, Int((Double(w) * Double(ih / iw)).rounded()))) : h
        resize(w, nh)
        return "底图没认出格子，板子按图的比例改成 \(w)×\(nh)，底图铺满。"
    }
}
