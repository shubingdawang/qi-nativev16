import SwiftUI

/// 从右边滑出来的抽屉，跟原来网页版一样。
/// 里面是这个区域的对话列表，能新建、置顶、删除、搜索。
struct ChatDrawer: View {

    let space: ChatSpace
    @Binding var isOpen: Bool
    var onEditPrompt: () -> Void = {}
    var onOpenSearch: () -> Void = {}
    var onOpenGroup: () -> Void = {}
    var onOpenMemoryLink: () -> Void = {}

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    @State private var dragX: CGFloat = 0

    /// 普通对话。群聊不在这儿——它单独钉在最上面那一格。
    private var list: [Conversation] {
        let all = app.conversations(in: space).filter { !$0.isGroup }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(search)
            || $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    private var group: Conversation? {
        app.conversations.first { $0.isGroup && $0.space == space.rawValue }
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.84, 340)

            // 关键：关上的时候整个面板从视图树里拿掉，
            // 而不是用位移把它推到屏幕外面——推的距离一旦算不准，
            // 就会留一条挂在边上，看起来像"永远开着"。
            ZStack(alignment: .trailing) {
                if isOpen {
                    Color.black.opacity(0.26)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .transition(.opacity)

                    panel(width: width)
                        .frame(width: width)
                        .offset(x: max(0, dragX))
                        .transition(.move(edge: .trailing))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.width > 0 { dragX = value.translation.width }
                                }
                                .onEnded { value in
                                    if value.translation.width > width * 0.3
                                        || value.predictedEndTranslation.width > width * 0.6 {
                                        close()
                                    }
                                    dragX = 0
                                }
                        )
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isOpen)
        }
        // 上下都要顶到屏幕边。只 ignore 底部的话，
        // 顶上会留一条跟着壁纸变色的白边，抽屉像是短了一截。
        .ignoresSafeArea()
        .allowsHitTesting(isOpen)
    }

    private func close() {
        dragX = 0
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { isOpen = false }
    }

    // MARK: 面板

    private func panel(width: CGFloat) -> some View {
        VStack(spacing: 0) {

            HStack {
                Text(space == .chat ? "絮语" : "工坊")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                // 只剩「新对话」了。群聊不再是能新建的东西——
                // 它是钉在下面那一格里的常驻位置，永远只有那一个。
                Button {
                    app.newConversation(in: space)
                    search = ""
                    close()
                } label: {
                    Image(systemName: Icon.compose)
                        .font(.system(size: 16))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 16)
            // 抽屉自己铺到状态栏底下了，顶上这段留白得自己补出来
            .padding(.top, 58)
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
                TextField("搜索对话", text: $search)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.softFillDeep))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {

                    // 群聊永远在这个位置。搜也搜不走、删也删不掉——
                    // 它不是一条对话记录，是一个固定的去处。
                    if space == .chat {
                        sectionTitle("协作")
                        groupRow
                            .padding(.bottom, 6)
                        sectionTitle("对话")
                    }

                    ForEach(list) { conv in
                        row(conv)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }

            Divider().opacity(0.4)

            // 「群成员」那一项删了。群里固定就是阿晏和工坊两位，
            // 加别的模型进来没有意义——它在这个群里没有记忆，谁都不是。

            Button {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onOpenMemoryLink() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                    Text("记忆合并")
                    Spacer()
                    if let id = app.activeID(for: space) {
                        let n = app.memoryPeers(of: id).count
                        if n > 0 {
                            Text("\(n)")
                                .font(.system(size: 11))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(app.settings.accentColor.opacity(0.25)))
                        }
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSoft(scheme))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Button {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onOpenSearch() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: Icon.search)
                    Text("聊天记录")
                    Spacer()
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSoft(scheme))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Button {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onEditPrompt() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.badge.star")
                    Text("这个对话的设定")
                    Spacer()
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSoft(scheme))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            // 底下也铺到边了，给 home indicator 让出位置
            .padding(.bottom, 42)
        }
        .background {
            GlassSurface(radius: 0, strength: app.settings.glassOpacity, extra: 0.25)
                .ignoresSafeArea()
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.cardStroke(scheme))
                .frame(width: 1)
                .ignoresSafeArea()
        }
        .shadow(color: Theme.shadow(scheme), radius: 20, x: -6, y: 0)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textMuted(scheme))
            .padding(.leading, 6)
            .padding(.top, 2)
    }

    /// 钉在最上面那一格：群聊。点一下就进去，没有就现建一个。
    private var groupRow: some View {
        let isActive = group?.id == app.activeID(for: space)
        return Button {
            app.openGroup(in: space)
            close()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(app.settings.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("群聊")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(group?.messages.isEmpty == false ? (group?.preview ?? "") : "协作者共同空间")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive
                          ? app.settings.accentColor.opacity(0.10)
                          : Theme.softFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(app.settings.accentColor.opacity(isActive ? 0.35 : 0),
                                          lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                // 先切过去再开设置面板——那个面板改的是"当前这个窗口"，
                // 不先切的话改到的是刚才那条普通对话
                app.openGroup(in: space)
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onOpenGroup() }
            } label: {
                Label("群成员", systemImage: "person.2")
            }
            Button(role: .destructive) {
                if let id = group?.id { app.clearMessages(id) }
            } label: {
                Label("清空这个群", systemImage: "trash")
            }
        }
    }

    /// 挂在对话标题后面的一小截状态：一个点 + 一句他在干嘛。
    @ViewBuilder
    private func presenceTail(_ conv: Conversation) -> some View {
        let state = app.presence(in: conv.id)
        HStack(spacing: 4) {
            Circle()
                .fill(state.busy ? app.settings.accentColor : Color.green.opacity(0.85))
                .frame(width: 5, height: 5)
            Text(state.text)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted(scheme))
                .lineLimit(1)
        }
        .fixedSize()
    }

    private func row(_ conv: Conversation) -> some View {
        let isActive = conv.id == app.activeID(for: space)
        return Button {
            app.setActive(conv.id, for: space)
            close()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(conv.title)
                            .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(Theme.textMain(scheme))
                            .lineLimit(1)
                        // 他在不在、在干嘛，就挂在标题后面。
                        // 不给外框——加了框就变成一枚标签，抢戏。
                        if space == .chat {
                            presenceTail(conv)
                        }
                    }
                    Text(conv.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 选中的那条以前用主色 0.18 铺底，配上「家」那套的褐主色
                // 就是一块发黑的板。改成很淡的一层 + 一道边，
                // 看得出选中，又不压着字。
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive
                          ? app.settings.accentColor.opacity(0.10)
                          : Theme.softFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(app.settings.accentColor.opacity(isActive ? 0.35 : 0),
                                          lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                if let i = app.index(of: conv.id) {
                    app.conversations[i].pinned.toggle()
                }
            } label: {
                Label(conv.pinned ? "取消置顶" : "置顶", systemImage: "pin")
            }
            Button(role: .destructive) {
                app.deleteConversation(conv.id)
                app.ensureActive(in: space)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
