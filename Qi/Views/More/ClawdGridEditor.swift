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

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 画布本身。
    ///
    /// ⚠️ **它不能是这一层的 `@State`。**
    ///
    /// 工坊那三个页签是 `switch tab` 切出来的——
    /// 切走一次这个 View 就被拆了，`@State` 跟着归零。
    /// 她的原话：「零件这边跟画那边我自己画的东西不是连接的」——
    /// 一半就是这个：她去零件那边加一下，再回来，画布是空的。
    ///
    /// 现在它住在 `ClawdStudioView`，这儿只拿一个绑定。
    @Binding var doc: ClawdDoodle

    /// 画完之后把 SVG 交出去（工坊那边拿它去渲染和保存）。
    /// 第二个参数是「要不要装在 clawd 身上」——她说预览不该老是那个身子。
    ///
    /// ⚠️ **它必须声明在 `doc` 后面。**
    /// 合成的构造器按声明顺序排参数，而尾随闭包填的是
    /// **最后一个**参数——写反了的话
    /// `ClawdGridEditor(doc: $doodle) { … }` 压根儿编译不过。
    var onChange: (String, Bool) -> Void

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
    /// 这一笔已经画过哪几格（同一格一笔之内只动一次）
    @State private var strokeCells: Set<String> = []
    /// 这一笔是在擦（落笔那一格决定的）
    @State private var strokeErasing = false
    /// 正拖着哪个零件；`movedStamp` 用来分辨「拖了」还是「只是点了一下」
    @State private var dragging: UUID?
    @State private var movedStamp = false
    /// 画布放大到几倍。她说「画布能缩放」——格子细了之后不放大根本点不准
    @State private var zoom: CGFloat = 1
    /// 放大之后画布挪到哪儿了
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?
    /// 现在这一拖是「挪画布」还是「画画」
    @State private var panning = false
    /// 预览里要不要装上 clawd 的身子。
    /// 她说「顶上预览不该老是 clawd 的身子」——画一朵花的时候，
    /// 那个身子只会碍事。
    @State private var withBody = true

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
                        push()
                        // 清掉画的东西，**格子粗细留着**——
                        // 她挑好了细格子，清一次又跳回粗的，得重挑
                        var blank = ClawdDoodle()
                        blank.grid = doc.grid
                        doc = blank
                        selected = nil
                        emit()
                    }
                    Spacer()
                    Text(mode == .paint ? "拖着画，再拖一遍擦掉"
                                        : "点空地摆一个，摁住已有的能拖着挪")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                canvasBar

                if mode == .paint { paintTools } else { stampTools }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        // ⚠️ **不能无条件 `emit()`。**
        //
        // 上一版这儿是 `.onAppear { emit() }`：每次切回「画」这一档，
        // 它一出现就把 `svg` 整个覆盖掉——
        // **她在零件那边加的东西当场就没了。**
        // 那就是她说的「我画了什么想在这边添加小部件或者动画都不行」。
        //
        // 现在只有**画布上真的有东西**的时候才报一次（用来初次对齐预览），
        // 空画布一律不碰外面那份。
        .onAppear { if !doc.isEmpty { emit() } }
    }

    // MARK: 画布

    private var board: some View {
        GeometryReader { geo in
            // 视窗永远是这么大；放大的是**里面那张画布**，
            // 大出去的部分靠 pan 挪着看（不用 ScrollView：
            // 滚动和画画抢的是同一根手指，摆在一起必然打架）。
            let viewW = geo.size.width
            let viewH = viewW * CGFloat(ClawdDoodle.baseRows) / CGFloat(ClawdDoodle.baseCols)
            let side = viewW * zoom
            let cell = side / CGFloat(doc.cols)
            let boardH = cell * CGFloat(doc.rows)

            ZStack(alignment: .topLeading) {
                // 底：clawd 的轮廓，淡淡的，好让她知道脸该画在哪儿。
                // **不装身子的时候不画它**——画一朵花的时候，
                // 底下压着个 clawd 只会让人对不准位置
                if withBody {
                    ClawdSilhouette()
                        .fill(Color(hexString: ClawdSVG.bodyColor)!.opacity(0.16))
                }

                // 上了色的格子
                ForEach(doc.paintedCells, id: \.key) { item in
                    Rectangle()
                        .fill(Color(hexString: item.hex) ?? .clear)
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(item.x) * cell, y: CGFloat(item.y) * cell)
                }

                // 摆上去的零件
                ForEach(doc.stamps) { s in
                    // **顺序有讲究**：先定尺寸、再套选中框、再翻转和转角度，
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
                        .rotationEffect(.degrees(s.rotation))
                        .position(x: CGFloat(s.x) * cell, y: CGFloat(s.y) * cell)
                }

                // 网格线。格子细的时候线密到糊成一片，淡一点
                GridLines(cols: doc.cols, rows: doc.rows)
                    .stroke(Theme.textMuted(scheme).opacity(doc.grid > 1 ? 0.09 : 0.16),
                            lineWidth: 0.5)
            }
            .frame(width: side, height: boardH)
            .offset(x: pan.width, y: pan.height)
            .frame(width: viewW, height: viewH, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if panning {
                            // 挪画布：跟着手指走，别挪出边儿
                            let base = panStart ?? pan
                            if panStart == nil { panStart = pan }
                            pan = clampPan(CGSize(width: base.width + v.translation.width,
                                                  height: base.height + v.translation.height),
                                           viewW: viewW, viewH: viewH,
                                           side: side, boardH: boardH)
                            return
                        }
                        // **拖着一路画过去**（她说的：不是一格格点）。
                        // 一笔之内同一格只动一次——不然手指在一格里抖两下，
                        // 画上去的又被自己擦掉了。
                        stroke(at: CGPoint(x: v.location.x - pan.width,
                                           y: v.location.y - pan.height),
                               cell: cell, start: v.translation == .zero)
                    }
                    .onEnded { v in
                        if panning { panStart = nil; return }
                        endStroke(at: CGPoint(x: v.location.x - pan.width,
                                              y: v.location.y - pan.height),
                                  cell: cell)
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.softFillDeep))
        }
        // 按比例把高度定死，不然 GeometryReader 撑不起来
        .aspectRatio(CGFloat(ClawdDoodle.baseCols) / CGFloat(ClawdDoodle.baseRows),
                     contentMode: .fit)
    }

    /// 画布那一排：放大、挪、格子粗细、要不要身子
    private var canvasBar: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text("放大")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Slider(value: $zoom, in: 1...4, step: 0.5)
                    .onChange(of: zoom) { _, _ in
                        // 缩回去的时候顺手把画布拉回原位，
                        // 不然会停在一个「明明没放大却缺一块」的位置上
                        if zoom <= 1 { pan = .zero; panning = false }
                    }
                Text(String(format: "%.1f×", zoom))
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(width: 32, alignment: .trailing)

                // 放大了才需要挪。没放大的时候摆个按钮在那儿只会让人误按
                if zoom > 1 {
                    Button {
                        panning.toggle()
                    } label: {
                        Image(systemName: panning ? "hand.draw.fill" : "hand.draw")
                            .font(.app(13))
                            .foregroundStyle(panning ? app.settings.accentColor
                                                     : Theme.textSoft(scheme))
                            .frame(width: 34, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(panning ? app.settings.accentColor.opacity(0.16)
                                              : Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Text("格子")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Picker("", selection: Binding(
                    get: { doc.grid },
                    set: { g in
                        push()
                        doc.setGrid(g)
                        selected = nil
                        emit()
                    }
                )) {
                    Text("粗").tag(1)
                    Text("中").tag(2)
                    Text("细").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Spacer(minLength: 0)

                Text("穿在身上")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Toggle("", isOn: Binding(get: { withBody },
                                         set: { withBody = $0; emit() }))
                    .labelsHidden()
            }

            Text(panning
                 ? "现在是挪画布：拖一下换个地方看。要接着画就再点一下那只手。"
                 : "「细」格子小一倍，适合画细节；换粗细的时候画好的会跟着换算，"
                   + "由细变粗会丢一点。关掉「装在身上」，预览里就只有你画的这一张。")
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
    }

    /// 别把画布挪出视窗外面去（挪没了就找不回来了）
    private func clampPan(_ p: CGSize, viewW: CGFloat, viewH: CGFloat,
                          side: CGFloat, boardH: CGFloat) -> CGSize {
        CGSize(width: min(0, max(viewW - side, p.width)),
               height: min(0, max(viewH - boardH, p.height)))
    }


    /// 手指落下、以及一路拖过去的每一帧
    private func stroke(at p: CGPoint, cell: CGFloat, start: Bool) {
        let x = Int(p.x / cell), y = Int(p.y / cell)
        guard x >= 0, x < doc.cols, y >= 0, y < doc.rows else { return }

        if mode == .paint {
            // 一笔只压一次撤销栈——每格压一次的话，
            // 她画一条线要按二十次撤销才退得回去
            if start {
                push()
                strokeCells.removeAll()
                // **落笔那一格决定这一笔是画还是擦**（画图软件都是这样）。
                // 不这么定的话，一条线拖过自己刚画的地方会把它擦掉——
                // 点着画的时候「再点一下擦掉」是对的，拖着画就不是了。
                strokeErasing = brushHex == ClawdDoodle.eraserHex
                    || doc.cells["\(x),\(y)"] == brushHex
            }
            let key = "\(x),\(y)"
            guard !strokeCells.contains(key) else { return }
            strokeCells.insert(key)
            if strokeErasing { doc.cells.removeValue(forKey: key) }
            else { doc.cells[key] = brushHex }
            emit()
            return
        }

        // 摆零件那边：手指落下时抓住脚下那一个，之后拖着它走
        if start {
            let reach = max(1, 2 / max(1, doc.grid))
            if let hit = doc.stamps.last(where: {
                abs($0.x - x) <= reach && abs($0.y - y) <= reach
            }) {
                dragging = hit.id
                selected = hit.id
                movedStamp = false
                return
            }
            dragging = nil
            return
        }
        // 拖着已经选中的那个走
        if let id = dragging,
           let i = doc.stamps.firstIndex(where: { $0.id == id }) {
            guard doc.stamps[i].x != x || doc.stamps[i].y != y else { return }
            if !movedStamp { push(); movedStamp = true }
            doc.stamps[i].x = x
            doc.stamps[i].y = y
            emit()
        }
    }

    /// 手指抬起来
    private func endStroke(at p: CGPoint, cell: CGFloat) {
        defer { strokeCells.removeAll(); dragging = nil }
        guard mode == .stamp else { return }

        let x = Int(p.x / cell), y = Int(p.y / cell)
        guard x >= 0, x < doc.cols, y >= 0, y < doc.rows else { return }

        // 抓着某个零件但一步都没挪 → 那就是点了它一下：选中／取消选中
        if let id = dragging {
            if !movedStamp { selected = (selected == id) ? nil : id }
            return
        }
        // 点在空地上 → 摆一个新的
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

            Text("在网格上直接绘制衣物、道具等元素。点击右上角调色盘可添加颜色，已调过的颜色保留在色板中。")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 摆零件那一栏

    private var stampTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("零件")
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
                    toolButton("左右翻转", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                        change { $0.flipH.toggle() }
                    }
                    toolButton("上下翻转", icon: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                        change { $0.flipV.toggle() }
                    }
                    toolButton("放大", icon: "plus.magnifyingglass") {
                        change { $0.scale = min(3, $0.scale + 0.25) }
                    }
                    toolButton("缩小", icon: "minus.magnifyingglass") {
                        change { $0.scale = max(0.5, $0.scale - 0.25) }
                    }
                }
                // 任意角度。左右翻上下翻只是两个固定角度，
                // 摆不出斜着的扫把、歪着的蝴蝶结——她要的就是这个。
                HStack(spacing: 8) {
                    toolButton("左转", icon: "rotate.left") {
                        change { $0.rotation = snap($0.rotation - 15) }
                    }
                    toolButton("右转", icon: "rotate.right") {
                        change { $0.rotation = snap($0.rotation + 15) }
                    }
                    toolButton("转正", icon: "arrow.counterclockwise") {
                        change { $0.rotation = 0 }
                    }
                }
                HStack(spacing: 8) {
                    Text("角度")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    // 拖着调**不压撤销栈**——拖一次要压几十份，
                    // 撤销就退不回画之前了。松手那一下才记一笔。
                    Slider(value: Binding(
                        get: { selectedStamp?.rotation ?? 0 },
                        set: { v in setRotation(v) }
                    ), in: -180...180, step: 1) { editing in
                        if editing { push() }
                    }
                    Text("\(Int(selectedStamp?.rotation ?? 0))°")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(width: 42, alignment: .trailing)
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
        // 边界先读出来：在 `change` 的闭包里再去读 doc，
        // 读到的是还没改之前那一份，看着对、其实绕
        let mx = doc.cols - 1, my = doc.rows - 1
        change {
            $0.x = max(0, min(mx, $0.x + dx))
            $0.y = max(0, min(my, $0.y + dy))
        }
    }

    private func change(_ edit: (inout ClawdStamp) -> Void) {
        guard let id = selected,
              let i = doc.stamps.firstIndex(where: { $0.id == id }) else { return }
        push()
        edit(&doc.stamps[i])
        emit()
    }

    private var selectedStamp: ClawdStamp? {
        guard let id = selected else { return nil }
        return doc.stamps.first { $0.id == id }
    }

    /// 转到 -180…180 之间，顺手把 0/90/180 附近吸过去（差几度看着就是歪的）
    private func snap(_ deg: Double) -> Double {
        var d = deg
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        for anchor in [-180.0, -90, 0, 90, 180] where abs(d - anchor) < 3 { return anchor }
        return d
    }

    /// 拖角度：**不走 `change`**，那个每次都会压一份撤销栈
    private func setRotation(_ v: Double) {
        guard let id = selected,
              let i = doc.stamps.firstIndex(where: { $0.id == id }) else { return }
        doc.stamps[i].rotation = snap(v)
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

    private func emit() { onChange(doc.svg(), withBody) }

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
    ///
    /// **格子粗细可以换**（她说「更小的格子」）：`grid` 是倍数，
    /// 1 = 20×15（粗，跟 clawd 本身一个颗粒度），2 = 40×30，3 = 60×45。
    /// 换的时候画好的东西会跟着换算，不会白画（见 `setGrid`）。
    static let baseCols = 20
    static let baseRows = 15

    /// 格子倍数。1 / 2 / 3
    var grid: Int = 1

    var cols: Int { ClawdDoodle.baseCols * max(1, grid) }
    var rows: Int { ClawdDoodle.baseRows * max(1, grid) }
    var cellW: Double { 320.0 / Double(cols) }
    var cellH: Double { 230.0 / Double(rows) }

    /// 换格子粗细。**画好的东西按比例跟着换算**——
    /// 直接清空的话，她画到一半想换个细的就得从头再来一遍。
    ///
    /// 变细：一格摊成 n×n 格；变粗：几格并一格，取左上角那一格的颜色
    /// （并起来必然要丢一点，这是没办法的事，所以界面上写明了）。
    mutating func setGrid(_ g: Int) {
        let from = max(1, grid), to = max(1, min(4, g))
        guard to != from else { return }
        var next: [String: String] = [:]
        for c in paintedCells {
            if to > from {
                let f = to / from
                let rem = to % from
                // 整数倍才摊得开；不是整数倍就按比例换算落点
                let nx = rem == 0 ? c.x * f : Int(Double(c.x) * Double(to) / Double(from))
                let ny = rem == 0 ? c.y * f : Int(Double(c.y) * Double(to) / Double(from))
                let span = rem == 0 ? f : 1
                for dx in 0..<span {
                    for dy in 0..<span {
                        next["\(nx + dx),\(ny + dy)"] = c.hex
                    }
                }
            } else {
                let nx = Int(Double(c.x) * Double(to) / Double(from))
                let ny = Int(Double(c.y) * Double(to) / Double(from))
                let key = "\(nx),\(ny)"
                if next[key] == nil { next[key] = c.hex }
            }
        }
        // 零件也跟着挪，落点保持在同一个位置上
        for i in stamps.indices {
            stamps[i].x = Int(Double(stamps[i].x) * Double(to) / Double(from))
            stamps[i].y = Int(Double(stamps[i].y) * Double(to) / Double(from))
        }
        cells = next
        grid = to
    }

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

    /// 翻译成 SVG。**加在骨架的脸那一块里**，所以画的东西会跟身子一起呼吸。
    func svg() -> String {
        var out = ""
        for c in paintedCells {
            let x = Double(c.x) * cellW
            let y = Double(c.y) * cellH
            out += String(format:
                "<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" fill=\"%@\"/>\n",
                x, y, cellW + 0.5, cellH + 0.5, c.hex)
        }
        for s in stamps { out += s.svg(cellW: cellW, cellH: cellH) + "\n" }
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
    /// 转多少度。她要的「任意角度」——
    /// 以前只有左右翻和上下翻，那是两个固定角度，摆不出斜着的扫把。
    var rotation: Double = 0

    /// 零件本身画在 48×48 的小方框里，摆的时候整体缩放平移。
    ///
    /// 变换的顺序：**先转再缩放**（写在 transform 里是从右往左读的），
    /// 反过来的话，翻转过的零件转起来方向是反的。
    func svg(cellW: Double, cellH: Double) -> String {
        let cx = Double(x) * cellW
        let cy = Double(y) * cellH
        let s = scale * (cellW * 3 / 48)
        let sx = (flipH ? -s : s), sy = (flipV ? -s : s)
        return String(format:
            "<g transform=\"translate(%.2f,%.2f) rotate(%.1f) scale(%.3f,%.3f) translate(-24,-24)\">%@</g>",
            cx, cy, rotation, sx, sy, ClawdStamp.shape(kind))
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
/// 画布底下那个淡淡的 clawd 轮廓。
///
/// ⚠️ **坐标不写在这儿**，读 `ClawdSVG.blocks`。
/// 这个 Shape 以前是照着骨架又抄了一遍方块，而且抄的是老版本——
/// 她连着两轮说「一条腿在身体外面」，改的一直是 SVG 那份，
/// 她看到的却是这一份。同一件东西**只能有一处坐标**。
struct ClawdSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 320, sy = rect.height / 230
        var p = Path()
        for b in ClawdSVG.blocks {
            p.addRect(CGRect(x: b.x * sx, y: b.y * sy,
                             width: b.w * sx, height: b.h * sy))
        }
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
