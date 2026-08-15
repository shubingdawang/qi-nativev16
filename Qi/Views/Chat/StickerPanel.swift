import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 输入框上方弹出来的表情面板。只显示我的表情，
/// 点一下进"待发送"，不会直接飞出去——文档里第一条常见坑就是这个。
struct StickerPanel: View {

    /// 挑中了哪一张
    var onPick: (Sticker) -> Void

    @ObservedObject private var store = StickerStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var keyword = ""
    @State private var importing = false
    @State private var picking: [PhotosPickerItem] = []
    @State private var editing: Sticker?

    private var list: [Sticker] {
        store.list(owner: "user", keyword: keyword).filter { $0.ready }
    }
    private var drafts: [Sticker] {
        store.list(owner: "user").filter { !$0.ready }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 10) {

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: Icon.search)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    TextField("按名字或情绪找", text: $keyword)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.softFillDeep))

                Menu {
                    Button {
                        importing = true
                    } label: {
                        Label("从文件（GIF / WebP）", systemImage: "doc")
                    }
                    Button {
                        // 用 PhotosPicker 挑静态图
                    } label: {
                        Label("从相册", systemImage: Icon.gallery)
                    }
                } label: {
                    Image(systemName: Icon.add)
                        .font(.system(size: 16))
                        .foregroundStyle(app.settings.accentColor)
                        .frame(width: 34, height: 34)
                }
            }

            if !drafts.isEmpty {
                Button {
                    editing = drafts.first
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11))
                        Text("有 \(drafts.count) 张还没写描述，写完才能发")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }

            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: Icon.sticker)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(app.settings.accentColor.opacity(0.5))
                    Text(keyword.isEmpty ? "还没有表情" : "没找到")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(list) { sticker in
                            Button {
                                if app.settings.haptics {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                onPick(sticker)
                            } label: {
                                StickerImage(sticker: sticker, size: 60)
                                    // 固定行高，不让图片原始宽高参与计算
                                    .frame(height: 68)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Text(sticker.name)
                                Button {
                                    editing = sticker
                                } label: {
                                    Label("改描述", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    store.remove(sticker)
                                } label: {
                                    Label("删掉", systemImage: Icon.trash)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 210)
            }
        }
        .padding(12)
        .glassBackground(radius: 22, strength: app.settings.glassOpacity)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType.gif, UTType.webP, UTType.png, UTType.jpeg],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for u in urls {
                let stop = u.startAccessingSecurityScopedResource()
                defer { if stop { u.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: u) else { continue }
                let ext = u.pathExtension.isEmpty ? "gif" : u.pathExtension.lowercased()
                if let made = store.add(data: data, ext: ext, owner: "user") {
                    var s = made
                    s.name = u.deletingPathExtension().lastPathComponent
                    store.update(s)
                    editing = s
                }
            }
        }
        .sheet(item: $editing) { sticker in
            StickerEditorView(sticker: sticker)
        }
    }
}

// MARK: - 填名称、描述、标签

struct StickerEditorView: View {

    @State var sticker: Sticker
    @ObservedObject private var store = StickerStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var tagText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        HStack {
                            Spacer()
                            StickerImage(sticker: sticker, size: 128)
                            Spacer()
                        }
                        .padding(.vertical, 8)

                        field("名称", "简短的一个词，比如「被窝刷牙」") {
                            TextField("", text: $sticker.name)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("画面描述")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            TextField("一个角色躺在蓝色被窝里刷牙，身体轻轻晃动。",
                                      text: $sticker.description, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                            Text("这是他理解这张表情的全部依据。写画面里有什么、在做什么动作，不用写好不好看。没有描述的表情，对他来说就是一张看不懂的图。")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        field("情绪标签", "一到五个词，顿号或逗号隔开") {
                            TextField("困、睡前、软乎乎", text: $tagText)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("归谁")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            Picker("", selection: $sticker.owner) {
                                Text(app.settings.userName.isEmpty ? "我的" : app.settings.userName + "的")
                                    .tag("user")
                                Text((app.settings.aiName.isEmpty ? "他" : app.settings.aiName) + "的")
                                    .tag("assistant")
                            }
                            .pickerStyle(.segmented)
                            Text("放进他的库，他才能在聊天里主动发。你只能发自己库里的。")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(sticker.name.isEmpty ? "新表情" : sticker.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        sticker.tags = tagText
                            .components(separatedBy: CharacterSet(charactersIn: "、,，/ "))
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        store.update(sticker)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    // 描述没填就不让存——文档里明说了不要让人跳过描述
                    .disabled(sticker.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || sticker.description.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        store.remove(sticker)
                        dismiss()
                    } label: {
                        Text("删掉这张").foregroundStyle(.red)
                    }
                }
            }
            .onAppear { tagText = sticker.tags.joined(separator: "、") }
        }
    }

    @ViewBuilder
    private func field<C: View>(_ title: String, _ hint: String,
                                @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            content()
                .textFieldStyle(.plain)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted(scheme))
        }
    }
}
