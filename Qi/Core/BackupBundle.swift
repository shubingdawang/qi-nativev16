import Foundation

/// 整包备份。
///
/// ## 为什么重写
///
/// 上一版的「导出备份」只装了三样：`providers` / `conversations` / `settings`。
/// 这意味着导出的那份文件里**没有**：
///
///   · 记忆库——身份、说好的规矩、那封写给下一个你的信、承诺、日记、
///     心情、脊椎。**这是整个 App 里最不可替代的东西**
///   · 备忘、通话记录、经期、念头池、clawd 小屋、表情、像素画、书、音乐…
///
/// 而她**每七天要重签一次包**。「我备份过了」在这种情况下是最危险的错觉。
///
/// ## 现在的做法
///
/// 不再手写清单，**把 Documents 里所有 .json 整个扫进去**。
/// 理由跟上一轮修 Codable 那件事一样：手写的清单一定会漏，
/// 而且新加的数据永远不会有人记得回来补一行。
/// 扫目录的做法对以后新增的任何存档都自动生效。
///
/// 加上那几个存在 UserDefaults 里的小开关（clawd 的币、勿扰、浮窗停靠…），
/// 它们值都是 JSON 装得下的类型，一起打包。
///
/// **v3 起图片和语音也进来了。** 她的原话：
/// 「备份我更倾向于全局备份，所有的一切全部备份下来，这样才是备份的意义。」
///
/// 她是对的——表情包的关键词是他一张张看着写出来的，图没了那些词就成了
/// 一串指向空处的标签。所以非 json 的文件走 `blobs`（base64）一起打包。
/// 代价是包会从几百 KB 变成几十上百 MB，导出的时候界面上会报实际大小。
/// 单个超过 20 MB 的（视频那种）跳过并在报告里列出来，不闷声丢。
enum BackupBundle {

    /// v3 = 多了 blobs（图片语音）。**还原时不检查版本**，v2 的照收。
    static let version = 3
    /// 单个文件超过这个就不装了，避免一份备份大到导不出来
    static let blobLimit = 20 * 1024 * 1024

    /// UserDefaults 里我们自己写的那些键。
    /// **新加了键记得来这儿补一个**，不然它不会进备份。
    static let defaultKeys = [
        "clawdCarrying", "clawdCheckIn", "clawdCoins", "clawdLinked",
        "dnd", "dndUntil", "memoStyle", "phoneActivityBookmark",
        "diaryStacked", "memoDockLeft", "memoDockY", "pixelModel",
        "lastBackupAt"
    ]

    /// 不进备份的那些。
    ///
    /// 现在只有回收站：`trash.json` 和 `Trash/` 那个目录。
    /// 她删掉的东西留在这台手机上三十天给她反悔，
    /// **但不该跟着备份走到下一台手机上去**。
    static func skipFromBackup(_ url: URL, root: URL) -> Bool {
        let rel = url.path.hasPrefix(root.path)
            ? String(url.path.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : url.lastPathComponent
        return rel == "trash.json" || rel.hasPrefix("Trash/")
    }

    // MARK: 打包

    static func make() -> Data? {
        var files: [String: Any] = [:]
        let root = Storage.documentsURL
        // **必须递归**：记忆库那一整摊在 `Documents/Memory/` 子目录里，
        // 只扫顶层的话，漏掉的恰好是最不能丢的那部分。
        let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "json" else { continue }
            // 被挪到一边的坏文件不用带走
            guard !url.lastPathComponent.contains(".坏了-") else { continue }
            // **回收站不进备份。** 她定的：
            // 「备份数据的时候回收站就直接不用备份，这样下次导入新的 app
            //   就是真的删除了。」
            // 对——不然导进新手机又冒出一堆她早就删掉的东西，
            // 那不叫还原，那叫翻旧账。
            guard !skipFromBackup(url, root: root) else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 键用相对路径，还原的时候照原样放回去
            let key = url.path.hasPrefix(root.path)
                ? String(url.path.dropFirst(root.path.count)).trimmingCharacters(
                    in: CharacterSet(charactersIn: "/"))
                : url.lastPathComponent
            files[key] = text
        }

        // 图片、语音、像素画、壁纸……**这些才是备份最容易漏的那半**。
        // 再扫一遍，非 json 的全部 base64 装进 blobs。
        var blobs: [String: String] = [:]
        var skipped: [String] = []
        let walker2 = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles])
        while let url = walker2?.nextObject() as? URL {
            guard url.pathExtension != "json" else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                    .isRegularFile == true else { continue }
            guard !skipFromBackup(url, root: root) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let key = url.path.hasPrefix(root.path)
                ? String(url.path.dropFirst(root.path.count)).trimmingCharacters(
                    in: CharacterSet(charactersIn: "/"))
                : url.lastPathComponent
            guard size <= blobLimit else { skipped.append(key); continue }
            guard let data = try? Data(contentsOf: url) else { skipped.append(key); continue }
            blobs[key] = data.base64EncodedString()
        }

        var flags: [String: Any] = [:]
        for k in defaultKeys {
            guard let v = UserDefaults.standard.object(forKey: k) else { continue }
            // JSON 装不下的（比如直接存成 Date 的）就跳过，
            // 不然整包序列化会失败，因小失大
            guard JSONSerialization.isValidJSONObject([v]) else { continue }
            flags[k] = v
        }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let bundle: [String: Any] = [
            "version": version,
            "createdAt": f.string(from: Date()),
            "files": files,
            "blobs": blobs,
            "skipped": skipped,
            "defaults": flags
        ]
        return try? JSONSerialization.data(withJSONObject: bundle,
                                           options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: 还原

    enum Restored {
        /// 新版整包
        case bundle(files: Int, blobs: Int)
        /// 老版那三样。**照样认**——她手里可能还留着以前导出的文件。
        case legacy
        case unreadable(String)
    }

    /// 把备份写回去。
    ///
    /// **只落盘，不动内存里那些已经加载好的 store。**
    /// 那些 store 全是单例，App 一启动就把文件读进来了，
    /// 这会儿直接改文件它们是不知道的，而且它们下一次保存
    /// 还会拿内存里的旧数据把刚还原的文件盖回去。
    /// 所以还原完必须让她重开一次 App——界面上会明确说这句话。
    /// 导进来的这份怎么跟现在的东西相处。
    ///
    /// 她的原话：「导入备份应该不是覆盖而是增加……不管导入什么时候的备份，
    /// 只增加目前没有的，已有的忽略。」
    ///
    /// 她说得对，而且这是**默认该有的样子**：备份是用来「找回丢掉的东西」的，
    /// 不是用来「把今天抹成那天」的。旧备份盖上去，今天聊的全没了——
    /// 那不叫还原，那叫回档。
    enum Mode {
        /// 只补现在没有的，已经有的一个字都不动
        case merge
        /// 整个盖掉（换手机、重装、想彻底回到那一天才用）
        case overwrite
    }

    static func restore(_ data: Data, mode: Mode = .merge) -> Restored {
        // 微信/邮件转一手的文件常常带 UTF-8 BOM 或者前后有空白，
        // 直接丢给 JSONSerialization 会解不开——**它解不开不等于这不是备份**。
        // 以前这儿直接说「可能不是本 App 导出的备份」，
        // 她拿着一份好好的备份被挡在门外，还查不出为什么。
        var cleaned = data
        if cleaned.starts(with: [0xEF, 0xBB, 0xBF]) { cleaned = cleaned.dropFirst(3) }
        while let f = cleaned.first, f == 0x20 || f == 0x0A || f == 0x0D || f == 0x09 {
            cleaned = cleaned.dropFirst()
        }
        while let l = cleaned.last, l == 0x20 || l == 0x0A || l == 0x0D || l == 0x09 || l == 0x00 {
            cleaned = cleaned.dropLast()
        }
        guard let root = try? JSONSerialization.jsonObject(with: cleaned) as? [String: Any]
        else {
            // 说清楚到底怎么了，别让她对着一句笼统的话干瞪眼
            let head = String(data: cleaned.prefix(60), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "（读不出文字）"
            return .unreadable(
                "这个文件解不成 JSON。\n\n大小：\(data.count) 字节\n"
                + "开头是：\(head)\n\n"
                + "要是开头看着像 { \"createdAt\" … 那就是备份没错，"
                + "多半是传的时候被截断了（微信里存下来的常有这问题）——"
                + "换 AirDrop 或者「存到文件」再试一次。")
        }

        // 老版备份：只有那三样，没有 files
        guard let files = root["files"] as? [String: Any] else {
            if root["conversations"] != nil { return .legacy }
            return .unreadable(
                "这个 JSON 里没有 files 也没有 conversations，还原不了。\n\n"
                + "它最外层的键是：" + root.keys.sorted().prefix(8).joined(separator: "、"))
        }
        // ⚠️ **不检查 version。** 旧构建导出的备份也照收——
        // 她拿旧构建的备份喂给新构建，卡在这儿一次了。
        // 里面全是 json 文件名 → 内容，字段对不上的那份自己会退回默认值，
        // 因为每个 store 的解码器都是容错的。

        var written = 0
        let dir = Storage.documentsURL
        for (name, value) in files {
            guard name.hasSuffix(".json"), var text = value as? String else { continue }
            // 别让备份文件里的路径把东西写到 Documents 外面去。
            // 这份文件是她自己导出的，但一个能往任意路径写文件的口子
            // 不该因为"来源可信"就留着。
            guard !name.hasPrefix("/"), !name.contains("..") else { continue }
            let url = dir.appendingPathComponent(name)
            // 记忆库在 Memory/ 子目录里，第一次还原的时候那个目录还不存在
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            if mode == .merge {
                // 当前这套配置不该被一份旧备份改掉——
                // 她现在用哪个模型、连哪台 MCP、字多大，跟「找回聊天记录」是两件事
                if keepMineWhenMerging.contains(name) { continue }
                if let mine = try? String(contentsOf: url, encoding: .utf8),
                   let merged = mergeJSON(mine: mine, theirs: text, name: name) {
                    text = merged
                }
                // 本地压根没有这个文件的话，就是直接写，那也是「增加」
            }

            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                written += 1
            }
        }

        // 图片语音那半。跟 json 一样按相对路径原样放回去。
        var blobCount = 0
        if let blobs = root["blobs"] as? [String: String] {
            for (name, b64) in blobs {
                guard !name.hasPrefix("/"), !name.contains("..") else { continue }
                guard let data = Data(base64Encoded: b64) else { continue }
                let url = dir.appendingPathComponent(name)
                // 合并的时候，已经在的图片一个都不碰——
                // 文件名是 UUID，同名就是同一张，覆盖没有意义只有风险
                if mode == .merge, FileManager.default.fileExists(atPath: url.path) { continue }
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? data.write(to: url, options: .atomic)) != nil { blobCount += 1 }
            }
        }

        // 那几个小开关（币、勿扰、浮窗位置）合并时不动——它们是「现在的偏好」
        if mode == .overwrite, let flags = root["defaults"] as? [String: Any] {
            for (k, v) in flags where defaultKeys.contains(k) {
                UserDefaults.standard.set(v, forKey: k)
            }
        }
        return .bundle(files: written, blobs: blobCount)
    }

    // MARK: 合并（「只增加，不覆盖」那条路）

    /// 这几份**永远保留现在这一份**，合并的时候跳过。
    ///
    /// 它们是「此刻的偏好和连接」，不是「攒下来的东西」：
    /// 一份上周的备份不该把她现在用的模型、连着的 MCP、调好的字号改回去。
    static let keepMineWhenMerging: Set<String> = [
        "settings.json", "mcp.json", "voices.json", "providers.json"
    ]

    /// 把备份里那份并进现在这份。返回合并后的 JSON 文本；合不了就返回 nil（那就保持原样）。
    ///
    /// 规矩只有三条，简单到不会出意外：
    ///   · **两边都是数组** → 按 `id` 认同一条，现在有的一个不动，
    ///     备份里多出来的追加进去
    ///   · **两边都是字典** → 现在缺的键才补（比如心情是「日期 → 那天」）
    ///   · **别的形状** → 保留现在这份
    ///
    /// `conversations.json` 单独处理：同一个窗口要**把消息并起来**，
    /// 不然「同 id 就跳过」等于备份里那半段聊天永远进不来。
    static func mergeJSON(mine: String, theirs: String, name: String) -> String? {
        guard let mineData = mine.data(using: .utf8),
              let theirsData = theirs.data(using: .utf8),
              let a = try? JSONSerialization.jsonObject(with: mineData),
              let b = try? JSONSerialization.jsonObject(with: theirsData)
        else { return nil }

        let merged: Any
        if name.hasSuffix("conversations.json"),
           let mineList = a as? [[String: Any]], let theirsList = b as? [[String: Any]] {
            merged = mergeConversations(mine: mineList, theirs: theirsList)
        } else if let mineList = a as? [Any], let theirsList = b as? [Any] {
            merged = mergeArrays(mine: mineList, theirs: theirsList)
        } else if let mineDict = a as? [String: Any], let theirsDict = b as? [String: Any] {
            var out = mineDict
            for (k, v) in theirsDict where out[k] == nil { out[k] = v }
            merged = out
        } else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(merged),
              let data = try? JSONSerialization.data(withJSONObject: merged,
                                                     options: [.prettyPrinted, .withoutEscapingSlashes])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 按 id 并两个数组。没有 id 的（比如规矩、待办那种纯字符串）按内容去重。
    private static func mergeArrays(mine: [Any], theirs: [Any]) -> [Any] {
        var out = mine
        var seen = Set<String>()
        for item in mine { seen.insert(identity(item)) }
        for item in theirs {
            let key = identity(item)
            if seen.insert(key).inserted { out.append(item) }
        }
        return out
    }

    /// 一条东西的身份。有 id 就用 id，没有就把它本身当成身份。
    private static func identity(_ item: Any) -> String {
        if let d = item as? [String: Any] {
            for k in ["id", "fileName", "term", "start"] {
                if let v = d[k] as? String { return k + ":" + v }
            }
        }
        if let s = item as? String { return "s:" + s }
        if let n = item as? NSNumber { return "n:" + n.stringValue }
        // 认不出身份的就拿整条的 JSON 当身份，至少不会重复塞同一条
        if let d = try? JSONSerialization.data(withJSONObject: [item]) {
            return "j:" + String(decoding: d, as: UTF8.self)
        }
        return "?"
    }

    /// 窗口要**并到消息这一层**。
    ///
    /// 同一个窗口两边都有，但里面的消息可能各有各的——
    /// 她在手机上接着聊了几十条，备份里是几天前那一段。
    /// 按窗口 id 认人，然后把消息按消息 id 并起来、**按时间排回去**。
    private static func mergeConversations(mine: [[String: Any]],
                                           theirs: [[String: Any]]) -> [[String: Any]] {
        var out = mine
        for their in theirs {
            let tid = (their["id"] as? String) ?? ""
            guard let at = out.firstIndex(where: { ($0["id"] as? String) == tid }) else {
                out.append(their)          // 这个窗口这边没有，整个拿过来
                continue
            }
            let mineMsgs = (out[at]["messages"] as? [[String: Any]]) ?? []
            let theirMsgs = (their["messages"] as? [[String: Any]]) ?? []
            var seen = Set(mineMsgs.compactMap { $0["id"] as? String })
            var all = mineMsgs
            for m in theirMsgs {
                guard let mid = m["id"] as? String else { continue }
                if seen.insert(mid).inserted { all.append(m) }
            }
            // 混进来的那些要插回正确的位置，不然时间线是乱的
            all.sort { ($0["createdAt"] as? String ?? "") < ($1["createdAt"] as? String ?? "") }
            out[at]["messages"] = all
        }
        return out
    }
}

// MARK: - 上次备份是什么时候

/// 备份提醒。
///
/// 她用 AltStore 侧载，**免费账号签的包七天到期**，
/// 到期之后 App 起不来，得重装——重装等于从零开始。
/// 所以七天不备份就该提醒她一次。
enum BackupClock {

    private static let key = "lastBackupAt"

    static var lastAt: Date? {
        let t = UserDefaults.standard.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func markDone() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }

    /// 隔了多少天没备份了。从来没备份过就返回 nil。
    static var daysSince: Int? {
        guard let last = lastAt else { return nil }
        return Int(Date().timeIntervalSince(last) / 86400)
    }

    /// 该提醒了吗。七天跟她重签包的周期对齐。
    static var overdue: Bool {
        guard let d = daysSince else { return true }   // 一次都没备份过
        return d >= 7
    }

    static var note: String {
        guard let d = daysSince else { return "还没备份过" }
        if d == 0 { return "今天备份过了" }
        if d == 1 { return "昨天备份的" }
        return "上次备份是 \(d) 天前"
    }
}
