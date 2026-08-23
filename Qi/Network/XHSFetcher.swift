import Foundation
import UIKit

/// 一条读回来的链接：小红书笔记、B 站视频、抖音视频。
///
/// 名字还叫 XHSNote 是因为它已经存在她手机里的聊天记录里了——
/// 改名等于把以前那些卡片全弄丢。**存下来的类型不能随便改名。**
struct XHSNote: Codable, Hashable {
    /// 哪家的。老数据里没这个字段，读出来算小红书（那时候只有小红书）。
    var source: LinkSource = .xhs
    var url: String = ""
    var title: String = ""
    var author: String = ""
    var desc: String = ""
    var imageURLs: [String] = []
    var likedCount: String = ""
    var commentCount: String = ""
    var collectedCount: String = ""
    /// 视频才有的两样
    var playCount: String = ""
    var duration: String = ""
    var comments: [XHSComment] = []
    /// 下载下来的图，存本地
    var localImages: [String] = []

    var imageCount: Int { imageURLs.count }

    /// 给模型看的那段文字。
    ///
    /// 视频那两家**必须写明他看不了视频**——卡片里只有封面和简介，
    /// 不说清楚他会当成自己看过，然后开始编里面的情节。
    var briefForModel: String {
        let head: String
        switch source {
        case .xhs:      head = "【小红书笔记】"
        case .bilibili: head = "【B 站视频】"
        case .douyin:   head = "【抖音视频】"
        }
        var s = head + "\n标题：\(title)"
        if !author.isEmpty {
            s += "\n" + (source == .xhs ? "作者" : "up 主") + "：\(author)"
        }
        if !desc.isEmpty { s += "\n简介：\(desc)" }
        if !duration.isEmpty { s += "\n时长：\(duration)" }
        if !playCount.isEmpty { s += "\n播放：\(playCount)" }
        if !likedCount.isEmpty {
            s += "\n互动：赞 \(likedCount)"
            if !commentCount.isEmpty { s += " · 评论 \(commentCount)" }
            if !collectedCount.isEmpty { s += " · 收藏 \(collectedCount)" }
        }
        if source != .xhs {
            s += "\n（视频本身你看不了，这里只有封面和简介——别装作看过。"
            s += "想知道里面讲了什么，问她。）"
        } else if imageCount > 0 {
            s += "\n配图 \(imageCount) 张（图片本身也一并给你了）"
        }
        if !comments.isEmpty {
            s += "\n\n评论区："
            for c in comments.prefix(8) {
                s += "\n· \(c.user)：\(c.content)"
                if !c.ipLocation.isEmpty { s += "（\(c.ipLocation)）" }
            }
        }
        return s
    }
}

struct XHSComment: Codable, Hashable {
    var user: String = ""
    var content: String = ""
    var ipLocation: String = ""
}

enum XHSFetcher {

    enum FetchError: LocalizedError {
        case badURL
        case noData
        case blocked

        var errorDescription: String? {
            switch self {
            case .badURL: return "这不像是小红书的链接"
            case .noData: return "读不出笔记内容，可能是笔记被删了或者页面改版了"
            case .blocked: return "拿不到页面，稍后再试"
            }
        }
    }

    // 「一段文字里有没有链接」挪到 LinkCards.detect 了——
    // 三家的正则得摆在一块儿比先后，分散在各家里就没法比。

    /// 抓一条笔记。
    ///
    /// 关键是**必须用手机 UA**——桌面 UA 拿到的页面结构不一样，会缺数据。
    /// 页面 HTML 里有个 window.__INITIAL_STATE__，笔记的全部内容都在里面，
    /// 不用登录，也不会触发风控（跟微信生成分享卡是同一个原理）。
    static func fetch(_ url: URL) async throws -> XHSNote {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw FetchError.blocked
        }
        guard let html = String(data: data, encoding: .utf8) else { throw FetchError.noData }

        guard let json = jsonBlob(from: html, after: "__INITIAL_STATE__") else {
            throw FetchError.noData
        }
        var note = parse(json)
        note.url = (response.url ?? url).absoluteString
        guard !note.title.isEmpty || !note.desc.isEmpty || !note.imageURLs.isEmpty else {
            throw FetchError.noData
        }
        return note
    }

    /// 从 HTML 里把某个标记后面那段 JSON 抠出来。
    ///
    /// 小红书用 `__INITIAL_STATE__`，抖音用 `_ROUTER_DATA`——同一套数括号的办法，
    /// 所以不是 private，抖音那边直接借这一份用。
    static func jsonBlob(from html: String, after marker: String) -> [String: Any]? {
        guard let start = html.range(of: marker) else { return nil }
        guard let braceStart = html[start.upperBound...].firstIndex(of: "{") else { return nil }

        // 数括号找到这段 JSON 的结尾，字符串里的括号不算
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        var i = braceStart
        while i < html.endIndex {
            let ch = html[i]
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == "\"" { inString.toggle() }
            else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { end = html.index(after: i); break }
                }
            }
            i = html.index(after: i)
        }
        guard let end else { return nil }

        var raw = String(html[braceStart..<end])
        // 页面里会写成 undefined，那不是合法 JSON
        raw = raw.replacingOccurrences(of: ":undefined", with: ":null")
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func parse(_ state: [String: Any]) -> XHSNote {
        var note = XHSNote()

        // 页面结构变过，两种路径都试一遍
        let noteRoot = state["noteData"] as? [String: Any] ?? [:]
        var data: [String: Any] = [:]
        if let d = (noteRoot["data"] as? [String: Any])?["noteData"] as? [String: Any] {
            data = d
        } else if let d = noteRoot["normalNotePreloadData"] as? [String: Any] {
            data = d
        } else if let note0 = state["note"] as? [String: Any],
                  let map = note0["noteDetailMap"] as? [String: Any],
                  let first = map.values.first as? [String: Any],
                  let d = first["note"] as? [String: Any] {
            data = d
        }

        note.title = (data["title"] as? String) ?? ""
        note.desc = (data["desc"] as? String) ?? ""

        if let user = data["user"] as? [String: Any] {
            note.author = (user["nickname"] as? String)
                ?? (user["nickName"] as? String) ?? ""
        }

        if let inter = data["interactInfo"] as? [String: Any] {
            note.likedCount = text(inter["likedCount"])
            note.commentCount = text(inter["commentCount"])
            note.collectedCount = text(inter["collectedCount"])
        } else {
            note.likedCount = text(data["likedCount"])
            note.commentCount = text(data["commentsCount"])
            note.collectedCount = text(data["collectedCount"])
        }

        if let list = data["imageList"] as? [[String: Any]] {
            note.imageURLs = list.compactMap { item in
                let candidates = [item["urlDefault"], item["url"], item["urlPre"]]
                for c in candidates {
                    if let s = c as? String, !s.isEmpty { return normalize(s) }
                }
                // 有些结构把地址埋在 infoList 里
                if let infos = item["infoList"] as? [[String: Any]] {
                    for info in infos {
                        if let s = info["url"] as? String, !s.isEmpty { return normalize(s) }
                    }
                }
                return nil
            }
        }

        if let comments = state["comment"] as? [String: Any],
           let map = comments["comments"] as? [String: Any],
           let first = map.values.first as? [String: Any],
           let list = first["list"] as? [[String: Any]] {
            note.comments = list.prefix(10).map { c in
                XHSComment(
                    user: ((c["userInfo"] as? [String: Any])?["nickname"] as? String) ?? "",
                    content: (c["content"] as? String) ?? "",
                    ipLocation: (c["ipLocation"] as? String) ?? ""
                )
            }
        }
        return note
    }

    /// 地址里常见两个毛病：unicode 转义、少了协议头
    private static func normalize(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u002f", with: "/")
        if s.hasPrefix("//") { s = "https:" + s }
        return s
    }

    private static func text(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    /// 把配图下载下来存本地。
    /// 图床有防盗链，得带上 Referer——**而且得是对应那家的**，
    /// 拿小红书的 Referer 去要 B 站的封面，回来的是 403。
    static func downloadImages(_ note: XHSNote,
                               progress: @MainActor @escaping (Int, Int) -> Void)
    async -> [String] {
        var saved: [String] = []
        let total = min(note.imageURLs.count, 9)
        for (i, link) in note.imageURLs.prefix(9).enumerated() {
            await progress(i + 1, total)
            guard let url = URL(string: link) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.setValue(note.source.referer, forHTTPHeaderField: "Referer")
            req.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let image = UIImage(data: data),
                  let name = ImageStore.save(image)
            else { continue }
            saved.append(name)
        }
        return saved
    }
}


/// ⚠️ 手写的解码器，不能删。
///
/// `XHSNote` 是拿 `try?` 解出来的（`ChatMessage` 里那句
/// `note = try? c.decodeIfPresent(XHSNote.self, ...)`）。
/// 合成的解码器少一个 key 就整条 throw，被 `try?` 一吞就变成 nil——
/// 也就是说**加个字段，她以前收到的卡片会一张不剩地消失**，而且不报错。
/// 这次加 `source` / `playCount` / `duration` 就是这种情况。
extension XHSNote {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decodeIfPresent(LinkSource.self, forKey: .source)) ?? .xhs
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? ""
        desc = (try? c.decodeIfPresent(String.self, forKey: .desc)) ?? ""
        imageURLs = (try? c.decodeIfPresent([String].self, forKey: .imageURLs)) ?? []
        likedCount = (try? c.decodeIfPresent(String.self, forKey: .likedCount)) ?? ""
        commentCount = (try? c.decodeIfPresent(String.self, forKey: .commentCount)) ?? ""
        collectedCount = (try? c.decodeIfPresent(String.self, forKey: .collectedCount)) ?? ""
        playCount = (try? c.decodeIfPresent(String.self, forKey: .playCount)) ?? ""
        duration = (try? c.decodeIfPresent(String.self, forKey: .duration)) ?? ""
        comments = (try? c.decodeIfPresent([XHSComment].self, forKey: .comments)) ?? []
        localImages = (try? c.decodeIfPresent([String].self, forKey: .localImages)) ?? []
    }
}
