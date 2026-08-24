import Foundation

/// 查一遍文件：**库里记着的那些东西，文件还在不在。**
///
/// ## 为什么要有这个东西
///
/// 她说的是「显示备份了多少张图片，可是相册里看不见，只能看见文字」，
/// 后来又加上「语音条也不能听了」「歌也放不出来」。
/// **这几句是同一件事**——见 `Storage.relativePath` 里那段：
/// v112 之前的备份把目录算丢了，还原的时候所有文件都被堆进 Documents 根目录。
///
/// 之所以看上去像四个毛病，是因为**记录和文件是两样东西**：
/// 名称、关键词、歌词、播放次数在 json 里，文件本身在 `Images/`、
/// `Stickers/`、`Voices/`、`Music/` 底下。记录在、文件没了，
/// 界面上就是一个名字底下空一块——**不报错，也不说话**，
/// 因为对界面来说「读不出这个文件」和「这里本来就是空的」长得一样。
///
/// 而在这之前，**App 里没有任何一处能回答「文件到底在不在」**。
/// 她只能对着一屏空白猜，我也只能对着代码猜——第一轮我就猜错了方向，
/// 白花了她一整窗。这个函数就是来结束猜的。
///
/// ⚠️ 会走几百上千个文件，**在后台线程上叫**。
enum MediaAudit {

    struct Report {
        /// 一类东西的账
        struct Line: Identifiable {
            var id: String { name }
            let name: String
            /// 量词。语音条不是「张」，歌也不是——
            /// 一句话里量词不对，读起来就像是机器凑出来的
            var unit: String = "张"
            /// 库里记着几个
            var recorded = 0
            /// 其中文件真的在的几个
            var present = 0
            var missing: Int { max(0, recorded - present) }
        }
        var lines: [Line] = []
        /// `Stickers/` 里躺着、但没有任何一条记录指向它的文件
        var orphans = 0
        var totalRecorded: Int { lines.reduce(0) { $0 + $1.recorded } }
        var totalMissing: Int { lines.reduce(0) { $0 + $1.missing } }

        /// 摆给她看的一段话。**别只报个数字**——
        /// 「丢了 12 张」和「该去做什么」之间不该再隔一层翻译。
        var text: String {
            var s = ""
            for l in lines where l.recorded > 0 {
                s += "· \(l.name)：记着 \(l.recorded) \(l.unit)"
                s += "，在的 \(l.present) \(l.unit)"
                s += l.missing > 0 ? "，**丢了 \(l.missing) \(l.unit)**\n" : "\n"
            }
            if s.isEmpty { s = "库里还什么都没有。\n" }
            if orphans > 0 {
                s += "· 另外表情那个目录里有 \(orphans) 个文件没有记录指向它们"
                    + "（多半是删过表情留下的）。\n"
            }
            if totalMissing > 0 {
                s += "\n**丢的那些是文件没了，不是记录坏了。**"
                    + "名字、关键词、歌词、播放次数都还在，文件找回来就自己对上了。\n\n"
                    + "v112 之前的备份**把目录算丢了**：还原的时候所有文件都被堆进了"
                    + "根目录，谁都找不着。相册只剩文字、表情空一块、语音条点不响、"
                    + "歌放不出来——**是同一件事**。拿新版重新导一份备份、再导回来就正了。"
            } else if totalRecorded > 0 {
                s += "\n每一条记录都找得到文件，这边是好的。"
            }
            return s
        }
    }

    /// 走一遍。**主线程上取一份名单，剩下的活在后台干。**
    ///
    /// ⚠️ `app` 是调用方传进来的，**不走单例**——
    /// `AppState` 压根儿没有 `shared`，它一直是 `@EnvironmentObject`。
    /// （我第一版就随手写了 `AppState.shared`。有 Xcode 的话编译器当场就拦下来了，
    /// 这台机器没有，拦不住。**写一个没亲眼看过的名字之前，先 grep 一遍。**）
    @MainActor
    static func run(app: AppState) async -> Report {
        // 名单先在主线程上抄出来（那几个 store 都是 @MainActor 的），
        // 再把这几个数组扔到后台去对文件——
        // 对文件那一步要 stat 上千次，不能压在主线程上。
        let stickerFiles = StickerStore.shared.stickers.flatMap {
            [$0.fileName, $0.thumbName].filter { !$0.isEmpty }
        }
        let mediaFiles = MediaStore.shared.items.map(\.fileName).filter { !$0.isEmpty }
        // ⚠️ 歌和语音也要查。
        //
        // 她报的那几件事——相册只剩文字、表情空一块、
        // 语音条点不响、歌放不出来——**是同一个 bug**
        // （备份把目录算丢了，见 `Storage.relativePath`）。
        // 既然是同一件事，查的时候就要一块儿查，
        // 别让她在四个页面各发现一次。
        let musicFiles = MusicLibrary.shared.tracks.map(\.localName).filter { !$0.isEmpty }
        let voiceFiles = voiceNames(app)

        return await Task.detached(priority: .utility) {
            check(stickerFiles: stickerFiles, mediaFiles: mediaFiles,
                  musicFiles: musicFiles, voiceFiles: voiceFiles)
        }.value
    }

    /// 聊天记录里那些语音条的文件名。
    ///
    /// ⚠️ 字段叫 `voiceName`，不叫 `audioName`，而且**不是可选的**——
    /// 没语音就是空字符串。（见 `ChatMessage`。）
    @MainActor
    private static func voiceNames(_ app: AppState) -> [String] {
        app.conversations.flatMap { c in
            c.messages.map(\.voiceName).filter { !$0.isEmpty }
        }
    }

    private static func check(stickerFiles: [String], mediaFiles: [String],
                              musicFiles: [String], voiceFiles: [String]) -> Report {
        var report = Report()
        let fm = FileManager.default

        let doc = Storage.documentsURL
        let stickerDir = doc.appendingPathComponent("Stickers", isDirectory: true)
        let imageDir = doc.appendingPathComponent("Images", isDirectory: true)
        let voiceDir = doc.appendingPathComponent("Voices", isDirectory: true)
        let musicDir = doc.appendingPathComponent("Music", isDirectory: true)

        func tally(_ name: String, _ unit: String,
                   _ files: [String], in dir: URL) -> Set<String> {
            var line = Report.Line(name: name, unit: unit)
            var used = Set<String>()
            for f in files {
                line.recorded += 1
                used.insert(f)
                if fm.fileExists(atPath: dir.appendingPathComponent(f).path) {
                    line.present += 1
                }
            }
            report.lines.append(line)
            return used
        }

        let usedStickers = tally("表情和 GIF", "张", stickerFiles, in: stickerDir)
        _ = tally("相册图片", "张", mediaFiles, in: imageDir)
        _ = tally("聊天里的语音条", "条", voiceFiles, in: voiceDir)
        _ = tally("歌的音频", "首", musicFiles, in: musicDir)

        // 没人认领的。**只数 `Stickers/`，不数 `Images/`。**
        //
        // `Images/` 里除了相册那些，还堆着聊天里发过的图、日记的配图、
        // 小屋的墙纸——它们都不在 `media.json` 里。
        // 拿相册那本账去对整个目录，会报出一个几百的「没人认领」，
        // 那个数**吓人而且是假的**。`Stickers/` 只有表情，对得上。
        //
        // ⚠️ 只数，不删。
        if let names = try? fm.contentsOfDirectory(atPath: stickerDir.path) {
            for n in names where !usedStickers.contains(n) { report.orphans += 1 }
        }

        return report
    }
}
