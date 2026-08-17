import SwiftUI

/// clawd 表情工坊的**摆积木**模式。
///
/// 她的原话：
/// 「表情工坊这样直接修改代码的方式对我来说有点太困难了，
///   希望是可以点击格子增加或者删减来自定义『零件』，
///   然后动作是可以上下左右翻转等等来实现各部位或者各格子的移动，
///   这样对我来说会方便很多，因为我完全不懂代码。
///   『零件』最好能放大缩小来全方位展示效果。
///   没有撤回删除键，我无法撤销操作。」
///
/// 所以这一页**一个字的代码都不用看**：
///
/// · 上面是格子。点一下上色，再点一下擦掉——clawd 本来就是方块拼的，
///   格子画出来的跟它原生的样子是一路的
/// · 「零件」是整块的（眼睛、腮红、闪光、泪、心…），点一下摆上去，
///   摆上去之后能**翻转、放大缩小、上下左右挪、删掉**
/// · **撤销**随时能按，一路退回去
///
/// 画完的东西会翻译成跟代码模式**同一份 SVG**，所以预览、导出、
/// 存进表情库那一整条路一个字都不用改。
struct ClawdGridEditor: View {

    /// 画完之后把 SVG 交出去（工坊那边拿它去渲染和保存）
    var onChange: (String) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var doc = ClawdDoodle()
    /// 撤销栈。每动一下压一份进去——**她要的第一件事就是这个**。
    @State private var history: [ClawdDoodle] = []
    @State private var mode: Mode = .paint
    /// 现在用的颜色（六位色号，带 #）。**存色号不存枚举**——
    /// 她要画衣服、扫把、洗澡的泡泡，固定那几个色根本不够用。
    @State private var brushHex = ClawdSVG.bodyColor
    /// 手边这一排色。前面是常用的，她自己调过的会插到最前面留着。
    @AppStorage("clawdPalette") private var paletteRaw = ClawdDoodle.defaultPaletteRaw
    @State private var stampKind: ClawdStamp.Kind = .eye
    @State private var selected: UUID?

    enum Mode: String, CaseIterable {
        case paint = "画格子"
        case stamp = "摆零件"
    }

    /// 那一排色。存成一串（`#RRGGBB` 用逗号隔开），好塞进 AppStorage。
    private var palette: [String] {
        get { paletteRaw.split(separator: ",").map(String.init) }
        nonmutating set { paletteRaw = newValue.joined(separator: ",") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                board

                // 撤销 / 清空。摆在最上面一排，随手够得着。
                HStack(spacing: 8) {
                    toolButton("撤销", icon: "arrow.uturn.backward",
                               enabled: !history.isEmpty) { undo() }
                    toolButton("清空", icon: "trash",
                               enabled: !doc.isEmpty) {
                        push(); doc = ClawdDoodle(); selected = nil; emit()
                    }
                    Spacer()
                    Text(mode == .paint ? "点格子上色，再点一下擦掉"
                                        : "点画布摆一个，点已有的选中它")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .paint { paintTools } else { stampTools }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear { emit() }
    }

    // MARK: 画布

    private var board: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let cell = side / CGFloat(ClawdDoodle.cols)
            let rows = CGFloat(ClawdDoodle.rows)

            ZStack(alignment: .topLeading) {
                // 底：clawd 的轮廓，淡淡的，好让她知道脸该画在哪儿
                ClawdSilhouette()
                    .fill(Color(hexString: ClawdSVG.bodyColor)!.opacity(0.16))

                // 上了色的格子
                ForEach(doc.paintedCells, id: \.key) { item in
                    Rectangle()
                        .fill(Color(hexString: item.hex) ?? .clear)
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(item.x) * cell, y: CGFloat(item.y) * cell)
                }

                // 摆上去的零件
                ForEach(doc.stamps) { s in
                    // **顺序有讲究**：先定尺寸、再套选中框、再翻转，
                    // **最后**才 position。position 会让这个 view 占满整块画布，
                    // 写在它后面的 overlay 会盖住整张画布而不是这个零件。
                    ClawdStampShape(kind: s.kind)
                        .frame(width: cell * 3 * s.scale, height: cell * 3 * s.scale)
                        .overlay {
                            if selected == s.id {
                                Rectangle()
                                    .strokeBorder(app.settings.accentColor,
                                                  style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                                    .padding(-4)
                            }
                        }
                        .scaleEffect(x: s.flipH ? -1 : 1, y: s.flipV ? -1 : 1)
                        .position(x: CGFloat(s.x) * cell, y: CGFloat(s.y) * cell)
                }

                // 网格线
                GridLines(cols: ClawdDoodle.cols, rows: ClawdDoodle.rows)
                    .stroke(Theme.textMuted(scheme).opacity(0.16), lineWidth: 0.5)
            }
            .frame(width: side, height: cell * rows)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { v in tap(at: v.location, cell: cell) }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.softFillDeep))
        }
        // 20 列 × 15 行，按比例把高度定死，不然 GeometryReader 撑不起来
        .aspectRatio(CGFloat(ClawdDoodle.cols) / CGFloat(ClawdDoodle.rows),
                     contentMode: .fit)
    }

    private func tap(at p: CGPoint, cell: CGFloat) {
        let x = Int(p.x / cell), y = Int(p.y / cell)
        guard x >= 0, x < ClawdDoodle.cols, y >= 0, y < ClawdDoodle.rows else { return }

        if mode == .paint {
            push()
            doc.toggle(x: x, y: y, hex: brushHex)
            emit()
            return
        }
        // 摆零件：先看点没点在已有的那些上面
        if let hit = doc.stamps.last(where: {
            abs($0.x - x) <= 2 && abs($0.y - y) <= 2
        }) {
            selected = (selected == hit.id) ? nil : hit.id
            return
        }
        push()
        let s = ClawdStamp(kind: stampKind, x: x, y: y)
        doc.stamps.append(s)
        selected = s.id
        emit()
    }

    // MARK: 画格子那一栏

    private var paintTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("用哪个颜色")
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                // 想要的色不在下面那一排里，就自己调一个。
                // 她说「给 clawd 画衣服、安排动作（扫地、洗澡）都需要其他颜色」——
                // 那就不能只给六个固定色。
                ColorPicker("", selection: Binding(
                    get: { Color(hexString: brushHex) ?? .gray },
                    set: { c in
                        brushHex = "#" + c.hexString
                        if !palette.contains(brushHex) { palette.insert(brushHex, at: 0) }
                        if palette.count > 24 { palette.removeLast() }
                    }
                ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30)

                Button {
                    brushHex = ClawdDoodle.eraserHex
                } label: {
                    Image(systemName: "eraser")
                        .font(.app(13))
                        .foregroundStyle(brushHex == ClawdDoodle.eraserHex
                                         ? app.settings.accentColor : Theme.textSoft(scheme))
                        .frame(width: 32, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.softFillDeep))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 7)], spacing: 7) {
                ForEach(palette, id: \.self) { hex in
                    Button {
                        brushHex = hex
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hexString: hex) ?? .gray)
                            .frame(height: 32)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(brushHex == hex
                                                  ? app.settings.accentColor
                                                  : Theme.softStroke,
                                                  lineWidth: brushHex == hex ? 2.4 : 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("画衣服、扫把、泡泡这些就在格子上直接画——颜色不够就点右上角那个调色盘，调过的会留在这一排里。")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 摆零件那一栏

    private var stampTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("摆什么")
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                ForEach(ClawdStamp.Kind.allCases, id: \.self) { k in
                    Button {
                        stampKind = k
                    } label: {
                        VStack(spacing: 3) {
                            ClawdStampShape(kind: k)
                                .frame(width: 26, height: 26)
                            Text(k.label)
                                .font(.app(9.5))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(stampKind == k
                                  ? app.settings.accentColor.opacity(0.18)
                                  : Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.3)

            if selected != nil {
                Text("选中的那个")
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                // 挪：上下左右各一格
                HStack(spacing: 8) {
                    toolButton("左", icon: "arrow.left") { move(dx: -1, dy: 0) }
                    toolButton("右", icon: "arrow.right") { move(dx: 1, dy: 0) }
                    toolButton("上", icon: "arrow.up") { move(dx: 0, dy: -1) }
                    toolButton("下", icon: "arrow.down") { move(dx: 0, dy: 1) }
                }
                HStack(spacing: 8) {
                    toolButton("左右翻", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                        change { $0.flipH.toggle() }
                    }
                    toolButton("上下翻", icon: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                        change { $0.flipV.toggle() }
                    }
                    toolButton("放大", icon: "plus.magnifyingglass") {
                        change { $0.scale = min(3, $0.scale + 0.25) }
                    }
                    toolButton("缩小", icon: "minus.magnifyingglass") {
                        change { $0.scale = max(0.5, $0.scale - 0.25) }
                    }
                }
                toolButton("删掉这个", icon: "trash", wide: true) {
                    guard let id = selected else { return }
                    push()
                    doc.stamps.removeAll { $0.id == id }
                    selected = nil
                    emit()
                }
            } else {
                Text("点画布摆一个上去；点已经摆好的那个，就能翻转、放大缩小、挪位置、删掉。")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 手脚

    private func move(dx: Int, dy: Int) {
        change {
            $0.x = max(0, min(ClawdDoodle.cols - 1, $0.x + dx))
            $0.y = max(0, min(ClawdDoodle.rows - 1, $0.y + dy))
        }
    }

    private func change(_ edit: (inout ClawdStamp) -> Void) {
        guard let id = selected,
              let i = doc.stamps.firstIndex(where: { $0.id == id }) else { return }
        push()
        edit(&doc.stamps[i])
        emit()
    }

    /// 动手之前先把现状压进撤销栈
    private func push() {
        history.append(doc)
        if history.count > 60 { history.removeFirst() }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        doc = last
        selected = nil
        emit()
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func emit() { onChange(doc.svg()) }

    private func toolButton(_ title: String, icon: String,
                            enabled: Bool = true, wide: Bool = false,
                            run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.app(11))
                Text(title).font(.app(11))
            }
            .foregroundStyle(enabled ? Theme.textMain(scheme)
                                     : Theme.textMuted(scheme).opacity(0.5))
            .frame(maxWidth: wide ? .infinity : nil)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - 她画的那张东西

/// 格子 + 零件。**这就是「不写代码的那份源文件」**，
/// 翻译成 SVG 之后跟代码模式画出来的是同一种东西。
struct ClawdDoodle: Codable, Equatable {

    /// 画布多少格。clawd 的 viewBox 是 320×230，
    /// 20×15 格正好一格 16×15.33，方块感跟它原来的样子对得上。
    static let cols = 20
    static let rows = 15
    static var cellW: Double { 320.0 / Double(cols) }
    static var cellH: Double { 230.0 / Double(rows) }

    /// 橡皮。用一个不可能画出来的值当记号。
    static let eraserHex = "#ERASE"

    /// 手边默认那一排色。
    ///
    /// **不是只有 clawd 那几个色**——她要给他画衣服、画扫把、画洗澡的泡泡，
    /// 所以这一排是一套能凑合过日子的常用色：clawd 本体两色 + 黑白灰 +
    /// 皮肤 + 红橙黄绿青蓝紫 + 几个柔和色。
    /// 她自己用调色盘调过的会插在最前面，跟着 AppStorage 一起留着。
    static let defaultPaletteRaw = [
        ClawdSVG.bodyColor, ClawdSVG.darkColor,
        "#000000", "#FFFFFF", "#9AA0A6", "#4A4A4A",
        "#FFD9B8", "#FF9A8B", "#FF6B81", "#E03131",
        "#FF922B", "#FFD43B", "#94D82D", "#37B24D",
        "#22B8CF", "#4DABF7", "#4C6EF5", "#9775FA",
        "#F783AC", "#8B5E34", "#C9A227", "#DEE2E6"
    ].joined(separator: ",")

    /// 上了色的格子。键是 "x,y"，值是**六位色号**。
    ///
    /// 以前值存的是一个六选一的枚举，画个衣服都凑不出颜色——
    /// 她说「颜色会不会太少了」，说的就是这个。改成直接存色号，
    /// 想要多少种就有多少种。
    var cells: [String: String] = [:]
    var stamps: [ClawdStamp] = []

    var isEmpty: Bool { cells.isEmpty && stamps.isEmpty }

    struct Painted { let key: String; let x: Int; let y: Int; let hex: String }

    var paintedCells: [Painted] {
        cells.compactMap { key, value in
            let parts = key.split(separator: ",")
            guard parts.count == 2,
                  let x = Int(parts[0]), let y = Int(parts[1]) else { return nil }
            return Painted(key: key, x: x, y: y, hex: value)
        }
        .sorted { $0.key < $1.key }
    }

    mutating func toggle(x: Int, y: Int, hex: String) {
        let key = "\(x),\(y)"
        // 橡皮 = 擦掉；同一个颜色再点一次也是擦掉（她说的「再点一下删减」）
        if hex == ClawdDoodle.eraserHex || cells[key] == hex {
            cells.removeValue(forKey: key)
        } else {
            cells[key] = hex
        }
    }

    /// 翻译成 SVG。**加在骨架的脸那一块里**，所以画的东西会跟身子一起呼吸。
    func svg() -> String {
        var out = ""
        for c in paintedCells {
            let x = Double(c.x) * ClawdDoodle.cellW
            let y = Double(c.y) * ClawdDoodle.cellH
            out += String(format:
                "<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" fill=\"%@\"/>\n",
                x, y, ClawdDoodle.cellW + 0.5, ClawdDoodle.cellH + 0.5, c.hex)
        }
        for s in stamps { out += s.svg() + "\n" }
        return out
    }
}

/// 一块整的「零件」
struct ClawdStamp: Identifiable, Codable, Equatable {

    enum Kind: String, CaseIterable, Codable {
        case eye, sleepy, blush, spark, tear, heart, brow, mouth
        // 道具。她说想给他安排动作——扫地、洗澡这些，光有表情零件摆不出来。
        case broom, bubble, star, bow

        var label: String {
            switch self {
            case .eye:    return "眼睛"
            case .sleepy: return "眯眼"
            case .blush:  return "腮红"
            case .spark:  return "闪光"
            case .tear:   return "眼泪"
            case .heart:  return "心"
            case .brow:   return "眉毛"
            case .mouth:  return "嘴"
            case .broom:  return "扫把"
            case .bubble: return "泡泡"
            case .star:   return "星星"
            case .bow:    return "蝴蝶结"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    /// 落在哪一格（格子坐标，翻译成 SVG 的时候再换算）
    var x: Int
    var y: Int
    var scale: Double = 1
    var flipH = false
    var flipV = false

    /// 零件本身画在 48×48 的小方框里，摆的时候整体缩放平移
    func svg() -> String {
        let cx = Double(x) * ClawdDoodle.cellW
        let cy = Double(y) * ClawdDoodle.cellH
        let s = scale * (ClawdDoodle.cellW * 3 / 48)
        let sx = (flipH ? -s : s), sy = (flipV ? -s : s)
        return String(format:
            "<g transform=\"translate(%.2f,%.2f) scale(%.3f,%.3f) translate(-24,-24)\">%@</g>",
            cx, cy, sx, sy, ClawdStamp.shape(kind))
    }

    /// 每个零件的形状。**全用矩形**——clawd 是方的，圆的反而不像它。
    static func shape(_ kind: Kind) -> String {
        switch kind {
        case .eye:
            return "<rect x=\"14\" y=\"10\" width=\"20\" height=\"28\" fill=\"#000\"/>"
        case .sleepy:
            return "<rect x=\"10\" y=\"20\" width=\"28\" height=\"8\" fill=\"#000\"/>"
        case .blush:
            return "<rect x=\"6\" y=\"18\" width=\"36\" height=\"14\" rx=\"7\" fill=\"#FF9A8B\" opacity=\".6\"/>"
        case .spark:
            return "<rect x=\"20\" y=\"6\" width=\"8\" height=\"36\" fill=\"#FFD86B\"/>"
                + "<rect x=\"6\" y=\"20\" width=\"36\" height=\"8\" fill=\"#FFD86B\"/>"
        case .tear:
            return "<rect x=\"20\" y=\"12\" width=\"8\" height=\"18\" fill=\"#8EC5FF\"/>"
                + "<rect x=\"16\" y=\"28\" width=\"16\" height=\"12\" rx=\"6\" fill=\"#8EC5FF\"/>"
        case .heart:
            return "<rect x=\"8\" y=\"12\" width=\"14\" height=\"14\" fill=\"#FF6B81\"/>"
                + "<rect x=\"26\" y=\"12\" width=\"14\" height=\"14\" fill=\"#FF6B81\"/>"
                + "<rect x=\"12\" y=\"22\" width=\"24\" height=\"12\" fill=\"#FF6B81\"/>"
                + "<rect x=\"18\" y=\"32\" width=\"12\" height=\"8\" fill=\"#FF6B81\"/>"
        case .brow:
            return "<rect x=\"8\" y=\"20\" width=\"32\" height=\"7\" fill=\"" + ClawdSVG.darkColor + "\" transform=\"rotate(-12 24 24)\"/>"
        case .mouth:
            return "<rect x=\"14\" y=\"18\" width=\"20\" height=\"12\" rx=\"5\" fill=\"" + ClawdSVG.darkColor + "\"/>"
        case .broom:
            return "<rect x=\"22\" y=\"2\" width=\"5\" height=\"30\" fill=\"#8B5E34\"/>"
                + "<rect x=\"12\" y=\"32\" width=\"25\" height=\"6\" fill=\"#C9A227\"/>"
                + "<rect x=\"14\" y=\"38\" width=\"4\" height=\"8\" fill=\"#C9A227\"/>"
                + "<rect x=\"22\" y=\"38\" width=\"4\" height=\"8\" fill=\"#C9A227\"/>"
                + "<rect x=\"30\" y=\"38\" width=\"4\" height=\"8\" fill=\"#C9A227\"/>"
        case .bubble:
            return "<rect x=\"14\" y=\"14\" width=\"20\" height=\"20\" rx=\"10\" fill=\"#BFE6FF\" opacity=\".75\"/>"
                + "<rect x=\"19\" y=\"19\" width=\"6\" height=\"6\" rx=\"3\" fill=\"#FFFFFF\" opacity=\".8\"/>"
        case .star:
            return "<rect x=\"21\" y=\"8\" width=\"6\" height=\"32\" fill=\"#FFD43B\"/>"
                + "<rect x=\"8\" y=\"21\" width=\"32\" height=\"6\" fill=\"#FFD43B\"/>"
                + "<rect x=\"14\" y=\"14\" width=\"20\" height=\"20\" fill=\"#FFD43B\" opacity=\".55\"/>"
        case .bow:
            return "<rect x=\"6\" y=\"16\" width=\"14\" height=\"16\" rx=\"4\" fill=\"#FF6B81\"/>"
                + "<rect x=\"28\" y=\"16\" width=\"14\" height=\"16\" rx=\"4\" fill=\"#FF6B81\"/>"
                + "<rect x=\"20\" y=\"20\" width=\"8\" height=\"8\" rx=\"2\" fill=\"#E03131\"/>"
        }
    }
}

// MARK: - 画布上的零件长什么样（SwiftUI 那份，跟上面的 SVG 一一对应）

struct ClawdStampShape: View {
    let kind: ClawdStamp.Kind

    var body: some View {
        GeometryReader { geo in
            let u = geo.size.width / 48
            ZStack(alignment: .topLeading) {
                switch kind {
                case .eye:
                    box(14, 10, 20, 28, .black, u)
                case .sleepy:
                    box(10, 20, 28, 8, .black, u)
                case .blush:
                    box(6, 18, 36, 14, Color(hexString: "FF9A8B")!.opacity(0.6), u, radius: 7)
                case .spark:
                    box(20, 6, 8, 36, Color(hexString: "FFD86B")!, u)
                    box(6, 20, 36, 8, Color(hexString: "FFD86B")!, u)
                case .tear:
                    box(20, 12, 8, 18, Color(hexString: "8EC5FF")!, u)
                    box(16, 28, 16, 12, Color(hexString: "8EC5FF")!, u, radius: 6)
                case .heart:
                    box(8, 12, 14, 14, Color(hexString: "FF6B81")!, u)
                    box(26, 12, 14, 14, Color(hexString: "FF6B81")!, u)
                    box(12, 22, 24, 12, Color(hexString: "FF6B81")!, u)
                    box(18, 32, 12, 8, Color(hexString: "FF6B81")!, u)
                case .brow:
                    box(8, 20, 32, 7, Color(hexString: ClawdSVG.darkColor)!, u)
                        .rotationEffect(.degrees(-12))
                case .mouth:
                    box(14, 18, 20, 12, Color(hexString: ClawdSVG.darkColor)!, u, radius: 5)
                case .broom:
                    box(22, 2, 5, 30, Color(hexString: "8B5E34")!, u)
                    box(12, 32, 25, 6, Color(hexString: "C9A227")!, u)
                    box(14, 38, 4, 8, Color(hexString: "C9A227")!, u)
                    box(22, 38, 4, 8, Color(hexString: "C9A227")!, u)
                    box(30, 38, 4, 8, Color(hexString: "C9A227")!, u)
                case .bubble:
                    box(14, 14, 20, 20, Color(hexString: "BFE6FF")!.opacity(0.75), u, radius: 10)
                    box(19, 19, 6, 6, Color.white.opacity(0.8), u, radius: 3)
                case .star:
                    box(21, 8, 6, 32, Color(hexString: "FFD43B")!, u)
                    box(8, 21, 32, 6, Color(hexString: "FFD43B")!, u)
                    box(14, 14, 20, 20, Color(hexString: "FFD43B")!.opacity(0.55), u)
                case .bow:
                    box(6, 16, 14, 16, Color(hexString: "FF6B81")!, u, radius: 4)
                    box(28, 16, 14, 16, Color(hexString: "FF6B81")!, u, radius: 4)
                    box(20, 20, 8, 8, Color(hexString: "E03131")!, u, radius: 2)
                }
            }
        }
    }

    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                     _ color: Color, _ u: CGFloat, radius: CGFloat = 0) -> some View {
        RoundedRectangle(cornerRadius: radius * u, style: .continuous)
            .fill(color)
            .frame(width: w * u, height: h * u)
            .offset(x: x * u, y: y * u)
    }
}

// MARK: - 底下那只淡淡的 clawd

/// 只是个参照，让她知道脸大概画在哪儿。形状跟骨架那几个 rect 对齐。
struct ClawdSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 320, sy = rect.height / 230
        var p = Path()
        func add(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            p.addRect(CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy))
        }
        add(0, 60, 40, 30)       // 左手
        add(280, 60, 40, 30)     // 右手
        add(40, 0, 240, 170)     // 身子
        add(40, 170, 30, 60)     // 腿
        add(100, 170, 30, 60)
        add(210, 170, 30, 60)
        add(270, 170, 30, 60)
        return p
    }
}

/// 网格线
struct GridLines: Shape {
    let cols: Int
    let rows: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cw = rect.width / CGFloat(cols)
        let ch = rect.height / CGFloat(rows)
        for i in 0...cols {
            p.move(to: CGPoint(x: CGFloat(i) * cw, y: 0))
            p.addLine(to: CGPoint(x: CGFloat(i) * cw, y: rect.height))
        }
        for i in 0...rows {
            p.move(to: CGPoint(x: 0, y: CGFloat(i) * ch))
            p.addLine(to: CGPoint(x: rect.width, y: CGFloat(i) * ch))
        }
        return p
    }
}
