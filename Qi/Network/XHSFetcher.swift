import Foundation
import UIKit

/// 一条小红书笔记。
struct XHSNote: Codable, Hashable {
    var url: String = ""
    var title: String = ""
    var author: String = ""
    var desc: String = ""
    var imageURLs: [String] = []
    var likedCount: String = ""
    var commentCount: String = ""
    var collectedCount: String = ""
    var comments: [XHSComment] = []
    /// 下载下来的图，存本地
    var localImages: [String] = []

    var imageCount: Int { imageURLs.count }

    /// 给模型看的那段文字
    var briefForModel: String {
        var s = "【小红书笔记】\n标题：\(title)"
        if !author.isEmpty { s += "\n作者：\(author)" }
        if !desc.isEmpty { s += "\n正文：\(desc)" }
        if !likedCount.isEmpty {
            s += "\n互动：赞 \(likedCount)"
            if !commentCount.isEmpty { s += " · 评论 \(commentCount)" }
            if !collectedCount.isEmpty { s += " · 收藏 \(collectedCount)" }
        }
        if imageCount > 0 { s += "\n配图 \(imageCount) 张（图片本身也一并给你了）" }
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

    /// 一段文字里有没有小红书链接
    static func extractLink(_ text: String) -> URL? {
        let pattern = #"https?://(www\.)?(xiaohongshu\.com|xhslink\.com)/\S+"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        var raw = String(text[r])
        // 中文标点常常被粘在链接尾巴上
        while let last = raw.last, "，。、）】」,.)]".contains(last) { raw.removeLast() }
        return URL(string: raw)
    }

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

        guard let json = initialState(from: html) else { throw FetchError.noData }
        var note = parse(json)
        note.url = (response.url ?? url).absoluteString
        guard !note.title.isEmpty || !note.desc.isEmpty || !note.imageURLs.isEmpty else {
            throw FetchError.noData
        }
        return note
    }

    /// 从 HTML 里把 __INITIAL_STATE__ 那段 JSON 抠出来
    private static func initialState(from html: String) -> [String: Any]? {
        guard let start = html.range(of: "__INITIAL_STATE__") else { return nil }
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
    /// 图床有防盗链，得带上 Referer，不然会被挡。
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
            req.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
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
