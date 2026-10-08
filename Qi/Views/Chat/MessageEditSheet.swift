import SwiftUI
import PhotosUI

/// 改一条消息：文字，**和图**。
///
/// 她报的：「我的消息长按编辑，没法在没有图片的句子上加上图片，也没法删掉图片。」
/// 以前这一页只有一个文本框，图是改不了的。
///
/// ⚠️ 单独成一个 View，别写回 `ChatView` 的 `.sheet` 闭包里：
/// 那儿在 `body` 里面，再塞一排图和一个选图器，类型检查就会超时
/// （CI 报过好几次 unable to type-check in reasonable time）。
struct MessageEditSheet: View {

    let message: ChatMessage
    let conversationID: UUID?
    var onClose: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var text = ""
    @State private var images: [String] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var loadingPicks = false

    /// 一条消息最多挂几张（跟聊天里一次能选的上限一样）
    private let maxImages = 20

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TextEditor(text: $text)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: app.settings.fontSize))
                            .frame(minHeight: 160)
                            .padding(12)
                            .glassCard(padding: 0)
                        if !mentionNames.isEmpty { mentionRow }
                        if message.role == .user { imageStrip }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) { saveButtons }
            }
        }
        .onAppear {
            text = message.content
            images = message.imageNames
        }
        .onChange(of: picks) { _, items in load(items) }
    }

    // MARK: @

    /// 群里能点的名字：他（不在成员里时）+ 各位成员
    private var mentionNames: [String] {
        guard let id = conversationID, let conv = app.conversation(id), conv.isGroup else { return [] }
        let him = app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName
        var names = conv.activeMembers.map(\.name).filter { !$0.isEmpty }
        if !names.contains(him) { names.insert(him, at: 0) }
        return names
    }

    private var mentionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mentionNames, id: \.self) { name in
                    Button { insertMention(name) } label: {
                        Text("@" + name)
                            .font(.app(13))
                            .foregroundStyle(Theme.textMain(scheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// 末尾已经打了一个「@」就补全它，不然接在末尾
    private func insertMention(_ name: String) {
        if text.hasSuffix("@") || text.hasSuffix("＠") {
            text = String(text.dropLast()) + "@" + name + " "
        } else {
            let sep = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
            text += sep + "@" + name + " "
        }
    }

    // MARK: 图

    /// 一排缩略图：每张右上角一个叉，最后是一个「＋」。
    private var imageStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(images.isEmpty ? "图片" : "图片 \(images.count)")
                .font(.app(12))
                .foregroundStyle(Theme.textMuted(scheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(images, id: \.self) { name in thumb(name) }
                    if images.count < maxImages { addButton }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .glassCard(padding: 0)
    }

    private func thumb(_ name: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = ImageStore.cached(name) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    images.removeAll { $0 == name }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(3)
        }
    }

    private var addButton: some View {
        PhotosPicker(selection: $picks,
                     maxSelectionCount: max(1, maxImages - images.count),
                     matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.softFillDeep)
                if loadingPicks {
                    ProgressView()
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .frame(width: 72, height: 72)
        }
    }

    /// 选好的图读出来、存进本机图库，名字接到这一排后面
    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingPicks = true
        Task { @MainActor in
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let name = ImageStore.save(img),
                   images.count < maxImages {
                    images.append(name)
                }
            }
            picks = []
            loadingPicks = false
        }
    }

    // MARK: 存

    @ViewBuilder
    private var saveButtons: some View {
        HStack(spacing: 14) {
            Button("存着") {
                save()
                onClose()
            }
            // 改自己那条的时候多一个「改完重发」（见原来那段注释：
            // 有时候她只是想改个错字，不想再花一次钱重跑一轮，所以两个都留着）
            if message.role == .user {
                Button("改完重发") {
                    save()
                    if let id = conversationID { app.retry(message.id, in: id) }
                    onClose()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private func save() {
        guard let id = conversationID else { return }
        app.editMessage(message.id, in: id, text: text,
                        images: images == message.imageNames ? nil : images)
    }
}
