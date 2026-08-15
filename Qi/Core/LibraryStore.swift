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
