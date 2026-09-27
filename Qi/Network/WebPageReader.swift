import Foundation

/// 任意一条网址：读出标题和正文给他看。
///
/// 她要的：「我希望他所有链接都能打开，有需要开 VPN 的可以先提醒我开 VPN。」
///
/// 以前 `open_link` 只认小红书、B 站、抖音三家（那三家有专门的卡片抓取，见 `LinkCards`），
/// 别的网址一律回一句「读不了，用 web_search」——她发一条 Notion 链接，他就只能干瞪眼。
///
/// ## 三步
///
///   ① **直接抓**：大多数文章页、博客、新闻，HTML 里本来就有正文，抽出来就是。
///   ② **阅读器代抓**（`r.jina.ai`）：Notion 这类页面是脚本现画的，
///      直接抓回来只有一个空壳。这个服务在它那边把页面跑一遍、转成纯文本再给我们。
///      不要密钥、不花钱。
///   ③ 两条都**连不上**：多半是那个站在国内打不开。回一句带「VPN」的话，
///      让他跟她说一声——她开了再发一次，他再读。
///
/// ⚠️ 读不到内容（连上了但是空的）和连不上是两回事：前者多半是要登录、
/// 或者没有公开分享，开 VPN 也没用，不能跟她说「开 VPN 就好了」。
enum WebPageReader {

    struct Page {
        var title: String
        var text: String
        /// 这份是怎么拿到的（给他看的说明里写一句，出错时好判断）
        var via: String
    }

    enum Failure: Error {
        /// 连不上（超时、拒绝、DNS 失败）——多半要开 VPN
        case unreachable(host: String, detail: String)
        /// 连上了但没有能读的正文——多半要登录，或者没公开分享
        case empty(host: String)
    }

    /// 国内一般打不开的站。连不上的时候，是这几家就把话说得更肯定一点。
    static let usuallyBlocked: [String] = [
        "google.", "youtube.", "youtu.be", "twitter.com", "x.com", "facebook.",
        "instagram.", "reddit.", "wikipedia.org", "notion.so", "notion.com",
        "notion.site", "telegram.", "t.me", "discord.", "medium.com",
        "pinterest.", "tumblr.", "twitch.", "vimeo.", "dropbox.", "quora.",
        "substack.com", "archive.org", "threads.net", "bsky.app"
    ]

    static func likelyNeedsVPN(_ host: String) -> Bool {
        let h = host.lowercased()
        return usuallyBlocked.contains { h.contains($0) }
    }

    private static let ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 正文太短就当成「脚本现画的空壳」，换阅读器再抓一次
    private static let minUseful = 200
    /// 给他的正文最多这么长。再长就是在拿上下文换一篇他读不完的东西
    static let maxChars = 8000

    static func read(_ url: URL) async throws -> Page {
        let host = url.host ?? url.absoluteString
        var directError: Error?

        // ① 直接抓
        do {
            let html = try await fetch(url, timeout: 10)
            let page = extract(html)
            if page.text.count >= minUseful {
                return Page(title: page.title, text: clip(page.text), via: "直接读取")
            }
        } catch {
            directError = error
        }

        // ② 阅读器代抓
        if let reader = URL(string: "https://r.jina.ai/" + url.absoluteString) {
            do {
                var req = URLRequest(url: reader, timeoutInterval: 25)
                req.setValue("text/plain", forHTTPHeaderField: "Accept")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    let text = String(decoding: data, as: UTF8.self)
                    let (title, body) = splitReader(text)
                    if body.count >= 60 {
                        return Page(title: title, text: clip(body), via: "阅读器代抓")
                    }
                    throw Failure.empty(host: host)
                }
            } catch let f as Failure {
                throw f
            } catch {
                // 阅读器自己也连不上：看直接那一下是不是也是连不上
                if let directError, isUnreachable(directError) {
                    throw Failure.unreachable(host: host, detail: directError.localizedDescription)
                }
                throw Failure.unreachable(host: host, detail: error.localizedDescription)
            }
        }

        if let directError, isUnreachable(directError) {
            throw Failure.unreachable(host: host, detail: directError.localizedDescription)
        }
        throw Failure.empty(host: host)
    }

    // MARK: 抓

    private static func fetch(_ url: URL, timeout: TimeInterval) async throws -> String {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        // 大多数是 UTF-8；GBK 的老站用 GB18030 兜一下
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb))
            ?? String(decoding: data, as: UTF8.self)
    }

    /// 是「连不上」还是「连上了但不对」。前者才提 VPN。
    static func isUnreachable(_ error: Error) -> Bool {
        guard let u = error as? URLError else { return false }
        switch u.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost,
             .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    // MARK: 抽正文

    private static func extract(_ html: String) -> (title: String, text: String) {
        func first(_ pattern: String) -> String? {
            guard let r = html.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            else { return nil }
            return String(html[r])
        }
        // 标题：og:title 优先，没有再用 <title>
        var title = ""
        if let m = first(#"<meta[^>]+property=["']og:title["'][^>]*>"#),
           let c = m.range(of: #"content=["'][^"']*["']"#, options: .regularExpression) {
            title = String(m[c]).dropFirst(9).dropLast().description
        } else if let t = first(#"<title[^>]*>[\s\S]*?</title>"#) {
            title = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        }

        var body = html
        // 不是正文的整块先拿掉
        for tag in ["script", "style", "noscript", "svg", "head", "nav", "footer", "form"] {
            body = body.replacingOccurrences(
                of: "<\(tag)[\\s\\S]*?</\(tag)>", with: " ",
                options: [.regularExpression, .caseInsensitive])
        }
        // 块级标签换成换行，别的标签直接剥
        body = body.replacingOccurrences(
            of: #"</?(p|div|br|li|h[1-6]|tr|section|article)[^>]*>"#, with: "\n",
            options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        body = decodeEntities(body)
        return (decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines),
                tidy(body))
    }

    /// 阅读器回来的格式：开头几行是 `Title: …` / `URL Source: …`，然后是 `Markdown Content:`
    private static func splitReader(_ text: String) -> (String, String) {
        var title = ""
        var body = text
        if let t = text.range(of: #"(?m)^Title:\s*(.*)$"#, options: .regularExpression) {
            title = String(text[t]).replacingOccurrences(of: "Title:", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        if let m = text.range(of: "Markdown Content:") {
            body = String(text[m.upperBound...])
        }
        return (title, tidy(body))
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let table = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                     "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—",
                     "&hellip;": "…", "&ldquo;": "“", "&rdquo;": "”"]
        for (k, v) in table { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }

    /// 连着的空白压成一个；空行最多留一个
    private static func tidy(_ s: String) -> String {
        let nl = "\n"
        let lines = s.components(separatedBy: nl)
            .map { $0.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        var blank = false
        for l in lines {
            if l.isEmpty {
                if !blank && !out.isEmpty { out.append("") }
                blank = true
            } else {
                out.append(l)
                blank = false
            }
        }
        return out.joined(separator: nl).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clip(_ s: String) -> String {
        s.count <= maxChars ? s : String(s.prefix(maxChars)) + "\n…（后面还有，太长截掉了）"
    }
}
