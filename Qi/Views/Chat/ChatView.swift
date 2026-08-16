import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {

    let space: ChatSpace
    let title: String
    /// 工坊只有一个固定窗口，用不上对话列表和左侧边栏
    var showsDrawer: Bool = true
    var showsSideMenu: Bool = true

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var keyboard = KeyboardWatcher.shared
    // 必须真的**订阅** CallStore，不能只是 CallStore.shared 这样读一下。
    // 只读不订阅的话，他打过来／挂断的时候 SwiftUI 根本不知道要重画，
    // 要等下一次别的什么状态变了才顺带刷出来——看起来就是"打电话有延迟"。
    @ObservedObject private var calls = CallStore.shared

    @State private var drawerOpen = false
    @State private var sideOpen = false
    @State private var destination: SideMenuItem?
    @State private var showingModelPicker = false
    @State private var showingSystemPrompt = false
    @State private var showingSearch = false
    @State private var showingTools = false
    @State private var draft = ""
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pendingImages: [UIImage] = []
    @State private var pendingFiles: [FileAttachment] = []
    @State private var importingFile = false
    @State private var showingPhotos = false
    @State private var stickerPanelOpen = false
    @State private var pendingSticker: Sticker?
    @StateObject private var recorder = VoiceRecorder()
    @State private var listening = false
    @State private var transcribing = false
    /// 刚录好、还没发出去的那段语音（存在 Voices 里的文件名）
    @State private var pendingVoice: String?
    /// 光标前面刚打了个 @，正等着挑人
    @State private var mentioning = false
    @State private var notice: String?
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var shareImage: ShareImage?
    @State private var quoting: ChatMessage?
    @State private var menuOpenID: UUID?
    @State private var editingMessage: ChatMessage?
    @State private var editText = ""
    @State private var reading: ChatMessage?
    @State private var browsing: BrowserLink?
    @State private var travelling: Journey?
    @State private var showingGroup = false
    @State private var showingMemoryLink = false

    private var activeConversation: Conversation? {
        app.conversation(app.activeID(for: space))
    }

    private var isRunning: Bool {
        guard let id = activeConversation?.id else { return false }
        return app.runningConversationIDs.contains(id)
    }

    /// 正攒着话、还没交出去
    private var waiting: Bool {
        app.isWaiting(activeConversation?.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {

            VStack(spacing: 0) {
                if let conv = activeConversation {
                    MessageListView(
                        conversation: conv,
                        space: space,
                        selecting: selecting,
                        selected: selected,
                        onToggle: { id in
                            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                            if !selecting { selecting = true }
                        },
                        onQuote: { msg in
                            quoting = msg
                        },
                        onChoice: { text in
                            // 点了哪个，那句话就当成她说的发出去，
                            // 同时把那张卡标成"已选"，免得回头还能再点一次
                            guard let conv = activeConversation else { return }
                            if let i = app.index(of: conv.id),
                               let mi = app.conversations[i].messages.lastIndex(where: {
                                   !$0.choices.isEmpty && $0.chosenOption.isEmpty
                               }) {
                                app.conversations[i].messages[mi].chosenOption = text
                            }
                            app.send(text: text, images: [], in: conv.id)
                        },
                        onSpeak: { msg in
                            guard let id = app.activeID(for: space) else { return }
                            Task {
                                if let err = await app.speak(msg.id, in: id) {
                                    notice = err
                                }
                            }
                        },
                        onOpenReader: { msg in
                            reading = msg
                        },
                        onOpenJourney: { j in
                            travelling = j
                        },
                        menuOpenID: menuOpenID,
                        onOpenMenu: { id in
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                menuOpenID = id
                            }
                        },
                        onCloseMenu: {
                            withAnimation(.easeOut(duration: 0.15)) { menuOpenID = nil }
                        },
                        onEdit: { msg in
                            editText = msg.content
                            editingMessage = msg
                        },
                        onMention: { name in
                            // insertMention 是原来给候选条用的，直接复用：
                            // 光标前有 @ 就替换掉，没有就补一个
                            if draft.hasSuffix("@") {
                                insertMention(name)
                            } else {
                                draft += (draft.isEmpty || draft.hasSuffix(" ") ? "" : " ")
                                    + "@" + name + " "
                            }
                        },
                        running: app.runningConversationIDs.contains(conv.id)
                    )
                    if selecting {
                        selectionBar(conv)
                    } else {
                        VStack(spacing: 0) {
                            // clawd 不再钉在这儿了——它现在满屏走，
                            // 挂在整页的最上面一层（见下面那个 ClawdRoamer）
                            VStack(spacing: 8) {
                            if stickerPanelOpen {
                                StickerPanel { sticker in
                                    // 选中只是进"待发送"，不会直接飞出去
                                    pendingSticker = sticker
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        stickerPanelOpen = false
                                    }
                                }
                                .padding(.horizontal, 12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            inputBar(conv)
                            }
                        }
                    }
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            // 窗口标题不在这儿了——它在右边三杠点进去的那个列表里。
            // 聊天页顶上留白，什么都不放，让内容自己往上顶。
            VStack(spacing: 6) {
                ListeningBar()
                    .padding(.horizontal, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 整页铺到状态栏底下了，这段留白自己补
            .padding(.top, 52)
            .animation(.spring(response: 0.3, dampingFraction: 0.85),
                       value: MusicPlayer.shared.current?.id)

            // 右上角那个抽屉把手，跟原来一样
            if showsDrawer {
            Button {
                hideKeyboard()
                drawerOpen = true
            } label: {
                VStack(spacing: 5) {
                    Capsule().frame(width: 20, height: 1.8)
                    Capsule().frame(width: 20, height: 1.8)
                    Capsule().frame(width: 20, height: 1.8)
                }
                .foregroundStyle(Theme.textSoft(scheme))
                .frame(width: 44, height: 44, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .padding(.top, 44)
            }

            if showsDrawer {
            ChatDrawer(space: space, isOpen: $drawerOpen,
                       onEditPrompt: { showingSystemPrompt = true },
                       onOpenSearch: { showingSearch = true },
                       onOpenGroup: { showingGroup = true },
                       onOpenMemoryLink: { showingMemoryLink = true })
            }

            // 菜单开着的时候，点别处就把它关掉
            if menuOpenID != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { menuOpenID = nil }
                    }
            }

            // 他打过来了：卡片压在所有东西上面
            if let incoming = calls.incoming {
                VStack {
                    IncomingCallView(
                        call: incoming,
                        onAnswer: { CallStore.shared.answer() },
                        onDecline: {
                            CallStore.shared.decline()
                            // 他该知道你没接——这事不该悄无声息
                            if let id = app.activeID(for: space), let i = app.index(of: id) {
                                var msg = ChatMessage(role: .user)
                                msg.content = "（她没接你的电话）"
                                app.conversations[i].messages.append(msg)
                            }
                        })
                    Spacer()
                }
                .padding(.top, 8)
                .zIndex(99)
            }

            // clawd 在整页上溜达。挂在这一层是因为它得能走到任何地方，
            // 又不能挡住底下的气泡——它自己那一小块接触摸，别处一律放过去。
            if space == .chat, let conv = activeConversation {
                let state = app.presence(in: conv.id)
                ClawdRoamer(busy: state.busy, activity: state.text)
                    .allowsHitTesting(menuOpenID == nil && !selecting)
            }

            // 置顶的备忘挂在最上面一层。
            // 之前夹在中间，被后面那些铺满屏幕的层盖住了，
            // 所以絮语页看不见、工坊（没有那些层）反而看得见。
            if !MemoStore.shared.pinned.isEmpty {
                MemoFloatingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // 从左边缘往右拉，拖出左侧边栏。
        //
        // 以前是在左边压一条 22 宽的透明条来接这个手势，两个毛病：
        // 太窄，手指偏一点就滑不出来；而且那条会把点击一起吃掉，
        // 压在它底下的气泡左半边长按不动。
        // 现在改成整页一个 simultaneous 手势，只看**起手位置**在不在左边缘——
        // 感应范围宽了一倍，也不再抢别人的点击。
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { v in
                    guard showsSideMenu, !sideOpen, !drawerOpen else { return }
                    // 屏幕左边**三分之一**起手都算。再窄下去就总是滑不出来。
                    guard v.startLocation.x < 140 else { return }
                    guard v.translation.width > 28
                            || v.predictedEndTranslation.width > 60 else { return }
                    // 竖着划的不算，那是在翻聊天记录
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    hideKeyboard()
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        sideOpen = true
                    }
                }
        )
        .onAppear {
            app.ensureActive(in: space)
            if space == .chat { app.isChatVisible = true }
        }
        .onDisappear {
            if space == .chat { app.isChatVisible = false }
        }
        .onChange(of: pickedItems) { _, items in loadPicked(items) }
        .sheet(isPresented: $showingModelPicker) { ModelPickerView(space: space) }
        .sheet(isPresented: $showingSystemPrompt) { SystemPromptView(space: space) }
        .sheet(isPresented: $showingTools) { ToolToggleView() }
        .sheet(isPresented: $showingMemoryLink) {
            if let id = app.activeID(for: space) {
                MemoryLinkView(space: space, conversationID: id)
            }
        }
        .sheet(isPresented: $showingGroup) {
            if let id = app.activeID(for: space) {
                GroupSetupView(conversationID: id)
            }
        }
        .sheet(isPresented: $showingSearch) {
            ChatSearchView(space: space) { id in
                app.setActive(id, for: space)
            }
        }
        .sheet(item: $destination) { item in
            SideMenuDestination(item: item)
        }
        .sheet(item: $shareImage) { item in
            ShareSheet(items: [item.image])
        }
        .photosPicker(isPresented: $showingPhotos, selection: $pickedItems,
                      maxSelectionCount: 6, matching: .images)
        .fileImporter(isPresented: $importingFile,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for u in urls {
                    if let item = FileStore.importFile(from: u) {
                        pendingFiles.append(item)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { calls.active != nil },
            set: { if !$0 && calls.active != nil { calls.hangUp(by: "me") } }
        )) {
            CallView()
        }
        .fullScreenCover(item: $travelling) { j in
            JourneyPlayerView(journey: j)
        }
        .fullScreenCover(item: $reading) { msg in
            MessageReaderView(
                message: msg,
                senderName: msg.role == .user
                    ? (app.settings.userName.isEmpty ? "我" : app.settings.userName)
                    : (msg.senderName.isEmpty ? app.settings.aiName : msg.senderName)
            )
        }
        .sheet(item: $browsing) { link in
            InAppBrowser(url: link.url)
                .ignoresSafeArea()
        }
        .environment(\.openURL, OpenURLAction { url in
            // 聊天里点链接就在 App 里开，不跳出去
            browsing = BrowserLink(url: url)
            return .handled
        })
        .sheet(item: $editingMessage) { msg in
            NavigationStack {
                ZStack {
                    WallpaperBackground()
                    VStack {
                        TextEditor(text: $editText)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: app.settings.fontSize))
                            .padding(12)
                            .glassCard(padding: 0)
                            .padding(16)
                        Spacer()
                    }
                }
                .navigationTitle("改一句")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { editingMessage = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            if let id = app.activeID(for: space) {
                                app.editMessage(msg.id, in: id, text: editText)
                            }
                            editingMessage = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("好") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        // 侧栏垫在整页下面。工坊那边 sideOpen 永远打不开，等于没有。
        .sideMenuShell(isOpen: $sideOpen) { item in
            destination = item
        }
    }

    // MARK: 输入栏

    @ViewBuilder
    private func inputBar(_ conv: Conversation) -> some View {
        VStack(spacing: 8) {

            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Button {
                                    pendingImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .padding(2)
                            }
                        }
                    }
                }
                .frame(height: 58)
            }

            // 打了 @ 就把群里的人列出来，点一下补进去
            if let conv = activeConversation, conv.isGroup, mentioning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(conv.activeMembers) { m in
                            Button {
                                insertMention(m.name)
                            } label: {
                                Text("@" + (m.name.isEmpty ? "没起名" : m.name))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMain(scheme))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(app.settings.accentColor.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 34)
            }

            if listening {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 7, height: 7)
                    Text(listeningHint)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.softFillDeep))
            }

            // 刚录好还没发的那段。点左边听一遍，点叉扔掉。
            if let v = pendingVoice {
                HStack(spacing: 10) {
                    Button {
                        VoicePlayer.shared.toggle(v)
                    } label: {
                        Image(systemName: VoicePlayer.shared.playingName == v
                              ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("语音 \(Int(VoiceStore.duration(v)))″")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        Text("跟文字一起发出去")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Spacer(minLength: 0)
                    Button {
                        VoiceStore.delete(v)
                        pendingVoice = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.softFillDeep))
            }

            if let s = pendingSticker {
                HStack(spacing: 8) {
                    StickerImage(sticker: s, size: 46)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        Text("跟文字一起发出去")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Spacer(minLength: 0)
                    Button {
                        pendingSticker = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.softFillDeep))
            }

            if !pendingFiles.isEmpty {
                VStack(spacing: 6) {
                    ForEach(pendingFiles) { f in
                        HStack(spacing: 8) {
                            Image(systemName: f.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(app.settings.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.displayName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMain(scheme))
                                    .lineLimit(1)
                                Text(f.unreadable ? "\(f.sizeText) · 读不出文字" : "\(f.sizeText) · 已读出内容")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            Spacer(minLength: 0)
                            Button {
                                FileStore.delete(f)
                                pendingFiles.removeAll { $0.id == f.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.softFillDeep))
                    }
                }
            }

            // 攒着话的时候得给个说法，不然看着像发出去了他却不理你
            if waiting {
                HStack(spacing: 7) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11))
                        .foregroundStyle(app.settings.accentColor)
                    Text("攒着呢，你不说了 \(Int(app.settings.segmentUserDelay)) 秒之后一起发。长按发送键马上发。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.softFillDeep))
            }

            if let q = quoting {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(app.settings.accentColor.opacity(0.6))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(q.role == .user
                             ? (app.settings.userName.isEmpty ? "我" : app.settings.userName)
                             : (q.senderName.isEmpty ? app.settings.aiName : q.senderName))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text(q.content)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        quoting = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.softFillDeep))
            }

            TextField(app.settings.inputPlaceholder, text: $draft, axis: .vertical)
                .onChange(of: draft) { _, text in
                    // 末尾是 @ 或者 @ 后面还没打完名字，就把人列出来
                    guard activeConversation?.isGroup == true else {
                        mentioning = false
                        return
                    }
                    if let at = text.lastIndex(of: "@") {
                        let tail = text[text.index(after: at)...]
                        mentioning = !tail.contains(" ") && tail.count < 12
                    } else {
                        mentioning = false
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: app.settings.fontSize))
                .lineLimit(1...6)
                .padding(.horizontal, 4)
                .padding(.top, 2)
                // 默认回车就是换行；想让它当发送用，去设置里开
                .submitLabel(app.settings.enterToSend ? .send : .return)
                .onSubmit {
                    guard app.settings.enterToSend, canSend else { return }
                    sendCurrent(conv)
                }

            HStack(spacing: 14) {
                // 「+」不再只是相册。什么都能发——
                // 文档、音频、压缩包、随便什么，选了就带上去。
                Menu {
                    Button {
                        showingPhotos = true
                    } label: {
                        Label("照片", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        importingFile = true
                    } label: {
                        Label("文件", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    hideKeyboard()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        stickerPanelOpen.toggle()
                    }
                } label: {
                    Image(systemName: Icon.sticker)
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(stickerPanelOpen
                                         ? app.settings.accentColor
                                         : Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)

                Button {
                    hideKeyboard()
                    showingTools = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(app.hasActiveTools ? app.settings.accentColor : Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)

                Button {
                    hideKeyboard()
                    showingModelPicker = true
                } label: {
                    Text(app.modelChipLabel(for: conv))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textSoft(scheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        // 这颗胶囊以前是一块死颜色（softFillDeep），
                        // 所以换玻璃、拉模糊它都纹丝不动。改成跟别处一样走 GlassSurface，
                        // 半径给得比高度大就是胶囊。
                        .glassBackground(radius: 20,
                                         strength: app.settings.glassOpacity,
                                         extra: 0.2)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // 打给他。跟他打过来那条路是同一套界面。
                Button {
                    hideKeyboard()
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    CallStore.shared.dial()
                } label: {
                    Image(systemName: "phone")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 按住说话，松手把识别到的话填进输入框
                Image(systemName: listening ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(listening
                                     ? app.settings.accentColor
                                     : Theme.textSoft(scheme))
                    .frame(width: 30, height: 30)
                    .background {
                        if listening {
                            Circle()
                                .fill(app.settings.accentColor.opacity(0.18))
                                // 说话大声一点圈就大一点
                                .scaleEffect(1 + recorder.level * 0.5)
                        }
                    }
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !listening else { return }
                                if app.settings.haptics {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                hideKeyboard()
                                startListening()
                            }
                            .onEnded { _ in
                                Task { await stopListening() }
                            }
                    )

                Button {
                    if isRunning {
                        app.cancelStream(for: conv.id)
                    } else {
                        sendCurrent(conv)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(app.settings.primaryColor
                                .opacity(canSend || isRunning || waiting ? 0.85 : 0.35))
                            .frame(width: 36, height: 36)
                        Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !isRunning)
                // 攒着的时候长按就是"不等了，现在就发"
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                        guard waiting else { return }
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        app.flushPending(conv.id)
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassBackground(radius: 24, strength: app.settings.glassOpacity)
        .shadow(color: Theme.shadow(scheme), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 12)
        // 键盘支起来的时候贴着键盘，收着的时候给底下导航条让出位置
        .padding(.bottom, keyboard.up ? 8 : Layout.tabBarSpace + 26)
    }

    // MARK: 挑句子时的那条操作栏

    @ViewBuilder
    private func selectionBar(_ conv: Conversation) -> some View {
        HStack(spacing: 0) {
            Button {
                selecting = false
                selected = []
            } label: {
                Text("取消")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            action("提炼", Icon.memory) {
                let picked = app.messages(selected, in: conv.id)
                selecting = false; selected = []
                notice = "在归纳…"
                Task {
                    let r = await app.synthesizeMemory(from: picked)
                    await MainActor.run { notice = r }
                }
            }

            action("收藏", Icon.star) {
                app.toggleStar(selected, in: conv.id)
                selecting = false; selected = []
            }

            action("分享", Icon.share) {
                let picked = app.messages(selected, in: conv.id)
                guard !picked.isEmpty else { return }
                if let img = ShareCardRenderer.render(messages: picked, settings: app.settings) {
                    shareImage = ShareImage(image: img)
                }
                selecting = false; selected = []
            }

            action("删掉", Icon.trash, tint: .red) {
                app.deleteMessages(selected, in: conv.id)
                selecting = false; selected = []
            }
        }
        .padding(.vertical, 12)
        .glassBackground(radius: 24, strength: app.settings.glassOpacity)
        .shadow(color: Theme.shadow(scheme), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 12)
        // 键盘支起来的时候贴着键盘，收着的时候给底下导航条让出位置
        .padding(.bottom, keyboard.up ? 8 : Layout.tabBarSpace + 26)
    }

    private func action(_ title: String, _ icon: String,
                        tint: Color? = nil, run: @escaping () -> Void) -> some View {
        Button {
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            run()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .regular))
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(selected.isEmpty
                             ? Theme.textMuted(scheme)
                             : (tint ?? app.settings.accentColor))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
    }

    /// 有文字、有表情、有图、有文件、有语音，任意一样就能发
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingImages.isEmpty
            || !pendingFiles.isEmpty
            || pendingSticker != nil
            || pendingVoice != nil
    }

    /// 录音那条提示写什么
    private var listeningHint: String {
        if transcribing { return "在听你说什么…" }
        return String(format: "录着呢 %.1f 秒，松手就认", recorder.seconds)
    }

    private func startListening() {
        listening = true
        // 不管走哪条识别，**都先把声音录成文件**。
        // 这样她说的话不只是变成一行字就没了，
        // 还能像微信那样留一条语音条，随时点开再听。
        do {
            try recorder.start()
        } catch {
            notice = "开不了录音：" + error.localizedDescription
            listening = false
        }
    }

    private func stopListening() async {
        defer { listening = false }

        guard let url = recorder.stop() else { return }
        guard recorder.seconds > 0.4 else {
            try? FileManager.default.removeItem(at: url)
            notice = "太短了，没录进去"
            return
        }

        // 先把录音留下来。识别成不成功都不影响这一条能不能听。
        if let data = try? Data(contentsOf: url),
           let saved = VoiceStore.save(data, ext: "m4a") {
            pendingVoice = saved
        }
        defer { try? FileManager.default.removeItem(at: url) }

        transcribing = true
        listening = true
        defer { transcribing = false }

        switch app.settings.voiceInput {
        case .onDevice:
            // 本机认，不花钱也不上传
            let text = await SpeechRecognizer.recognizeFile(url)
            if text.isEmpty {
                notice = "没认出来说了什么，语音还是能发的"
            } else {
                draft = draft.isEmpty ? text : draft + " " + text
            }
        default:
            do {
                let t: Transcript
                if app.settings.voiceInput == .senseVoice {
                    t = try await SenseVoiceAPI.transcribe(url, key: app.settings.siliconKey)
                } else {
                    // 用配好的那个 ElevenLabs 密钥，不用再注册一家
                    let voice = app.activeVoice ?? app.voices.first
                    t = try await ElevenSTT.transcribe(
                        url,
                        key: voice?.apiKey ?? "",
                        baseURL: voice?.baseURL ?? "")
                }
                let line = t.briefForModel
                draft = draft.isEmpty ? line : draft + " " + line
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    private func insertMention(_ name: String) {
        guard let at = draft.lastIndex(of: "@") else {
            draft += "@" + name + " "
            mentioning = false
            return
        }
        draft = String(draft[..<at]) + "@" + name + " "
        mentioning = false
        if app.settings.haptics {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func sendCurrent(_ conv: Conversation) {
        // 只打了字、没带别的东西，而且开了「我分段发」——
        // 那这一句先攒着，等她真的不说了再一起交给他
        if app.settings.segmentUser
            && pendingImages.isEmpty && pendingFiles.isEmpty
            && pendingSticker == nil && pendingVoice == nil && quoting == nil {
            let line = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            draft = ""
            mentioning = false
            app.queueSend(text: line, in: conv.id)
            return
        }

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        let quoted = quoting
        let files = pendingFiles
        let sticker = pendingSticker
        let voice = pendingVoice ?? ""
        draft = ""
        pendingVoice = nil
        pendingImages = []
        pendingFiles = []
        pickedItems = []
        pendingSticker = nil
        quoting = nil
        mentioning = false
        app.send(text: text, images: images, in: conv.id,
                 files: files, sticker: sticker, quoting: quoted, voiceName: voice)
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            await MainActor.run {
                pendingImages.append(contentsOf: loaded)
                pickedItems = []
            }
        }
    }
}

// MARK: - 消息列表

struct MessageListView: View {

    let conversation: Conversation
    let space: ChatSpace
    var selecting: Bool = false
    var selected: Set<UUID> = []
    var onToggle: (UUID) -> Void = { _ in }
    var onQuote: (ChatMessage) -> Void = { _ in }
    var onChoice: (String) -> Void = { _ in }
    var onSpeak: (ChatMessage) -> Void = { _ in }
    var onOpenReader: (ChatMessage) -> Void = { _ in }
    var onOpenJourney: (Journey) -> Void = { _ in }
    var menuOpenID: UUID? = nil
    var onOpenMenu: (UUID) -> Void = { _ in }
    var onCloseMenu: () -> Void = {}
    var onEdit: (ChatMessage) -> Void = { _ in }
    /// 长按头像 @ 这个人
    var onMention: (String) -> Void = { _ in }
    /// 这个窗口是不是正在等他回话
    var running: Bool = false

    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if conversation.messages.isEmpty {
                        emptyHint.padding(.top, 100)
                    }
                    ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubbleView(
                            message: message,
                            conversationID: conversation.id,
                            selecting: selecting,
                            isSelected: selected.contains(message.id),
                            onToggleSelect: { onToggle(message.id) },
                            onQuote: { onQuote(message) },
                            onChoice: { onChoice($0) },
                            onSpeak: { onSpeak(message) },
                            onOpenReader: { onOpenReader(message) },
                            onOpenJourney: { onOpenJourney($0) },
                            onEdit: { onEdit(message) },
                            menuOpenID: menuOpenID,
                            onOpenMenu: { onOpenMenu(message.id) },
                            onCloseMenu: onCloseMenu,
                            showsHeader: showsHeader(at: index),
                            onMention: { onMention($0) }
                        )
                        .id(message.id)
                    }
                    // 他开始回、但一个字还没出来的那几秒，别让屏幕空着——
                    // 那几秒最容易让人以为是断了
                    if running,
                       let last = conversation.messages.last,
                       last.role != .assistant
                        || (last.content.isEmpty && last.toolRuns.isEmpty
                            && (last.reasoning ?? "").isEmpty) {
                        TypingBubble(name: last.role == .assistant ? last.senderName : "")
                            .padding(.top, 2)
                    }

                    Color.clear.frame(height: 1).id("__bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 100)
                .padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            // 正文、思考链、工具调用，只要有一样在往外冒字，就跟着滚
            .onChange(of: conversation.scrollTick) { _, _ in
                proxy.scrollTo("__bottom", anchor: .bottom)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
            // 注意：App 只是切到后台再回来的话不滚。
            // 你可能正翻着上面某句话跑去别的 App 查东西，回来还得在原地。
            // 只有整个 App 被杀掉、重新打开的那一次，才回到最新。
            .onAppear {
                proxy.scrollTo("__bottom", anchor: .bottom)
                // 图片和长文排版完还会再撑高一点，稍等再补一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
        }
    }

    /// 这一条上面要不要挂头像那行。
    ///
    /// 规矩是**一句话挂一次**——一句话指的是一整条消息：
    /// 他那边思考链、工具、正文加起来算一条；分段发的那几个气泡
    /// 本来就在同一条里，所以也只挂一次。
    /// 唯一要合并的是同一个 turn 拆出来的那两条（文字 + 表情），
    /// 那是一次发送，不该挂两个头像。
    private func showsHeader(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let msg = conversation.messages[index]
        let prev = conversation.messages[index - 1]
        if let t = msg.turnID, t == prev.turnID { return false }
        return true
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            if app.hasUsableModel {
                Text("说点什么吧").foregroundStyle(.secondary)
            } else {
                Text("还没配置模型").foregroundStyle(.secondary)
                Text("去「设置 → 供应商」加一个")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
