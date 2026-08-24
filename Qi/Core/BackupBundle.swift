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

    /// 这份文件是不是一整包备份。**只看开头那几 KB。**
    ///
    /// 她拿记忆库里那些单个 json（`partner_message.json` 这种）
    /// 走「导入备份」那个口，得到一句「没有 files 也没有 conversations」——
    /// **那句话没错，但它没告诉她该去哪儿。**
    /// 现在先认一认：不是整包的，界面那边会自动改走记忆库那条路。
    ///
    /// 认一份备份不需要把它整个读进来——顶层那几个键都在最前面。
    /// 她那份要是有三百兆，为了「认一下」就读进内存三百兆是荒唐的。
    static func looksLikeBundle(fileAt url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 8192) else { return false }
        // `String(decoding:as:)` 不会因为末尾截断了半个汉字就返回 nil
        let s = String(decoding: head, as: UTF8.self)
        return s.contains("\"files\"") || s.contains("\"blobs\"")
            || s.contains("\"conversations\"")
    }

    static func looksLikeBundle(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return obj["files"] != nil || obj["conversations"] != nil || obj["blobs"] != nil
    }

    /// UserDefaults 里我们自己写的那些键。
    /// **新加了键记得来这儿补一个**，不然它不会进备份。
    static let defaultKeys = [
        "clawdCarrying", "clawdCheckIn", "clawdCoins", "clawdLinked",
        "dnd", "dndUntil", "memoStyle", "phoneActivityBookmark",
        "diaryViewMode", "memoDockLeft", "memoDockY", "pixelModel",
        "auroraOn", "monopolyBoardImage",
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

    /// 打完包之后交代一句：装了多少份数据、多少张图、多大、谁没装进去。
    ///
    /// **这个必须报出来。** 她说「图片并没有备份，没有备份图片我之前写的
    /// 关键词全都白瞎了」——她没法从一个 json 文件的外表看出里面有没有图。
    /// 现在导完当场告诉她「\(blobs) 个图片语音」，
    /// 是 0 就是 0，一眼看得见，不用等到还原那天才发现。
    struct Report {
        var files = 0
        var blobs = 0
        var skipped: [String] = []
        var bytes = 0
    }

    /// 把一个字符串写成合法的 JSON 字面量（带引号）。
    ///
    /// 自己手写 JSON 的时候**键名必须走这儿**——
    /// 文件名里出现一个引号或者反斜杠，整份备份就成了废文件。
    private static func quoted(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s]),
              let t = String(data: d, encoding: .utf8),
              t.count >= 2 else { return "\"\"" }
        // `["…"]` → 去掉外面那对方括号
        return String(t.dropFirst().dropLast())
    }

    /// **一边算一边往文件里写**，不在内存里攒出一整份。
    ///
    /// ## 为什么非改不可
    ///
    /// 上一版是 `make() -> Data?`：把所有图片 base64 塞进一个字典，
    /// 再交给 `JSONSerialization` 序列化成一整块 `Data`。
    /// 她的图要是有 200 MB，这条路上的峰值内存是——
    /// 原始字节 200 MB + base64 267 MB + 序列化出来的 270 MB
    /// ≈ **七八百兆，全在主线程上**。
    ///
    /// 手机给一个 App 的内存没那么宽裕。结果就是两种：
    /// 要么被系统当场杀掉，要么 `JSONSerialization` 返回 nil，
    /// 而 nil 那一支只说了句「导出失败」——**她照样以为自己备份过了**。
    ///
    /// 现在改成流式：json 那半很小，照旧整块写；
    /// 图片语音**一次只读一个文件**，转完 base64 立刻写进磁盘、立刻放掉。
    /// 峰值内存 = 最大的那一个文件，跟她有多少张图无关。
    ///
    /// ⚠️ 这个函数**会读一大堆文件、跑很久**，一定要在后台线程上叫。
    static func write(to dest: URL,
                      progress: ((String) -> Void)? = nil) -> Report {
        var report = Report()
        let root = Storage.documentsURL

        // ── 先收 json 那半（小，整块处理没问题）──────────────
        progress?("正在收拾数据…")
        var files: [String: Any] = [:]
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

        report.files = files.count

        // ── 图片语音先只**点名**，不读内容 ────────────────────
        //
        // 这一步只收路径和大小。真正的字节留到往文件里写的那一刻再读，
        // 读一个写一个，读完就放掉。
        var blobURLs: [(url: URL, key: String)] = []
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
            guard size <= blobLimit else { report.skipped.append(key); continue }
            blobURLs.append((url, key))
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

        // ── 开写 ────────────────────────────────────────────
        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: dest) else { return report }
        defer { try? handle.close() }

        func put(_ s: String) {
            guard let d = s.data(using: .utf8) else { return }
            try? handle.write(contentsOf: d)
            report.bytes += d.count
        }

        // 小的那几块照旧整块序列化——它们加起来也就几兆
        let filesJSON = (try? JSONSerialization.data(
            withJSONObject: files, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let flagsJSON = (try? JSONSerialization.data(
            withJSONObject: flags, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        put("{\"version\":\(version),")
        put("\"createdAt\":\(quoted(f.string(from: Date()))),")
        put("\"files\":" + filesJSON + ",")
        put("\"blobs\":{")

        var first = true
        for (i, item) in blobURLs.enumerated() {
            if i % 25 == 0 {
                progress?("正在装第 \(i + 1) / \(blobURLs.count) 个图片语音…")
            }
            // ⚠️ `autoreleasepool` 不能省。
            // 一次循环里生出来的那块 Data 和那个 base64 字符串
            // 要是攒到整个循环跑完才放，等于什么都没改。
            var ok = false
            autoreleasepool {
                guard let data = try? Data(contentsOf: item.url, options: [.mappedIfSafe])
                else { return }
                let b64 = data.base64EncodedString()
                if !first { put(",") }
                // 分开写，**别拼成一个字符串**——
                // b64 可能有二十几兆，拼一次就等于又复制一份
                put(quoted(item.key))
                put(":\"")
                put(b64)
                put("\"")
                ok = true
            }
            if ok { first = false; report.blobs += 1 }
            else { report.skipped.append(item.key) }
        }

        put("},")
        let skippedJSON = (try? JSONSerialization.data(
            withJSONObject: report.skipped))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        put("\"skipped\":" + skippedJSON + ",")
        put("\"defaults\":" + flagsJSON + "}")

        progress?("写完了")
        return report
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

    // MARK: 从文件还原（不把整包读进内存那条路）

    /// 从磁盘上那份备份还原。
    ///
    /// ## 跟 `restore(_ data:)` 差在哪
    ///
    /// 那一版要求先 `Data(contentsOf:)` 把整包读进内存，
    /// 再交给 `JSONSerialization` 解析——**两份都在内存里**。
    /// 一份 300 MB 的备份，这一下就是六七百兆，还全在主线程上。
    /// 她说的「导入备份有点卡」就是这个。
    ///
    /// 这一版：
    ///   ① 文件**内存映射**进来（`.mappedIfSafe`），不真的占内存
    ///   ② 先在字节层面找到 `"blobs"` 那一大块的范围，**不解析它**
    ///   ③ 把那一块挖掉，剩下的（json 那半，很小）才交给 JSONSerialization
    ///   ④ 图片语音一个一个抠出来、解一个写一个，写完就放掉
    ///
    /// 峰值内存 = 最大的那一张图，跟备份多大无关。
    ///
    /// ⚠️ 一定要在后台线程上叫。
    static func restore(from url: URL, mode: Mode = .merge,
                        progress: ((String) -> Void)? = nil) -> Restored {
        guard let mapped = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return .unreadable("这份文件读不出来。")
        }

        // 找 blobs 那一块在哪儿
        // 参数类型写全。`withUnsafeBytes` 有两个重载（还有个老的指针版），
        // 不写清楚的话编译器要在两者之间犹豫。
        let range: Range<Int>? = mapped.withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) -> Range<Int>? in
            blobsRange(raw)
        }

        guard let blobs = range else {
            // 没找到就走老路。**老备份、v2 的包、被改过的包都从这儿过**，
            // 一份都不能因为「新写法认不出来」就被挡在门外。
            progress?("正在还原…")
            return restore(mapped, mode: mode)
        }

        // ── 先把 json 那半还原了 ────────────────────────────
        //
        // 把 blobs 那一大块换成一个空对象，剩下的就小得可以随便解析。
        progress?("正在还原数据…")
        var rest = Data()
        rest.append(mapped.subdata(in: 0..<blobs.lowerBound))
        rest.append(contentsOf: [UInt8(ascii: "{"), UInt8(ascii: "}")])
        rest.append(mapped.subdata(in: blobs.upperBound..<mapped.count))

        let head = restore(rest, mode: mode)
        guard case .bundle(let written, _) = head else { return head }

        // ── 再一个一个把图片语音抠出来 ──────────────────────
        var count = 0
        let dir = Storage.documentsURL
        var pairs: [(String, Range<Int>)] = []
        mapped.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            pairs = blobPairs(raw, in: blobs)
        }

        for (i, pair) in pairs.enumerated() {
            if i % 25 == 0 {
                progress?("正在放回第 \(i + 1) / \(pairs.count) 个图片语音…")
            }
            let name = pair.0
            guard !name.hasPrefix("/"), !name.contains("..") else { continue }
            let out = dir.appendingPathComponent(name)
            // 合并的时候，已经在的图片一个都不碰——
            // 文件名是 UUID，同名就是同一张，覆盖没有意义只有风险
            if mode == .merge, FileManager.default.fileExists(atPath: out.path) { continue }
            autoreleasepool {
                let b64 = String(decoding: mapped.subdata(in: pair.1), as: UTF8.self)
                guard let data = Data(base64Encoded: b64) else { return }
                try? FileManager.default.createDirectory(
                    at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? data.write(to: out, options: .atomic)) != nil { count += 1 }
            }
        }

        return .bundle(files: written, blobs: count)
    }

    // MARK: 在字节里找东西
    //
    // 下面这两个函数是**手写的 JSON 扫描**。平时不该这么干——
    // 有现成的解析器就用现成的。这儿的理由只有一个：
    // **不能把那几百兆读进内存。** 而所有现成的解析器都要求先读进来。
    //
    // 扫的时候要认得三件事：字符串里的引号不算结构、反斜杠转义、
    // 大括号方括号的层数。认全了这三件，找一段范围是很稳的。

    /// 找到顶层那个 `"blobs"` 的值（那一整个大括号）在哪儿。
    private static func blobsRange(_ b: UnsafeRawBufferPointer) -> Range<Int>? {
        let n = b.count
        var i = 0, depth = 0
        var inStr = false, esc = false
        var keyStart = -1
        var lastKey = ""

        while i < n {
            let c = b[i]
            if inStr {
                if esc { esc = false }
                else if c == 0x5C { esc = true }
                else if c == 0x22 {
                    inStr = false
                    // 只有顶层那一层的键才需要认，深处的不管
                    if depth == 1, i - keyStart <= 16 {
                        lastKey = String(decoding: UnsafeRawBufferPointer(
                            rebasing: b[keyStart..<i]), as: UTF8.self)
                    }
                }
                i += 1
                continue
            }
            switch c {
            case 0x22: inStr = true; keyStart = i + 1
            case 0x7B:                                  // {
                if depth == 1, lastKey == "blobs" {
                    guard let end = matchBrace(b, from: i) else { return nil }
                    return i..<end
                }
                depth += 1
            case 0x7D: depth -= 1                       // }
            case 0x5B: depth += 1                       // [
            case 0x5D: depth -= 1                       // ]
            default: break
            }
            i += 1
        }
        return nil
    }

    /// 从 `from`（那个 `{`）开始，找到配对的 `}`，返回它**后面一位**。
    private static func matchBrace(_ b: UnsafeRawBufferPointer, from: Int) -> Int? {
        var i = from, depth = 0
        var inStr = false, esc = false
        while i < b.count {
            let c = b[i]
            if inStr {
                if esc { esc = false }
                else if c == 0x5C { esc = true }
                else if c == 0x22 { inStr = false }
                i += 1
                continue
            }
            if c == 0x22 { inStr = true }
            else if c == 0x7B { depth += 1 }
            else if c == 0x7D {
                depth -= 1
                if depth == 0 { return i + 1 }
            }
            i += 1
        }
        return nil
    }

    /// 把 blobs 那一块里的每一对「文件名 → base64」点出来。
    ///
    /// **只返回范围，不复制内容**——真正取字节留到写文件那一刻，
    /// 一次只取一个。
    private static func blobPairs(_ b: UnsafeRawBufferPointer,
                                  in range: Range<Int>) -> [(String, Range<Int>)] {
        var out: [(String, Range<Int>)] = []
        var i = range.lowerBound + 1                    // 跳过开头那个 {
        let end = range.upperBound - 1                  // 结尾那个 } 不进来

        /// 从 `at`（一个 `"`）开始，返回收尾那个 `"` 的下标
        func closeQuote(_ at: Int) -> Int? {
            var j = at + 1
            var esc = false
            while j < end {
                let c = b[j]
                if esc { esc = false }
                else if c == 0x5C { esc = true }
                else if c == 0x22 { return j }
                j += 1
            }
            return nil
        }

        func skipBlank() {
            while i < end {
                let c = b[i]
                guard c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x2C
                else { return }
                i += 1
            }
        }

        while i < end {
            skipBlank()
            guard i < end, b[i] == 0x22, let kEnd = closeQuote(i) else { break }
            let rawKey = String(decoding: UnsafeRawBufferPointer(
                rebasing: b[(i + 1)..<kEnd]), as: UTF8.self)
            i = kEnd + 1
            skipBlank()
            guard i < end, b[i] == 0x3A else { break }  // :
            i += 1
            skipBlank()
            guard i < end, b[i] == 0x22, let vEnd = closeQuote(i) else { break }
            // 键有可能被转义过（路径里的斜杠、罕见的引号），
            // 走一趟正经解析把它还原成本来的样子
            let key = unescape(rawKey)
            out.append((key, (i + 1)..<vEnd))
            i = vEnd + 1
        }
        return out
    }

    /// 把一段 JSON 字符串字面量的内容还原成原文
    private static func unescape(_ raw: String) -> String {
        guard raw.contains("\\") else { return raw }
        guard let d = ("\"" + raw + "\"").data(using: .utf8),
              let s = try? JSONSerialization.jsonObject(
                with: d, options: [.fragmentsAllowed]) as? String
        else { return raw }
        return s
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
