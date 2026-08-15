import SwiftUI
import UniformTypeIdentifiers

/// 书房。导进来的书都在这儿。
struct LibraryView: View {

    @ObservedObject private var store = LibraryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var importing = false
    @State private var busy = false
    @State private var notice: String?
    @State private var reading: Book?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {

                if store.books.isEmpty && !busy {
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(app.settings.accentColor.opacity(0.5))
                        Text("书架还空着")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text("点右上角导入 txt 或 epub。\n每本书可以单独决定要不要跟他一起读。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted(scheme).opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 70)
                }

                if busy {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("正在拆书…")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .padding(.vertical, 20)
                }

                if let notice {
                    Text(notice)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                ForEach(store.books) { book in
                    Button {
                        reading = book
                    } label: {
                        bookRow(book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            store.toggleShared(book.id)
                        } label: {
                            Label(book.shared ? "不跟他一起读了" : "叫他一起读",
                                  systemImage: book.shared ? "person.slash" : "person.2")
                        }
                        Button(role: .destructive) {
                            store.remove(book.id)
                        } label: {
                            Label("从书架拿走", systemImage: Icon.trash)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("书房")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    importing = true
                } label: {
                    Image(systemName: Icon.add)
                }
                .disabled(busy)
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [
                          .plainText,
                          UTType("org.idpf.epub-container") ?? .data,
                          .data
                      ],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await load(urls) }
        }
        .fullScreenCover(item: $reading) { book in
            ReaderView(bookID: book.id)
        }
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            // 没有封面就用书名头一个字凑一个
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(app.settings.accentColor.opacity(0.22))
                Text(String(book.title.prefix(1)))
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .frame(width: 44, height: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(2)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                HStack(spacing: 6) {
                    Text(book.progressText)
                    let n = store.annotations(for: book.id).count
                    if n > 0 { Text("· 划了 \(n) 处") }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted(scheme))

                if book.shared {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 8))
                        Text("一起读")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(app.settings.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(app.settings.accentColor.opacity(0.16)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(padding: 0)
    }

    private func load(_ urls: [URL]) async {
        busy = true
        notice = nil
        for u in urls {
            do {
                _ = try await store.importBook(from: u)
            } catch {
                notice = error.localizedDescription
            }
        }
        busy = false
    }
}

// MARK: - 读

/// 读书页。选中一段就是划线，划线之后可以在那句话底下说话。
struct ReaderView: View {

    let bookID: UUID

    @ObservedObject private var store = LibraryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var chapter = 0
    @State private var showChapters = false
    @State private var picking = false
    @State private var openedAnnotation: Annotation?
    @State private var fontSize: Double = 17

    private var book: Book? { store.book(bookID) }
    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }

    private var marks: [Annotation] {
        store.annotations(for: bookID, chapter: chapter)
    }

    var body: some View {
        ZStack {
            WallpaperBackground()

            VStack(spacing: 0) {
                header

                if let book, book.chapters.indices.contains(chapter) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(book.chapters[chapter].title)
                                .font(.system(size: 19, weight: .medium, design: .serif))
                                .foregroundStyle(Theme.textMain(scheme))
                                .padding(.bottom, 4)

                            if picking {
                                // 划线模式：一段一段点，点中的就是划下的
                                ForEach(paragraphs.indices, id: \.self) { i in
                                    paragraphButton(paragraphs[i], index: i)
                                }
                            } else {
                                ForEach(paragraphs.indices, id: \.self) { i in
                                    paragraphText(paragraphs[i], index: i)
                                }
                            }

                            chapterNav
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        .sheet(isPresented: $showChapters) { chapterList }
        .sheet(item: $openedAnnotation) { a in
            AnnotationSheet(annotation: a)
        }
        .onAppear { chapter = book?.chapterIndex ?? 0 }
        .onDisappear {
            store.saveProgress(bookID, chapter: chapter, offset: 0)
            if store.readingID == bookID { store.readingID = nil }
        }
        .onChange(of: chapter) { _, c in
            store.saveProgress(bookID, chapter: c, offset: 0)
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: Icon.close)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSoft(scheme))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(book?.title ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(book?.progressText ?? "")
                    if !marks.isEmpty { Text("· 这章划了 \(marks.count) 处") }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted(scheme))
            }

            Spacer(minLength: 0)

            // 划线开关
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { picking.toggle() }
            } label: {
                Image(systemName: picking ? "highlighter" : "highlighter")
                    .font(.system(size: 15))
                    .foregroundStyle(picking ? app.settings.accentColor : Theme.textSoft(scheme))
            }
            .buttonStyle(.plain)

            // 一起读
            if let book {
                Button {
                    store.toggleShared(book.id)
                    if book.shared { store.readingID = nil }
                    else { store.readingID = book.id }
                } label: {
                    Image(systemName: book.shared ? "person.2.fill" : "person.2")
                        .font(.system(size: 15))
                        .foregroundStyle(book.shared
                                         ? app.settings.accentColor
                                         : Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)
            }

            Button {
                showChapters = true
            } label: {
                Text("目录")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSoft(scheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassBackground(radius: 0, strength: app.settings.glassOpacity * 0.9)
    }

    // MARK: 正文

    private var paragraphs: [String] {
        guard let book, book.chapters.indices.contains(chapter) else { return [] }
        return book.chapters[chapter].text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func markFor(_ index: Int) -> Annotation? {
        marks.first { $0.location == index }
    }

    private func paragraphText(_ text: String, index: Int) -> some View {
        let mark = markFor(index)
        return Text(text)
            .font(.system(size: fontSize))
            .foregroundStyle(Theme.textMain(scheme))
            .lineSpacing(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if mark != nil {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(app.settings.accentColor.opacity(0.16))
                        .padding(.horizontal, -3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let mark { openedAnnotation = mark }
            }
    }

    private func paragraphButton(_ text: String, index: Int) -> some View {
        let mark = markFor(index)
        return Button {
            if let mark {
                openedAnnotation = mark
            } else {
                let a = store.addAnnotation(bookID: bookID, chapter: chapter,
                                            quote: text, location: index, author: me)
                if app.settings.haptics {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                openedAnnotation = a
            }
        } label: {
            Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.textMain(scheme))
                .lineSpacing(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(mark != nil
                              ? app.settings.accentColor.opacity(0.2)
                              : Theme.textMuted(scheme).opacity(0.05))
                        .padding(.horizontal, -4)
                }
        }
        .buttonStyle(.plain)
    }

    private var chapterNav: some View {
        HStack {
            Button {
                if chapter > 0 { chapter -= 1 }
            } label: {
                Text("上一章")
                    .font(.system(size: 13))
                    .foregroundStyle(chapter > 0
                                     ? app.settings.accentColor
                                     : Theme.textMuted(scheme).opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(chapter == 0)

            Spacer()

            Button {
                if let book, chapter < book.chapters.count - 1 { chapter += 1 }
            } label: {
                Text("下一章")
                    .font(.system(size: 13))
                    .foregroundStyle(app.settings.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(chapter >= (book?.chapters.count ?? 1) - 1)
        }
        .padding(.top, 24)
    }

    private var chapterList: some View {
        NavigationStack {
            List {
                ForEach((book?.chapters ?? []).indices, id: \.self) { i in
                    Button {
                        chapter = i
                        showChapters = false
                    } label: {
                        HStack {
                            Text(book?.chapters[i].title ?? "")
                                .font(.system(size: 14))
                                .foregroundStyle(i == chapter
                                                 ? app.settings.accentColor
                                                 : Theme.textMain(scheme))
                                .lineLimit(1)
                            Spacer()
                            let n = store.annotations(for: bookID, chapter: i).count
                            if n > 0 {
                                Text("\(n)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                        }
                    }
                }
            }
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 这一句

/// 点划过的地方弹出来的。上面是那句话，底下是围着它说的话。
struct AnnotationSheet: View {

    @State var annotation: Annotation

    @ObservedObject private var store = LibraryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }
    private var fresh: Annotation { store.annotation(annotation.id) ?? annotation }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // 划下的那句
                            HStack(alignment: .top, spacing: 9) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(app.settings.accentColor.opacity(0.6))
                                    .frame(width: 3)
                                Text(fresh.quote)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textSoft(scheme))
                                    .lineSpacing(5)
                            }
                            .padding(.bottom, 4)

                            ForEach(fresh.notes) { note in
                                noteRow(note)
                            }

                            if fresh.notes.isEmpty {
                                Text("还没说什么。这句话为什么打动你？")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                        }
                        .padding(18)
                    }

                    HStack(spacing: 8) {
                        TextField("再说一句…", text: $draft, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .glassBackground(radius: 20, strength: app.settings.glassOpacity)

                        Button {
                            store.reply(to: fresh.id, text: draft, by: me)
                            draft = ""
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textMain(scheme))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(app.settings.accentColor.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("这一句")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: Icon.close)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        store.removeAnnotation(fresh.id)
                        dismiss()
                    } label: {
                        Text("取消划线").foregroundStyle(.red)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func noteRow(_ note: AnnotationNote) -> some View {
        let mine = note.author == me
        return HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                Text(note.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMain(scheme))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .glassBackground(radius: 15, strength: app.settings.glassOpacity,
                                     extra: mine ? 0.3 : 0)
                Text(stamp(note))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func stamp(_ note: AnnotationNote) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return note.author + " · " + f.string(from: note.createdAt)
    }
}
