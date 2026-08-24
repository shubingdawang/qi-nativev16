import Foundation

/// 查一遍图：**库里记着的那些图，文件还在不在。**
///
/// ## 为什么要有这个东西
///
/// 她两次说的是同一句话：「显示备份了多少张图片，可是相册里看不见，
/// 只能看见文字。」
///
/// 那一屏之所以只有文字，是因为**记录和图是两样东西**：
/// 名称、画面描述、情绪标签存在 `stickers.json` / `media.json` 里，
/// 图本身是 `Stickers/` 和 `Images/` 下面一个个独立的文件。
/// 记录还在、文件没了，界面上就是一个名字底下空一块——
/// 它不会报错，因为对界面来说「读不出这张图」和「这张图是空的」长得一样。
///
/// 而在这之前，**App 里没有任何一处能回答「文件到底在不在」**。
/// 她只能看着一屏空白猜，我也只能看着代码猜。这个函数就是来结束猜的：
/// 记着 N 张、在的 M 张、丢的 N−M 张，还有多少张躺在磁盘上没人认领。
///
/// ⚠️ 会走几百上千个文件，**在后台线程上叫**。
enum MediaAudit {

    struct Report {
        /// 一类东西的账
        struct Line: Identifiable {
            var id: String { name }
            let name: String
            /// 库里记着几张
            var recorded = 0
            /// 其中文件真的在的几张
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
                s += "· \(l.name)：记着 \(l.recorded) 张，在的 \(l.present) 张"
                s += l.missing > 0 ? "，**丢了 \(l.missing) 张**\n" : "\n"
            }
            if s.isEmpty { s = "库里还没有图。\n" }
            if orphans > 0 {
                s += "· 另外表情那个目录里有 \(orphans) 个文件没有记录指向它们"
                    + "（多半是删过表情留下的）。\n"
            }
            if totalMissing > 0 {
                s += "\n**丢的那些是文件没了，不是记录坏了。**"
                    + "名称和关键词都还在，把图找回来（重新导一份带图的备份进来）"
                    + "就能对上。\n\n"
                    + "导备份的时候留意那句「N 个图片语音」——"
                    + "那个数现在是**写完之后重新数出来的**，是 0 就是真的一张都没装进去。"
            } else if totalRecorded > 0 {
                s += "\n每一张记录都找得到文件，这边是好的。"
            }
            return s
        }
    }

    /// 走一遍。**主线程上取一份名单，剩下的活在后台干。**
    @MainActor
    static func run() async -> Report {
        // 名单先在主线程上抄出来（两个 store 都是 @MainActor 的），
        // 再把这几个数组扔到后台去对文件——
        // 对文件那一步要 stat 上千次，不能压在主线程上。
        let stickerFiles = StickerStore.shared.stickers.flatMap {
            [$0.fileName, $0.thumbName].filter { !$0.isEmpty }
        }
        let mediaFiles = MediaStore.shared.items.map(\.fileName).filter { !$0.isEmpty }

        return await Task.detached(priority: .utility) {
            check(stickerFiles: stickerFiles, mediaFiles: mediaFiles)
        }.value
    }

    private static func check(stickerFiles: [String], mediaFiles: [String]) -> Report {
        var report = Report()
        let fm = FileManager.default

        let stickerDir = Storage.documentsURL.appendingPathComponent("Stickers", isDirectory: true)
        let imageDir = Storage.documentsURL.appendingPathComponent("Images", isDirectory: true)

        func tally(_ name: String, _ files: [String], in dir: URL) -> Set<String> {
            var line = Report.Line(name: name)
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

        let usedStickers = tally("表情和 GIF", stickerFiles, in: stickerDir)
        let usedImages = tally("相册图片", mediaFiles, in: imageDir)

        _ = usedImages
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
