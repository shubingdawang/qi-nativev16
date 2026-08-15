import Foundation
import SwiftUI

/// 一条记录。可以是备忘、待办，也可以只是一句想留住的话。
struct Memo: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 正文
    var text: String = ""
    /// 挂在聊天页上时，露出来那一小节写什么。
    /// 比如「十点前」「很重要」——一眼扫过去就知道是什么事。
    var badge: String = ""
    /// 浮窗上那行字的颜色。只管浮窗，备忘页里跟着系统深浅色走。
    var colorHex: String = ""
    /// 置顶了才会挂到聊天页上
    var pinned: Bool = false
    /// 谁写的
    var author: String = ""
    var createdAt: Date = Date()

    var doneAt: Date? = nil
    var doneBy: String = ""
    var cancelledAt: Date? = nil
    var cancelledBy: String = ""

    /// 事后补的话
    var notes: [MemoNote] = []

    var isDone: Bool { doneAt != nil }
    var isCancelled: Bool { cancelledAt != nil }
    var isActive: Bool { !isDone && !isCancelled }

    /// 完成一小时之内还留在列表上（划掉的样子），过了才收进历史。
    /// 给个反悔的余地，也让你看得见"今天做完了什么"。
    var stillOnList: Bool {
        guard let doneAt else { return !isCancelled }
        return Date().timeIntervalSince(doneAt) < 3600
    }

    var color: Color? {
        colorHex.isEmpty ? nil : Color(hexString: colorHex)
    }
}

struct MemoNote: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var author: String = ""
    var text: String = ""
    var createdAt: Date = Date()
}

/// 备忘长什么样。四套，在备忘页顶上随时换。
enum MemoStyle: Int, CaseIterable, Identifiable {
    case plain = 0      // 素
    case note = 1       // 便签
    case tape = 2       // 胶带
    case ticket = 3     // 票根

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .plain:  return "素"
        case .note:   return "便签"
        case .tape:   return "胶带"
        case .ticket: return "票根"
        }
    }
}

@MainActor
final class MemoStore: ObservableObject {

    static let shared = MemoStore()

    @Published var memos: [Memo] = [] {
        didSet { if loaded { Storage.save(memos, to: "memos.json") } }
    }
    @Published var style: MemoStyle = .plain {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "memoStyle") }
    }

    private var loaded = false

    init() {
        memos = Storage.load([Memo].self, from: "memos.json") ?? []
        style = MemoStyle(rawValue: UserDefaults.standard.integer(forKey: "memoStyle")) ?? .plain
        loaded = true
    }

    /// 还挂在列表上的（含刚完成不到一小时的）
    var onList: [Memo] {
        memos.filter { $0.stillOnList }
            .sorted { a, b in
                if a.pinned != b.pinned { return a.pinned }
                if a.isDone != b.isDone { return !a.isDone }
                return a.createdAt > b.createdAt
            }
    }

    /// 置顶的，聊天页上挂着的就是这些
    var pinned: [Memo] {
        memos.filter { $0.pinned && $0.isActive }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 已经收起来的
    var history: [Memo] {
        memos.filter { !$0.stillOnList }
            .sorted { a, b in
                (a.doneAt ?? a.cancelledAt ?? a.createdAt)
                    > (b.doneAt ?? b.cancelledAt ?? b.createdAt)
            }
    }

    @discardableResult
    func add(_ text: String, badge: String = "", author: String,
             pinned: Bool = false, colorHex: String = "") -> Memo {
        var m = Memo(text: text, badge: badge, colorHex: colorHex,
                     pinned: pinned, author: author)
        m.createdAt = Date()
        memos.append(m)
        return m
    }

    func update(_ memo: Memo) {
        guard let i = memos.firstIndex(where: { $0.id == memo.id }) else { return }
        memos[i] = memo
    }

    func complete(_ id: UUID, by who: String) {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].doneAt = Date()
        memos[i].doneBy = who
    }

    /// 手误点了完成，撤回来重新挂上
    func undoComplete(_ id: UUID) {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].doneAt = nil
        memos[i].doneBy = ""
    }

    func cancel(_ id: UUID, by who: String) {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].cancelledAt = Date()
        memos[i].cancelledBy = who
    }

    /// 从历史里捞回来
    func restore(_ id: UUID) {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].doneAt = nil
        memos[i].doneBy = ""
        memos[i].cancelledAt = nil
        memos[i].cancelledBy = ""
    }

    func annotate(_ id: UUID, text: String, by who: String) {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].notes.append(MemoNote(author: who, text: text))
    }

    func remove(_ id: UUID) {
        memos.removeAll { $0.id == id }
    }

    func togglePin(_ id: UUID) {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[i].pinned.toggle()
    }

    func memo(_ id: UUID) -> Memo? { memos.first { $0.id == id } }

    /// 按前几位 id 找，给他用的
    func find(prefix: String) -> Memo? {
        let p = prefix.lowercased()
        return memos.first { $0.id.uuidString.lowercased().hasPrefix(p) && $0.isActive }
    }
}
