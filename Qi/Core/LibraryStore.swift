import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {

    static let shared = LibraryStore()

    @Published var books: [Book] = [] {
        didSet { if loaded { Storage.save(books, to: "books.json") } }
    }
    @Published var annotations: [Annotation] = [] {
        didSet { if loaded { Storage.save(annotations, to: "annotations.json") } }
    }
    /// 正在读哪本。他要能知道"现在读到哪儿"，就靠这个。
    @Published var readingID: UUID?

    private var loaded = false

    init() {
        books = Storage.load([Book].self, from: "books.json") ?? []
        annotations = Storage.load([Annotation].self, from: "annotations.json") ?? []
        shelfNames = Storage.load([String].self, from: "book-shelves.json") ?? []
        loaded = true
    }

    // MARK: 书

    /// 导入一本。解析在后台跑完，只有最后落库这一下回主线程。
    func importBook(from url: URL) async throws -> Book {
        let book = try await Task.detached(priority: .userInitiated) {
            try BookParser.parse(url)
        }.value
        books.append(book)
        return book
    }

    func book(_ id: UUID?) -> Book? {
        guard let id else { return nil }
        return books.first { $0.id == id }
    }

    func update(_ book: Book) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i] = book
    }

    func remove(_ id: UUID) {
        books.removeAll { $0.id == id }
        annotations.removeAll { $0.bookID == id }
    }

    /// 记一下读到哪儿了
    func saveProgress(_ id: UUID, chapter: Int, offset: Double) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].chapterIndex = chapter
        books[i].offset = offset
    }

    // MARK: 给他看的

    /// 她这会儿正在读的那本（**而且是愿意跟他一起读的**）。
    /// 没开「叫他一起读」的书，他连书名都看不到。
    var sharedReading: Book? {
        guard let id = readingID, let b = book(id), b.shared else { return nil }
        return b
    }

    /// 跟某一句**像**的旧批注。
    ///
    /// 她要的：「跟他说上次的批注或写读后感的句子跟这次的很像，
    /// 他也能知道上次的句子是什么。」
    ///
    /// 复用记忆库那套二元组相似度（`MemoryRecall.similarity`）——
    /// 纯算术、不调模型，跟「她搜记忆」走的是同一把尺子。
    func similarAnnotations(to quote: String, excluding id: UUID?, limit: Int = 5)
        -> [(Annotation, Double)] {
        annotations
            .filter { $0.id != id }
            .map { ($0, MemoryRecall.similarity(quote, $0.quote)) }
            .filter { $0.1 >= 0.25 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0 }
    }

    /// 把某条批注标成「聊过了」——句子边上那个小气泡就是它。
    func markDiscussed(_ id: UUID, talkID: UUID? = nil) {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[i].discussed = true
        if let talkID, !annotations[i].talkIDs.contains(talkID) {
            annotations[i].talkIDs.append(talkID)
        }
    }

    func setColor(_ id: UUID, hex: String) {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[i].colorHex = hex
    }

    /// 全部批注，新的在前。批注页（首页那个「选项 2」）用它。
    var allMarks: [Annotation] {
        annotations.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: 书架（分类）

    /// 有哪些书架。**自己建的 + 书上带着的**，并起来。
    /// 跟相册那套一个道理：空书架推不出来，所以名单要单独存一份。
    @Published var shelfNames: [String] = [] {
        didSet { if loaded { Storage.save(shelfNames, to: "book-shelves.json") } }
    }

    func shelves() -> [String] {
        var names = Set(shelfNames)
        names.formUnion(books.map { $0.shelf })
        names.remove("")
        return names.sorted()
    }

    /// 某个书架上的书。传空字符串就是「还没归架」的那些。
    func books(onShelf shelf: String) -> [Book] {
        books.filter { $0.shelf == shelf }
            .sorted { $0.addedAt > $1.addedAt }
    }

    @discardableResult
    func createShelf(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !shelves().contains(n) else { return false }
        shelfNames.append(n)
        return true
    }

    func renameShelf(from old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != old else { return }
        for i in books.indices where books[i].shelf == old { books[i].shelf = n }
        shelfNames.removeAll { $0 == old }
        if !shelfNames.contains(n) { shelfNames.append(n) }
    }

    /// 拆书架。**书不删**，退回「还没归架」——
    /// 拆个架子把书一起烧了，那不叫整理。
    func removeShelf(_ name: String) {
        for i in books.indices where books[i].shelf == name { books[i].shelf = "" }
        shelfNames.removeAll { $0 == name }
    }

    func move(_ id: UUID, toShelf shelf: String) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].shelf = shelf
        if !shelf.isEmpty { createShelf(shelf) }
    }

    func setCover(_ id: UUID, fileName: String) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].coverName = fileName
    }

    func toggleShared(_ id: UUID) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].shared.toggle()
    }

    // MARK: 划线和批注

    func annotations(for bookID: UUID, chapter: Int? = nil) -> [Annotation] {
        annotations
            .filter { $0.bookID == bookID && (chapter == nil || $0.chapterIndex == chapter) }
            .sorted { $0.location < $1.location }
    }

    @discardableResult
    func addAnnotation(bookID: UUID, chapter: Int, quote: String,
                       location: Int, author: String, note: String = "") -> Annotation {
        var a = Annotation(bookID: bookID, chapterIndex: chapter,
                           quote: quote, location: location, author: author)
        if !note.isEmpty {
            a.notes.append(AnnotationNote(author: author, text: note))
        }
        annotations.append(a)
        return a
    }

    func reply(to id: UUID, text: String, by who: String) {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[i].notes.append(AnnotationNote(author: who, text: text))
    }

    func removeAnnotation(_ id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    func annotation(_ id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func find(prefix: String) -> Annotation? {
        let p = prefix.lowercased()
        return annotations.first { $0.id.uuidString.lowercased().hasPrefix(p) }
    }

    // MARK: 给他看的

    /// 他能看到的书：只有你打开了"一起读"的那些。
    var sharedBooks: [Book] { books.filter { $0.shared } }

    /// 现在读到哪儿，连同这一章的划线，整理成一段话
    func readingContext() -> String? {
        guard let book = book(readingID), book.shared else { return nil }
        let idx = min(book.chapterIndex, max(0, book.chapters.count - 1))
        guard book.chapters.indices.contains(idx) else { return nil }
        let chapter = book.chapters[idx]

        var s = "她正在读《\(book.title)》"
        if !book.author.isEmpty { s += "（\(book.author)）" }
        s += "，\(book.progressText)：\(chapter.title)。"

        let marks = annotations(for: book.id, chapter: idx)
        if !marks.isEmpty {
            s += "\n这一章划过的地方："
            for m in marks.prefix(8) {
                s += "\n· [\(m.id.uuidString.prefix(6))]「\(m.quote.prefix(50))」"
                if let last = m.notes.last {
                    s += " —— \(last.author)：\(last.text.prefix(40))"
                }
            }
        }
        return s
    }
}
