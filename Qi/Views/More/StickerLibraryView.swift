import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 相册。顶上三段切换，跟聊天记录那页一个用法：
/// 图片（按文件夹放的那些）、表情包（静态的）、GIF（会动的）。
///
/// 只有你能往库里加东西，加的时候写名称和描述、选归谁。
/// 他只能发，不能加、不能改、不能删。
struct StickerLibraryView: View {

    @ObservedObject private var store = StickerStore.shared
    @ObservedObject private var media = MediaStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var tab = 0                // 0 图片，1 表情包，2 GIF
    @State private var owner = "user"
    @State private var keyword = ""
    @State private var importing = false
    @State private var picking: [PhotosPickerItem] = []
    /// GIF 那一栏点「从相册」时开的选择器
    @State private var pickingAnimated = false
    @State private var editing: Sticker?
    /// 正在让他写关键词
    @State private var tagging = false
    @State private var tagNote: String?

    private var list: [Sticker] {
        store.list(owner: owner, keyword: keyword)
            .filter { tab == 2 ? $0.animated : !$0.animated }
    }

    /// 还缺关键词的静图。**只算静图**——会动的她自己写。
    private var needTagging: [Sticker] {
        store.list(owner: owner, keyword: "")
            .filter { !$0.animated && !$0.fileName.isEmpty
                      && ($0.tags.isEmpty || $0.description.isEmpty) }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 0) {

            Picker("", selection: $tab) {
                Text("图片").tag(0)
                Text("表情包").tag(1)
                Text("GIF").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)

            if tab == 0 {
                FolderGridView(kind: "photo")
            } else {
                stickerSide
            }
        }
        .navigationTitle("相册")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { s in
            StickerEditorView(sticker: s)
        }
        .alert("写关键词", isPresented: Binding(
            get: { tagNote != nil }, set: { if !$0 { tagNote = nil } }
        )) {
            Button("好") { tagNote = nil }
        } message: {
            Text(tagNote ?? "")
        }
    }

    // MARK: 表情那一侧

    private var stickerSide: some View {
        VStack(spacing: 10) {

            Picker("", selection: $owner) {
                Text(app.settings.userName.isEmpty ? "我的" : app.settings.userName + "的").tag("user")
                Text((app.settings.aiName.isEmpty ? "他" : app.settings.aiName) + "的").tag("assistant")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: Icon.search)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    TextField("按名字或情绪找", text: $keyword)
                        .textFieldStyle(.plain)
                        .font(.app(13))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.softFillDeep))

                // GIF 也从相册选。存在相册里的动图，原来只能走「文件」
                // 那条路，等于先导出再导入，绕一大圈。
                // 「从文件」留着，因为有些 GIF 确实只在文件 App 里。
                if tab == 2 {
                    Menu {
                        Button {
                            pickingAnimated = true
                        } label: {
                            Label("从相册", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            importing = true
                        } label: {
                            Label("从文件", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: Icon.add)
                            .font(.app(16))
                            .foregroundStyle(app.settings.accentColor)
                            .frame(width: 32, height: 32)
                    }
                } else {
                    // 让他给静图写关键词。**只在「表情包」那一栏给**——
                    // 她说的：「仅限图片表情包，gif 那边我给他写」。
                    // 会动的他只看得见第一帧，写出来经常离题。
                    if tab == 1, !needTagging.isEmpty {
                        Button {
                            guard !tagging else { return }
                            tagging = true
                            let batch = needTagging
                            Task {
                                let n = await app.tagStickerLibrary(batch)
                                tagging = false
                                tagNote = n > 0
                                    ? "他看完写好了 \(n) 张。"
                                    : "一张都没写成——检查一下模型是不是能看图。"
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if tagging {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(.app(15))
                                }
                                Text(tagging ? "写着呢…" : "让他写词 \(needTagging.count)")
                                    .font(.app(12))
                            }
                            .foregroundStyle(app.settings.accentColor)
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                        }
                        .buttonStyle(.plain)
                        .disabled(tagging)
                    }
                    let tint = app.settings.accentColor
                    PhotosPicker(selection: $picking, maxSelectionCount: 20, matching: .images) {
                        Image(systemName: Icon.add)
                            .font(.app(16))
                            .foregroundStyle(tint)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            ScrollView {
                if list.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: Icon.sticker)
                            .font(.app(30, weight: .light))
                            .foregroundStyle(app.settings.accentColor.opacity(0.5))
                        Text(emptyText)
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(list) { sticker in
                        VStack(spacing: 4) {
                            StickerImage(sticker: sticker, size: 62)
                                .frame(height: 68)
                            Text(sticker.name.isEmpty ? "没名字" : sticker.name)
                                .font(.app(10))
                                .foregroundStyle(sticker.ready
                                                 ? Theme.textMuted(scheme)
                                                 : Color.orange)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = sticker }
                        .contextMenu {
                            if !sticker.description.isEmpty {
                                Text(sticker.description)
                            }
                            Button {
                                editing = sticker
                            } label: {
                                Label("改描述", systemImage: "pencil")
                            }
                            Button {
                                var s = sticker
                                s.owner = s.owner == "user" ? "assistant" : "user"
                                store.update(s)
                            } label: {
                                Label(sticker.owner == "user" ? "挪给他" : "挪回我这",
                                      systemImage: "arrow.left.arrow.right")
                            }
                            Button(role: .destructive) {
                                store.remove(sticker)
                            } label: {
                                Label("删掉", systemImage: Icon.trash)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType.gif, UTType.webP],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for u in urls {
                let stop = u.startAccessingSecurityScopedResource()
                defer { if stop { u.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: u) else { continue }
                let ext = u.pathExtension.isEmpty ? "gif" : u.pathExtension.lowercased()
                if var made = store.add(data: data, ext: ext, owner: owner) {
                    made.name = u.deletingPathExtension().lastPathComponent
                    store.update(made)
                    editing = made
                }
            }
        }
        .photosPicker(isPresented: $pickingAnimated, selection: $picking,
                      maxSelectionCount: 20, matching: .images)
        .onChange(of: picking) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for p in items {
                    guard let data = try? await p.loadTransferable(type: Data.self) else { continue }
                    // 照原样存。相册里的 GIF 拿到的就是原始字节，
                    // **不能当 png 存**——一转就只剩第一帧，动不起来了。
                    let ext = Self.guessExt(data)
                    await MainActor.run {
                        if let made = store.add(data: data, ext: ext, owner: owner) {
                            editing = made
                        }
                    }
                }
                await MainActor.run { picking = [] }
            }
        }
    }

    /// 看头几个字节判断这是什么图。
    /// 相册给回来的是原始字节，GIF 就得按 gif 存，转成 png 只剩第一帧。
    static func guessExt(_ data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        if head.count >= 3, head[0] == 0x47, head[1] == 0x49, head[2] == 0x46 { return "gif" }
        if head.count >= 12,
           head[0] == 0x52, head[1] == 0x49, head[2] == 0x46, head[3] == 0x46,
           head[8] == 0x57, head[9] == 0x45, head[10] == 0x42, head[11] == 0x50 { return "webp" }
        if head.count >= 8, head[0] == 0x89, head[1] == 0x50 { return "png" }
        if head.count >= 3, head[0] == 0xFF, head[1] == 0xD8 { return "jpg" }
        return "png"
    }

    private var emptyText: String {
        if !keyword.isEmpty { return "没找到" }
        if owner == "assistant" {
            return "他这儿还没有表情。\n加进来的表情他才能在聊天里主动发。"
        }
        return tab == 2 ? "还没有会动的表情\n点右上角从文件里选 GIF 或 WebP" : "还没有表情\n点右上角从相册选"
    }
}
