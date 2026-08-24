import SwiftUI
import PhotosUI

/// 相册首页。先看到的是一排文件夹，前片颜色跟着主题色走。
/// 点进去才是图片。表情包也走这套，只是格子小一点。
struct FolderGridView: View {

    let kind: String
    /// 表情包被点中时，直接把图交出去（比如发到对话里）
    var onPick: ((UIImage) -> Void)? = nil

    @ObservedObject private var store = MediaStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var creating = false
    /// 点开了哪个文件夹。用它来跳转，不用 NavigationLink 包着卡片。
    @State private var opened: String?
    @State private var newName = ""
    @State private var deletingFolder: String?
    @State private var renaming: String?
    /// 长按选中的那个文件夹，弹操作单
    @State private var acting: String?
    @State private var renameText = ""

    private var folders: [String] { store.folders(kind) }
    private var looseCount: Int { store.list(kind, folder: "").count }

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {

                // 「全部」那一格**撤了**。
                //
                // 她说：「相册里的全部原来是全部图片的意思，我一直不知道，
                // 所以希望删掉，可以改回原来的文件夹。」
                // 一个既不能删又不能改名、点进去还跟别的重复的格子，
                // 解释起来比它省下的事还多。现在只剩真的文件夹 +「未归类」。
                if looseCount > 0 {
                    folderCell(title: "未归类", count: looseCount,
                               tint: app.settings.accentColor.opacity(0.75))
                        .contentShape(Rectangle())
                        .onTapGesture { opened = "" }
                }

                ForEach(Array(folders.enumerated()), id: \.element) { index, name in
                    // 长按菜单挂在卡片本身上。挂在 NavigationLink 外面的话，
                    // 手势会被跳转吃掉，长按根本不响应。
                    folderCell(title: name,
                               count: store.list(kind, folder: name).count,
                               tint: tint(for: index))
                        .contentShape(Rectangle())
                        .onTapGesture { opened = name }
                        // 用自己的长按，不用 contextMenu——
                        // 那个跟 onTapGesture 放一起时经常识别不到
                        .onLongPressGesture(minimumDuration: 0.4) {
                            if app.settings.haptics {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            acting = name
                        }
                }

                Button {
                    newName = ""
                    creating = true
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    Theme.textMuted(scheme).opacity(0.4),
                                    style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])
                                )
                                .frame(width: 64, height: 59)
                            Image(systemName: Icon.add)
                                .font(.app(17, weight: .light))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        Text("新建")
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationDestination(item: $opened) { folder in
            MediaGridView(kind: kind, folder: folder, onPick: onPick)
        }
        .alert("改名", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("新名字", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("改好了") {
                if let old = renaming {
                    store.renameFolder(kind, from: old, to: renameText)
                }
                renaming = nil
            }
        }
        .confirmationDialog(
            "「\(acting ?? "")」",
            isPresented: Binding(get: { acting != nil },
                                 set: { if !$0 { acting = nil } }),
            titleVisibility: .visible
        ) {
            Button("改个名字") {
                renameText = acting ?? ""
                renaming = acting
                acting = nil
            }
            Button("删掉这个文件夹", role: .destructive) {
                deletingFolder = acting
                acting = nil
            }
            Button("算了", role: .cancel) { acting = nil }
        }
        .confirmationDialog(
            "删掉文件夹「\(deletingFolder ?? "")」？",
            isPresented: Binding(get: { deletingFolder != nil },
                                 set: { if !$0 { deletingFolder = nil } }),
            titleVisibility: .visible
        ) {
            Button("连里面的一起删", role: .destructive) {
                if let name = deletingFolder {
                    store.deleteFolder(kind, name: name, keepImages: false)
                }
                deletingFolder = nil
            }
            Button("仅删除文件夹，保留图片") {
                if let name = deletingFolder {
                    store.deleteFolder(kind, name: name, keepImages: true)
                }
                deletingFolder = nil
            }
            Button("算了", role: .cancel) { deletingFolder = nil }
        } message: {
            let n = deletingFolder.map { store.list(kind, folder: $0).count } ?? 0
            Text("里面有 \(n) 张。删掉就找不回来了，也可以只删文件夹、把图片退回「未归类」。")
        }
        .alert("新建文件夹", isPresented: $creating) {
            TextField("起个名字", text: $newName)
            Button("取消", role: .cancel) {}
            Button("建好了") {
                // 文件夹现在是独立存的，空的就是空的——
                // 不再往 items 里塞占位空记录（那是「空文件夹显示 1」的根）
                store.createFolder(kind, name: newName)
            }
        }
    }

    private func folderCell(title: String, count: Int, tint: Color) -> some View {
        VStack(spacing: 8) {
            FolderIcon(tint: tint, size: 68)
            VStack(spacing: 1) {
                Text(title)
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
    }

    /// 每个文件夹在主题色附近取一个略微不同的色相，整体还是一家人
    private func tint(for index: Int) -> Color {
        let base = app.settings.accentColor
        let shifts: [Double] = [0, 0.10, -0.08, 0.18, -0.15, 0.25]
        let s = shifts[index % shifts.count]
        return base.opacity(1).hueRotated(by: s)
    }
}

extension Color {
    /// 在原色基础上转一点色相，用来给多个文件夹做区分
    func hueRotated(by amount: Double) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        var nh = h + CGFloat(amount)
        if nh > 1 { nh -= 1 }
        if nh < 0 { nh += 1 }
        return Color(UIColor(hue: nh, saturation: s, brightness: b, alpha: a))
    }
}

// MARK: - 文件夹里的图片

struct MediaGridView: View {

    let kind: String
    let folder: String
    var onPick: ((UIImage) -> Void)? = nil

    @ObservedObject private var store = MediaStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var picked: [PhotosPickerItem] = []
    @State private var preview: MediaItem?
    @State private var moving: MediaItem?
    @State private var keyword = ""
    @State private var tagging = false
    @State private var taggingText = ""

    /// 「全部」是所有图，别的就是那个文件夹里的
    private var inScope: [MediaItem] {
        folder == MediaStore.allFolder
            ? store.list(kind).filter { !$0.fileName.isEmpty }
            : store.list(kind, folder: folder)
    }

    private var items: [MediaItem] {
        let base = inScope
        guard !keyword.isEmpty else { return base }
        return base.filter { $0.note.localizedCaseInsensitiveContains(keyword) }
    }

    /// 还没写关键词的表情包
    private var untagged: [MediaItem] {
        inScope.filter { $0.note.isEmpty }
    }

    private var columns: [GridItem] {
        let n = kind == "sticker" ? 4 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: n)
    }

    var body: some View {
        ScrollView {
            if kind == "sticker" {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: Icon.search)
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                        TextField("按关键词找", text: $keyword)
                            .textFieldStyle(.plain)
                            .font(.app(14))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.softFillDeep))

                    if !untagged.isEmpty {
                        Button {
                            runTagging()
                        } label: {
                            HStack(spacing: 6) {
                                if tagging { ProgressView().scaleEffect(0.7) }
                                Text(tagging ? taggingText : "有 \(untagged.count) 张还没写关键词")
                                    .font(.app(12))
                            }
                            .foregroundStyle(app.settings.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(app.settings.accentColor.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .disabled(tagging)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            if items.isEmpty {
                VStack(spacing: 10) {
                    FolderIcon(tint: app.settings.accentColor, size: 74, showPaper: false)
                        .opacity(0.5)
                    Text("这里还空着")
                        .font(.app(14))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text("点右上角放几张进来")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme).opacity(0.8))
                }
                .padding(.top, 90)
                .frame(maxWidth: .infinity)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    if let image = ImageStore.cached(item.fileName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: kind == "sticker" ? 74 : 108)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onTapGesture {
                                if let onPick { onPick(image) } else { preview = item }
                            }
                            .contextMenu {
                                if !item.note.isEmpty {
                                    Text(item.note)
                                }
                                Button {
                                    preview = item
                                } label: {
                                    Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
                                }
                                Button {
                                    moving = item
                                } label: {
                                    Label("挪到别的文件夹", systemImage: "folder")
                                }
                                Button(role: .destructive) {
                                    store.remove(item)
                                } label: {
                                    Label("删掉", systemImage: Icon.trash)
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .navigationTitle(folder == MediaStore.allFolder
                         ? "全部" : (folder.isEmpty ? "未归类" : folder))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $picked, maxSelectionCount: 30, matching: .images) {
                    Image(systemName: Icon.add)
                }
            }
        }
        .onChange(of: picked) { _, list in importPicked(list) }
        .fullScreenCover(item: $preview) { (item: MediaItem) in
            // 把这一屏能看的全给它，才翻得了页
            ImagePreviewView(items: items,
                             index: items.firstIndex(where: { $0.id == item.id }) ?? 0,
                             store: store)
        }
        .confirmationDialog("挪到哪儿", isPresented: Binding(
            get: { moving != nil },
            set: { if !$0 { moving = nil } }
        )) {
            ForEach(store.folders(kind), id: \.self) { name in
                if name != folder {
                    Button(name) {
                        if let m = moving { store.move(m, to: name) }
                        moving = nil
                    }
                }
            }
            if !folder.isEmpty && folder != MediaStore.allFolder {
                Button("拿出来") {
                    if let m = moving { store.move(m, to: "") }
                    moving = nil
                }
            }
            Button("算了", role: .cancel) { moving = nil }
        }
    }

    /// 悄悄请他看一眼新表情，写几个关键词。
    /// 不在对话里留任何痕迹，只有这条进度显示给你看。
    private func runTagging() {
        let todo = untagged
        guard !todo.isEmpty else { return }
        tagging = true
        taggingText = "在看了…"
        Task {
            await app.tagStickers(todo) { done, total in
                Task { @MainActor in
                    taggingText = done >= total ? "写好了" : "在看第 \(done + 1) 张，共 \(total) 张"
                }
            }
            await MainActor.run {
                tagging = false
                taggingText = ""
            }
        }
    }

    private func importPicked(_ list: [PhotosPickerItem]) {
        guard !list.isEmpty else { return }
        Task {
            for p in list {
                if let data = try? await p.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    // 在「全部」里加图 = 加到未归类（「全部」不是个能装东西的地方）
                    let dest = folder == MediaStore.allFolder ? "" : folder
                    await MainActor.run { store.add(image, kind: kind, folder: dest) }
                }
            }
            await MainActor.run { picked = [] }
        }
    }
}
