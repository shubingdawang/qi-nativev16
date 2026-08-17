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
    /// 封面图地址
    var artworkURL: String = ""
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
        artworkURL = (try? c.decodeIfPresent(String.self, forKey: .artworkURL)) ?? ""
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
        let stored = t
        Task.detached {
            let asset = AVURLAsset(url: MusicStore.url(name))
            guard let items = try? await asset.load(.commonMetadata) else { return }
            var title = stored.title, artist = "", album = ""
            for item in items {
                // try? 已经把两层可选压成一层了，不用再解一次
                guard let key = item.commonKey?.rawValue,
                      let value = try? await item.load(.stringValue),
                      !value.isEmpty
                else { continue }
                if key == "title" { title = value }
                if key == "artist" { artist = value }
                if key == "albumName" { album = value }
            }
            // 跨线程只传不会再变的值，别把 var 直接捞过去
            let readTitle = title, readArtist = artist, readAlbum = album
            await MainActor.run {
                MusicLibrary.shared.refine(name, title: readTitle,
                                           artist: readArtist, album: readAlbum)
            }
        }
        return t
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
    @Published var playing = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0

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

    func start(_ track: Track) {
        stop()
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
            Task { @MainActor in self?.stop() }
        }

        p.play()
        publishNowPlaying()
        wireRemoteCommands()
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

    init() {
        tracks = Storage.load([Track].self, from: "music.json") ?? []
        loaded = true
    }

    func add(_ track: Track) {
        tracks.append(track)
    }

    func remove(_ track: Track) {
        MusicStore.delete(track)
        tracks.removeAll { $0.id == track.id }
    }

    /// 元数据读出来之后补上
    func refine(_ localName: String, title: String, artist: String, album: String) {
        guard let i = tracks.firstIndex(where: { $0.localName == localName }) else { return }
        if !title.isEmpty { tracks[i].title = title }
        if !artist.isEmpty { tracks[i].artist = artist }
        if !album.isEmpty { tracks[i].album = album }
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
        guard !k.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(k)
                || $0.artist.localizedCaseInsensitiveContains(k)
        }
    }
}
