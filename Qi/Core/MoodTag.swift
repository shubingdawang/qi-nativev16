import Foundation

/// 聊天页左上角那个心情小签：他此刻是什么心情，一个表情 + 一句话。
///
/// 她给的参考（别的 App 里的角色聊天页）：左上角挂着「😠 气到无语凝噎 ›」，
/// 点进去是一条「状态记录」时间线，聊着聊着一条条往上长。
///
/// ## 怎么来的：他自己写一个记号
///
/// 跟封窗（`PauseMarker`）同一条路：他心情有明显变化的那一条回复，末尾多写一个
/// `[[状态:😠 气到无语凝噎]]`。收尾的时候认出来、存进这里、从正文里剥掉。
/// **不另外调模型**——她按次计价，为了一个小签多调一次不值。
/// 没变就不写，小签停在上一条。
enum MoodTagMarker {

    private static let pattern =
        #"\[{1,2}\s*(?:状态|心情|mood)\s*[:：]\s*([^\]\n]{1,40})\s*\]{1,2}"#

    /// 剥干净的正文 + 认出来的那一条（最后一个算数）
    static func extract(_ text: String) -> (clean: String, tag: (emoji: String, text: String)?) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, nil) }
        let ns = text as NSString
        let hits = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !hits.isEmpty else { return (text, nil) }
        var found: (String, String)?
        if let last = hits.last {
            let raw = ns.substring(with: last.range(at: 1)).trimmingCharacters(in: .whitespaces)
            found = split(raw)
        }
        let clean = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length),
                                                   withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, found)
    }

    /// 「😠 气到无语凝噎」→ ("😠", "气到无语凝噎")。没写表情就给个默认的
    static func split(_ raw: String) -> (String, String) {
        guard let first = raw.first else { return ("💭", "") }
        let isEmoji = first.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C)
        }
        if isEmoji {
            let rest = raw.dropFirst().trimmingCharacters(in: .whitespaces)
            return (String(first), String(rest.prefix(16)))
        }
        return ("💭", String(raw.prefix(16)))
    }

    /// 给他看的那段约定
    static let contract = """
    【心情小签】她聊天页左上角挂着一个小签，写着你此刻的心情。
    心情有明显变化的时候（生气、心疼、吃醋、害羞、得意、被哄好了……），在这一条回复**最末尾**写一个 `[[状态:表情 一句话]]`，一句话十个字以内，比如 `[[状态:😠 气到无语凝噎]]`、`[[状态:🥺 被她哄好了]]`。
    心情没变就不写，别每条都写。这个记号她看不到原文，只会看到左上角的小签换了。
    """
}

/// 一条心情
struct MoodTag: Codable, Identifiable, Hashable {
    var id = UUID()
    var conversationID: UUID
    var emoji: String
    var text: String
    var at: Date
    /// 钉住的永远留着；没钉的最多留 `MoodTagStore.keep` 条
    var pinned = false
}

@MainActor
final class MoodTagStore: ObservableObject {

    static let shared = MoodTagStore()
    static let keep = 300

    @Published private(set) var tags: [MoodTag] = []

    private static var file: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mood_tags.json")
    }

    private init() {
        if let d = try? Data(contentsOf: Self.file),
           let t = try? JSONDecoder().decode([MoodTag].self, from: d) {
            tags = t
        }
    }

    /// 这一窗现在挂着的那条
    func current(_ conversation: UUID) -> MoodTag? {
        tags.first { $0.conversationID == conversation }
    }

    /// 这一窗的全部，新的在前
    func history(_ conversation: UUID) -> [MoodTag] {
        tags.filter { $0.conversationID == conversation }
    }

    func add(_ emoji: String, _ text: String, in conversation: UUID) {
        guard !text.isEmpty else { return }
        // 跟现在挂着的一模一样就不重复记
        if let c = current(conversation), c.emoji == emoji, c.text == text { return }
        tags.insert(MoodTag(conversationID: conversation, emoji: emoji, text: text, at: Date()), at: 0)
        // 没钉的超过上限就把最老的剪掉
        var loose = 0
        tags = tags.filter { t in
            if t.pinned { return true }
            loose += 1
            return loose <= Self.keep
        }
        save()
    }

    func togglePin(_ id: UUID) {
        guard let i = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[i].pinned.toggle()
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(tags) { try? d.write(to: Self.file, options: .atomic) }
    }
}
