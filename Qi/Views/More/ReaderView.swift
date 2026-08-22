import SwiftUI

// MARK: - 读一本书
//
// 她把这一页描述得最细，一条条照着做：
//
//   · 设置以**点击屏幕**的形式像弹窗一样弹出（点正中间那一条）
//   · 字号、行距、翻页方式（上下滑／左右滑／仿真翻页）
//   · 右上角是**选句子**和**目录**
//   · 选句之后，点句子里的字 → **红色下划线** → 他就知道她在这一句里
//   · 划下来的句子用**透明马克笔**画起来，颜色可选
//   · 跟他聊过的句子边上有**小气泡**，点开能看当时说了什么
//
// ## 为什么是按「句子」切，不是按段落
//
// 上一版是一段一段点的。可她说的是「点击句子中的文字」——
// 一段话里她想指的往往就是其中一句，整段划下来等于没指。
// 所以这一版先把段落切成句子（按中英文句读切），点中哪一句就是哪一句。

struct ReaderView: View {

    let bookID: UUID
    /// 从批注页点进来的话，进来就滚到那一句
    var jumpTo: Annotation? = nil

    @ObservedObject private var store = LibraryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var chapter = 0
    @State private var showChapters = false
    @State private var showSettings = false
    @State private var picking = false
    /// 选句模式里点中的那一句（还没落成批注，红色下划线的那句）
    @State private var aiming: String?
    @State private var openedMark: Annotation?
    @State private var noteDraft = ""
    @State private var writingNote = false

    private var book: Book? { store.book(bookID) }
    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }
    private var marks: [Annotation] { store.annotations(for: bookID, chapter: chapter) }

    /// 这一章切成一句一句。**先按段落分，再按句读切**——
    /// 段落之间要留空，句子之间不留。
    private var sentences: [(para: Int, text: String)] {
        guard let book, book.chapters.indices.contains(chapter) else { return [] }
        var out: [(Int, String)] = []
        let paras = book.chapters[chapter].text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for (pi, para) in paras.enumerated() {
            var buf = ""
            for ch in para {
                buf.append(ch)
                // 中英文的句号问号感叹号省略号，都算一句到头
                if "。！？!?…".contains(ch) {
                    let t = buf.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { out.append((pi, t)) }
                    buf = ""
                }
            }
            let rest = buf.trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { out.append((pi, rest)) }
        }
        return out
    }

    var body: some View {
        ZStack {
            WallpaperBackground()

            if let book, book.chapters.indices.contains(chapter) {
                pages(book)
            } else {
                Text("这本书打不开了").foregroundStyle(Theme.textMuted(scheme))
            }

            // 左右两侧那两条**翻页热区**（她说的：手势在两侧，稍微大一点，
            // 中间留着召唤设置）。只在「左右滑」那一档才摆。
            if app.settings.readerPageMode != "scroll" {
                HStack(spacing: 0) {
                    tapZone { turn(-1) }
                    // 正中间这一条是**召唤设置**用的，别让翻页占了
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                showSettings.toggle()
                            }
                        }
                    tapZone { turn(1) }
                }
                .ignoresSafeArea()
            }

            // 顶上那一条。**平时藏着**，点中间才出来——读书的时候屏幕上不该有别的东西。
            if showSettings {
                VStack {
                    topBar
                    Spacer()
                    settingsPanel
                }
                .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(showSettings ? false : true)
        .toolbar(showSettings ? .visible : .hidden, for: .navigationBar)
        .sheet(isPresented: $showChapters) { chapterList }
        .sheet(item: $openedMark) { m in
            AnnotationSheet(annotation: m)
        }
        .alert("写点什么", isPresented: $writingNote) {
            TextField("读后感、想说的话，留空也行", text: $noteDraft)
            Button("取消", role: .cancel) { aiming = nil }
            Button("画起来") { commitMark() }
        } message: {
            Text(aiming.map { "「" + $0.prefix(30) + "」" } ?? "")
        }
        .onAppear {
            chapter = jumpTo?.chapterIndex ?? book?.chapterIndex ?? 0
            store.readingID = bookID
        }
        .onDisappear {
            store.saveProgress(bookID, chapter: chapter, offset: 0)
            if store.readingID == bookID { store.readingID = nil }
        }
        .onChange(of: chapter) { _, c in
            store.saveProgress(bookID, chapter: c, offset: 0)
        }
    }

    /// 两侧那条翻页热区。**做宽一点**（她说的「稍微大一点」），
    /// 但透明——不该在正文上压一块看得见的东西。
    private func tapZone(_ run: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: 84)
            .contentShape(Rectangle())
            .onTapGesture { run() }
    }

    // MARK: 正文

    @ViewBuilder
    private func pages(_ book: Book) -> some View {
        switch app.settings.readerPageMode {
        case "curl":
            // **真的书页卷曲**（系统的 UIPageViewController.pageCurl）。
            // 上一版这儿跟 slide 共用了 SwiftUI 的 `.page` 过渡——那是平推不是卷曲，
            // 我当时还写了句「真卷曲要自己画 Metal」，**那句话说大了**：
            // iOS 自带的就是真的，包一层 UIKit 就能拿到（见 PageCurlView.swift）。
            PageCurlView(count: book.chapters.count, index: $chapter) { i in
                ScrollView { chapterBody(book, i) }
            }
            .ignoresSafeArea(edges: .bottom)
        case "slide":
            // 平推。内容跟上面一样，只是换个走法。
            TabView(selection: $chapter) {
                ForEach(book.chapters.indices, id: \.self) { i in
                    ScrollView { chapterBody(book, i) }
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
        default:
            ScrollViewReader { proxy in
                ScrollView {
                    chapterBody(book, chapter)
                    chapterNav
                }
                .onAppear {
                    // 从批注页点进来的，滚到那一句
                    guard let target = jumpTo else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation { proxy.scrollTo(target.quote, anchor: .center) }
                    }
                }
            }
        }
    }

    private func chapterBody(_ book: Book, _ index: Int) -> some View {
        VStack(alignment: .leading, spacing: app.settings.readerSpacing) {
            Text(book.chapters[index].title)
                .font(.app(19, weight: .medium, design: .serif))
                .foregroundStyle(Theme.textMain(scheme))
                .padding(.bottom, 6)

            ForEach(Array(sentences.enumerated()), id: \.offset) { _, s in
                sentence(s.text)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 70)
        // 点正中间召唤设置（上下滑那一档没有两侧热区，就靠这个）
        .contentShape(Rectangle())
        .onTapGesture {
            guard app.settings.readerPageMode == "scroll" else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                showSettings.toggle()
            }
        }
    }

    /// 一句话。
    ///
    /// 三种样子叠在一起，互不冲突：
    ///   · 已经划过 → 底下垫一层**透明马克笔**（字还看得见，这是马克笔不是涂改液）
    ///   · 正在选（aiming）→ **红色下划线**（她要的那个）
    ///   · 聊过 → 句末跟一个**小气泡**，点开看当时聊了什么
    @ViewBuilder
    private func sentence(_ text: String) -> some View {
        let mark = marks.first { $0.quote == text }
        let aimed = aiming == text

        HStack(alignment: .top, spacing: 3) {
            Text(text)
                .font(.system(size: app.settings.readerFont, design: .serif))
                .foregroundStyle(Theme.textMain(scheme))
                .lineSpacing(app.settings.readerSpacing * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .background(mark?.color.opacity(0.30) ?? .clear)
                .overlay(alignment: .bottom) {
                    if aimed {
                        Rectangle().fill(.red).frame(height: 1.6)
                    }
                }
                .id(text)

            if let mark, mark.discussed {
                Button { openedMark = mark } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(app.settings.accentColor.opacity(0.85))
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 选句模式下点一句 = 瞄准它；再点一次 = 落成批注
            guard picking else { return }
            if let mark {
                openedMark = mark
            } else if aimed {
                noteDraft = ""
                writingNote = true
            } else {
                aiming = text
            }
        }
    }

    private var chapterNav: some View {
        HStack {
            Button { turn(-1) } label: { Text("上一章").font(.app(13)) }
                .disabled(chapter == 0)
            Spacer()
            Text("\(chapter + 1) / \(book?.chapters.count ?? 0)")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
            Spacer()
            Button { turn(1) } label: { Text("下一章").font(.app(13)) }
                .disabled(chapter >= (book?.chapters.count ?? 1) - 1)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    // MARK: 顶上那条 + 设置面板

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.app(15))
            }
            Text(book?.title ?? "")
                .font(.app(13, weight: .medium))
                .lineLimit(1)
            Spacer()
            // 她要的：右上角是「选择句子」和「目录」
            Button {
                picking.toggle()
                aiming = nil
            } label: {
                Text(picking ? "选好了" : "选句子")
                    .font(.app(12))
                    .foregroundStyle(picking ? app.settings.accentColor
                                             : Theme.textSoft(scheme))
            }
            Button { showChapters = true } label: {
                Image(systemName: "list.bullet").font(.app(14))
            }
        }
        .foregroundStyle(Theme.textMain(scheme))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassBackground(radius: 0, strength: app.settings.glassOpacity)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if picking {
                Text("点一句 → 再点一次画起来。已经画过的点开能看聊过什么。")
                    .font(.app(11))
                    .foregroundStyle(app.settings.accentColor)
            }

            row("字号") {
                Slider(value: $app.settings.readerFont, in: 13...26, step: 1)
                Text("\(Int(app.settings.readerFont))").font(.app(11)).frame(width: 24)
            }
            row("行距") {
                Slider(value: $app.settings.readerSpacing, in: 2...20, step: 1)
                Text("\(Int(app.settings.readerSpacing))").font(.app(11)).frame(width: 24)
            }
            row("翻页") {
                Picker("", selection: $app.settings.readerPageMode) {
                    Text("上下滑").tag("scroll")
                    Text("左右滑").tag("slide")
                    Text("仿真").tag("curl")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("马克笔")
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
                HStack(spacing: 10) {
                    ForEach(MarkerColors.all, id: \.hex) { c in
                        Button {
                            app.settings.markerHex = c.hex
                        } label: {
                            Circle()
                                .fill((Color(hexString: c.hex) ?? .yellow).opacity(0.55))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Circle().strokeBorder(
                                        app.settings.markerHex == c.hex
                                        ? Theme.textMain(scheme) : .clear,
                                        lineWidth: 1.6)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .glassBackground(radius: 20, strength: app.settings.glassOpacity)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    private func row(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.app(12))
                .foregroundStyle(Theme.textSoft(scheme))
                .frame(width: 34, alignment: .leading)
            content()
        }
    }

    private var chapterList: some View {
        NavigationStack {
            List(Array((book?.chapters ?? []).enumerated()), id: \.offset) { i, ch in
                Button {
                    chapter = i
                    showChapters = false
                } label: {
                    HStack {
                        Text(ch.title.isEmpty ? "第 \(i + 1) 章" : ch.title)
                            .font(.app(14))
                            .foregroundStyle(i == chapter ? app.settings.accentColor
                                                          : Theme.textMain(scheme))
                        Spacer()
                        if i == chapter {
                            Image(systemName: "book.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(app.settings.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: 动作

    private func turn(_ step: Int) {
        guard let book else { return }
        let next = chapter + step
        guard book.chapters.indices.contains(next) else { return }
        withAnimation(.easeOut(duration: 0.2)) { chapter = next }
    }

    /// 把瞄准的那句真的画起来
    private func commitMark() {
        guard let text = aiming else { return }
        let a = store.addAnnotation(bookID: bookID, chapter: chapter,
                                    quote: text, location: 0,
                                    author: me, note: noteDraft)
        store.setColor(a.id, hex: app.settings.markerHex)
        aiming = nil
        noteDraft = ""
    }
}
