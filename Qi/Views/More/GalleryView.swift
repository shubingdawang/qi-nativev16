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

    @Published var items: [MediaItem] = [] {
        didSet { if loaded { Storage.save(items, to: "media.json") } }
    }
    private var loaded = false

    init() {
        items = Storage.load([MediaItem].self, from: "media.json") ?? []
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

    /// 某一类下面有哪些文件夹
    func folders(_ kind: String) -> [String] {
        var names = Set(items.filter { $0.kind == kind }.map { $0.folder })
        names.remove("")
        return names.sorted()
    }

    func list(_ kind: String, folder: String) -> [MediaItem] {
        items.filter { $0.kind == kind && $0.folder == folder }
            .sorted { $0.createdAt > $1.createdAt }
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
