import SwiftUI
import PhotosUI

// MARK: - 数据

struct MediaItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    /// photo = 相册，sticker = 表情包
    var kind: String = "photo"
    /// 归在哪个文件夹里，空字符串表示还没归类
    var folder: String = ""
    var note: String = ""
    var createdAt: Date = Date()
}

@MainActor
final class MediaStore: ObservableObject {

    static let shared = MediaStore()

    /// 「全部」不是一个文件夹，是一个**视图**——这一类的所有图都在里面。
    /// 用一个真实文件夹起不出来的名字当记号（开头是控制字符）。
    /// 她说「全部删不掉也改不了名」——对，它本来就不该能删：
    /// 现在界面上也把它画成不一样的样子，不再假装是个文件夹。
    static let allFolder = "\u{1}all"

    @Published var items: [MediaItem] = [] {
        didSet { if loaded { Storage.save(items, to: "media.json") } }
    }

    /// 文件夹自己的名单，按类别分（photo / sticker）。
    ///
    /// **以前没有这个东西**：文件夹是从图片的归属反推出来的，
    /// 所以「新建一个空文件夹」只能靠往 items 里塞一条 `fileName: ""` 的占位记录。
    /// 那条占位记录就是她看到的三个 bug 的总根：
    ///
    /// · 空文件夹下面显示 **1** —— 占位记录也被数进去了
    /// · 删文件夹选「只删文件夹、图片拿出来」，占位记录跟着挪进未归类 →
    ///   「全部」下面变成 **2**，而且那条垃圾记录永远留在库里
    /// · 「全部」删不掉改不了名 —— 它压根不是文件夹，是「没归类的那些」
    ///
    /// 现在文件夹是独立存的，空文件夹就是空的，一条占位记录都不用。
    @Published var folderNames: [String: [String]] = [:] {
        didSet { if loaded { Storage.save(folderNames, to: "media-folders.json") } }
    }
    private var loaded = false

    init() {
        items = Storage.load([MediaItem].self, from: "media.json") ?? []
        folderNames = Storage.load([String: [String]].self, from: "media-folders.json") ?? [:]

        // 一次性搬家：把老库里那些占位空记录收拾掉，
        // 它们代表的文件夹名转成正经文件夹，别让她的文件夹凭空少掉。
        let placeholders = items.filter { $0.fileName.isEmpty }
        if !placeholders.isEmpty {
            for p in placeholders where !p.folder.isEmpty {
                var list = folderNames[p.kind] ?? []
                if !list.contains(p.folder) { list.append(p.folder) }
                folderNames[p.kind] = list
            }
            items.removeAll { $0.fileName.isEmpty }
        }
        loaded = true
        // 搬完存一次（上面那几笔是在 loaded=false 的时候改的，didSet 没写盘）
        if !placeholders.isEmpty {
            Storage.save(items, to: "media.json")
            Storage.save(folderNames, to: "media-folders.json")
        }
    }

    func list(_ kind: String) -> [MediaItem] {
        items.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
    }

    func add(_ image: UIImage, kind: String, folder: String = "") {
        // 表情包不用存太大，省空间
        guard let name = ImageStore.save(image, quality: kind == "sticker" ? 0.8 : 0.9) else { return }
        items.append(MediaItem(fileName: name, kind: kind, folder: folder))
    }

    /// 某一类下面有哪些文件夹。
    /// 自己建的 + 图片上带着的（老数据、或者别处 move 进来的），并起来。
    func folders(_ kind: String) -> [String] {
        var names = Set(folderNames[kind] ?? [])
        names.formUnion(items.filter { $0.kind == kind }.map { $0.folder })
        names.remove("")
        return names.sorted()
    }

    func createFolder(_ kind: String, name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        var list = folderNames[kind] ?? []
        guard !list.contains(n) else { return }
        list.append(n)
        folderNames[kind] = list
    }

    func renameFolder(_ kind: String, from old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != old else { return }
        for item in list(kind, folder: old) { move(item, to: n) }
        var list = folderNames[kind] ?? []
        list.removeAll { $0 == old }
        if !list.contains(n) { list.append(n) }
        folderNames[kind] = list
    }

    /// 删文件夹。`keepImages` 为真就只删壳子，图片退回未归类。
    func deleteFolder(_ kind: String, name: String, keepImages: Bool) {
        for item in list(kind, folder: name) {
            if keepImages { move(item, to: "") } else { remove(item) }
        }
        var list = folderNames[kind] ?? []
        list.removeAll { $0 == name }
        folderNames[kind] = list
    }

    /// 文件夹里的图。**空文件名的不算**——那种是老数据留下的占位记录。
    func list(_ kind: String, folder: String) -> [MediaItem] {
        items.filter { $0.kind == kind && $0.folder == folder && !$0.fileName.isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 这一类一共多少张（不分文件夹）
    func count(_ kind: String) -> Int {
        items.filter { $0.kind == kind && !$0.fileName.isEmpty }.count
    }

    /// 按关键词找图。照片和表情都翻，先看备注再看文件夹名。
    func search(_ keyword: String) -> [MediaItem] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }
        return items.filter {
            $0.note.localizedCaseInsensitiveContains(k)
                || $0.folder.localizedCaseInsensitiveContains(k)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func setNote(_ note: String, for item: MediaItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].note = note
    }

    func move(_ item: MediaItem, to folder: String) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].folder = folder
    }

    func remove(_ item: MediaItem) {
        ImageStore.delete(item.fileName)
        items.removeAll { $0.id == item.id }
    }
}

// MARK: - 看大图

struct ImagePreviewView: View {

    let item: MediaItem
    @ObservedObject var store: MediaStore
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = ImageStore.load(item.fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale = max(1, min(4, $0)) }
                                .onEnded { _ in
                                    if scale < 1.05 { withAnimation { scale = 1 } }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation { scale = scale > 1 ? 1 : 2.5 }
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }.tint(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            if let image = ImageStore.load(item.fileName) {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            }
                        } label: {
                            Label("存到系统相册", systemImage: "square.and.arrow.down")
                        }
                        Button(role: .destructive) {
                            store.remove(item)
                            dismiss()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").tint(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
