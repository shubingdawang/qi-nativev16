import Foundation

/// App 到底占了多少地方，分门别类算一遍。
///
/// 为什么要有这一页：她用 AltStore 侧载，机器上的空间是有数的；
/// 而这个 App 最能长的是**图片**——表情、她发的照片、像素画、
/// 回收站里还压着三十天的那些。不摆出来的话，
/// 她只会在某天看到「存储空间不足」，然后不知道该删什么。
///
/// **纯算术**：走一遍文件夹加加尺寸，不联网也不花钱。
/// 但文件多的时候要走几百个文件，所以在后台线程上算。
enum StorageUsage {

    struct Item: Identifiable {
        var id: String { name }
        let name: String
        let bytes: Int64
        /// 这一摊是什么，一句话
        let note: String
    }

    struct Report {
        var items: [Item] = []
        var total: Int64 = 0
        /// 整个手机还剩多少
        var freeOnDevice: Int64 = 0
    }

    /// 算一遍。**别在主线程上叫**——文件多的时候要走一会儿。
    static func measure() -> Report {
        let doc = Storage.documentsURL
        var items: [Item] = []

        items.append(Item(name: "图片",
                          bytes: size(of: Storage.imagesURL)
                               + size(of: doc.appendingPathComponent("Stickers", isDirectory: true)),
                          note: "表情、她发的照片、像素画、他画的那些"))
        items.append(Item(name: "回收站",
                          bytes: size(of: doc.appendingPathComponent("Trash", isDirectory: true)),
                          note: "删掉的东西在这儿压三十天，过期自己清"))
        items.append(Item(name: "语音",
                          bytes: size(of: doc.appendingPathComponent("Voice", isDirectory: true))
                               + size(of: doc.appendingPathComponent("Audio", isDirectory: true)),
                          note: "按住说的那些，还有他念出来的"))
        items.append(Item(name: "文件",
                          bytes: size(of: doc.appendingPathComponent("Files", isDirectory: true)),
                          note: "工坊里收的那些文档"))
        items.append(Item(name: "书",
                          bytes: size(of: doc.appendingPathComponent("Books", isDirectory: true)),
                          note: "导进书房的那几本"))
        items.append(Item(name: "音乐",
                          bytes: size(of: doc.appendingPathComponent("Music", isDirectory: true)),
                          note: "导进来的整曲"))
        items.append(Item(name: "记忆库",
                          // 路径自己拼：MemoryStore.root 挂在主线程上，
                          // 而这个函数是特意放到后台线程跑的（要走几百个文件）。
                          bytes: size(of: doc.appendingPathComponent("Memory",
                                                                     isDirectory: true)),
                          note: "记忆、日记、承诺、那封信、聊天存档"))

        // 剩下的都算「别的」：一堆 json（聊天记录、设置、各种小账本）
        let all = size(of: doc)
        let counted = items.reduce(Int64(0)) { $0 + $1.bytes }
        items.append(Item(name: "别的",
                          bytes: max(0, all - counted),
                          note: "聊天记录和各种小账本，都是 json，很小"))

        return Report(items: items.filter { $0.bytes > 0 }
                                  .sorted { $0.bytes > $1.bytes },
                      total: all,
                      freeOnDevice: freeSpace())
    }

    /// 一个文件夹有多大。子文件夹一起算。
    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(v?.fileSize ?? 0)
        }
        guard let e = fm.enumerator(at: url,
                                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                    options: []) else { return 0 }
        var sum: Int64 = 0
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { sum += Int64(v?.fileSize ?? 0) }
        }
        return sum
    }

    /// 整台手机还剩多少空间
    static func freeSpace() -> Int64 {
        let v = try? Storage.documentsURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// 写成人看的：1.2 GB / 340 MB / 8 KB
    static func human(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }
}
