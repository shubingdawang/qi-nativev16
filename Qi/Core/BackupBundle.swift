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
/// **图片和语音没进来**：壁纸、表情、像素画、录音是单独的文件，
/// 加进来备份会从几百 KB 变成几百 MB。界面上会写明这件事，不装懂。
enum BackupBundle {

    static let version = 2

    /// UserDefaults 里我们自己写的那些键。
    /// **新加了键记得来这儿补一个**，不然它不会进备份。
    static let defaultKeys = [
        "clawdCarrying", "clawdCheckIn", "clawdCoins", "clawdLinked",
        "dnd", "dndUntil", "memoStyle", "phoneActivityBookmark",
        "diaryStacked", "memoDockLeft", "memoDockY", "pixelModel",
        "lastBackupAt"
    ]

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
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 键用相对路径，还原的时候照原样放回去
            let key = url.path.hasPrefix(root.path)
                ? String(url.path.dropFirst(root.path.count)).trimmingCharacters(
                    in: CharacterSet(charactersIn: "/"))
                : url.lastPathComponent
            files[key] = text
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
        let root: [String: Any] = [
            "version": version,
            "createdAt": f.string(from: Date()),
            "files": files,
            "defaults": flags
        ]
        return try? JSONSerialization.data(withJSONObject: root,
                                           options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: 还原

    enum Restored {
        /// 新版整包
        case bundle(files: Int)
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
    static func restore(_ data: Data) -> Restored {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unreadable("这个文件不是 JSON，可能不是本 App 导出的备份。") }

        // 老版备份：只有那三样，没有 files
        guard let files = root["files"] as? [String: Any] else {
            return root["conversations"] != nil ? .legacy
                : .unreadable("这个文件里没有可还原的数据。")
        }

        var written = 0
        let root = Storage.documentsURL
        for (name, value) in files {
            guard name.hasSuffix(".json"), let text = value as? String else { continue }
            // 别让备份文件里的路径把东西写到 Documents 外面去。
            // 这份文件是她自己导出的，但一个能往任意路径写文件的口子
            // 不该因为"来源可信"就留着。
            guard !name.hasPrefix("/"), !name.contains("..") else { continue }
            let url = root.appendingPathComponent(name)
            // 记忆库在 Memory/ 子目录里，第一次还原的时候那个目录还不存在
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                written += 1
            }
        }

        if let flags = root["defaults"] as? [String: Any] {
            for (k, v) in flags where defaultKeys.contains(k) {
                UserDefaults.standard.set(v, forKey: k)
            }
        }
        return .bundle(files: written)
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
