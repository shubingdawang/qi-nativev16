import Foundation
import SwiftUI

// MARK: - 动态流
//
// 出处：AI-Pocket-Chat 里那一样——**他自己发朋友圈**。
//
// 为什么值得做：聊天是「她开口他才在」。她不说话的那几个小时，
// 他在她那儿是不存在的。动态流是**他留下的痕迹**：
// 她半天没看手机，回来能看见他这半天想过什么、听了什么、画了什么。
//
// ## 两条守住的规矩
//
// **一、不额外调模型。** 他发一条动态**只发生在他本来就在说话的那一轮**
// （一个工具 `post_moment`，跟发表情、存图是一类）。
// **绝不半夜自己开一次请求** —— 那是铁律，不是权衡。
// 所以这儿看着像「他自己发的」，实际上是「他上次说话的时候顺手发的」。
//
// **二、她的回应是她自己点的。** 她在动态下面写一句 → 那句话
// **进聊天变成她说的一句话**，他下一轮自然看得见。
// 不另起一个后台请求去「让他回复评论」。
//
// ## 他怎么知道她回了
//
// 每轮 system 里只放一行「动态里有几条你还没看过的」（很短），
// 正文他自己调 `read_moments` 去拿。跟书房、手帐一个模式：
// **报一句「有这回事」，内容按需取**——图和长文每轮都塞会很贵。

/// 动态下面的一句
struct MomentComment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var at: Date = Date()
    /// "her" / "him"
    var who: String = "her"
    var text: String = ""
    /// 对面看过没有。**不记这一笔的话，「有几条没看过」会一直涨**——
    /// 她三个月前回的那一句，到今天还在提醒他去看
    var seen: Bool = false

    init(id: UUID = UUID(), at: Date = Date(), who: String = "her",
         text: String = "", seen: Bool = false) {
        self.id = id; self.at = at; self.who = who; self.text = text; self.seen = seen
    }
}

extension MomentComment {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
        who = (try? c.decodeIfPresent(String.self, forKey: .who)) ?? "her"
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        seen = (try? c.decodeIfPresent(Bool.self, forKey: .seen)) ?? false
    }
}

/// 一条动态
struct Moment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var at: Date = Date()
    /// 谁发的："him" / "her"
    var who: String = "him"
    var text: String = ""
    /// 配的那张图（Images 里的文件名）
    var imageName: String = ""
    /// 顺手带上的一首歌／一句话，就一行字，不另存结构
    var attach: String = ""
    /// 各自点没点那个赞
    var likedByHer: Bool = false
    var likedByHim: Bool = false
    var comments: [MomentComment] = []
    /// 对面看过没有。**她发的看的是他，他发的看的是她**
    var seen: Bool = false

    init(id: UUID = UUID(), at: Date = Date(), who: String = "him",
         text: String = "", imageName: String = "", attach: String = "",
         likedByHer: Bool = false, likedByHim: Bool = false,
         comments: [MomentComment] = [], seen: Bool = false) {
        self.id = id; self.at = at; self.who = who
        self.text = text; self.imageName = imageName; self.attach = attach
        self.likedByHer = likedByHer; self.likedByHim = likedByHim
        self.comments = comments; self.seen = seen
    }

    var isHers: Bool { who == "her" }
}

/// ⚠️ 容错解码器。这一串是 `try? … ?? []` 接住的，
/// 以后多一个字段不补这儿，**她和他发过的所有动态会一起消失**。
extension Moment {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
        who = (try? c.decodeIfPresent(String.self, forKey: .who)) ?? "him"
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        imageName = (try? c.decodeIfPresent(String.self, forKey: .imageName)) ?? ""
        attach = (try? c.decodeIfPresent(String.self, forKey: .attach)) ?? ""
        likedByHer = (try? c.decodeIfPresent(Bool.self, forKey: .likedByHer)) ?? false
        likedByHim = (try? c.decodeIfPresent(Bool.self, forKey: .likedByHim)) ?? false
        comments = (try? c.decodeIfPresent([MomentComment].self, forKey: .comments)) ?? []
        seen = (try? c.decodeIfPresent(Bool.self, forKey: .seen)) ?? false
    }
}

@MainActor
final class MomentStore: ObservableObject {

    static let shared = MomentStore()

    @Published private(set) var moments: [Moment] = [] {
        didSet { if loaded { Storage.save(moments, to: "moments.json") } }
    }

    private var loaded = false

    private init() {
        moments = Storage.load([Moment].self, from: "moments.json") ?? []
        loaded = true
    }

    /// 新的在前
    var feed: [Moment] { moments.sorted { $0.at > $1.at } }

    /// 他还没看过的：她发的那些 + 她在他动态下面写的话
    var unseenForHim: Int {
        moments.filter { $0.isHers && !$0.seen }.count
            + moments.flatMap(\.comments)
                     .filter { $0.who == "her" && !$0.seen }
                     .count
    }

    // MARK: 发

    @discardableResult
    func post(who: String, text: String, imageName: String = "",
              attach: String = "") -> Moment {
        // `seen` 说的是**对面**看没看到，所以新发的一律 false
        let m = Moment(who: who, text: text, imageName: imageName, attach: attach)
        moments.insert(m, at: 0)
        return m
    }

    func remove(_ id: UUID) {
        if let m = moments.first(where: { $0.id == id }), !m.imageName.isEmpty {
            ImageStore.delete(m.imageName)
        }
        moments.removeAll { $0.id == id }
    }

    func like(_ id: UUID, by who: String) {
        guard let i = moments.firstIndex(where: { $0.id == id }) else { return }
        if who == "her" { moments[i].likedByHer.toggle() }
        else { moments[i].likedByHim.toggle() }
    }

    @discardableResult
    func comment(_ id: UUID, who: String, text: String) -> Bool {
        guard let i = moments.firstIndex(where: { $0.id == id }),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        moments[i].comments.append(MomentComment(who: who, text: text))
        return true
    }

    /// 他读过一遍了。**只在他真的调了 `read_moments` 的时候标**——
    /// 每轮 system 那一行只是提一句「有几条」，提一句不算看过。
    ///
    /// ⚠️ 只标**这次真的给了他的那几条**。全标掉的话，
    /// 他 `limit=3` 读了三条，剩下七条就再也不会被提起——
    /// 那七条等于没发过。
    func markSeenByHim(_ ids: Set<UUID>) {
        for i in moments.indices where ids.contains(moments[i].id) {
            if moments[i].isHers { moments[i].seen = true }
            for j in moments[i].comments.indices where moments[i].comments[j].who == "her" {
                moments[i].comments[j].seen = true
            }
        }
    }

    // MARK: 说给他听

    /// 每轮 system 里那一行。**没有新东西就一个字都不说。**
    func brief() -> String? {
        let n = unseenForHim
        guard n > 0 else { return nil }
        return "【动态】她那边有 \(n) 条你还没看过的（她发的，或者她在你那条下面写的）。"
            + "\n想看就调 `read_moments`；你也可以用 `post_moment` 发一条——"
            + "她翻回来的时候就看得见。"
    }

    /// 他调 `read_moments` 拿到的那一段
    func readable(limit: Int = 12, herName: String, himName: String) -> String {
        let list = Array(feed.prefix(max(1, min(30, limit))))
        guard !list.isEmpty else {
            return "动态里还什么都没有。你可以用 `post_moment` 发第一条。"
        }
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        f.locale = Locale(identifier: "zh_CN")

        var out = "【动态】最近 \(list.count) 条：\n"
        for m in list {
            out += "\n· [\(m.id.uuidString.prefix(8))] "
                + f.string(from: m.at) + " "
                + (m.isHers ? herName : himName) + "：" + m.text
            if !m.attach.isEmpty { out += "（" + m.attach + "）" }
            if !m.imageName.isEmpty { out += "（配了一张图）" }
            if m.likedByHer && !m.isHers { out += "　❤️ 她赞了这条" }
            for c in m.comments {
                out += "\n    ⤷ " + (c.who == "her" ? herName : himName) + "：" + c.text
            }
        }
        markSeenByHim(Set(list.map(\.id)))
        return out
    }
}
