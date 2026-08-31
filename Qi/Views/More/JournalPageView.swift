import SwiftUI
import PhotosUI

/// 做一页手帐。
///
/// 一页就是一块自由画布：拖到哪儿放哪儿，两指能转能缩放。
/// **不做网格、不做对齐**——手帐好看恰恰在于它是歪的。
struct JournalPageView: View {

    @State var page: JournalPage

    @ObservedObject private var store = JournalStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 选中的那样东西。选中了才显示它的调节条。
    @State private var picked: UUID?
    /// 选中的那块文字里，点中的是第几个字。`nil` = 整块。
    /// 她要的「每个字单独选颜色和大小」全靠它。
    @State private var charFocus: Int?
    /// 正在拖的那一下挪了多远（不落库，松手才写回去）
    @State private var dragBy: CGSize = .zero
    @State private var pinchScale: Double = 1
    @State private var twist: Double = 0

    @State private var showingPalette = true
    @State private var showingQuotes = false
    @State private var showingPapers = false
    @State private var photoItem: PhotosPickerItem?
    @State private var editingText: JournalElement?
    @State private var draftText = ""
    @State private var showingPhotoPicker = false

    var body: some View {
        VStack(spacing: 0) {
            canvas
            if showingPalette { palette }
        }
        .navigationTitle(page.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 「给他看」。**默认关**——手帐上常常是随手写的心事，
            // 她点头他才看得见。开了他就能把这一页原样画成图看见，
            // 也能往右下角贴一张便签。
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    page.shared.toggle()
                    store.save(page)
                } label: {
                    Image(systemName: page.shared ? "person.2.fill" : "person.2")
                        .foregroundStyle(page.shared
                                         ? app.settings.accentColor
                                         : Theme.textMuted(scheme))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showingPalette.toggle() }
                } label: {
                    Image(systemName: showingPalette ? "chevron.down" : "plus.circle")
                }
            }
        }
        .onDisappear { store.save(page) }
        .sheet(isPresented: $showingQuotes) {
            QuotePickerSheet { text, who in
                var e = JournalKit.make(.quote)
                e.text = text
                e.who = who
                e.z = nextZ
                page.elements.append(e)
                picked = e.id
                charFocus = nil
                store.save(page)
            }
        }
        .sheet(item: $editingText) { e in
            textEditor(for: e)
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem,
                      matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
    }

    private var nextZ: Int { (page.elements.map(\.z).max() ?? 0) + 1 }

    // MARK: 画布

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                // 纸。**跟快照共用同一份** `JournalPaperView`——
                // 纸纹在这儿画一套、那儿画一套的话，
                // 他看到的那张迟早跟她屏幕上的对不上
                JournalPaperView(hex: page.paperHex, pattern: page.paperPattern,
                                 weave: page.paperWeave)
                    .onTapGesture { picked = nil; charFocus = nil }

                ForEach(page.elements.sorted { $0.z < $1.z }) { e in
                    element(e, in: geo.size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func element(_ e: JournalElement, in size: CGSize) -> some View {
        let live = picked == e.id
        let scale = e.scale * (live ? pinchScale : 1)
        let angle = e.angle + (live ? twist : 0)

        render(e)
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .position(
                x: e.x * size.width + (live ? dragBy.width : 0),
                y: e.y * size.height + (live ? dragBy.height : 0)
            )
            .overlay {
                // 选中的圈一下。虚线框，不遮内容。
                if live {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(app.settings.accentColor,
                                      style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: 200, height: 120)
                        .position(x: e.x * size.width + dragBy.width,
                                  y: e.y * size.height + dragBy.height)
                        .allowsHitTesting(false)
                }
            }
            .onTapGesture {
                if picked == e.id {
                    // 已经选中了再点，就是要改内容
                    if e.kind == .text || e.kind == .note || e.kind == .quote {
                        draftText = e.text
                        editingText = e
                    }
                } else {
                    picked = e.id
                    charFocus = nil
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { v in
                        picked = e.id
                        charFocus = nil
                        dragBy = v.translation
                    }
                    .onEnded { v in
                        commit(e.id) {
                            $0.x = min(1.05, max(-0.05,
                                $0.x + v.translation.width / size.width))
                            $0.y = min(1.05, max(-0.05,
                                $0.y + v.translation.height / size.height))
                            $0.z = nextZ
                        }
                        dragBy = .zero
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        picked = e.id
                        charFocus = nil
                        pinchScale = v.magnification
                    }
                    .onEnded { v in
                        commit(e.id) {
                            $0.scale = min(4, max(0.3, $0.scale * v.magnification))
                        }
                        pinchScale = 1
                    }
            )
            .simultaneousGesture(
                RotateGesture()
                    .onChanged { v in
                        picked = e.id
                        charFocus = nil
                        twist = v.rotation.degrees
                    }
                    .onEnded { v in
                        commit(e.id) { $0.angle += v.rotation.degrees }
                        twist = 0
                    }
            )
    }

    private func commit(_ id: UUID, _ change: (inout JournalElement) -> Void) {
        guard let i = page.elements.firstIndex(where: { $0.id == id }) else { return }
        change(&page.elements[i])
        store.save(page)
    }

    // MARK: 每样东西长什么样

    /// 画出一样东西。
    /// **不叫 body(of:)**——View 协议本身有个 body，同名太容易出岔子。
    ///
    /// 一个元素长什么样。**整段搬去 JournalSnapshot.swift 了**——
    /// 编辑页和「给他看的那张快照」必须是同一份渲染器，
    /// 两份迟早会长歪，那时候他看到的就不再是她看到的了。
    @ViewBuilder
    private func render(_ e: JournalElement) -> some View {
        // 选中的那一块文字才让点字——没选中的时候点它是要拖它，
        // 逐字的点击会把拖拽吃掉。
        if e.kind == .text, picked == e.id {
            JournalCharText(element: e, focus: charFocus) { i in
                charFocus = (charFocus == i) ? nil : i
                if app.settings.haptics {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        } else {
            JournalElementView(e)
        }
    }

    private func charButton(_ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.app(12))
                .foregroundStyle(Theme.textSoft(scheme))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    /// 把第 `at` 个字改成这个颜色。
    ///
    /// ⚠️ 数组可能比正文短（她后来又加了字），所以**先补齐再写**，
    /// 不然下标就越界了。补出来的位置留空字符串，取的时候会退回整块的颜色。
    private func setChar(_ e: inout JournalElement, at: Int, hex: String) {
        let n = Array(e.text).count
        guard at >= 0, at < n else { return }
        if e.charColors.count < n {
            e.charColors += Array(repeating: "", count: n - e.charColors.count)
        }
        e.charColors[at] = hex
    }

    /// 把第 `at` 个字放大缩小。规矩同上。
    private func setCharSize(_ e: inout JournalElement, at: Int, mul: Double) {
        let n = Array(e.text).count
        guard at >= 0, at < n else { return }
        if e.charScales.count < n {
            e.charScales += Array(repeating: 1, count: n - e.charScales.count)
        }
        let now = e.charScales[at] > 0 ? e.charScales[at] : 1
        e.charScales[at] = max(0.5, min(3.0, now * mul))
    }

    // MARK: 底下那排素材

    private var palette: some View {
        VStack(spacing: 10) {
            if let id = picked,
               let e = page.elements.first(where: { $0.id == id }) {
                selectedBar(e)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(JournalKind.allCases, id: \.self) { kind in
                        Button {
                            add(kind)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: kind.icon)
                                    .font(.app(15))
                                Text(kind.rawValue)
                                    .font(.app(9))
                            }
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(width: 52, height: 46)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showingPapers.toggle()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "doc.plaintext")
                                .font(.app(15))
                            Text("纸底")
                                .font(.app(9))
                        }
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 52, height: 46)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            }

            if showingPapers {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        // 现成的几张纸之外，也能自己调一个——
                        // 她说「所有选择颜色的地方都加上调色盘」
                        ColorPicker("", selection: Binding(
                            get: { Color(hexString: page.paperHex) ?? Color(hexString: "F3E9D8")! },
                            set: { page.paperHex = $0.hexString; store.save(page) }
                        ), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 42, height: 30)

                        ForEach(JournalKit.papers, id: \.1) { name, hex in
                            Button {
                                page.paperHex = hex
                                store.save(page)
                            } label: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hexString: hex) ?? .gray)
                                    .frame(width: 42, height: 30)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(app.settings.accentColor,
                                                          lineWidth: page.paperHex == hex ? 2 : 0)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }

                // 纸上的纹路。**每一格就是那张纸本身的小样**——
                // 写「格纹」两个字她还得先点一次才知道长什么样
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(JournalKit.paperPatterns, id: \.1) { name, key in
                            Button {
                                page.paperPattern = key
                                store.save(page)
                            } label: {
                                JournalPaperView(hex: page.paperHex, pattern: key,
                                                 weave: page.paperWeave)
                                    .frame(width: 42, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(app.settings.accentColor,
                                                          lineWidth: page.paperPattern == key ? 2 : 0)
                                    }
                                    .overlay(alignment: .bottom) {
                                        Text(name)
                                            .font(.app(8))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                            .padding(.bottom, 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }

                // 纸的织纹。**跟上面那排格线是两层**：
                // 格线是印在纸上的，织纹是纸本身的质地，可以同时有。
                // 这一排是真实拍的布纹（CC0，见 Resources/Weave/来历.txt），
                // 不是画的——画不出亚麻那种毛边。
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(JournalKit.weaves, id: \.1) { name, key in
                            Button {
                                // 再点一下取消，跟胶带那边一个规矩
                                page.paperWeave = (page.paperWeave == key) ? "" : key
                                store.save(page)
                            } label: {
                                JournalPaperView(hex: page.paperHex,
                                                 pattern: "plain", weave: key)
                                    .frame(width: 42, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(app.settings.accentColor,
                                                          lineWidth: page.paperWeave == key ? 2 : 0)
                                    }
                                    .overlay(alignment: .bottom) {
                                        Text(name)
                                            .font(.app(8))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                            .padding(.bottom, 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// 选中之后那一排：换色、置顶、删掉。
    /// 胶带和画出来的贴纸底下多一排——**第二层颜色**。
    private func selectedBar(_ e: JournalElement) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            firstBar(e)
            // 她定的：「可以给贴纸单独图案和背景选色，
            // 比如一个素底点点图案的胶带，我想做红白配色，
            // 我就可以把底色选红色、圆点点选白色。」
            //
            // ⚠️ 只给**画出来的**那两种。emoji 贴纸和照片没有「第二层」，
            // 给它们摆一排点不动的颜色只会让人以为坏了。
            if e.kind == .tape || (e.kind == .sticker && !e.pattern.isEmpty) {
                secondBar(e)
            }
        }
    }

    /// 第二层颜色。胶带是花纹，贴纸是底下那圈白边。
    private func secondBar(_ e: JournalElement) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Text(e.kind == .tape ? "花纹" : "衬底")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(width: 26)
                // 头一个是「还原成白」——她十有八九还是最常用白的。
                Button {
                    commit(e.id) { $0.inkHex = "" }
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle().strokeBorder(
                                e.hasInk ? Theme.softStroke : app.settings.accentColor,
                                lineWidth: e.hasInk ? 1 : 2)
                        }
                }
                .buttonStyle(.plain)
                ForEach(JournalKit.stickerInks, id: \.1) { _, hex in
                    Button {
                        commit(e.id) { $0.inkHex = hex }
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().strokeBorder(
                                    app.settings.accentColor,
                                    lineWidth: e.inkHex == hex ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func firstBar(_ e: JournalElement) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                // 点中某个字之后，这一排先出现「这个字」的三个钮：
                // 放大、缩小、还原。不点字就不出现——不占地方。
                if e.kind == .text, let at = charFocus {
                    let chars = Array(e.text)
                    if at < chars.count {
                        Text(String(chars[at]))
                            .font(.app(15, weight: .medium, design: .serif))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(app.settings.accentColor.opacity(0.16)))
                    }
                    charButton("textformat.size.smaller") {
                        commit(e.id) { setCharSize(&$0, at: at, mul: 1 / 1.18) }
                    }
                    charButton("textformat.size.larger") {
                        commit(e.id) { setCharSize(&$0, at: at, mul: 1.18) }
                    }
                    charButton("arrow.uturn.backward") {
                        commit(e.id) {
                            if at < $0.charScales.count { $0.charScales[at] = 1 }
                            if at < $0.charColors.count { $0.charColors[at] = "" }
                        }
                    }
                    Divider().frame(height: 20)
                }
                ForEach(colorsFor(e.kind), id: \.1) { _, hex in
                    Button {
                        // ⚠️ 点中了某个字就**只改那一个字**。
                        // 她要的：「可以每个字单独点击颜色选，
                        // 点击颜色后打的字就是这个颜色。」
                        // 没点中字就还是整块换色（原来那个行为）。
                        if let at = charFocus, e.kind == .text {
                            commit(e.id) { setChar(&$0, at: at, hex: hex) }
                        } else {
                            commit(e.id) { $0.colorHex = hex }
                        }
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex) ?? .gray)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle().strokeBorder(
                                    app.settings.accentColor,
                                    lineWidth: e.colorHex == hex ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                }

                // 胶带的花纹。画出来的，所以换个颜色就是另一卷。
                if e.kind == .tape {
                    ForEach(JournalKit.tapePatterns, id: \.1) { name, key in
                        Button {
                            commit(e.id) { $0.pattern = key }
                        } label: {
                            JournalTapeView(color: e.color, pattern: key,
                                            ink: e.hasInk ? e.ink : nil,
                                            width: 34, height: 18)
                                .overlay {
                                    if e.pattern == key {
                                        Rectangle()
                                            .strokeBorder(app.settings.accentColor,
                                                          lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                }

                if e.kind == .sticker || e.kind == .stamp {
                    // 画出来的那几张。**摆在 emoji 前面**——
                    // 这一排才是新东西，摆后面她翻不到
                    if e.kind == .sticker {
                        ForEach(JournalKit.stickerShapes, id: \.1) { name, key in
                            Button {
                                commit(e.id) {
                                    $0.pattern = key
                                    // 从 emoji 换过来的时候还没有颜色，给一个
                                    if $0.colorHex.isEmpty || $0.colorHex == "FFFFFF" {
                                        $0.colorHex = JournalKit.stickerInks.first?.1 ?? "8FAE84"
                                    }
                                }
                            } label: {
                                JournalStickerView(
                                    shape: key,
                                    color: e.pattern == key
                                        ? e.color
                                        : (Color(hexString: "A8A296") ?? .gray),
                                    side: 20,
                                    backing: e.hasInk ? e.ink : nil)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }
                    ForEach(JournalKit.stickers.prefix(12), id: \.self) { s in
                        Button {
                            // 挑了 emoji 就是不要画的那张了
                            commit(e.id) { $0.emoji = s; $0.pattern = "" }
                        } label: {
                            Text(s).font(.app(20))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if e.kind == .photo || e.kind == .frame || e.kind == .cutout {
                    small("贴图") { showingPhotoPicker = true }
                }

                small("拉正") { commit(e.id) { $0.angle = 0 } }
                // ⚠️ 「改文字」得单独给个钮。
                // 以前是「选中之后再点一下」进编辑，可现在点字是选那个字——
                // 一个动作不能既是选字又是改内容。
                if e.kind == .text || e.kind == .note || e.kind == .quote {
                    small("改文字") {
                        draftText = e.text
                        editingText = e
                    }
                }
                small("置顶") { commit(e.id) { $0.z = nextZ } }
                small("删掉") {
                    if !e.imageName.isEmpty { ImageStore.delete(e.imageName) }
                    page.elements.removeAll { $0.id == e.id }
                    picked = nil
                    charFocus = nil
                    store.save(page)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func small(_ t: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t)
                .font(.app(11))
                .foregroundStyle(Theme.textSoft(scheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    private func colorsFor(_ kind: JournalKind) -> [(String, String)] {
        switch kind {
        case .tape:          return JournalKit.tapes
        case .note:          return JournalKit.notes
        case .text, .quote:  return JournalKit.inks
        // 画出来的贴纸跟着颜色走，所以这一排给的是贴纸色不是墨水色
        case .sticker:       return JournalKit.stickerInks
        default:             return JournalKit.inks
        }
    }

    // MARK: 加一样

    private func add(_ kind: JournalKind) {
        if kind == .quote {
            showingQuotes = true
            return
        }
        var e = JournalKit.make(kind)
        e.z = nextZ
        // 落在画布中间偏上一点，随机错开一点点，
        // 连着加几个不会全叠在同一个点上
        e.x = 0.5 + Double.random(in: -0.12...0.12)
        e.y = 0.4 + Double.random(in: -0.12...0.12)
        page.elements.append(e)
        picked = e.id
        charFocus = nil
        store.save(page)
        if kind == .photo || kind == .frame || kind == .cutout {
            showingPhotoPicker = true
        }
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item, let id = picked else { return }
        // 是不是「剪贴」那一样。**这决定了怎么存**：
        // 剪贴那种是透明底的 PNG，走 `save(_ image:)` 会被重编码成 jpg，
        // 透明的地方全变成白块——那张贴纸就废了。
        let cut = page.elements.first { $0.id == id }?.kind == .cutout
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let name: String?
            if cut {
                // 原样落盘，一个字节都不重编码
                name = ImageStore.saveOriginal(data)
            } else if let image = UIImage(data: data) {
                name = ImageStore.save(image)
            } else {
                name = nil
            }
            guard let name else { return }
            await MainActor.run {
                commit(id) {
                    if !$0.imageName.isEmpty { ImageStore.delete($0.imageName) }
                    $0.imageName = name
                }
                photoItem = nil
            }
        }
    }

    private func textEditor(for e: JournalElement) -> some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack {
                    TextEditor(text: $draftText)
                        .scrollContentBackground(.hidden)
                        .font(.app(15))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.softFillDeep))
                        .padding(16)
                    Spacer()
                }
            }
            .navigationTitle("改字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { editingText = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("好") {
                        commit(e.id) { $0.text = draftText }
                        editingText = nil
                    }
                }
            }
        }
    }
}

// MARK: - 从收藏里挑一句

/// **她收藏一句话的时候多半就是想把它留下来**，
/// 让她再抄一遍是浪费。所以这儿直接把星标过的句子摆出来，点一句就贴上去。
struct QuotePickerSheet: View {

    var onPick: (String, String) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""

    private struct Item: Identifiable {
        let id = UUID()
        let text: String
        let who: String
        let at: Date
    }

    private var items: [Item] {
        var out: [Item] = []
        for c in app.conversations {
            for m in c.messages where m.starred {
                let t = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                let who = m.role == .user
                    ? (app.settings.userName.isEmpty ? "我" : app.settings.userName)
                    : (m.senderName.isEmpty
                       ? (app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName)
                       : m.senderName)
                out.append(Item(text: t, who: who, at: m.createdAt))
            }
        }
        let sorted = out.sorted { $0.at > $1.at }
        guard !keyword.isEmpty else { return sorted }
        return sorted.filter { $0.text.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if items.isEmpty {
                            Text(keyword.isEmpty
                                 ? "还没有收藏的句子。在聊天里长按一句话就能收藏。"
                                 : "没搜到")
                                .font(.app(12))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.top, 50)
                        }
                        ForEach(items) { item in
                            Button {
                                onPick(item.text, item.who)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.text)
                                        .font(.app(14))
                                        .foregroundStyle(Theme.textMain(scheme))
                                        .lineLimit(4)
                                        .multilineTextAlignment(.leading)
                                    Text(item.who)
                                        .font(.app(10))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .glassCard(padding: 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .searchable(text: $keyword, prompt: "搜收藏的句子")
            .navigationTitle("插入收藏的句子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关掉") { dismiss() }
                }
            }
        }
    }
}
