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

    @State private var drawerOpen = false
    @State private var sideOpen = false
    @State private var destination: SideMenuItem?
    @State private var showingModelPicker = false
    @State private var showingSystemPrompt = false
    @State private var showingSearch = false
    @State private var showingTools = false
    /// 输入框里的字。**存在 AppState 里，不是 @State**——
    /// 见 `AppState.drafts` 那段：切去设置页再回来不能白打。
    ///
    /// 写成计算属性（不是 Binding），这样底下几十处 `draft = …`、
    /// `draft.hasSuffix(…)` 一个字都不用改；TextField 那儿单独给它一个
    /// `draftBinding`。
    private var draft: String {
        get { app.drafts[draftKey] ?? "" }
        nonmutating set { app.drafts[draftKey] = newValue }
    }
    private var draftKey: UUID { activeConversation?.id ?? Self.noConversation }
    private static let noConversation = UUID()
    private var draftBinding: Binding<String> {
        Binding(get: { draft }, set: { draft = $0 })
    }
    /// 她在打字。列表看见它变就滚到底。
    @State private var typingTick = 0
    @FocusState private var inputFocused: Bool
    /// 从聊天记录点进来的那一条，滚到它那儿并闪一下
    @State private var jumpTo: UUID?
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showingPlus = false
    @State private var pendingImages: [UIImage] = []
    /// 已经原样存好的动图（gif）。**不走 pendingImages**——
    /// 那条路要过一遍 UIImage，动画会被压成第一帧。
    @State private var pendingGIFs: [String] = []
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
    /// 刚录那条**是怎么说的**，跟 pendingVoice 一起发出去
    @State private var pendingTone: String = ""
    /// 光标前面刚打了个 @，正等着挑人
    @State private var mentioning = false
    @State private var notice: String?
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var shareImage: ShareImage?
    @State private var quoting: ChatMessage?
    @State private var menuOpenID: UUID?
    /// 菜单是对着哪一条开的。**存整条**，不只是 id——
    /// 面板挪到这一层之后要拿它的正文去复制、翻译、判断有没有语音。
    @State private var menuMessage: ChatMessage?
    @State private var editingMessage: ChatMessage?
    @State private var editText = ""
    @State private var reading: ChatMessage?
    @State private var browsing: BrowserLink?
    @State private var travelling: Journey?
    /// 从这趟旅行的第几处进去（她在卡片上停在哪张）
    @State private var travellingAt = 0
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
                        onOpenJourney: { j, at in
                            travellingAt = at
                            travelling = j
                        },
                        menuOpenID: menuOpenID,
                        onOpenMenu: { msg in
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                menuOpenID = msg.id
                                menuMessage = msg
                            }
                        },
                        onCloseMenu: {
                            withAnimation(.easeOut(duration: 0.15)) { closeMenu() }
                        },
                        onEdit: { msg in
                            editText = msg.content
                            editingMessage = msg
                        },
                        onRetry: { msg in app.retry(msg.id, in: conv.id) },
                        onOpenLibrary: { place in
                            // 存到哪儿决定开哪一栏：动图 → GIF，
                            // 表情包 → 表情包，别的（相册文件夹）→ 图片
                            StickerLibraryView.openTab = place.contains("动图") ? 2
                                : (place.contains("表情") ? 1 : 0)
                            destination = SideMenuItem.all.first { $0.id == "sticker" }
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
                        running: app.runningConversationIDs.contains(conv.id),
                        typingTick: typingTick,
                        jumpTo: jumpTo,
                        onJumped: { jumpTo = nil }
                    )
                    // 表情面板开着的时候，点聊天区任何一处就收起来（她要的）。
                    // **不能盖一层全屏透明层**——那层会连表情本身一起挡住，
                    // 变成点哪儿都只是关掉、一张也选不中。
                    // 挂在消息区上就正好：这块本来就是「空白处」。
                    .simultaneousGesture(TapGesture().onEnded {
                        if stickerPanelOpen {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                stickerPanelOpen = false
                            }
                        }
                    })
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
            // 放歌那条**不在这儿了**。
            //
            // 它以前是顶上一条横贯全屏的 bar，右端压在三条杠底下，
            // 关闭叉点不着（她说的「重合了、关不掉」），
            // 而且一直霸占着顶部那一条。
            // 现在是能拖的悬浮窗，挂在 RootView 上——全 App 都看得见，
            // 翻到札记、设置那些页面也还在。见 MusicFloatingView。

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
                        withAnimation(.easeOut(duration: 0.15)) { closeMenu() }
                    }
            }

            // 长按一条消息之后的功能面板。
            //
            // **必须排在上面那层透明层后面**（也就是压在它上面），
            // 否则手指永远先碰到透明层，按钮点了没反应——那正是她报的第 9 条。
            if let msg = menuMessage, menuOpenID == msg.id {
                messageMenu(msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
            }

            // 他打过来那张卡片、还有通话那一屏，都**挪到 RootView 去了**。
            //
            // 挂在这儿有个死角：从「通话」历史页点拨号的时候，
            // 絮语这一页根本不在屏上，谁也没把界面弹出来——
            // 结果就是"拨出去毫无反应，但历史里有一条记录"。
            // 通话是全 App 的事，得挂在全 App 都在的那一层。

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
            ChatSearchView(space: space) { convID, msgID in
                app.setActive(convID, for: space)
                // 跳到那一句。延一下等这一窗渲染出来再滚。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    jumpTo = msgID
                }
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
        .fullScreenCover(item: $travelling) { j in
            JourneyPlayerView(journey: j, startAt: travellingAt)
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

            if !pendingImages.isEmpty || !pendingGIFs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // 会动的那几张单列一遍——它们没进 pendingImages
                        // （进了就会被压成第一帧），不在这儿画的话
                        // 选完看不见、也撤不掉
                        ForEach(Array(pendingGIFs.enumerated()), id: \.offset) { index, name in
                            ZStack(alignment: .topTrailing) {
                                AnimatedImageView(url: ImageStore.url(for: name),
                                                  contentMode: .scaleAspectFill)
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Button {
                                    pendingGIFs.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .padding(2)
                            }
                        }
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
                                    .font(.app(12))
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
                        .font(.app(13))
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
                            .font(.app(22))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("语音 \(Int(VoiceStore.duration(v)))″")
                            .font(.app(12, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        // 攒够八条之前这里一直是「跟文字一起发出去」，
                        // 之后才会变成他能听出来的那句。
                        // 摆出来是因为：这是他会「听」到的东西，
                        // 不该只有他知道，她自己也得看得见。
                        Text(pendingTone.isEmpty ? "跟文字一起发出去" : pendingTone)
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Spacer(minLength: 0)
                    Button {
                        VoiceStore.delete(v)
                        pendingVoice = nil
                        // 语气是这条语音的，语音扔了它也得跟着走，
                        // 不然会挂到下一条纯文字消息上
                        pendingTone = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.app(15))
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
                            .font(.app(12, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        Text("跟文字一起发出去")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Spacer(minLength: 0)
                    Button {
                        pendingSticker = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.app(11, weight: .medium))
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
                                .font(.app(14))
                                .foregroundStyle(app.settings.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.displayName)
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textMain(scheme))
                                    .lineLimit(1)
                                Text(f.unreadable ? "\(f.sizeText) · 读不出文字" : "\(f.sizeText) · 已读出内容")
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            Spacer(minLength: 0)
                            Button {
                                FileStore.delete(f)
                                pendingFiles.removeAll { $0.id == f.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.app(10, weight: .medium))
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
                        .font(.app(11))
                        .foregroundStyle(app.settings.accentColor)
                    Text("攒着呢，你不说了 \(Int(app.settings.segmentUserDelay)) 秒之后一起发。长按发送键马上发。")
                        .font(.app(11))
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
                            .font(.app(10, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text(q.content)
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        quoting = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.app(11, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.softFillDeep))
            }

            TextField(app.settings.inputPlaceholder, text: draftBinding, axis: .vertical)
                .focused($inputFocused)
                .onChange(of: inputFocused) { _, on in
                    // 点进输入框就滚到最底下。
                    // 她说的：「点击输入框应该滚动到最下方才对，
                    // 不然看不见他上面发的消息」——键盘弹起来会顶掉最后几条。
                    if on { typingTick += 1 }
                }
                .onChange(of: draft) { _, text in
                    // 她一开始打字，列表就滚到最底下。
                    // 以前不滚，打字的时候最后那几条被键盘顶上去看不见了。
                    typingTick += 1
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
                // ⚠️ 这儿原来是 `Menu { … }.buttonStyle(.plain)`。
                // **点了没反应**（她报的）：Menu 套上 .plain 之后，
                // 那个 buttonStyle 会把菜单自己的手势吃掉，
                // 键盘正弹着的时候尤其明显——点下去什么都不弹。
                // 换成普通按钮 + confirmationDialog，行为是确定的。
                Button {
                    hideKeyboard()
                    showingPlus = true
                } label: {
                    Image(systemName: "plus")
                        .font(.app(19, weight: .light))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .confirmationDialog("要发点什么", isPresented: $showingPlus,
                                    titleVisibility: .hidden) {
                    Button("照片") { showingPhotos = true }
                    Button("文件") { importingFile = true }
                    Button("取消", role: .cancel) {}
                }

                Button {
                    hideKeyboard()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        stickerPanelOpen.toggle()
                    }
                } label: {
                    Image(systemName: Icon.sticker)
                        .font(.app(17, weight: .light))
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
                        .font(.app(15, weight: .light))
                        .foregroundStyle(app.hasActiveTools ? app.settings.accentColor : Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)

                Button {
                    hideKeyboard()
                    showingModelPicker = true
                } label: {
                    Text(app.modelChipLabel(for: conv))
                        .font(.app(12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textSoft(scheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        // **玻璃不能套在玻璃上。**
                        //
                        // 这颗胶囊上一版是一整块 GlassSurface，而它就摆在输入框
                        // 那块 GlassSurface 上面——等于糊了两遍、深色下那层黑
                        // 也压了两遍。结果它读起来是一坨比输入框更深的疙瘩，
                        // 不是一颗胶囊。她说的"很突兀"就是这个。
                        //
                        // 玻璃上面该放的是一层薄薄的提亮，不是第二块玻璃。
                        // 这样照样跟着深浅色走，只是不再自己糊一遍。
                        .background(
                            Capsule().fill(scheme == .dark
                                           ? Color.white.opacity(0.14)
                                           : Color.white.opacity(0.42))
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                Color.white.opacity(scheme == .dark ? 0.10 : 0.45),
                                lineWidth: 0.7)
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // 打给他。跟他打过来那条路是同一套界面。
                // 没模型就是打不通——这个电话是真要问他的，不是摆设。
                Button {
                    hideKeyboard()
                    guard app.activeHim != nil else {
                        notice = "还没选模型，这通电话没人接。去输入框上那颗胶囊选一个。"
                        return
                    }
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    CallStore.shared.dial()
                } label: {
                    // 跟这一排别的图标同色。
                    //
                    // 以前没选模型的时候它是 `textMuted × 0.5`，淡得像坏了——
                    // 她说的「这个电话 icon 颜色比其他的都淡」就是这个。
                    // 打不通这件事不该靠把图标画糊来说，点下去那句提示已经说了。
                    Image(systemName: "phone")
                        .font(.app(16, weight: .light))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 按住说话，松手把识别到的话填进输入框
                Image(systemName: listening ? "mic.fill" : "mic")
                    .font(.app(16, weight: .light))
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
                            .font(.app(15, weight: .semibold))
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
        // 这道影子以前是 Theme.shadow —— 深色下是 40% 的黑、
        // 半径 14 往下偏 6，落在底栏上就是**一道边界分明的暗带**，
        // 玻璃反而像贴上去的一张卡片。她说的"突兀"是这个。
        //
        // 玻璃本来就不靠影子跟背景分开，靠的是它自己那圈边光。
        // 影子只需要托住它一点点：摊得更开、淡到几乎看不见。
        .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.05),
                radius: 22, x: 0, y: 8)
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
                    .font(.app(14))
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
        // 这道影子以前是 Theme.shadow —— 深色下是 40% 的黑、
        // 半径 14 往下偏 6，落在底栏上就是**一道边界分明的暗带**，
        // 玻璃反而像贴上去的一张卡片。她说的"突兀"是这个。
        //
        // 玻璃本来就不靠影子跟背景分开，靠的是它自己那圈边光。
        // 影子只需要托住它一点点：摊得更开、淡到几乎看不见。
        .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.05),
                radius: 22, x: 0, y: 8)
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
                Image(systemName: icon).font(.app(16, weight: .regular))
                Text(title).font(.app(11))
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
            || !pendingImages.isEmpty || !pendingGIFs.isEmpty
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

        // 停之前先把振幅序列拿走——stop() 之后 recorder 还留着它，
        // 但下一次按住说话就会重置，所以在这儿取最稳
        let shape = recorder.samples
        let step = recorder.sampleInterval

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
            // 她**是怎么说的**。本机算，不花钱，不联网。
            // 认不出字也照样算——语气跟识别成不成功是两回事。
            noteTone(shape: shape, step: step, text: text)
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
                noteTone(shape: shape, step: step, text: t.text)
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    /// 算这一句的语气，记进基线，留给待发送的那条消息。
    ///
    /// 全是本机的纯算术，一分钱不花、一个字节不上传。
    /// 攒够 8 条之前 `note` 一律返回空——那会儿它还不知道什么叫「她的平时」，
    /// **宁可不说也不要说错**。
    private func noteTone(shape: [Double], step: Double, text: String) {
        let f = VoiceProsody.features(samples: shape, interval: step, text: text)
        guard f.usable else { return }
        pendingTone = VoiceBaseline.shared.note(for: f)
        // 只有正常走完这一轮才记进基线。半截的、太短的都不算，
        // 不然基线会被污染。
        VoiceBaseline.shared.remember(f)
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
            && pendingImages.isEmpty && pendingGIFs.isEmpty && pendingFiles.isEmpty
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
        let gifs = pendingGIFs
        let quoted = quoting
        let files = pendingFiles
        let sticker = pendingSticker
        let voice = pendingVoice ?? ""
        let tone = pendingTone
        draft = ""
        pendingVoice = nil
        pendingTone = ""
        pendingImages = []
        pendingGIFs = []
        pendingFiles = []
        pickedItems = []
        pendingSticker = nil
        quoting = nil
        mentioning = false
        app.send(text: text, images: images, in: conv.id,
                 imageNames: gifs,
                 files: files, sticker: sticker, quoting: quoted,
                 voiceName: voice, voiceTone: tone)
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var loaded: [UIImage] = []
            var gifs: [String] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                // 会动的原样落盘，别过 UIImage
                if ImageStore.isAnimated(data) {
                    if let name = ImageStore.saveOriginal(data) { gifs.append(name) }
                } else if let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            let picked = gifs
            await MainActor.run {
                pendingImages.append(contentsOf: loaded)
                pendingGIFs.append(contentsOf: picked)
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
    var onOpenJourney: (Journey, Int) -> Void = { _, _ in }
    var menuOpenID: UUID? = nil
    var onOpenMenu: (ChatMessage) -> Void = { _ in }
    var onCloseMenu: () -> Void = {}
    var onEdit: (ChatMessage) -> Void = { _ in }
    var onRetry: (ChatMessage) -> Void = { _ in }
    var onOpenLibrary: (String) -> Void = { _ in }
    /// 长按头像 @ 这个人
    var onMention: (String) -> Void = { _ in }
    /// 这个窗口是不是正在等他回话
    var running: Bool = false
    /// 她每敲一下这个数就变。变了就滚到底——
    /// 打字的时候最后几条会被键盘顶上去，不滚就看不见自己在回哪一句。
    var typingTick: Int = 0
    /// 从聊天记录搜索点进来的那一条：滚过去，别停在最底下
    var jumpTo: UUID? = nil
    var onJumped: () -> Void = {}

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
                            onOpenJourney: { j, at in onOpenJourney(j, at) },
                            onEdit: { onEdit(message) },
                            menuOpenID: menuOpenID,
                            onOpenMenu: { onOpenMenu(message) },
                            onRetry: { onRetry(message) },
                            onOpenLibrary: { place in onOpenLibrary(place) },
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
            .onChange(of: typingTick) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
            // 从聊天记录点进来的那一条：滚到屏幕正中，别停在底下。
            // **要压过上面那两条**——它们会无脑滚到底，
            // 所以这条排在后面，最后一个说了算。
            .onChange(of: jumpTo) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                onJumped()
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
                .font(.app(38))
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

// MARK: - 长按一条消息之后的功能面板

extension ChatView {

    func closeMenu() {
        menuOpenID = nil
        menuMessage = nil
    }

    /// 微信那样的两行格子。
    ///
    /// 为什么不是原来那条横的：八个按钮排一条，屏幕装不下（她原话
    /// 「一长条有点出屏幕了」）。格子每行五个，多少个功能都放得下，
    /// 而且从底下升上来，永远在手指够得着的地方。
    @ViewBuilder
    func messageMenu(_ msg: ChatMessage) -> some View {
        let cid = app.activeID(for: space)
        VStack {
            Spacer()
            VStack(spacing: 0) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0),
                                         count: 5),
                          spacing: 18) {
                    menuItem("复制", "doc.on.doc") {
                        UIPasteboard.general.string = msg.content
                    }
                    menuItem("引用", "quote.opening") { quoting = msg }
                    menuItem(msg.starred ? "取消收藏" : "收藏", "star") {
                        if let cid { app.toggleStar([msg.id], in: cid) }
                    }
                    menuItem("删除", "trash") {
                        if let cid { app.deleteMessage(msg.id, in: cid) }
                    }
                    menuItem("多选", "checklist") {
                        selecting = true
                        selected.insert(msg.id)
                    }
                    menuItem("编辑", "square.and.pencil") {
                        editText = msg.content
                        editingMessage = msg
                    }
                    menuItem("重发", "arrow.clockwise") {
                        if let cid { app.retry(msg.id, in: cid) }
                    }
                    menuItem(msg.voiceName.isEmpty ? "念出来" : "听", "speaker.wave.2") {
                        guard let cid else { return }
                        Task {
                            if let err = await app.speak(msg.id, in: cid) { notice = err }
                        }
                    }
                    menuItem(msg.translation == nil ? "翻译" : "收起译文", "character.book.closed") {
                        guard let cid else { return }
                        if msg.translation == nil {
                            app.translate(msg.id, in: cid)
                        } else {
                            app.clearTranslation(msg.id, in: cid)
                        }
                    }
                    menuItem("全屏看", "arrow.up.left.and.arrow.down.right") {
                        reading = msg
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.86))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 18)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func menuItem(_ title: String, _ icon: String,
                          run: @escaping () -> Void) -> some View {
        Button {
            // **先关面板再做事**：有些动作（重发、删除）会把这条消息本身
            // 从列表里拿掉，面板还开着就会指着一条不存在的消息
            withAnimation(.easeOut(duration: 0.15)) { closeMenu() }
            run()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(height: 24)
                Text(title)
                    .font(.app(11))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
