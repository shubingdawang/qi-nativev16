import Foundation

/// 她的网易云账号：每日推荐、私人 FM、红心、歌单、听歌记录。
///
/// ## 这一条跟 `MusicSearch` 的分工
///
/// `MusicSearch.searchNeteaseDirect` 是**不登录**那条：搜歌、拿歌词、拿能放的整首。
/// 这一条是**登录之后**才有的东西——全靠她自己那两个 cookie：
///
///     MUSIC_U   登录态。有它就是「她本人在用网页版」
///     __csrf    改东西（红心、往歌单里加歌）时要带上的校验串
///
/// 参考的是那份 netease-music-mcp（Python，要电脑一直开着）。
/// 它其实就是**带着 cookie 打网页接口**，纯 HTTP，所以直接搬进手机，不用电脑。
///
/// ## ⚠️ 老实说清楚这条的毛病
///
/// - `__csrf` 会过期，过期了改东西会报 301 / 「需要登录」，要她重新抓一次。
///   **报错原样告诉她**，别改写成「网络不好」——她要做的是去重抓 cookie。
/// - 这些接口是网易云网页自己在用的，没有文档，哪天改了就得跟着改。
/// - cookie 等于她的登录态，**只存在本机**，不进备份、不发给模型。
enum NeteaseAccount {

    // MARK: - cookie

    /// 存在本机的那两个值
    struct Cookie: Equatable {
        var musicU: String = ""
        var csrf: String = ""

        var isSet: Bool { !musicU.isEmpty }

        static func load() -> Cookie {
            let d = UserDefaults.standard
            return Cookie(musicU: d.string(forKey: "neteaseMusicU") ?? "",
                          csrf: d.string(forKey: "neteaseCsrf") ?? "")
        }

        func save() {
            let d = UserDefaults.standard
            d.set(musicU, forKey: "neteaseMusicU")
            d.set(csrf, forKey: "neteaseCsrf")
            // 换了账号，之前记的 uid 就不作数了
            d.removeObject(forKey: "neteaseUid")
        }

        /// 她可能整段 cookie 粘进来（浏览器里复制的那一长串），
        /// 也可能只粘了 MUSIC_U 那一截的值。两种都认。
        static func parse(_ raw: String) -> Cookie {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.contains("=") else { return Cookie(musicU: text, csrf: "") }
            var c = Cookie()
            for part in text.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "MUSIC_U": c.musicU = kv[1]
                case "__csrf": c.csrf = kv[1]
                default: break
                }
            }
            return c
        }
    }

    enum Fail: LocalizedError {
        case noCookie
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .noCookie:
                return "还没登网易云。「音乐」页 → 网易云账号，把 cookie 粘进去。"
            case .server(let code, let msg):
                if code == 301 || msg.contains("登录") {
                    return "网易云说要重新登录（\(code)）：cookie 过期了，去浏览器里重新复制一次。"
                }
                return "网易云回了 \(code)。\(msg)"
            }
        }
    }

    /// 一首歌（只留要用的）
    struct Song: Hashable {
        var id: Int
        var name: String
        var artist: String

        var line: String { "\(name) — \(artist)（id \(id)）" }

        init(id: Int, name: String, artist: String) {
            self.id = id; self.name = name; self.artist = artist
        }

        /// 网易云接口里歌手在 `ar` 或 `artists` 里，两种都有
        init?(_ j: [String: Any]) {
            guard let id = (j["id"] as? NSNumber)?.intValue,
                  let name = j["name"] as? String else { return nil }
            let people = (j["ar"] as? [[String: Any]]) ?? (j["artists"] as? [[String: Any]]) ?? []
            self.init(id: id, name: name,
                      artist: people.compactMap { $0["name"] as? String }.joined(separator: " / "))
        }
    }

    // MARK: - 请求

    /// 打一个网页接口。**一律 POST 表单**——这批接口 GET 有时给空。
    private static func call(_ path: String, _ form: [String: String] = [:],
                             write: Bool = false) async throws -> [String: Any] {
        let cookie = Cookie.load()
        guard cookie.isSet else { throw Fail.noCookie }

        var q = URLComponents(string: "https://music.163.com" + path)!
        if write, !cookie.csrf.isEmpty {
            q.queryItems = [URLQueryItem(name: "csrf_token", value: cookie.csrf)]
        }
        var req = URLRequest(url: q.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        // ⚠️ `os=pc` 要带：不带的话每日推荐这类接口会当成网页游客，给空
        req.setValue("MUSIC_U=\(cookie.musicU); __csrf=\(cookie.csrf); os=pc; appver=2.10.13",
                     forHTTPHeaderField: "Cookie")
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                     + "(KHTML, like Gecko) Chrome/124.0 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")

        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = (body.percentEncodedQuery ?? "").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Fail.server(0, String(data: data, encoding: .utf8).map { String($0.prefix(120)) } ?? "")
        }
        let code = (j["code"] as? NSNumber)?.intValue ?? 200
        guard code == 200 else {
            throw Fail.server(code, (j["msg"] as? String) ?? (j["message"] as? String) ?? "")
        }
        return j
    }

    /// 她的 uid。第一次问一下账号接口，之后记在本机
    static func uid() async throws -> (Int, String) {
        let d = UserDefaults.standard
        if let u = d.object(forKey: "neteaseUid") as? Int, u > 0 {
            return (u, d.string(forKey: "neteaseNick") ?? "")
        }
        let j = try await call("/api/nuser/account/get")
        let profile = j["profile"] as? [String: Any]
        let account = j["account"] as? [String: Any]
        guard let u = (profile?["userId"] as? NSNumber)?.intValue
                ?? (account?["id"] as? NSNumber)?.intValue else {
            throw Fail.server(301, "没拿到账号，cookie 可能不对")
        }
        let nick = (profile?["nickname"] as? String) ?? ""
        d.set(u, forKey: "neteaseUid")
        d.set(nick, forKey: "neteaseNick")
        return (u, nick)
    }

    // MARK: - 读

    static func daily() async throws -> [Song] {
        let j = try await call("/api/v3/discovery/recommend/songs")
        let data = j["data"] as? [String: Any]
        return ((data?["dailySongs"] as? [[String: Any]]) ?? []).compactMap(Song.init)
    }

    static func fm() async throws -> [Song] {
        let j = try await call("/api/v1/radio/get")
        return ((j["data"] as? [[String: Any]]) ?? []).compactMap(Song.init)
    }

    /// 一串 id → 歌名歌手
    static func detail(_ ids: [Int]) async throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        let c = "[" + ids.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
        let j = try await call("/api/v3/song/detail", ["c": c])
        return ((j["songs"] as? [[String: Any]]) ?? []).compactMap(Song.init)
    }

    /// 红心过的歌（最近的 limit 首）
    static func liked(limit: Int = 30) async throws -> [Song] {
        let (u, _) = try await uid()
        let j = try await call("/api/song/like/get", ["uid": "\(u)"])
        let ids = ((j["ids"] as? [NSNumber]) ?? []).map(\.intValue)
        return try await detail(Array(ids.prefix(limit)))
    }

    struct Playlist {
        var id: Int
        var name: String
        var count: Int
        /// 是她自己建的（能往里加歌），还是收藏的别人的
        var mine: Bool
    }

    static func playlists() async throws -> [Playlist] {
        let (u, _) = try await uid()
        let j = try await call("/api/user/playlist", ["uid": "\(u)", "limit": "60", "offset": "0"])
        return ((j["playlist"] as? [[String: Any]]) ?? []).compactMap { p in
            guard let id = (p["id"] as? NSNumber)?.intValue else { return nil }
            let creator = (p["creator"] as? [String: Any])?["userId"] as? NSNumber
            return Playlist(id: id, name: (p["name"] as? String) ?? "",
                            count: (p["trackCount"] as? NSNumber)?.intValue ?? 0,
                            mine: creator?.intValue == u)
        }
    }

    static func playlist(_ id: Int, limit: Int = 40) async throws -> (String, [Song]) {
        let j = try await call("/api/v6/playlist/detail", ["id": "\(id)", "n": "1000"])
        let p = j["playlist"] as? [String: Any]
        let name = (p?["name"] as? String) ?? ""
        let tracks = ((p?["tracks"] as? [[String: Any]]) ?? []).compactMap(Song.init)
        if tracks.count >= min(limit, 1) { return (name, Array(tracks.prefix(limit))) }
        // 歌单太长的时候 tracks 只给前几首，剩下的只有 id
        let ids = ((p?["trackIds"] as? [[String: Any]]) ?? []).compactMap { ($0["id"] as? NSNumber)?.intValue }
        return (name, try await detail(Array(ids.prefix(limit))))
    }

    /// 最近听过的。`week` = 这一周，否则是全部
    static func history(week: Bool = true, limit: Int = 20) async throws -> [(Song, Int)] {
        let (u, _) = try await uid()
        let j = try await call("/api/v1/play/record", ["uid": "\(u)", "type": week ? "1" : "0"])
        let rows = (j[week ? "weekData" : "allData"] as? [[String: Any]]) ?? []
        return rows.prefix(limit).compactMap { r in
            guard let s = (r["song"] as? [String: Any]).flatMap(Song.init) else { return nil }
            return (s, (r["playCount"] as? NSNumber)?.intValue ?? 0)
        }
    }

    // MARK: - 改

    static func like(_ id: Int, _ on: Bool) async throws {
        _ = try await call("/api/radio/like",
                           ["alg": "itembased", "trackId": "\(id)", "like": on ? "true" : "false", "time": "3"],
                           write: true)
    }

    static func editPlaylist(_ pid: Int, add: Bool, songs: [Int]) async throws {
        _ = try await call("/api/playlist/manipulate/tracks",
                           ["op": add ? "add" : "del", "pid": "\(pid)",
                            "trackIds": "[" + songs.map(String.init).joined(separator: ",") + "]",
                            "imme": "true"],
                           write: true)
    }

    // MARK: - 给模型的那一件工具

    /// 找歌：写了 id 就直接用，写的是歌名就搜一下取第一首
    static func resolve(_ song: String) async throws -> Song? {
        if let id = Int(song.trimmingCharacters(in: .whitespaces)) {
            return try await detail([id]).first
        }
        let q = song.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? song
        guard let url = URL(string: "https://music.163.com/api/search/get/web?type=1&offset=0&limit=1&s=\(q)")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        let (data, _) = try await URLSession.shared.data(for: req)
        let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let songs = (j?["result"] as? [String: Any])?["songs"] as? [[String: Any]]
        return songs?.first.flatMap(Song.init)
    }

    /// 在歌单里找：写 id 或者歌单名（包含就算）
    static func findPlaylist(_ key: String) async throws -> Playlist? {
        let all = try await playlists()
        if let id = Int(key) { return all.first { $0.id == id } }
        return all.first { $0.name == key } ?? all.first { $0.name.contains(key) }
    }

    /// `netease` 那件工具。返回给模型看的一段话
    static func tool(_ args: [String: Any]) async -> (String, Bool) {
        let action = (args["action"] as? String) ?? "account"
        let song = (args["song"] as? String) ?? ""
        let list = (args["playlist"] as? String) ?? ""
        func lines(_ s: [Song]) -> String {
            s.isEmpty ? "（空的）" : s.enumerated().map { "\($0.offset + 1). \($0.element.line)" }.joined(separator: "\n")
        }
        do {
            switch action {
            case "daily":
                return ("今天网易云给她推的：\n" + lines(Array(try await daily().prefix(15))), false)
            case "fm":
                return ("私人 FM 接下来几首：\n" + lines(try await fm()), false)
            case "liked":
                return ("她最近红心的：\n" + lines(try await liked()), false)
            case "history":
                let rows = try await history()
                return ("她这一周听得最多的：\n" + (rows.isEmpty ? "（空的，可能她关了听歌排行的公开）"
                    : rows.enumerated().map { "\($0.offset + 1). \($0.element.0.line) · \($0.element.1) 次" }
                        .joined(separator: "\n")), false)
            case "playlists":
                let all = try await playlists()
                return ("她的歌单：\n" + all.map {
                    "· \($0.name)（\($0.count) 首，id \($0.id)）" + ($0.mine ? "" : " · 收藏的")
                }.joined(separator: "\n"), false)
            case "playlist":
                guard let p = try await findPlaylist(list) else { return ("没找到歌单「\(list)」", true) }
                let (name, songs) = try await playlist(p.id)
                return ("「\(name)」里的歌：\n" + lines(songs), false)
            case "like", "unlike":
                guard let s = try await resolve(song) else { return ("没找到「\(song)」", true) }
                try await like(s.id, action == "like")
                return ((action == "like" ? "红心了：" : "取消红心：") + s.line, false)
            case "add", "remove":
                guard let s = try await resolve(song) else { return ("没找到「\(song)」", true) }
                guard let p = try await findPlaylist(list) else { return ("没找到歌单「\(list)」", true) }
                guard p.mine else { return ("「\(p.name)」是收藏的别人的歌单，改不了。", true) }
                try await editPlaylist(p.id, add: action == "add", songs: [s.id])
                return ((action == "add" ? "加进「\(p.name)」了：" : "从「\(p.name)」拿掉了：") + s.line, false)
            default:
                let (u, nick) = try await uid()
                return ("登着的是「\(nick)」（uid \(u)）。", false)
            }
        } catch {
            return (error.localizedDescription, true)
        }
    }
}
