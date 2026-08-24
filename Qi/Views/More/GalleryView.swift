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

    /// 还原完重读一遍。⚠️ `loaded` 先关掉——读的时候不许写盘。
    func reload() {
        loaded = false
        items = Storage.load([MediaItem].self, from: "media.json") ?? []
        folderNames = Storage.load([String: [String]].self, from: "media-folders.json") ?? [:]
        loaded = true
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

    /// 这一屏能翻的全部图。**不是只给一张**——
    /// 她说的第 1 条：「点击查看后并不能放大后移动查看细节，也不能翻页」。
    /// 只给一张的话，翻页这件事从根上就不成立。
    let items: [MediaItem]
    /// 从第几张开始看
    @State var index: Int
    @ObservedObject var store: MediaStore
    /// 能不能在这儿删。**聊天里点开的图不能删**——
    /// 那几张不在相册库里，按下去删的会是别人（同名的库存图），
    /// 或者什么都不发生。
    var canDelete: Bool = true
    @Environment(\.dismiss) private var dismiss

    /// 放大倍数和位移。**每翻一页都要归零**，
    /// 不然上一张放大着的状态会带到下一张，看着像卡住了。
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var current: MediaItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $index) {
                    ForEach(items.indices, id: \.self) { i in
                        page(items[i])
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // 放大之后要能拖着看细节，而拖和翻页是同一种手势——
                // 所以**放大着的时候把翻页关掉**，缩回去再打开。
                .highPriorityGesture(scale > 1.01 ? panGesture : nil)
                .onChange(of: index) { _, _ in resetZoom() }

                if items.count > 1 {
                    VStack {
                        Spacer()
                        Text("\(index + 1) / \(items.count)")
                            .font(.app(12))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.35)))
                            .padding(.bottom, 26)
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
                            if let c = current, let image = ImageStore.cached(c.fileName) {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            }
                        } label: {
                            Label("存到系统相册", systemImage: "square.and.arrow.down")
                        }
                        if canDelete {
                            Button(role: .destructive) {
                                guard let c = current else { return }
                                store.remove(c)
                                // 删完还有别的就留在这一页，没有了才退出去
                                if items.count <= 1 { dismiss() }
                                else { index = min(index, items.count - 2) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").tint(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func page(_ item: MediaItem) -> some View {
        Group {
            // 会动的要逐帧播，`Image(uiImage:)` 只画第一帧
            if item.fileName.lowercased().hasSuffix(".gif") {
                AnimatedImageView(url: ImageStore.url(for: item.fileName))
            } else if let image = ImageStore.cached(item.fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .scaleEffect(scale)
        .offset(offset)
        .gesture(
            MagnificationGesture()
                .onChanged { v in
                    scale = max(1, min(6, lastScale * v))
                }
                .onEnded { _ in
                    lastScale = scale
                    if scale < 1.05 { withAnimation(.easeOut(duration: 0.2)) { resetZoom() } }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.22)) {
                if scale > 1.01 { resetZoom() }
                else { scale = 2.5; lastScale = 2.5 }
            }
        }
    }

    /// 放大之后拖着看细节
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                offset = CGSize(width: lastOffset.width + v.translation.width,
                                height: lastOffset.height + v.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func resetZoom() {
        scale = 1; lastScale = 1
        offset = .zero; lastOffset = .zero
    }
}

extension ImagePreviewView {
    /// 聊天里点开的图：给一串文件名就行，只看不删。
    @MainActor
    init(names: [String], index: Int) {
        self.init(items: names.map { MediaItem(fileName: $0) },
                  index: index,
                  store: MediaStore.shared,
                  canDelete: false)
    }
}
