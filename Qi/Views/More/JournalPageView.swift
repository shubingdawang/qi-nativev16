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
                // 纸
                (Color(hexString: page.paperHex) ?? Color(hexString: "F3E9D8")!)
                    .overlay {
                        // 纸的纹理。很淡，凑近才看得见——
                        // 没有它那就是一块塑料色板，不像纸。
                        GrainOverlay(opacity: 0.05)
                    }
                    .onTapGesture { picked = nil }

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
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { v in
                        picked = e.id
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
    @ViewBuilder
    private func render(_ e: JournalElement) -> some View {
        switch e.kind {
        case .text:
            Text(e.text)
                .font(.app(17, weight: .medium, design: .serif))
                .foregroundStyle(e.color)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 220)

        case .tape:
            // 胶带：半透明一条，两头是撕开的毛边
            Rectangle()
                .fill(e.color.opacity(0.62))
                .frame(width: 110, height: 26)
                .overlay {
                    // 撕口那两道
                    HStack {
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 3)
                        Spacer()
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 3)
                    }
                }

        case .sticker:
            Text(e.emoji).font(.app(34))

        case .stamp:
            // 邮票：锯齿边靠一圈白点做出来
            Text(e.emoji.isEmpty ? "📮" : e.emoji)
                .font(.app(26))
                .frame(width: 54, height: 62)
                .background {
                    ZStack {
                        Rectangle().fill(Color(hexString: "F6F2E8")!)
                        Rectangle()
                            .strokeBorder(e.color.opacity(0.5),
                                          style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    }
                }

        case .clip:
            // 夹子：一个圆角小方块加一道内线
            RoundedRectangle(cornerRadius: 3)
                .fill(e.color)
                .frame(width: 20, height: 30)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                        .padding(4)
                }
                .shadow(color: .black.opacity(0.16), radius: 2, y: 1)

        case .note:
            Text(e.text)
                .font(.app(13))
                .foregroundStyle(Color(hexString: "3A362E")!)
                .padding(10)
                .frame(width: 110, alignment: .topLeading)
                .frame(minHeight: 90, alignment: .topLeading)
                .background(e.color)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)

        case .photo:
            if let img = ImageStore.load(e.imageName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipped()
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 120)
            }

        case .frame:
            // 拍立得：白框，底下留一条写字的地方
            VStack(spacing: 0) {
                if let img = ImageStore.load(e.imageName) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 116, height: 116).clipped()
                } else {
                    Rectangle().fill(Color(hexString: "DDD8CE")!)
                        .frame(width: 116, height: 116)
                        .overlay {
                            Text("点两下贴图")
                                .font(.app(10))
                                .foregroundStyle(Color(hexString: "8A8378")!)
                        }
                }
                Text(e.text)
                    .font(.app(10))
                    .foregroundStyle(Color(hexString: "6B655A")!)
                    .frame(width: 116, height: 26)
            }
            .padding(7)
            .background(Color.white)
            .shadow(color: .black.opacity(0.18), radius: 5, y: 3)

        case .quote:
            // 摘句：带引号，底下写是谁说的
            VStack(alignment: .leading, spacing: 5) {
                Text("「" + e.text + "」")
                    .font(.app(14, design: .serif))
                    .foregroundStyle(e.color)
                    .fixedSize(horizontal: false, vertical: true)
                if !e.who.isEmpty {
                    Text("—— " + e.who)
                        .font(.app(10))
                        .foregroundStyle(e.color.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: 190)
            .padding(10)
            .background {
                Rectangle().fill(Color.white.opacity(0.42))
            }
        }
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
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// 选中之后那一排：换色、置顶、删掉
    private func selectedBar(_ e: JournalElement) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(colorsFor(e.kind), id: \.1) { _, hex in
                    Button {
                        commit(e.id) { $0.colorHex = hex }
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

                if e.kind == .sticker || e.kind == .stamp {
                    ForEach(JournalKit.stickers.prefix(12), id: \.self) { s in
                        Button {
                            commit(e.id) { $0.emoji = s }
                        } label: {
                            Text(s).font(.app(20))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if e.kind == .photo || e.kind == .frame {
                    small("贴图") { showingPhotoPicker = true }
                }

                small("拉正") { commit(e.id) { $0.angle = 0 } }
                small("置顶") { commit(e.id) { $0.z = nextZ } }
                small("删掉") {
                    if !e.imageName.isEmpty { ImageStore.delete(e.imageName) }
                    page.elements.removeAll { $0.id == e.id }
                    picked = nil
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
        store.save(page)
        if kind == .photo || kind == .frame { showingPhotoPicker = true }
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item, let id = picked else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let name = ImageStore.save(image) else { return }
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
            .navigationTitle("挑一句贴上去")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关掉") { dismiss() }
                }
            }
        }
    }
}
