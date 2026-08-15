import Foundation
import AVFoundation
import UIKit

/// 一首歌。
///
/// 说明一下来源的限制：网易云、QQ 音乐下载的歌存在它们自己的沙盒里，
/// 别的 App 一律读不到，这是 iOS 的硬规矩，绕不过去。
/// 所以这里的歌只有两个来源：
///   1. 网上搜到的试听片段（三十秒，免费，不用登录）
///   2. 你自己导进来的音频文件
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
    /// 试听是三十秒，本地文件是整首
    var isPreview: Bool { localName.isEmpty }

    var subtitle: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
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
    }

    func pause() {
        player?.pause()
        playing = false
    }

    func resume() {
        player?.play()
        playing = true
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
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

    func search(_ keyword: String) -> [Track] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(k)
                || $0.artist.localizedCaseInsensitiveContains(k)
        }
    }
}
