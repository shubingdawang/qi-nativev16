import Foundation
import AVFoundation
import UIKit
import MediaPlayer   // 「正在播放」：灵动岛、锁屏、控制中心、耳机线控

/// 一首歌。
///
/// 三个来源，从好到差：
///   1. **手机直连网易云** —— 整首 + 歌词，不用电脑不用登录。常态走这条
///   2. 她电脑上那套 NeteaseCloudMusicApi —— 多的是 VIP 和高音质
///   3. iTunes 那三十秒试听 —— 前两条都不成时的兜底
///   4. 她自己从「文件」导进来的音频
///
/// 有一条绕不过去：**网易云、QQ 音乐 App 里下载的歌存在它们自己的沙盒里，
/// 别的 App 一律读不到**，这是 iOS 的硬规矩。所以「把已下载的歌拿过来放」
/// 做不到，只能是上面这几条。
struct Track: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    /// 封面图地址（网上来的那种）
    var artworkURL: String = ""
    /// 封面图存在本机的文件名。
    /// 自己导进来的音频，封面是从文件里的 **APIC 帧**扒出来存下来的——
    /// 她那首《天天 Close to you》文件里就带着一张 107KB 的 JPEG，
    /// 以前我们只读歌名歌手、把封面整个漏掉了，所以歌词页永远是个音符图标。
    var artworkName: String = ""
    /// 网上那段试听
    var previewURL: String = ""
    /// 自己导进来的文件名
    var localName: String = ""
    /// 歌词，LRC 原文。空的就是没有。
    /// 存原文不存解析结果：LRC 是**通用格式**，
    /// 她从网易云导出、从歌词网站抄的，粘进来都能直接用。
    var lyrics: String = ""
    /// 网上来的但是整首（网易云那条路拿到的）。
    /// iTunes 那条只有三十秒，两种都不是本地文件，得分开。
    var fullLength: Bool = false

    /// 分组名。空 = 跟着 `artist` 走。
    ///
    /// ⚠️ **分组名是另一个字段，不是盖掉 `artist`。**
    ///
    /// 她的原话：「长按可以选择分组，以免一些歌手艺名不同。」
    /// 同一个人在不同文件里的歌手名写法往往不一样
    /// （简繁体、中英文、带不带乐队名），
    /// 按原始歌手名分组就会把一个人拆成好几组。
    ///
    /// 而 `artist` 是**从文件里读出来的事实**，不该被抹掉——
    /// 她改的是「我把它们归在一起」，不是「这首歌的歌手写错了」。
    /// 两件事混在一个字段里，改完就再也分不开了。
    var artistGroup: String = ""

    /// 没歌手名的那一组叫什么
    static let unknownArtist = "不知道歌手"

    /// 分组的时候用哪个名字
    var groupName: String {
        let g = artistGroup.trimmingCharacters(in: .whitespaces)
        if !g.isEmpty { return g }
        let a = artist.trimmingCharacters(in: .whitespaces)
        return a.isEmpty ? Track.unknownArtist : a
    }

    /// 是不是只有三十秒的试听。
    /// 本地文件和网易云那条都是整首，只有 iTunes 那条是试听。
    var isPreview: Bool { localName.isEmpty && !fullLength }

    var subtitle: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// 容错解码，理由见 Models.swift 末尾那一整段。
//
// Track 存在 music.json 里，也嵌在每条消息的 `track` 字段里。
// **不写这个的话，刚才加的 lyrics / fullLength 两个字段会让她整个音乐库
// 在升级那一下清空**——合成的解码器碰到缺的键直接抛，
// 而 MusicLibrary 那边是 `Storage.load(…) ?? []`。
//
// 必须写在这个文件里（合成的 CodingKeys 是 private，文件作用域），
// 也必须写在 extension 里（不然 memberwise init 就没了）。
extension Track {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        artist = (try? c.decodeIfPresent(String.self, forKey: .artist)) ?? ""
        album = (try? c.decodeIfPresent(String.self, forKey: .album)) ?? ""
        // ⚠️ 新字段必须在这儿补一行，不补的话
        // 整个音乐库会在升级那一下变空（见 `Storage.load`）
        artistGroup = (try? c.decodeIfPresent(String.self, forKey: .artistGroup)) ?? ""
        artworkURL = (try? c.decodeIfPresent(String.self, forKey: .artworkURL)) ?? ""
        artworkName = (try? c.decodeIfPresent(String.self, forKey: .artworkName)) ?? ""
        previewURL = (try? c.decodeIfPresent(String.self, forKey: .previewURL)) ?? ""
        localName = (try? c.decodeIfPresent(String.self, forKey: .localName)) ?? ""
        lyrics = (try? c.decodeIfPresent(String.self, forKey: .lyrics)) ?? ""
        fullLength = (try? c.decodeIfPresent(Bool.self, forKey: .fullLength)) ?? false
    }
}

enum MusicSearch {

    enum SearchError: LocalizedError {
        case nothing(String)
        var errorDescription: String? {
            switch self {
            case .nothing(let q): return "没搜到「\(q)」"
            }
        }
    }

    /// 用 iTunes 的公开搜索接口找歌。不要密钥、不用登录，
    /// 拿回来的是三十秒试听和封面——给一张卡片配个氛围够用了。
    static func search(_ keyword: String, limit: Int = 6) async throws -> [Track] {
        let q = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        guard let url = URL(string:
            "https://itunes.apple.com/search?term=\(q)&media=music&limit=\(limit)&country=CN")
        else { throw SearchError.nothing(keyword) }

        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], !results.isEmpty
        else { throw SearchError.nothing(keyword) }

        return results.compactMap { item in
            guard let preview = item["previewUrl"] as? String else { return nil }
            var t = Track()
            t.title = (item["trackName"] as? String) ?? ""
            t.artist = (item["artistName"] as? String) ?? ""
            t.album = (item["collectionName"] as? String) ?? ""
            t.previewURL = preview
            // 默认给的封面很小，换成大图
            if let art = item["artworkUrl100"] as? String {
                t.artworkURL = art.replacingOccurrences(of: "100x100", with: "400x400")
            }
            return t.title.isEmpty ? nil : t
        }
    }

    // MARK: 网易云 · 直连（手机自己打，不用电脑）

    // **这条才是默认走的路。**
    //
    // 一开始我做的是「接她电脑上那三个服务」，她说得对——那太鸡肋了：
    // 电脑得开机、隧道得通，为了听首歌要维护一整条链路。
    //
    // 但「要 cookie、要服务器」这个前提只对 **VIP 歌**成立。
    // 网易云有三个**不用登录、不用加密**的公开接口，手机可以直接打：
    //
    //   搜索  music.163.com/api/search/get/web        普通 GET
    //   歌词  music.163.com/api/song/lyric            普通 GET
    //   音频  music.163.com/song/media/outer/url      302 跳到真正的 mp3
    //
    // 加密那套（weapi/eapi，也就是 NeteaseCloudMusicApi 存在的理由）
    // 是为了登录态、VIP、高音质。**普通歌不需要。**
    //
    // 老实说清楚这条路的边界：
    //   · VIP 歌、下架的歌放不了——那个 302 会跳到 404，我们提前筛掉
    //   · 音质是 128k，不是无损
    //   · 这几个接口是网易云自己网页在用的，没有文档，哪天改了就得跟着改
    //
    // 要 VIP 和高音质，再回去配电脑那条（下面那个 searchNetease）。

    /// 网页请求头。不带这两个的话搜索接口会给空结果。
    private static func neteaseRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                     + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
                     forHTTPHeaderField: "User-Agent")
        return req
    }

    static func searchNeteaseDirect(_ keyword: String, limit: Int = 10) async throws -> [Track] {
        let q = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        guard let url = URL(string:
            "https://music.163.com/api/search/get/web?csrf_token=&type=1"
            + "&offset=0&total=true&limit=\(limit)&s=\(q)")
        else { throw SearchError.nothing(keyword) }

        let (data, _) = try await URLSession.shared.data(for: neteaseRequest(url))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]], !songs.isEmpty
        else { throw SearchError.nothing(keyword) }

        var ids: [Int] = []
        var out: [Track] = []
        for song in songs {
            guard let sid = song["id"] as? Int else { continue }
            var t = Track()
            t.title = (song["name"] as? String) ?? ""
            if let artists = song["artists"] as? [[String: Any]] {
                t.artist = artists.compactMap { $0["name"] as? String }
                    .joined(separator: " / ")
            }
            if let album = song["album"] as? [String: Any] {
                t.album = (album["name"] as? String) ?? ""
                t.artworkURL = (album["picUrl"] as? String) ?? ""
            }
            t.previewURL = "https://music.163.com/song/media/outer/url?id=\(sid).mp3"
            t.fullLength = true
            guard !t.title.isEmpty else { continue }
            ids.append(sid)
            out.append(t)
        }
        guard !out.isEmpty else { throw SearchError.nothing(keyword) }

        // 歌词和"能不能放"一起并发去问，别一首一首串着等
        let checked = await withTaskGroup(of: (Int, Bool, String).self) { group in
            for sid in ids {
                group.addTask { await directDetail(sid) }
            }
            var map: [Int: (Bool, String)] = [:]
            for await (sid, ok, lyric) in group { map[sid] = (ok, lyric) }
            return map
        }

        var kept: [Track] = []
        for (i, sid) in ids.enumerated() where i < out.count {
            guard let d = checked[sid] else { continue }
            // 放不了的直接不摆出来。**点了没反应比没这首歌更糟。**
            guard d.0 else { continue }
            var t = out[i]
            t.lyrics = d.1
            kept.append(t)
        }
        guard !kept.isEmpty else { throw SearchError.nothing(keyword) }
        return kept
    }

    /// 这首能不能放 + 它的歌词
    private static func directDetail(_ sid: Int) async -> (Int, Bool, String) {
        var playable = false
        var lyric = ""

        // 能不能放：那个 302 对 VIP 和下架的歌会跳到 404 页面。
        // 只发 HEAD，不真的把歌下下来。
        if let u = URL(string:
            "https://music.163.com/song/media/outer/url?id=\(sid).mp3") {
            var req = neteaseRequest(u)
            req.httpMethod = "HEAD"
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse {
                let final = http.url?.absoluteString ?? ""
                playable = (200..<300).contains(http.statusCode)
                    && !final.contains("/404")
                    && !final.isEmpty
            }
        }

        if playable, let u = URL(string:
            "https://music.163.com/api/song/lyric?id=\(sid)&lv=1&kv=1&tv=-1"),
           let (data, _) = try? await URLSession.shared.data(for: neteaseRequest(u)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // lrc 是原文，tlyric 是翻译。都有就叠起来——
            // 听英文歌的时候想同时看见中文。
            let lrc = ((json["lrc"] as? [String: Any])?["lyric"] as? String) ?? ""
            let tr = ((json["tlyric"] as? [String: Any])?["lyric"] as? String) ?? ""
            lyric = tr.isEmpty ? lrc : lrc + "\n" + tr
        }
        return (sid, playable, lyric)
    }

    // MARK: 网易云 · 走她电脑上那套（可选，为了 VIP）

    /// 从她自己那台电脑上的网易云接口找歌。
    ///
    /// **接的是底下那层 NeteaseCloudMusicApi**（那个 Node 服务），
    /// 不是 netease-music-mcp 自己那个 API server——
    /// 前者的三条路由是公开且稳定的：
    ///
    ///   `/search?keywords=`  找歌
    ///   `/song/url?id=`      拿能播的地址
    ///   `/lyric?id=`         拿歌词（带时间戳的 LRC）
    ///
    /// 后者是那个项目自己定的，版本一动就可能变。挑稳的那层接。
    ///
    /// **跟 iTunes 那条的区别**：这条拿到的是**整首**，还带歌词；
    /// 代价是要她电脑上那几个服务开着、手机够得着（隧道或者同一个局域网），
    /// 而且 VIP 的歌要她自己的 cookie 才放得了。够不着就自动退回 iTunes。
    static func searchNetease(_ keyword: String, base: String,
                              limit: Int = 8) async throws -> [Track] {
        let root = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !root.isEmpty else { throw SearchError.nothing(keyword) }
        let q = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        guard let url = URL(string: "\(root)/search?keywords=\(q)&limit=\(limit)")
        else { throw SearchError.nothing(keyword) }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]], !songs.isEmpty
        else { throw SearchError.nothing(keyword) }

        var out: [Track] = []
        for song in songs {
            guard let sid = song["id"] as? Int else { continue }
            var t = Track()
            t.title = (song["name"] as? String) ?? ""
            if let artists = song["artists"] as? [[String: Any]] {
                t.artist = artists.compactMap { $0["name"] as? String }
                    .joined(separator: " / ")
            }
            if let album = song["album"] as? [String: Any] {
                t.album = (album["name"] as? String) ?? ""
                t.artworkURL = (album["picUrl"] as? String) ?? ""
            }
            t.previewURL = "\(root)/song/url?id=\(sid)"
            t.fullLength = true
            out.append(t)
        }
        guard !out.isEmpty else { throw SearchError.nothing(keyword) }

        // 地址和歌词一首一首去拿。**并发拿**，不然八首歌串着请求要好几秒。
        let ids = songs.compactMap { $0["id"] as? Int }
        let details = await withTaskGroup(of: (Int, String, String).self) { group in
            for sid in ids {
                group.addTask { await detail(sid, root: root) }
            }
            var map: [Int: (String, String)] = [:]
            for await (sid, playURL, lyric) in group { map[sid] = (playURL, lyric) }
            return map
        }

        for i in out.indices where i < ids.count {
            if let d = details[ids[i]] {
                if !d.0.isEmpty { out[i].previewURL = d.0 }
                out[i].lyrics = d.1
            }
        }
        // 拿不到播放地址的多半是 VIP 或者下架了，别摆出来让她点了没反应
        return out.filter { $0.previewURL.contains("http") }
    }

    /// 一首歌的播放地址和歌词
    private static func detail(_ sid: Int, root: String) async -> (Int, String, String) {
        var playURL = ""
        var lyric = ""

        if let u = URL(string: "\(root)/song/url?id=\(sid)"),
           let (data, _) = try? await URLSession.shared.data(from: u),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = json["data"] as? [[String: Any]],
           let first = arr.first,
           let s = first["url"] as? String {
            playURL = s
        }

        if let u = URL(string: "\(root)/lyric?id=\(sid)"),
           let (data, _) = try? await URLSession.shared.data(from: u),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // lrc 是原文，tlyric 是翻译。两个都有就叠起来——
            // 她听英文歌的时候想同时看见中文。
            let lrc = ((json["lrc"] as? [String: Any])?["lyric"] as? String) ?? ""
            let tr = ((json["tlyric"] as? [String: Any])?["lyric"] as? String) ?? ""
            lyric = tr.isEmpty ? lrc : lrc + "\n" + tr
        }
        return (sid, playURL, lyric)
    }
}

// MARK: - 存

enum MusicStore {

    static var dir: URL {
        let url = Storage.documentsURL.appendingPathComponent("Music", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    /// 这首歌的文件还在不在。
    ///
    /// 为什么需要这个：备份里**单个超过 20 MB 的文件是不装的**
    /// （整包会大到导不出来）。所以一首大歌还原回来之后，
    /// 库里那一条还在、封面还在、歌词还在，**只有音频没了**——
    /// 以前点下去 `AVPlayer` 拿到一个不存在的地址，一声不吭什么都不放。
    /// 她说的「导入备份进来的歌曲并不能播放」就是这个。
    static func exists(_ name: String) -> Bool {
        !name.isEmpty && FileManager.default.fileExists(atPath: url(name).path)
    }

    /// 从「文件」里导一首进来。
    /// 网易云会员能下载的歌，先存到「文件」App，再从这儿导入就行。
    static func importFile(from source: URL) -> Track? {
        let needsStop = source.startAccessingSecurityScopedResource()
        defer { if needsStop { source.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: source) else { return nil }
        let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension.lowercased()
        let name = UUID().uuidString + "." + ext
        do {
            try data.write(to: url(name), options: .atomic)
        } catch { return nil }

        var t = Track()
        t.localName = name
        t.title = source.deletingPathExtension().lastPathComponent

        // 文件里常带着歌名和歌手。读元数据在新系统上是异步的，
        // 这里不等它——先用文件名顶上，读到了再补。
        MusicStore.readMeta(of: name, fallbackTitle: t.title)
        return t
    }

    /// 把音频文件里的元数据读出来补进库里：歌名、歌手、专辑、**封面**、内嵌歌词。
    ///
    /// 单独拎出来是因为**老库里那些歌也要补**——
    /// 这个功能是后加的，她之前导进去的歌全都没有封面。
    /// 放到那首的时候会回头调一次这里（见 `MusicLibrary.ensureMeta`）。
    static func readMeta(of name: String, fallbackTitle: String) {
        let stored = fallbackTitle
        Task.detached {
            let asset = AVURLAsset(url: MusicStore.url(name))
            guard let items = try? await asset.load(.commonMetadata) else { return }
            var title = stored, artist = "", album = ""
            var artData: Data?
            var embedded = ""
            for item in items {
                // try? 已经把两层可选压成一层了，不用再解一次
                if let key = item.commonKey?.rawValue {
                    // 封面是 Data 不是 String，得单独走一条
                    if key == "artwork" {
                        artData = try? await item.load(.dataValue)
                        continue
                    }
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        if key == "title" { title = value }
                        if key == "artist" { artist = value }
                        if key == "albumName" { album = value }
                    }
                }
                // 内嵌歌词（USLT）。**大部分文件里根本没有**——
                // 她给的那首就没有，只有 YouTube 的版权说明。
                // 没有的话下面 MusicLibrary 会去网易云按歌名歌手补一次。
                if let id = item.identifier?.rawValue,
                   id.contains("lyrics") || id.contains("USLT"),
                   let value = try? await item.load(.stringValue),
                   value.count > 20 {
                    embedded = value
                }
            }
            // 跨线程只传不会再变的值，别把 var 直接捞过去
            let readTitle = title, readArtist = artist, readAlbum = album
            let readLyrics = embedded
            let artName = artData.flatMap { UIImage(data: $0) }.flatMap {
                ImageStore.save($0, quality: 0.9)
            }
            await MainActor.run {
                MusicLibrary.shared.refine(name, title: readTitle,
                                           artist: readArtist, album: readAlbum,
                                           artworkName: artName ?? "",
                                           lyrics: readLyrics)
            }
        }
    }

    static func delete(_ track: Track) {
        guard !track.localName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(track.localName))
    }
}

// MARK: - 放

/// 全局一个播放器。放歌的时候语音条会让位，不会两个声音打架。
@MainActor
final class MusicPlayer: NSObject, ObservableObject {

    static let shared = MusicPlayer()

    @Published var current: Track?
    /// 放完一首之后干什么：停 / 单曲循环 / 随机。默认停。
    ///
    /// **不用 @AppStorage**：那个是给 View 用的，挂在 ObservableObject 上
    /// 改了不会通知界面，按钮的图标会一直是旧的。自己存 UserDefaults。
    @Published var repeatMode: Repeat = Repeat(
        rawValue: UserDefaults.standard.string(forKey: "musicRepeat") ?? "") ?? .off {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "musicRepeat") }
    }
    @Published var playing = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    /// 点了一首文件已经不在的歌。界面拿它弹一句话——
    /// **不能一声不吭**，不然她只会觉得「这 App 坏了」。
    @Published var missingFile: String?

    private var player: AVPlayer?
    private var observer: Any?

    func toggle(_ track: Track) {
        if current?.id == track.id {
            playing ? pause() : resume()
            return
        }
        start(track)
    }

    /// 这首歌的歌词，解析好的
    @Published private(set) var lines: [LyricLine] = []

    /// 现在唱到哪一句
    var currentLine: Int? { Lyrics.current(lines, at: progress) }

    /// 她刚粘了一段歌词进来，正在放的这首要当场跟上
    func applyLyrics(_ raw: String, to id: UUID) {
        guard current?.id == id else { return }
        current?.lyrics = raw
        lines = Lyrics.parse(raw)
    }

    /// 元数据是异步读出来的（封面、歌名、歌手都可能晚几百毫秒才到）。
    /// 正在放的就是这首的话，把读到的那份换上去——
    /// 不然封面要等下次重放才出得来。
    func refreshCurrent(with track: Track) {
        guard current?.id == track.id else { return }
        current = track
        if !track.lyrics.isEmpty { lines = Lyrics.parse(track.lyrics) }
        publishNowPlaying()
    }

    func start(_ track: Track) {
        stop()

        // 文件不在了就直说（备份没带上那些大文件）
        if !track.localName.isEmpty, !MusicStore.exists(track.localName) {
            missingFile = track.title.isEmpty ? "这首歌" : track.title
            Console.log(.warn, "歌文件不在了", track.title + " · " + track.localName)
            return
        }

        let url: URL? = track.localName.isEmpty
            ? URL(string: track.previewURL)
            : MusicStore.url(track.localName)
        guard let url else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        lines = Lyrics.parse(track.lyrics)

        let p = AVPlayer(url: url)
        player = p
        current = track
        playing = true

        observer = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.3, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.progress = time.seconds
                if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.duration = d
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }

        p.play()
        publishNowPlaying()
        wireRemoteCommands()
        // 缺封面就回头读一次文件，缺歌词就去网上补一次。
        // 放在起播之后：这两件事都不该挡着歌先响。
        MusicLibrary.shared.ensureMeta(for: track)
    }

    /// 放完一首之后干什么。
    ///
    /// 她说「一首歌播完就不再播了」——以前放完直接 stop，
    /// 连「刚才放的是哪首」都一起清掉，歌词页就空成一张白纸。
    enum Repeat: String, CaseIterable {
        case off, one, shuffle
        var label: String {
            switch self {
            case .off:     return "放完就停"
            case .one:     return "单曲循环"
            case .shuffle: return "随机播放"
            }
        }
        var icon: String {
            switch self {
            case .off:     return "arrow.right.to.line"
            case .one:     return "repeat.1"
            case .shuffle: return "shuffle"
            }
        }
        var next: Repeat {
            switch self {
            case .off: return .one
            case .one: return .shuffle
            case .shuffle: return .off
            }
        }
    }

    /// 放完一首。按当前模式决定下一步。
    ///
    /// **不管哪种模式，`current` 都留着**——她说「即使没有播放音乐，
    /// 也应该停留在上一次播放的音乐页面」。以前放完就清空，
    /// 歌词页当场变成一张「这首还没有歌词」的白纸。
    func finished() {
        countPlay()
        switch repeatMode {
        case .one:
            seek(to: 0)
            player?.play()
            playing = true
        case .shuffle:
            let pool = MusicLibrary.shared.tracks.filter { $0.id != current?.id }
            if let next = pool.randomElement() { start(next) } else { seek(to: 0); pause() }
        case .off:
            // 停在结尾，但**不清空**：歌还在，封面歌词都还在
            seek(to: 0)
            pause()
        }
    }

    /// 这首放完了，计一次数。她要的「每首歌播放次数统计」就靠它。
    private func countPlay() {
        guard let t = current else { return }
        MusicLibrary.shared.countPlay(t.id)
    }

    func pause() {
        player?.pause()
        playing = false
        publishNowPlaying()
    }

    func resume() {
        player?.play()
        playing = true
        publishNowPlaying()
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = seconds
        publishNowPlaying()
    }

    func stop() {
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        playing = false
        progress = 0
        duration = 0
        current = nil
        lines = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: 灵动岛 / 锁屏 / 控制中心

    // **她要的「播放时在灵动岛显示」走的就是这条路，不是自己做一个 Live Activity。**
    //
    // 系统本来就有一套「正在播放」：只要音频会话是 playback、
    // 又往 MPNowPlayingInfoCenter 填了信息，iOS 自己会把它摆到
    // 灵动岛、锁屏和控制中心上，还带上封面和进度条。
    //
    // 自己写 Live Activity 反而更差：得动 Widget 那个 target 和 pbxproj、
    // 两份 Attributes 要同步、样式还得自己画一套——
    // 最后做出来的是一个比系统那个更丑、更容易坏的复制品。
    // 而且系统这条**连耳机线控和 CarPlay 一起带上了**。

    private var remoteWired = false

    private func publishNowPlaying() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        if !t.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = t.album }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // 本地那张封面（从文件的 APIC 帧扒出来的）直接就能用，不用等网络
        if !t.artworkName.isEmpty, let image = ImageStore.load(t.artworkName) {
            info[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            return
        }

        // 封面单独去拿。拿到之前先把上面那些字显示出来，
        // 别为了等一张图让整条「正在播放」都不出现。
        guard !t.artworkURL.isEmpty, let url = URL(string: t.artworkURL) else { return }
        let wanted = t.id
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                guard let self, self.current?.id == wanted else { return }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] =
                    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    /// 锁屏和耳机上的那几个键。只挂一次。
    private func wireRemoteCommands() {
        guard !remoteWired else { return }
        remoteWired = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playing ? self.pause() : self.resume()
            }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
    }
}


/// 自己导进来的歌。元数据是慢慢读出来的，读到了再回填。
@MainActor
final class MusicLibrary: ObservableObject {

    static let shared = MusicLibrary()

    @Published var tracks: [Track] = [] {
        didSet { if loaded { Storage.save(tracks, to: "music.json") } }
    }
    private var loaded = false

    /// 每首放过多少次。**单独存**，不塞进 Track——
    /// 那个结构体嵌在每条消息里，加一个字段等于把整份聊天记录也撑大一圈。
    @Published private(set) var plays: [String: Int] = [:] {
        didSet { if loaded { Storage.save(plays, to: "music-plays.json") } }
    }

    init() {
        tracks = Storage.load([Track].self, from: "music.json") ?? []
        plays = Storage.load([String: Int].self, from: "music-plays.json") ?? [:]
        loaded = true
        refreshMissing()
    }

    /// 还原完重读一遍。⚠️ `loaded` 先关掉——读的时候不许写盘。
    func reload() {
        loaded = false
        tracks = Storage.load([Track].self, from: "music.json") ?? []
        plays = Storage.load([String: Int].self, from: "music-plays.json") ?? [:]
        loaded = true
        refreshMissing()
    }

    func countPlay(_ id: UUID) {
        plays[id.uuidString, default: 0] += 1
    }

    func playCount(_ t: Track) -> Int { plays[t.id.uuidString] ?? 0 }

    /// 放得最多的那些，给「听得最多」那一页用
    /// ⚠️ 走 `playable`：音频没了的那些在别处都藏起来了，
    /// 「听得最多」那一页也不该把它们摆出来。
    var mostPlayed: [(Track, Int)] {
        playable.map { ($0, playCount($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    func add(_ track: Track) {
        tracks.append(track)
        refreshMissing()
    }

    /// 同一首歌，库里有没有更好的一版。
    ///
    /// 她的原话：「阿晏给我播放了一首需要 vip 的音乐（只能听 30s 没有歌词），
    /// 随后我将歌曲导入后我希望可以直接替换掉这个 30s 的。」
    ///
    /// 聊天里那张卡当时存的是一份**快照**——他放的时候只有 iTunes 那段试听，
    /// 那张卡就永远是试听。可她后来把整首导进来了，同一首歌在库里明明躺着
    /// 一个有歌词有封面的完整版。
    ///
    /// 所以卡片不再认那份快照，每次显示都来这儿问一句：**这首歌现在最好的是哪一版？**
    /// 排序：本地整首 > 网易云整首 > 试听。顺带把歌词和封面也补过去——
    /// 有时候整首在别处、歌词却是她单独贴的。
    func best(for track: Track) -> Track {
        let key = (track.title + "|" + track.artist).lowercased()
            .replacingOccurrences(of: " ", with: "")
        let same = tracks.filter {
            ($0.title + "|" + $0.artist).lowercased()
                .replacingOccurrences(of: " ", with: "") == key
        }
        guard !same.isEmpty else { return track }
        func rank(_ t: Track) -> Int {
            // ⚠️ 本地那一版**文件还在**才算最好的。
            // 不查这一下的话，聊天里那张卡会挑中一个已经没了的文件，
            // 点下去只弹「文件不在了」——而库里明明还躺着一版能放的网络整首。
            if !t.localName.isEmpty { return missingIDs.contains(t.id) ? 0 : 3 }
            if t.fullLength { return 2 }
            return 1
        }
        var pick = same.max(by: { rank($0) < rank($1) }) ?? track
        // 库里那份要是还不如手上这份，就用手上的
        if rank(track) > rank(pick) { pick = track }
        // 缺的补上：歌词和封面各自去同名的那几份里找一个有的
        if pick.lyrics.isEmpty {
            pick.lyrics = same.first(where: { !$0.lyrics.isEmpty })?.lyrics ?? track.lyrics
        }
        if pick.artworkName.isEmpty, pick.artworkURL.isEmpty {
            if let art = same.first(where: { !$0.artworkName.isEmpty }) {
                pick.artworkName = art.artworkName
            } else {
                pick.artworkURL = track.artworkURL
            }
        }
        return pick
    }

    /// 两首是不是同一首歌（按歌名+歌手认，不认 id）。
    /// 导进来的那一版跟聊天卡片里那一版 id 天生不一样，认 id 就永远对不上。
    static func sameSong(_ a: Track?, _ b: Track) -> Bool {
        guard let a else { return false }
        if a.id == b.id { return true }
        func key(_ t: Track) -> String {
            (t.title + "|" + t.artist).lowercased()
                .replacingOccurrences(of: " ", with: "")
        }
        return key(a) == key(b) && !b.title.isEmpty
    }

    /// 把几首歌归到同一个分组名下。
    /// 传空字串 = 改回去跟着原始歌手名走。
    func regroup(_ id: UUID, to name: String) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].artistGroup = name.trimmingCharacters(in: .whitespaces)
    }

    /// 现有的分组名（给菜单摆出来，省得她每次重打）
    var groupNames: [String] {
        var seen: Set<String> = []
        for t in tracks where t.groupName != Track.unknownArtist {
            seen.insert(t.groupName)
        }
        return seen.sorted()
    }

    func remove(_ track: Track) {
        MusicStore.delete(track)
        tracks.removeAll { $0.id == track.id }
        refreshMissing()
    }

    /// 元数据读出来之后补上
    func refine(_ localName: String, title: String, artist: String, album: String,
                artworkName: String = "", lyrics: String = "") {
        guard let i = tracks.firstIndex(where: { $0.localName == localName }) else { return }
        if !title.isEmpty { tracks[i].title = title }
        if !artist.isEmpty { tracks[i].artist = artist }
        if !album.isEmpty { tracks[i].album = album }
        if !artworkName.isEmpty { tracks[i].artworkName = artworkName }
        if !lyrics.isEmpty { tracks[i].lyrics = lyrics }
        let t = tracks[i]
        // 正在放的就是这首的话，当场把封面和歌词换上去，
        // 不然她得退出去重放一遍才看得见
        MusicPlayer.shared.refreshCurrent(with: t)
        if t.lyrics.isEmpty { Task { await fetchLyricsOnline(for: t.id) } }
    }

    /// 放某一首之前先看看它缺不缺东西。
    ///
    /// 本地那些歌是**老库里就有的**——封面和内嵌歌词是这一版才开始读的，
    /// 所以放到它们的时候回头读一次文件；网上那些歌缺歌词就去补一次。
    /// 两件事都不花钱：一个是读本机文件，一个是一次普通 GET。
    func ensureMeta(for track: Track) {
        if !track.localName.isEmpty && track.artworkName.isEmpty {
            MusicStore.readMeta(of: track.localName, fallbackTitle: track.title)
        } else if track.lyrics.isEmpty {
            Task { await fetchLyricsOnline(for: track.id) }
        }
    }

    /// 文件里没有歌词的时候，去网易云那个公开接口按「歌名 歌手」补一次。
    ///
    /// **只查歌词，不换歌**：她导进来的那首还是放本地文件。
    /// 这一步不花钱（不调模型），只是一次普通 GET；查不到就算了，不打扰她。
    /// 每首只查一次——查过了 lyrics 就不空了，进不来第二次。
    func fetchLyricsOnline(for id: UUID) async {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        let t = tracks[i]
        guard t.lyrics.isEmpty else { return }
        let key = [t.title, t.artist].filter { !$0.isEmpty }.joined(separator: " ")
        guard key.count >= 2 else { return }
        guard let found = try? await MusicSearch.searchNeteaseDirect(key, limit: 5) else { return }
        // 挑歌名最像的那条，别拿搜索结果第一条硬套
        let best = found.first { $0.title.localizedCaseInsensitiveContains(t.title) }
            ?? found.first { t.title.localizedCaseInsensitiveContains($0.title) }
            ?? found.first
        guard let lrc = best?.lyrics, !lrc.isEmpty else { return }
        setLyrics(lrc, for: id)
    }

    /// 给某一首配上歌词。
    ///
    /// 正在放的那首也要**当场更新**，不然她粘完歌词得重放一遍才看得见。
    func setLyrics(_ raw: String, for id: UUID?) {
        guard let id else { return }
        if let i = tracks.firstIndex(where: { $0.id == id }) {
            tracks[i].lyrics = raw
        }
        MusicPlayer.shared.applyLyrics(raw, to: id)
    }

    func search(_ keyword: String) -> [Track] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        let pool = playable
        guard !k.isEmpty else { return pool }
        return pool.filter {
            $0.title.localizedCaseInsensitiveContains(k)
                || $0.artist.localizedCaseInsensitiveContains(k)
        }
    }

    // MARK: 文件还在不在

    /// 音频文件已经不在了的那些歌的 id。
    ///
    /// 她的原话：「音乐既然没有备份了，就不要显示歌名了，
    /// 不然每次还要一个个删掉有点麻烦。」
    ///
    /// 她说得对：一个点下去只会弹「文件不在了」的名字，摆在那儿只有添堵的作用。
    /// **但不从 `music.json` 里删掉**——把音频找回来（重新导一份带音频的备份、
    /// 或者从「文件」再导一次），播放次数、歌词、封面就都还在。
    /// 删掉是不可逆的，而藏起来随时能翻回来。
    ///
    /// ⚠️ 存成一份名单而不是每次现问文件系统：`body` 每一帧都会重跑，
    /// 二十几首歌就是每帧二十几次 `fileExists`。
    @Published private(set) var missingIDs: Set<UUID> = []

    /// 音频还在的那些。**列表一律走这儿。**
    /// 纯网络那些（`localName` 是空的）不靠本地文件，照样显示。
    var playable: [Track] { tracks.filter { !missingIDs.contains($0.id) } }

    /// 音频没了的那些。给「清掉」和那句提示用。
    var orphans: [Track] { tracks.filter { missingIDs.contains($0.id) } }

    /// 重新点一遍名。**导入、还原、删歌之后都要叫一次**——
    /// 不叫的话她刚导回来的歌还在藏着。
    func refreshMissing() {
        missingIDs = Set(tracks.filter {
            !$0.localName.isEmpty && !MusicStore.exists($0.localName)
        }.map(\.id))
    }

    /// 把音频已经不在的那些从库里清掉。她自己点才清。
    func dropOrphans() -> Int {
        let gone = orphans
        guard !gone.isEmpty else { return 0 }
        let ids = Set(gone.map(\.id))
        tracks.removeAll { ids.contains($0.id) }
        refreshMissing()
        return gone.count
    }
}
