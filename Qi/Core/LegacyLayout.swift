import Foundation

/// 把老备份里那些**光秃秃的文件名**送回它本来该在的目录。
///
/// ## 这是在补一个已经发生了的事故
///
/// v112 之前的备份，键全是 `memories.json`、`72EC22F6….png` 这样，
/// 没有目录（根因见 `Storage.relativePath` 里那大段）。
/// 拿这种包还原，每一个文件都被放进 Documents 的**根目录**：
///
/// · `Memory/memories.json` → `memories.json` → **记忆库 0 条、日记 0 篇、存档 0 份**
/// · `Images/x.jpg` → `x.jpg` → 相册里只剩文字
/// · `Stickers/x.gif` → `x.gif` → 表情空一块
/// · `Voices/x.mp3` → `x.mp3` → 语音条点不响
/// · `Music/x.mp3` → `x.mp3` → 歌放不出来
///
/// 她手里那几份备份都是这么打的，**里面的字节一个都没少**，
/// 少的只是「这个文件该放哪儿」。所以不是重导一份就完事——
/// 还原这一头也得认得老包，不然她那几份包永远还原不回来。
///
/// ⚠️ **只对没有目录的键动手。** 新包的键带着 `Images/` 这种前缀，
/// 一个字都不碰。
enum LegacyLayout {

    /// 记忆库那一摊的文件名。**这份名单跟 `MemoryStore` 里的读写一一对应**，
    /// 那边加了一份新的，这儿要跟着加——不然老包还原回来又少一样。
    static let memoryFiles: Set<String> = [
        "memories.json", "diaries.json", "current_state.json",
        "state_history.json", "live_checkpoint.json", "spine.json",
        "rules.json", "open_tasks.json", "promises.json", "letter.json",
        "partner_message.json", "periods.json", "moods.json",
        "emotional_events.json", "memories_log.json", "transcripts.json",
        "candidates.json", "glossary.json", "identity.txt"
    ]

    /// 存档那些单独的文件，名字是记忆 id 的前八位（`0f61881f.json`），
    /// 住在 `Memory/transcripts/` 里。
    ///
    /// ⚠️ 认得严一点：**正好八位十六进制 + `.json`**。
    /// 松了会把根目录的正经文件（`settings.json` 那些）也卷进去。
    static func isTranscript(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let stem = String(name.dropLast(5))
        guard stem.count == 8 else { return false }
        return stem.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// 会动会响的那几种后缀，用来分「语音/音乐」和「图片」
    private static let audioExts: Set<String> = ["mp3", "m4a", "wav", "caf", "aac", "flac"]

    /// json / txt 那一半：这时候还没有别的线索，只能按名字判。
    static func home(forText name: String) -> String {
        guard !name.contains("/") else { return name }        // 新包，别碰
        if memoryFiles.contains(name) { return "Memory/" + name }
        if isTranscript(name) { return "Memory/transcripts/" + name }
        return name                                           // 根目录本来就在根目录
    }

    /// 图片语音那一半：**靠已经还原好的那几份记录认领**。
    ///
    /// 为什么不按后缀猜：一个 `.mp3` 可能是她录的语音条，也可能是她导进来的歌；
    /// 一个 `.gif` 可能是表情，也可能是聊天里发过的图。
    /// **谁的记录里写着这个文件名，它就是谁的**——这是唯一不会猜错的判法。
    ///
    /// `records` 是「哪份记录 → 它的正文」，由调用方在 json 还原完之后读出来。
    static func home(forBlob name: String, records: Records) -> String {
        guard !name.contains("/") else { return name }        // 新包，别碰
        if memoryFiles.contains(name) { return "Memory/" + name }

        // 认领。顺序要紧：表情最专一，先问它
        if records.mentions(name, in: "stickers.json") { return "Stickers/" + name }
        if records.mentions(name, in: "music.json") { return "Music/" + name }
        if records.mentions(name, in: "media.json") { return "Images/" + name }

        // 没人明说的，按后缀走一个不会更坏的默认：
        // 会响的归语音（聊天里的语音条最多），别的归图片。
        let ext = (name as NSString).pathExtension.lowercased()
        return (audioExts.contains(ext) ? "Voices/" : "Images/") + name
    }

    // MARK: 把已经放错的挪回去

    /// 开 App 的时候修一次：**Documents 根目录里那些被放错地方的文件，挪回原位。**
    ///
    /// ## 为什么不是「让她重导一次备份」
    ///
    /// 因为东西**已经在这台手机上了**。
    /// 她上一次还原，62 份数据和 8 个文件确确实实都写进来了，
    /// 只是全被堆在了根目录——`memories.json` 就躺在那儿，
    /// 65 条记忆一条没少，只是没人去那个位置找它。
    ///
    /// 让她重导一次也能好，但那是**让她替我收拾**。
    /// 东西在手边就自己挪回去，她开一次 App 记忆库就回来了。
    ///
    /// ## 挪什么、不挪什么
    ///
    /// **只看根目录这一层**（不递归），而且只挪那些「根目录本来就不该有」的：
    ///
    /// · 记忆库那几个名字、八位十六进制的存档 → `Memory/`
    /// · 任何**非 json 的文件** → 按记录认领（`home(forBlob:)`）
    ///   根目录本来就不该有二进制文件，有就是那个 bug 留下的
    ///
    /// **根目录的正经 json 一个都不碰**（`settings.json`、`conversations.json`…），
    /// 它们本来就住在这儿。
    ///
    /// ⚠️ **目标位置已经有东西了就不挪**，宁可留一份垃圾在根目录，
    /// 也不能盖掉那个位置上正当的那份。
    ///
    /// ⚠️ **必须在任何一个 store 读文件之前叫。**
    /// 那些 store 是「读进内存 → 以后按内存往回写」的，
    /// 先让 `MemoryStore` 读了一份空的，它下一次保存就把刚挪回去的盖了。
    /// 现在挂在 `QiApp.init()` 里，那是最早的那一下。
    @discardableResult
    static func repairDocumentsRoot() -> Int {
        let fm = FileManager.default
        let root = Storage.documentsURL
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return 0 }

        let records = Records(dir: root)
        var moved = 0

        for name in names {
            let src = root.appendingPathComponent(name)
            // 目录不动
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue
            else { continue }
            // 解不开被挪到一边的那些原件留在原地，它们就该在根目录待着
            guard !name.contains(".坏了-") else { continue }

            // ⚠️ 这个局部变量**不能叫 `home`**：底下要调 `home(forBlob:records:)`，
            // 同名的话 Swift 会先看见这个 String，然后报「String 不能当函数调用」。
            // 有 Xcode 的话这一下当场就红了，这台机器上得自己看出来。
            let target: String
            if memoryFiles.contains(name) {
                target = "Memory/" + name
            } else if isTranscript(name) {
                target = "Memory/transcripts/" + name
            } else if name.hasSuffix(".json") {
                continue                       // 根目录的正经数据，本来就在家
            } else {
                target = home(forBlob: name, records: records)
            }
            guard target != name else { continue }

            let dest = root.appendingPathComponent(target)

            // 那个位置已经有东西了。**默认不盖**——宁可在根目录留一份垃圾，
            // 也不能盖掉正当的那一份。
            //
            // ⚠️ 只有一个例外：**那份是空壳**。
            //
            // 这个例外非有不可。她的记忆库现在显示 0 条——
            // 只要她在装新版之前点开过记忆库那一页，`MemoryStore` 就会
            // 读到空的、然后把一份 `[]` 写进 `Memory/memories.json`。
            // 于是根目录那份**装着 65 条记忆的真货**会因为「目标已存在」
            // 被永远挡在门外，而挡住它的是一个两字节的 `[]`。
            //
            // 四个字节里装不下任何东西（`[]`、`{}`、空文件都在这个数以内），
            // 拿真货换掉它不会丢任何信息。
            if fm.fileExists(atPath: dest.path) {
                // ⚠️ 写成两行，别挤成 `(try? fm.attributesOfItem(...)[.size]) as? Int`——
                // `try?` 套下标再套 `as?`，中间会绕出一层可选的可选，
                // 这种式子在没有编译器的机器上是纯赌。
                let attrs = try? fm.attributesOfItem(atPath: dest.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                guard size <= 4 else { continue }
                try? fm.removeItem(at: dest)
            }

            try? fm.createDirectory(at: dest.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            if (try? fm.moveItem(at: src, to: dest)) != nil { moved += 1 }
        }

        if moved > 0 {
            Console.log(.app, "把放错地方的文件挪回去了", "\(moved) 个")
        }
        return moved
    }

    /// 认领要用的那几份记录。**读一次，别一个文件问一遍**——
    /// 她有一千张图的时候，那就是一千遍把 `books.json` 读进内存。
    final class Records {
        private var cache: [String: String] = [:]
        private let dir: URL

        init(dir: URL) { self.dir = dir }

        func mentions(_ name: String, in file: String) -> Bool {
            if cache[file] == nil {
                cache[file] = (try? String(contentsOf: dir.appendingPathComponent(file),
                                           encoding: .utf8)) ?? ""
            }
            guard let text = cache[file], !text.isEmpty else { return false }
            return text.contains(name)
        }
    }
}
