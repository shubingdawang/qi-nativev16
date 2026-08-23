import Foundation
import UIKit

/// 她发进来的链接，能变成卡片的都在这儿。
///
/// 原来只认小红书。她问：
/// > 那能不能举一反三哔哩哔哩的卡片框呢？抖音呢？抖音他能看吗？
///
/// 能，但三家的难度差得远，得说清楚：
///
/// · **小红书**：页面里有 `__INITIAL_STATE__`，正文、图、评论全在里面。最全。
/// · **哔哩哔哩**：有公开接口 `x/web-interface/view`，不用登录不用 key，
///   标题、简介、封面、UP 主、播放/点赞一次拿全。**最稳的一个。**
/// · **抖音**：没有能用的公开接口，只能去分享页里抠 `_ROUTER_DATA`，
///   抠不到再退回 og 标签。**抖音风控紧，这条随时可能失效**——
///   失效了不会崩，会退回一条普通的带网址的消息。
///
/// ⚠️ 视频他**看不了**，卡片给的是封面和简介。
/// 所以给他的那段文字里会写明这一点，免得他装作看过。
enum LinkSource: String, Codable {
    case xhs = "小红书"
    case bilibili = "哔哩哔哩"
    case douyin = "抖音"

    /// 图床防盗链认的是这个，带错了拿回来一张 403
    var referer: String {
        switch self {
        case .xhs:      return "https://www.xiaohongshu.com/"
        case .bilibili: return "https://www.bilibili.com/"
        case .douyin:   return "https://www.douyin.com/"
        }
    }
}

enum LinkCards {

    private static let mobileUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 一段文字里第一个能变成卡片的链接是谁家的。
    ///
    /// **按出现位置挑，不按家数挑**——她一条消息里贴两个不同站的链接时，
    /// 应该读她先写的那个。
    static func detect(_ text: String) -> (url: URL, source: LinkSource)? {
        let table: [(LinkSource, String)] = [
            (.xhs, #"https?://(www\.)?(xiaohongshu\.com|xhslink\.com)/\S+"#),
            (.bilibili, #"https?://(www\.|m\.)?(bilibili\.com|b23\.tv)/\S+"#),
            (.douyin, #"https?://(www\.|v\.)?(douyin\.com|iesdouyin\.com)/\S+"#)
        ]
        var best: (Int, URL, LinkSource)?
        for (source, pattern) in table {
            guard let r = text.range(of: pattern, options: .regularExpression) else { continue }
            var raw = String(text[r])
            // 中文标点常常被粘在链接尾巴上
            while let last = raw.last, "，。、）】」,.)]".contains(last) { raw.removeLast() }
            guard let url = URL(string: raw) else { continue }
            let at = text.distance(from: text.startIndex, to: r.lowerBound)
            if best == nil || at < best!.0 { best = (at, url, source) }
        }
        guard let best else { return nil }
        return (best.1, best.2)
    }

    static func fetch(_ url: URL, source: LinkSource) async throws -> XHSNote {
        switch source {
        case .xhs:      return try await XHSFetcher.fetch(url)
        case .bilibili: return try await bilibili(url)
        case .douyin:   return try await douyin(url)
        }
    }

    // MARK: 通用

    private static func get(_ url: URL, referer: String) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        return try await URLSession.shared.data(for: req)
    }

    /// 短链跳转到哪儿去了。URLSession 自己会跟到底，读回来的 `response.url` 就是终点。
    private static func resolve(_ url: URL, referer: String) async -> URL {
        guard let (_, resp) = try? await get(url, referer: referer) else { return url }
        return resp.url ?? url
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[r])
    }

    private static func str(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    /// 大数字读着费劲：`1234567` → `123.5 万`
    private static func humanCount(_ any: Any?) -> String {
        let raw = str(any)
        guard let n = Int(raw) else { return raw }
        if n >= 10000 { return String(format: "%.1f 万", Double(n) / 10000) }
        return "\(n)"
    }

    // MARK: 哔哩哔哩

    private static func bilibili(_ link: URL) async throws -> XHSNote {
        var url = link
        if url.host?.contains("b23.tv") == true {
            url = await resolve(url, referer: LinkSource.bilibili.referer)
        }
        let full = url.absoluteString

        // BV 号优先；老的 av 号也认
        var query = ""
        if let bv = firstMatch(full, #"BV[0-9A-Za-z]{10}"#) {
            query = "bvid=" + bv
        } else if let av = firstMatch(full, #"av[0-9]{1,12}"#) {
            query = "aid=" + av.dropFirst(2)
        }
        guard !query.isEmpty,
              let api = URL(string: "https://api.bilibili.com/x/web-interface/view?" + query)
        else { throw XHSFetcher.FetchError.badURL }

        let (data, _) = try await get(api, referer: LinkSource.bilibili.referer)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["code"] as? NSNumber)?.intValue == 0,
              let d = obj["data"] as? [String: Any]
        else { throw XHSFetcher.FetchError.noData }

        var note = XHSNote()
        note.source = .bilibili
        note.url = full
        note.title = str(d["title"])
        note.desc = str(d["desc"])
        note.author = str((d["owner"] as? [String: Any])?["name"])
        if let pic = d["pic"] as? String, !pic.isEmpty {
            note.imageURLs = [pic.hasPrefix("//") ? "https:" + pic : pic]
        }
        if let stat = d["stat"] as? [String: Any] {
            note.likedCount = humanCount(stat["like"])
            note.commentCount = humanCount(stat["reply"])
            note.collectedCount = humanCount(stat["favorite"])
            note.playCount = humanCount(stat["view"])
        }
        if let sec = (d["duration"] as? NSNumber)?.intValue, sec > 0 {
            note.duration = String(format: "%d:%02d", sec / 60, sec % 60)
        }
        guard !note.title.isEmpty else { throw XHSFetcher.FetchError.noData }
        return note
    }

    // MARK: 抖音

    /// 抖音这条**不保证长期能用**。
    /// 没有公开接口，只能从分享页里抠 `_ROUTER_DATA`；
    /// 抠不到就退回 og 标签，两条都不行才算失败。
    private static func douyin(_ link: URL) async throws -> XHSNote {
        var url = link
        if url.host?.contains("v.douyin.com") == true {
            url = await resolve(url, referer: LinkSource.douyin.referer)
        }
        let full = url.absoluteString

        guard let idText = firstMatch(full, #"(video|note)/[0-9]{6,25}"#)?
            .components(separatedBy: "/").last
            ?? firstMatch(full, #"modal_id=[0-9]{6,25}"#)?.components(separatedBy: "=").last
        else { throw XHSFetcher.FetchError.badURL }

        guard let share = URL(string: "https://www.iesdouyin.com/share/video/\(idText)/")
        else { throw XHSFetcher.FetchError.badURL }

        let (data, _) = try await get(share, referer: LinkSource.douyin.referer)
        guard let html = String(data: data, encoding: .utf8) else {
            throw XHSFetcher.FetchError.noData
        }

        var note = XHSNote()
        note.source = .douyin
        note.url = full

        if let router = XHSFetcher.jsonBlob(from: html, after: "_ROUTER_DATA"),
           let item = douyinItem(router) {
            note.title = str(item["desc"])
            note.author = str((item["author"] as? [String: Any])?["nickname"])
            if let cover = (item["video"] as? [String: Any])?["cover"] as? [String: Any],
               let list = cover["url_list"] as? [String], let first = list.first {
                note.imageURLs = [first]
            }
            if let stat = item["statistics"] as? [String: Any] {
                note.likedCount = humanCount(stat["digg_count"])
                note.commentCount = humanCount(stat["comment_count"])
                note.collectedCount = humanCount(stat["collect_count"])
                note.playCount = humanCount(stat["play_count"])
            }
        }

        // 抠不着就退回 og 标签。给得少，但总比一串网址强。
        if note.title.isEmpty {
            note.title = ogTag(html, "og:title")
            if note.imageURLs.isEmpty {
                let img = ogTag(html, "og:image")
                if !img.isEmpty { note.imageURLs = [img] }
            }
        }
        guard !note.title.isEmpty || !note.imageURLs.isEmpty else {
            throw XHSFetcher.FetchError.noData
        }
        return note
    }

    /// `_ROUTER_DATA` 里那条视频埋在 `loaderData` 下面一个带 id 的 key 里，
    /// key 叫什么随版本变——所以是把每个分支都翻一遍找 `item_list`。
    private static func douyinItem(_ router: [String: Any]) -> [String: Any]? {
        guard let loader = router["loaderData"] as? [String: Any] else { return nil }
        for value in loader.values {
            guard let page = value as? [String: Any] else { continue }
            if let res = page["videoInfoRes"] as? [String: Any],
               let list = res["item_list"] as? [[String: Any]],
               let first = list.first {
                return first
            }
        }
        return nil
    }

    private static func ogTag(_ html: String, _ property: String) -> String {
        let pattern = "<meta[^>]+property=[\"']" + property + "[\"'][^>]+content=[\"']([^\"']+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return "" }
        let ns = html as NSString
        guard let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return "" }
        return ns.substring(with: m.range(at: 1))
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
