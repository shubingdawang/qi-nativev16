import SwiftUI
import PhotosUI
import UniformTypeIdentifiers   // fileImporter 要的 .epub

// MARK: - 书房
//
// 她描述得很细，照着做：
//
//   · 首页两栏：**书架** 和 **批注**
//   · 书架那栏是一个个**长书架**，有几个分类就有几个架子；
//     架子上摆着书**脊**——竖着的窄条，书名竖排，跟真书架一样
//   · 点进一个架子，所有书**封面朝着我**，封面下面是书名／作者／读到哪儿
//   · **没有封面就拿书名当封面**（她说的）
//   · 长按能改封面、能换架子
//   · 批注那栏是一条条我们划过的句子，标着在哪个架子的哪本书，
//     点一下**直接跳到那句所在的地方**

struct BookshelfView: View {

    @ObservedObject private var store = LibraryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var tab = 0            // 0 书架，1 批注
    @State private var importing = false
    @State private var busy = false
    @State private var notice: String?
    @State private var creatingShelf = false
    @State private var newShelf = ""
    @State private var openShelf: String?
    @State private var jumpTo: Annotation?

    var body: some View {
        ZStack {
            WallpaperBackground()

            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("书架").tag(0)
                    Text("批注").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                if tab == 0 { shelvesPane } else { marksPane }
            }
        }
        .navigationTitle("书房")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        importing = true
                    } label: {
                        Label("导入一本（txt / epub）", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        newShelf = ""
                        creatingShelf = true
                    } label: {
                        Label("加一个书架", systemImage: "plus.rectangle.on.folder")
                    }
                } label: {
                    Image(systemName: Icon.add)
                }
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.plainText, .epub, .data],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { load(urls) }
        }
        .alert("加一个书架", isPresented: $creatingShelf) {
            TextField("比如「小说」「诗」「工具书」", text: $newShelf)
            Button("取消", role: .cancel) {}
            Button("建好了") { store.createShelf(newShelf); newShelf = "" }
        } message: {
            Text("书架就是分类。有几个架子，书房里就摆几排。")
        }
        .alert("书房", isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } }
        )) {
            Button("好") { notice = nil }
        } message: { Text(notice ?? "") }
        .navigationDestination(item: $openShelf) { name in
            ShelfBooksView(shelf: name)
        }
        .navigationDestination(item: $jumpTo) { a in
            ReaderView(bookID: a.bookID, jumpTo: a)
        }
    }

    // MARK: 书架那一栏

    private var shelvesPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if busy {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("正在拆书…").font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .padding(.horizontal, 18)
                }

                let names = store.shelves()
                let loose = store.books(onShelf: "")

                if names.isEmpty && loose.isEmpty && !busy {
                    empty
                }

                ForEach(names, id: \.self) { name in
                    shelfRow(title: name, books: store.books(onShelf: name))
                }
                // 还没归架的那些也摆一排，不然导进来找不着
                if !loose.isEmpty {
                    shelfRow(title: "还没归架", books: loose)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
    }

    /// 一排书架：上面是书脊，下面是那块板子。
    ///
    /// **书脊是竖着的窄条、书名竖排**——她要的就是「书脊面对着我」。
    /// 没有封面的书，脊上就是书名本身；有封面的，从封面上取一条颜色当脊色，
    /// 这样一排看下去深深浅浅，像真的一架书。
    private func shelfRow(title: String, books: [Book]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("\(books.count) 本")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                Button {
                    openShelf = title == "还没归架" ? "" : title
                } label: {
                    Text("看封面")
                        .font(.app(11))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 7)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(books) { book in
                        NavigationLink {
                            ReaderView(bookID: book.id)
                        } label: {
                            spine(book)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { bookMenu(book) }
                    }
                    if books.isEmpty {
                        Text("这个架子还空着")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.vertical, 34)
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(height: 132)

            // 架子那块板
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(
                    colors: [Theme.textMuted(scheme).opacity(0.30),
                             Theme.textMuted(scheme).opacity(0.14)],
                    startPoint: .top, endPoint: .bottom))
                .frame(height: 5)
                .padding(.horizontal, 14)
                .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
        }
    }

    /// 一本书的**脊**
    private func spine(_ book: Book) -> some View {
        let tone = Self.spineTone(for: book)
        return VStack(spacing: 0) {
            Text(book.coverTitle)
                .font(.app(11, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.95))
                // 竖排：一个字一行
                .lineLimit(nil)
                .frame(width: 15)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
        }
        .frame(width: 27, height: 118, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [tone, tone.opacity(0.78)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(alignment: .bottom) {
            // 读过一点就在脊底下留一道浅印子
            if book.progress > 0.01 {
                Rectangle()
                    .fill(.white.opacity(0.55))
                    .frame(width: 27 * book.progress, height: 2)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(.black.opacity(0.14), lineWidth: 0.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    /// 脊的颜色。按书名算一个固定的色相——**同一本书永远同一个颜色**，
    /// 不然每次进来一架书的颜色都在跳。
    static func spineTone(for book: Book) -> Color {
        let seed = abs(book.title.hashValue)
        let hue = Double(seed % 360) / 360
        return Color(hue: hue, saturation: 0.34, brightness: 0.52)
    }

    // MARK: 批注那一栏

    /// 一条条我们划过的句子。**点一下直接跳回那一句所在的地方**（她要的）。
    private var marksPane: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                let all = store.allMarks
                if all.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "highlighter")
                            .font(.app(30, weight: .light))
                            .foregroundStyle(app.settings.accentColor.opacity(0.5))
                        Text("还没划过句子")
                            .font(.app(13))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text("读书的时候点右上角「选句子」，\n点中的那句就会被马克笔画起来。")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme).opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 70)
                }

                ForEach(all) { m in
                    Button { jumpTo = m } label: { markCard(m) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.removeAnnotation(m.id)
                            } label: {
                                Label("撤掉这道线", systemImage: Icon.trash)
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
    }

    private func markCard(_ m: Annotation) -> some View {
        let book = store.book(m.bookID)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // 那支马克笔的颜色
                Circle().fill(m.color.opacity(0.75)).frame(width: 8, height: 8)
                Text(shelfCrumb(book))
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                if m.discussed {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(app.settings.accentColor.opacity(0.8))
                }
                Text(String(m.createdAt.formatted(.dateTime.month().day())))
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            // 划过的那句，底下垫一层马克笔
            Text(m.quote)
                .font(.app(14, design: .serif))
                .foregroundStyle(Theme.textMain(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 3)
                .background(m.color.opacity(0.28))

            ForEach(m.notes) { n in
                Text("⤷ " + n.author + "：" + n.text)
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(13)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
    }

    /// 「小说 · 《活着》 · 第 3 章」这种面包屑，她说要「备注那个分类里的哪一本」
    private func shelfCrumb(_ book: Book?) -> String {
        guard let book else { return "（这本书已经不在了）" }
        let shelf = book.shelf.isEmpty ? "还没归架" : book.shelf
        return shelf + " · 《" + book.title + "》"
    }

    // MARK: 零碎

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.app(32, weight: .light))
                .foregroundStyle(app.settings.accentColor.opacity(0.5))
            Text("书房还空着")
                .font(.app(13))
                .foregroundStyle(Theme.textMuted(scheme))
            Text("右上角导入 txt 或 epub，再建几个书架把它们归进去。\n每本书可以单独决定要不要叫他一起读。")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme).opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 70)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bookMenu(_ book: Book) -> some View {
        Button {
            store.toggleShared(book.id)
        } label: {
            Label(book.shared ? "不跟他一起读了" : "叫他一起读",
                  systemImage: book.shared ? "person.slash" : "person.2")
        }
        Menu {
            Button("还没归架") { store.move(book.id, toShelf: "") }
            ForEach(store.shelves(), id: \.self) { name in
                Button(name) { store.move(book.id, toShelf: name) }
            }
        } label: {
            Label("换个架子", systemImage: "arrow.right.square")
        }
        Button(role: .destructive) {
            store.remove(book.id)
        } label: {
            Label("从书房拿走", systemImage: Icon.trash)
        }
    }

    private func load(_ urls: [URL]) {
        busy = true
        Task {
            var done = 0
            for u in urls {
                let granted = u.startAccessingSecurityScopedResource()
                defer { if granted { u.stopAccessingSecurityScopedResource() } }
                do { _ = try await store.importBook(from: u); done += 1 }
                catch { notice = error.localizedDescription }
            }
            busy = false
            if done > 0 { notice = "导进来 \(done) 本。长按可以归到书架上。" }
        }
    }
}

// MARK: - 一个架子里的书：封面朝外

/// 她要的：「点进分类，所有书封面朝着我，封面下方是书名／作者／读的进度。
/// 如果没有封面，就以书的书名作为封面。长按可以修改封面，可以修改分类。」
struct ShelfBooksView: View {

    /// 空字符串＝「还没归架」那一堆
    let shelf: String

    @ObservedObject private var store = LibraryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var pickingCoverFor: Book?
    @State private var picked: PhotosPickerItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(store.books(onShelf: shelf)) { book in
                        NavigationLink {
                            ReaderView(bookID: book.id)
                        } label: {
                            coverCell(book)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                pickingCoverFor = book
                            } label: {
                                Label(book.coverName.isEmpty ? "配一张封面" : "换封面",
                                      systemImage: "photo")
                            }
                            if !book.coverName.isEmpty {
                                Button {
                                    store.setCover(book.id, fileName: "")
                                } label: {
                                    Label("不要封面了（用书名）", systemImage: "textformat")
                                }
                            }
                            Menu {
                                Button("还没归架") { store.move(book.id, toShelf: "") }
                                ForEach(store.shelves(), id: \.self) { name in
                                    Button(name) { store.move(book.id, toShelf: name) }
                                }
                            } label: {
                                Label("换个架子", systemImage: "arrow.right.square")
                            }
                            Button {
                                store.toggleShared(book.id)
                            } label: {
                                Label(book.shared ? "不跟他一起读了" : "叫他一起读",
                                      systemImage: book.shared ? "person.slash" : "person.2")
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, Layout.tabBarExpanded)
            }
        }
        .navigationTitle(shelf.isEmpty ? "还没归架" : shelf)
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: Binding(
            get: { pickingCoverFor != nil },
            set: { if !$0 { pickingCoverFor = nil } }
        ), selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in saveCover(item) }
    }

    private func coverCell(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCover(book: book)
                .frame(height: 138)

            Text(book.title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !book.author.isEmpty {
                Text(book.author)
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 4) {
                if book.shared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(app.settings.accentColor)
                }
                Text(book.progress < 0.005
                     ? "还没开始"
                     : "读了 \(Int(book.progress * 100))%")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func saveCover(_ item: PhotosPickerItem?) {
        guard let item, let book = pickingCoverFor else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let name = ImageStore.save(image) else { return }
            await MainActor.run {
                store.setCover(book.id, fileName: name)
                pickingCoverFor = nil
                picked = nil
            }
        }
    }
}

// MARK: - 一张封面

/// 有图就用图；**没图就拿书名当封面**（她说的）。
/// 没图那一版不是放一个占位图标——是把书名认真排一排，
/// 一格纯色底、书名竖着居中、底下一道作者。看着就是一本没有封面的书，
/// 而不是「这里缺一张图」。
struct BookCover: View {

    let book: Book
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if !book.coverName.isEmpty, let img = ImageStore.load(book.coverName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                let tone = BookshelfView.spineTone(for: book)
                LinearGradient(colors: [tone, tone.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 8) {
                    Text(book.coverTitle)
                        .font(.app(15, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                    if !book.author.isEmpty {
                        Rectangle().fill(.white.opacity(0.5))
                            .frame(width: 22, height: 0.8)
                        Text(book.author)
                            .font(.app(10))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.black.opacity(0.12), lineWidth: 0.7)
        }
        // 书脊那一侧压一道暗，看着像一本有厚度的书
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.22), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 8)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .shadow(color: .black.opacity(0.18), radius: 5, x: 1, y: 3)
    }
}
