import Foundation
import SwiftUI

// MARK: - 划下的那句歌词
//
// 出处：avisforevelyn/Duetto。它那套是「两个人同步听同一首歌，
// AI 也在听」——真的把音频下载下来做多模态分析。
//
// **音频那一半我们不做**，理由说清楚：
// 那要把整首歌传出去、要能听音频的模型、要缓存分析结果，
// 一次听歌花的钱比聊一整天还多。而它自己文档里就写着有
// **lyrics fallback**——歌词兜底那条路。歌词我们本来就有。
//
// 真正值钱、而且我们做得起的是它这一条：
//
//   > Quote any lyric to spark conversations;
//   > these quotes become archived memories tied to specific passages.
//
// 划一句歌词、跟他聊那一句、那一句从此带着你们聊过的痕迹——
// **这跟书房里划句子是同一套机制**，只是对象从书页换成了歌词。
// 所以这儿的结构是照 `Annotation` 抄的，字段名都对齐，
// 将来要合成一套「划下的东西」也好合。

struct SongMark: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 哪一首。**按歌名+歌手认，不按 Track.id**——
    /// 同一首歌导进来的版本和网上搜到的版本 id 天生不一样
    /// （音乐卡那条 bug 就是这么来的），认 id 会把同一首歌拆成两首。
    var songKey: String = ""
    var title: String = ""
    var artist: String = ""
    /// 划的是哪一句
    var quote: String = ""
    /// 这句在第几秒。点一下能跳回去听。
    var at: Double = 0
    var notes: [AnnotationNote] = []
    var createdAt: Date = Date()
    var author: String = ""
    var colorHex: String = ""
    /// 跟他聊过没有
    var discussed: Bool = false
    /// 聊的是哪一轮，点小气泡顺着它跳回去
    var talkIDs: [UUID] = []

    var color: Color {
        Color(hexString: colorHex) ?? Color(hexString: "F2C94C") ?? .yellow
    }

    /// 一首歌的身份。**跟 MusicLibrary.sameSong 用同一把尺子。**
    static func key(_ t: Track) -> String {
        (t.title + "|" + t.artist).lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    init(id: UUID = UUID(), songKey: String = "", title: String = "", artist: String = "",
         quote: String = "", at: Double = 0, author: String = "", colorHex: String = "") {
        self.id = id; self.songKey = songKey; self.title = title; self.artist = artist
        self.quote = quote; self.at = at; self.author = author; self.colorHex = colorHex
    }

    /// 老数据里没有后加的那几样，缺了不能让整份划线读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        songKey = (try? c.decodeIfPresent(String.self, forKey: .songKey)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        artist = (try? c.decodeIfPresent(String.self, forKey: .artist)) ?? ""
        quote = (try? c.decodeIfPresent(String.self, forKey: .quote)) ?? ""
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
        notes = (try? c.decodeIfPresent([AnnotationNote].self, forKey: .notes)) ?? []
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? ""
        colorHex = (try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? ""
        discussed = (try? c.decodeIfPresent(Bool.self, forKey: .discussed)) ?? false
        talkIDs = (try? c.decodeIfPresent([UUID].self, forKey: .talkIDs)) ?? []
    }
}

// MARK: - 存哪儿

@MainActor
final class SongMarkStore: ObservableObject {

    static let shared = SongMarkStore()

    @Published var marks: [SongMark] = [] {
        didSet { if loaded { Storage.save(marks, to: "song-marks.json") } }
    }
    private var loaded = false

    private init() {
        marks = Storage.load([SongMark].self, from: "song-marks.json") ?? []
        loaded = true
    }

    /// 这一首划过的，按歌里的时间排——**跟着歌走，不是按划的先后**
    func marks(for track: Track) -> [SongMark] {
        let key = SongMark.key(track)
        return marks.filter { $0.songKey == key }.sorted { $0.at < $1.at }
    }

    func mark(at line: String, in track: Track) -> SongMark? {
        let key = SongMark.key(track)
        return marks.first { $0.songKey == key && $0.quote == line }
    }

    @discardableResult
    func add(_ line: LyricLine, in track: Track,
             author: String, note: String, colorHex: String) -> SongMark {
        var m = SongMark(songKey: SongMark.key(track),
                         title: track.title, artist: track.artist,
                         quote: line.text, at: line.at,
                         author: author, colorHex: colorHex)
        if !note.isEmpty {
            m.notes.append(AnnotationNote(author: author, text: note))
        }
        marks.append(m)
        return m
    }

    func remove(_ id: UUID) { marks.removeAll { $0.id == id } }

    func reply(to id: UUID, text: String, by who: String) {
        guard let i = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[i].notes.append(AnnotationNote(author: who, text: text))
    }

    func markDiscussed(_ id: UUID, talkID: UUID? = nil) {
        guard let i = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[i].discussed = true
        if let talkID, !marks[i].talkIDs.contains(talkID) {
            marks[i].talkIDs.append(talkID)
        }
    }

    /// 跟某一句**像**的旧划线。
    /// 跟书房那边同一把尺子（`MemoryRecall.similarity`，纯算术不花钱）——
    /// 她说「这句跟上次那首里那句好像」的时候，他自己就能对上。
    func similar(to quote: String, limit: Int = 5) -> [(SongMark, Double)] {
        marks
            .map { ($0, MemoryRecall.similarity(quote, $0.quote)) }
            .filter { $0.1 >= 0.25 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0 }
    }

    /// 全部，新的在前
    var all: [SongMark] { marks.sorted { $0.createdAt > $1.createdAt } }
}
