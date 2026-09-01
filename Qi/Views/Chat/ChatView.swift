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
    /// 退到后台的时候把草稿存回去，见 `stashDraft()`
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var keyboard = KeyboardWatcher.shared

    @State private var drawerOpen = false
    @State private var sideOpen = false
    @State private var destination: SideMenuItem?
    @State private var showingSearch = false
    /// 输入框里的字。
    ///
    /// ⚠️ **敲字只动这个本地 `@State`，不动 `app.drafts`。**
    ///
    /// 她报的：「聊天非常卡顿，就连我打字都一卡一卡的。」
    /// 原来这儿是个读写 `app.drafts` 的计算属性——`drafts` 是
    /// `AppState` 上的 `@Published`，于是**每敲一个字就等于通知全 App
    /// 重新求值一遍**：一屏消息、侧边栏、输入栏、悬浮窗，全部跟着走一轮。
    /// 打字是所有交互里频率最高的一件事，这个代价直接顶在指尖上。
    ///
    /// 存回 `app.drafts` 的时机改成**离开这段对话的时候**
    /// （切窗口 / 退到后台 / 页面消失），见 `stashDraft()`。
    /// 「切去设置页再回来不能白打」照样成立，因为那时候页面已经走了 `onDisappear`。
    @State private var draftText: String = ""
    /// 现在这份草稿是哪段对话的。切窗口的时候靠它把旧的存回去。
    @State private var draftOwner: UUID?

    private var draft: String {
        get { draftText }
        nonmutating set { draftText = newValue }
    }
    private var draftKey: UUID { activeConversation?.id ?? Self.noConversation }
    private static let noConversation = UUID()
    private var draftBinding: Binding<String> { $draftText }

    /// 把手里这份存回 `AppState`，再把新那段对话的取出来。
    /// 只在换窗口/离开页面的时候调，一次打字过程里一次都不会走到。
    private func syncDraft(to key: UUID) {
        if let owner = draftOwner, owner != key {
            if draftText.isEmpty { app.drafts[owner] = nil }
            else { app.drafts[owner] = draftText }
        }
        if draftOwner != key {
            draftText = app.drafts[key] ?? ""
            draftOwner = key
        }
    }

    private func stashDraft() {
        guard let owner = draftOwner else { return }
        if draftText.isEmpty { app.drafts[owner] = nil }
        else { app.drafts[owner] = draftText }
    }

    /// 她在打字。列表看见它变就滚到底。
    ///
    /// ⚠️ **不是每个字都递一次。** 每递一次，整个消息列表要重新求值、
    /// 还要跑一段 `withAnimation` 的滚动——一秒钟五六下，就是她说的那种一卡一卡。
    /// 真正需要滚的只有「输入栏长高了一行」那一下，见 `bumpTypingIfGrew`。
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
    // 看一段视频（见 `VideoDigest`）。
    // 抽帧和转台词都在本机跑，不花钱；
    // 花钱的只有她自己按那一下发送。
    @State private var showingVideos = false
    @State private var pickedVideo: [PhotosPickerItem] = []
    /// 正在抽帧。要跑好几秒，**界面上得有个在动的东西**
    @State private var videoBusy: String?
    @State private var stickerPanelOpen = false
    @State private var pendingSticker: Sticker?
    @StateObject private var recorder = VoiceRecorder()
    @State private var listening = false
    @State private var transcribing = false
    /// 刚录好、还没发出去的那段语音（存在 Voices 里的文件名）
    @State private var pendingVoice: String?
    /// 刚录那条**是怎么说的**，跟 pendingVoice 一起发出去
    @State private var pendingTone: String = ""
    /// 待发的那段视频：原件给她，帧和说明给他。三样一起走。
    @State private var pendingVideo: String?
    @State private var pendingVideoFrames: [String] = []
    @State private var pendingVideoNote: String = ""
    /// 输入栏那一块现在有多高。消息区拿它当底部留白，
    /// 最后一条才不会永远压在玻璃底下。
    @State private var composerHeight: CGFloat = 96
    /// 她自己的动作 / 心里话：现在开着哪一个框（nil = 都没开）
    @State private var beatKind: String?
    @State private var beatText = ""
    @FocusState private var beatFocused: Bool
    /// 光标前面刚打了个 @，正等着挑人
    @State private var mentioning = false
    @State private var notice: String?
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var shareImage: ShareImage?
    @State private var quoting: ChatMessage?
    @State private var menuOpenID: UUID?
    /// 菜单打开那一刻，她翻在第几页（0 = 现在这版）
    @State private var menuEditPage = 0
    /// 菜单是对着哪一条开的。**存整条**，不只是 id——
    /// 面板挪到这一层之后要拿它的正文去复制、翻译、判断有没有语音。
    @State private var menuMessage: ChatMessage?
    @State private var editingMessage: ChatMessage?
    /// 点开了哪一条的「过程」。弹窗挂在这一页上，不挂在气泡上。
    /// 这一页上那七张面板，**共用一个 presentation 宿主**。
    /// 理由见下面 `.sheet(item: $panel)` 那儿。
    @State private var panel: ChatPanel?
    @State private var editText = ""
    @State private var reading: ChatMessage?
    @State private var browsing: BrowserLink?
    @State private var travelling: Journey?
    /// 从这趟旅行的第几处进去（她在卡片上停在哪张）
    @State private var travellingAt = 0

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
                        onOpenMenu: { msg, page in
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                                menuOpenID = msg.id
                                menuMessage = msg
                                // 她正翻在第几页。「删这一版」靠它才知道删哪一版。
                                menuEditPage = page
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
                        onOpenProcess: { msg in panel = .process(msg) },
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
                        // 输入栏那块玻璃现在压在消息上面，底下留出它那么高
                        bottomInset: composerHeight + 12,
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
                    // ⚠️ 输入栏**不再占一行布局**了。
                    //
                    // 以前它跟消息区并排在一个 VStack 里：消息区到它上沿为止，
                    // 底下那一条是它自己的地盘。于是往下滑的时候
                    // **消息滑到那儿就被它挡住**——她说「所有消息拖到输入框
                    // 就会被输入框后面的背景遮住」。
                    //
                    // 现在它是**浮在消息上面的一块玻璃**：消息整屏铺到底，
                    // 从它背后透出来。玻璃本来就是干这个的——
                    // 底下没东西可透的时候，它跟一块不透明的板子没区别。
                    //
                    // 消息区底下留出它那么高的空（`composerHeight`），
                    // 最后一条才不会永远压在它下面。
                    EmptyView()
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            // 输入栏浮在最底下，压在消息上面。见上面那段。
            .overlay(alignment: .bottom) {
                if let conv = activeConversation {
                    if selecting {
                        selectionBar(conv)
                    } else {
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
                        // 量一下自己多高，交给消息区当底部留白。
                        // 写死一个数是不行的——待发的图、暂存那条、
                        // 引用那条都会把它顶高。
                        .background(GeometryReader { geo in
                            Color.clear.onAppear { composerHeight = geo.size.height }
                                // ⚠️ 高度变化**不带动画**。
                                //
                                // 带动画的话，列表底部那段留白会在几帧里
                                // 慢慢长出来，而滑到底那一下已经滑了——
                                // 两个动画抢同一个位置，看起来就是气泡在抽。
                                .onChange(of: geo.size.height) { _, h in
                                    var t = Transaction()
                                    t.disablesAnimations = true
                                    withTransaction(t) { composerHeight = h }
                                    // 输入栏长高/变矮了，底下那几条会被顶出去——
                                    // **打字期间只有这一下需要滚**。
                                    typingTick += 1
                                }
                        })
                    }
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
                       onEditPrompt: { panel = .prompt },
                       onOpenSearch: { showingSearch = true },
                       onOpenGroup: { panel = .group },
                       onOpenMemoryLink: { panel = .memory })
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
                ClawdRoamer(busy: state.busy,
                            activity: state.text,
                            // 这一轮出错了没有：最后一条挂着错就是出了
                            upset: conv.messages.last?.errorText != nil,
                            // 她上次说话是什么时候——那只困不困看这个
                            lastHerAt: conv.messages.last(where: { $0.role == .user })?.createdAt)
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
                    // 她正拎着 clawd 往边上挪——那一下不是要开侧边栏
                    guard !ClawdStore.clawdHeld else { return }
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
            // 把这段对话上次没打完的那半句取回来
            syncDraft(to: draftKey)
        }
        .onDisappear {
            if space == .chat { app.isChatVisible = false }
            // 走的时候才存。打字期间一次都不写 `app.drafts`——
            // 它是 `@Published`，每写一次全 App 重新求值一遍。
            stashDraft()
        }
        // 换了一段对话：旧的那份存回去，新的那份取出来
        .onChange(of: draftKey) { _, key in syncDraft(to: key) }
        // 退到后台也存一次，免得直接被系统回收掉就白打了
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stashDraft() }
        }
        .onChange(of: pickedItems) { _, items in loadPicked(items) }
        // ⚠️⚠️ **这七张合成了一张**（见 `ChatPanel`）。
        //
        // 以前是七个 `.sheet(isPresented:)` 一个接一个串在这同一个 view 上，
        // 加上别的一共十四个。SwiftUI 对「同一层挂一大串 presentation」
        // 很脆：这个结构已经害过两次——上一次是气泡上挂五个，
        // 表现是**整个 App 点哪儿都没反应**；她这次报的是
        // **从别的页面回絮语就崩**。
        //
        // 合成一个 `.sheet(item:)` 之后，同一时刻只有一个 presentation 宿主。
        // 以后再加新面板，**往 `ChatPanel` 里加一个 case**，
        // 不要再往这儿续 `.sheet`。
        .sheet(item: $panel) { which in
            switch which {
            case .model:  ModelPickerView(space: space)
            case .prompt: SystemPromptView(space: space)
            case .tools:  ToolToggleView()
            case .poke:
                if let id = app.activeID(for: space) { PokeSheet(conversationID: id) }
            case .memory:
                if let id = app.activeID(for: space) {
                    MemoryLinkView(space: space, conversationID: id)
                }
            case .group:
                if let id = app.activeID(for: space) {
                    GroupSetupView(conversationID: id)
                }
            case .process(let msg):
                ProcessSheet(message: msg)
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
        // 她在书房点了句子边上那个小气泡 → 跳回当时聊的那几句。
        // 书房是从 sheet 里起的，所以先把 sheet 关掉再滚。
        .onChange(of: app.pendingChatJump?.message) { _, msgID in
            guard let msgID, let want = app.pendingChatJump,
                  want.conversation == activeConversation?.id else { return }
            app.pendingChatJump = nil
            destination = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                jumpTo = msgID
            }
        }
        .sheet(item: $shareImage) { item in
            ShareSheet(items: [item.image])
        }
        .photosPicker(isPresented: $showingPhotos, selection: $pickedItems,
                      maxSelectionCount: 6, matching: .images)
        // 一次只收一段。两段视频抽出二十多张图，
        // 他看到的是一堆分不清哪段是哪段的画面
        .photosPicker(isPresented: $showingVideos, selection: $pickedVideo,
                      maxSelectionCount: 1, matching: .videos)
        .onChange(of: pickedVideo) { _, items in loadVideo(items) }
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
                .navigationTitle("编辑")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { editingMessage = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // 改自己那条的时候，两个按钮：存着、改完重发。
                        //
                        // 她问的：「claude code 里可以在模型回复前打断，
                        // 然后自己修改好再发，我的 app 可以吗？」
                        //
                        // 以前要点两次：存一次，再长按一次点「重发」。
                        // 而第二步藏在长按菜单里，**根本看不出来要去那里找**。
                        //
                        // ⚠️ 两个都留着：有时候她只是想把错字改了，
                        // 不想再花一次钱重跑一轮。
                        HStack(spacing: 14) {
                            Button("存着") {
                                if let id = app.activeID(for: space) {
                                    app.editMessage(msg.id, in: id, text: editText)
                                }
                                editingMessage = nil
                            }
                            if msg.role == .user {
                                Button("改完重发") {
                                    if let id = app.activeID(for: space) {
                                        app.editMessage(msg.id, in: id, text: editText)
                                        // `retry` 自己会先 `cancelStream`，
                                        // 正在说着的那一轮不用她先去按停。
                                        app.retry(msg.id, in: id)
                                    }
                                    editingMessage = nil
                                }
                                .fontWeight(.semibold)
                            }
                        }
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

    // MARK: 输入栏拆开的那几块
    //
    // ⚠️ **别再把它们塞回 `inputBar` 里去。**
    //
    // 原来这些全在 `inputBar` 一个函数里：六百行、一百四十六个修饰符，
    // 同一个不透明返回类型。那个类型是一层套一层的 `ModifiedContent`，
    // mangled name 长到 **Swift 解析这个类型名本身就把栈用光了**——
    // 她报的「从其他页面进入絮语就崩溃」，崩溃日志指的就是这儿：
    //
    //     EXC_BAD_ACCESS · Stack Guard（栈溢出）
    //     swift_getTypeByMangledName
    //       → swift_getOpaqueTypeMetadataImpl
    //         → closure #14 in closure #1 in ChatView.inputBar(_:)
    //
    // ⚠️ 这不是「渲染慢」，是**类型系统在建这个 view 的时候递归爆栈**。
    // 所以优化渲染救不了它，只能把那个类型拆小。
    // 每一块现在有自己的不透明类型，各自解析、递归都变浅。

    @ViewBuilder
    private var barVideoBusy: some View {
        if let videoBusy {
            HStack(spacing: 7) {
                ProgressView().scaleEffect(0.7)
                Text(videoBusy)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    /// ⚠️ 这一块**套了 `AnyView`**：类型擦除把元数据的递归从根上切断。
    /// 输入栏一屏只画一次，`AnyView` 那点代价在这儿无所谓，
    /// 而它是防止「类型名长到解析就爆栈」最稳的一道。
    private var barPending: some View {
        AnyView(Group {
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
        })
    }

    @ViewBuilder
    private func barMention(_ conv: Conversation) -> some View {
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
    }

    @ViewBuilder
    private var barListening: some View {
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
    }

    @ViewBuilder
    /// ⚠️ 这一块**套了 `AnyView`**：类型擦除把元数据的递归从根上切断。
    /// 输入栏一屏只画一次，`AnyView` 那点代价在这儿无所谓，
    /// 而它是防止「类型名长到解析就爆栈」最稳的一道。
    private var barVoice: some View {
        AnyView(Group {
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
        })
    }

    @ViewBuilder
    private var barSticker: some View {
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
    }

    @ViewBuilder
    private var barFiles: some View {
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
    }

    @ViewBuilder
    private var barVideo: some View {
        if let v = pendingVideo {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.app(12))
                    .foregroundStyle(app.settings.accentColor)
                Text("一段视频")
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
                Spacer(minLength: 0)
                Button {
                    VideoStore.delete(v)
                    for f in pendingVideoFrames { ImageStore.delete(f) }
                    pendingVideo = nil
                    pendingVideoFrames = []
                    pendingVideoNote = ""
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

    @ViewBuilder
    private var barWaiting: some View {
        if waiting {
            HStack(spacing: 7) {
                Image(systemName: "hourglass")
                    .font(.app(11))
                    .foregroundStyle(app.settings.accentColor)
                Text("已暂存，包含文字、图片与语音。"
                     + "按发送键一起发出，不会自动发；"
                     + "输入框为空时再按暂存键可撤回。")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.softFillDeep))
        }
    }

    @ViewBuilder
    private var barQuote: some View {
        if let q = quoting {
            // ⚠️ `alignment: .top` + `fixedSize`：不这么写的话，
            // 那道竖线会跟着容器一路拉长，中间全是空的（她报的第 11 条）。
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(app.settings.accentColor.opacity(0.6))
                    .frame(width: 3)
                    .frame(maxHeight: 30)
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
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.softFillDeep))
        }
    }

    @ViewBuilder
    /// ⚠️ 这一块**套了 `AnyView`**：类型擦除把元数据的递归从根上切断。
    /// 输入栏一屏只画一次，`AnyView` 那点代价在这儿无所谓，
    /// 而它是防止「类型名长到解析就爆栈」最稳的一道。
    private func barField(_ conv: Conversation) -> some View {
        AnyView(Group {
            TextField(app.settings.inputPlaceholder, text: draftBinding, axis: .vertical)
                .focused($inputFocused)
                .onChange(of: inputFocused) { _, on in
                    // 点进输入框就滚到最底下。
                    // 她说的：「点击输入框应该滚动到最下方才对，
                    // 不然看不见他上面发的消息」——键盘弹起来会顶掉最后几条。
                    if on { typingTick += 1 }
                }
                .onChange(of: draft) { old, text in
                    // 她一开始打字，列表就滑到最底下。
                    // 以前不滑，打字的时候最后那几条被键盘顶上去看不见了。
                    //
                    // ⚠️ **这儿不再递 `typingTick` 了。**
                    // 真正需要滚的只有「输入栏长高了一行」那一下，
                    // 而那一下 `composerHeight` 会变——就在量高度那儿递（见上面）。
                    // 每个字递一次的话，整个消息列表要重新求值、
                    // 还要跑一段带动画的滚动，一秒五六下，
                    // 就是她说的「打字都一卡一卡的」。
                    // 打字的节奏。**只递字数，不递内容**——
                    // 写成字数不是为了省事，是为了那边拿不到内容：
                    // 拿得到就迟早会有人顺手用上。
                    TypingWatcher.shared.typed(from: old.count, to: text.count)
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

        })
    }

    @ViewBuilder
    /// ⚠️ 这一块**套了 `AnyView`**：类型擦除把元数据的递归从根上切断。
    /// 输入栏一屏只画一次，`AnyView` 那点代价在这儿无所谓，
    /// 而它是防止「类型名长到解析就爆栈」最稳的一道。
    private func barTools(_ conv: Conversation) -> some View {
        AnyView(Group {
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
                    Button("视频") { showingVideos = true }
                    Button("文件") { importingFile = true }
                    // 戳一戳也是「发点什么」——发过去的是一件事，不是一句话
                    Button("戳一戳") { panel = .poke }
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
                        // ⚠️ 没有这两行，能点的只有**笔画本身**那几个像素。
                        // 细线图标（.light）尤其难点——她说的「点不了表情和工具」
                        // 就是这个。旁边那个 + 号一直有，所以它一直好用。
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    hideKeyboard()
                    panel = .tools
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.app(15, weight: .light))
                        .foregroundStyle(app.hasActiveTools ? app.settings.accentColor : Theme.textSoft(scheme))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    hideKeyboard()
                    panel = .model
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

                // 开了「我分段发」的时候，这儿是**两个键**：
                // 左边「暂存」把这一条攒进这一轮，右边「直接发送」把攒着的
                // 连同框里这条一起交出去。
                //
                // 以前只有一个键 + 一个倒计时（长按才是马上发）。
                // 她定的：「有时候我想找一个很久的图片发给他，
                // 就会超出我设置的时间，这样有点赶。」
                // ——按钮不会自己走，找多久都行。
                if app.settings.segmentUser, !isRunning {
                    // 已经攒着东西了而且框里是空的 → 这一下是**取消**。
                    //
                    // 她定的：「新增再次点击暂存按钮取消暂存，有时候会误触。」
                    //
                    // ⚠️ 条件里要加 `!canSend`：框里还有字的时候，
                    // 她按它显然是想**再攒一句**，不是想把前面那些撤掉。
                    let undo = waiting && !canSend
                    Button {
                        if undo {
                            // 退回输入框，一个字都不丢
                            let back = app.unstage(conv.id)
                            if !back.isEmpty {
                                let gap = "\n\n"
                                draft = draft.isEmpty ? back : back + gap + draft
                            }
                            if app.settings.haptics {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            inputFocused = true
                        } else {
                            sendCurrent(conv)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Theme.softFillDeep)
                                .frame(width: 36, height: 36)
                            Image(systemName: undo
                                  ? "arrow.uturn.backward"
                                  : "tray.and.arrow.down.fill")
                                .font(.app(13.5, weight: .semibold))
                                .foregroundStyle(undo || canSend
                                                 ? app.settings.primaryColor
                                                 : Theme.textMuted(scheme))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend && !undo)
                    .accessibilityLabel(undo ? "取消暂存" : "暂存")
                }

                Button {
                    if isRunning {
                        app.cancelStream(for: conv.id)
                    } else if app.settings.segmentUser {
                        // 框里还有东西就先攒进去，再一起交出去——
                        // 不然「打了一句直接按发送」会把这一句漏掉
                        if canSend { sendCurrent(conv) }
                        app.flushPending(conv.id)
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
                .disabled(!canSend && !isRunning && !waiting)
                .accessibilityLabel(app.settings.segmentUser ? "直接发送" : "发送")
            }
        })
    }

    private func inputBar(_ conv: Conversation) -> some View {
        VStack(spacing: 8) {

            // 抽帧要跑好几秒。**不摆一个在动的东西在这儿，
            // 她只会以为点坏了**——而且会再点一遍。
            barVideoBusy

            barPending

            // 打了 @ 就把群里的人列出来，点一下补进去
            barMention(conv)

            barListening

            // 刚录好还没发的那段。点左边听一遍，点叉扔掉。
            barVoice

            barSticker

            barFiles

            // 待发的那段视频。**只摆一条，不摆那十二张帧**——
            // 帧是给他看的，她这边看到的应该是「一段视频」这一件东西。
            barVideo

            // 攒着话的时候得给个说法，不然看着像发出去了他却不理你
            barWaiting

            // 她自己的动作和心里话。
            //
            // 她定的：「给我也设置一个动作块心理块，就在我的输入法上方两个选项，
            // 一个动作一个心理，点击后上方出现一个框，可以输入我的动作和心理，
            // 跟他发这些是一样的表达方式。」
            //
            // ⚠️ 走的就是**他那一套标记**（`[[act:]]` / `[[mind:]]`）：
            // 摆出来之前会被剥成气泡上方那两行小字（`MessageBeats`），
            // 而他收到的历史里标记还在——他因此知道她做了什么、没说出口什么。
            // 单独做一套只会变成两种写法，而且他那边读不懂。
            beatRow
            barQuote

            barField(conv)
            barTools(conv)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        // 她定的：**气泡和输入框不要边框**（设置页那些卡片照旧要）。
        // 卡片需要边——它要从背景里分出来；
        // 输入框和气泡不需要——它们本来就有形状，
        // 而且就在手边，描一圈反而把整条变重了。
        .glassBackground(radius: 24, strength: app.settings.glassOpacity, edge: false)
        // ⚠️ 这里以前还有一道影子。**删了。**
        //
        // 两个理由，都是改成「浮在消息上面」之后才成立的：
        // ① 它现在压在消息上，一道摔开的暗影就是把整屏横切一道；
        // ② `.shadow` 盖在 `Material` 上会逼出离屏渲染，
        //    滑动时被跳掉就闪（跟 `GlassEdge` 那句 `.blur` 同一类毛病）。
        //
        // 玻璃本来就不靠影子跟背景分开，靠的是它自己那圈边光。
        .padding(.horizontal, 12)
        // 键盘支起来的时候贴着键盘，收着的时候给底下导航条让出位置
        .padding(.bottom, keyboard.up ? 8 : Layout.tabBarSpace + 26)
    }

    // MARK: 她自己的动作 / 心里话

    /// 输入框上面那两个小按钮，以及点开之后那个框。
    @ViewBuilder
    private var beatRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                beatChip("动作", "act", "chevron.right")
                beatChip("心理", "mind", "quote.opening")
                Spacer(minLength: 0)
            }

            if let kind = beatKind {
                HStack(spacing: 8) {
                    TextField(kind == "act" ? "你做了什么" : "你没说出口的那句",
                              text: $beatText, axis: .vertical)
                        .font(.app(13))
                        .lineLimit(1...3)
                        .focused($beatFocused)
                        .onSubmit { commitBeat() }
                    Button("加上") { commitBeat() }
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(beatText.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Theme.textMuted(scheme)
                                         : app.settings.accentColor)
                        .disabled(beatText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.softFillDeep))
            }
        }
    }

    private func beatChip(_ title: String, _ kind: String, _ icon: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                if beatKind == kind {
                    beatKind = nil
                    beatText = ""
                } else {
                    beatKind = kind
                    beatText = ""
                }
            }
            // 点开就把光标放进去。**少一次点击**——
            // 这个框本来就是为了「顺手补一句」而存在的。
            if beatKind != nil { beatFocused = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.app(9, weight: .semibold))
                Text(title).font(.app(11.5))
            }
            .foregroundStyle(beatKind == kind
                             ? app.settings.accentColor : Theme.textMuted(scheme))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.softFillDeep))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 把这一条落进草稿。
    ///
    /// ⚠️ **摆在草稿最前面。** 动作和心里话是那句话的背景，
    /// 先发生、后开口；缀在后面读起来是「说完了再补个动作」。
    private func commitBeat() {
        let t = beatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = beatKind, !t.isEmpty else { return }
        let br = "\n"
        let mark = "[[" + kind + ":" + t + "]]"
        draft = draft.isEmpty ? mark : mark + br + draft
        beatText = ""
        withAnimation(.easeOut(duration: 0.16)) { beatKind = nil }
        // 光标回输入框，她接着打那句话
        inputFocused = true
        typingTick += 1
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
        // 她定的：**气泡和输入框不要边框**（设置页那些卡片照旧要）。
        // 卡片需要边——它要从背景里分出来；
        // 输入框和气泡不需要——它们本来就有形状，
        // 而且就在手边，描一圈反而把整条变重了。
        .glassBackground(radius: 24, strength: app.settings.glassOpacity, edge: false)
        // ⚠️ 这里以前还有一道影子。**删了。**
        //
        // 两个理由，都是改成「浮在消息上面」之后才成立的：
        // ① 它现在压在消息上，一道摔开的暗影就是把整屏横切一道；
        // ② `.shadow` 盖在 `Material` 上会逼出离屏渲染，
        //    滑动时被跳掉就闪（跟 `GlassEdge` 那句 `.blur` 同一类毛病）。
        //
        // 玻璃本来就不靠影子跟背景分开，靠的是它自己那圈边光。
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
            || pendingVideo != nil
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
            await noteTone(shape: shape, step: step, text: text, audio: url)
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
                await noteTone(shape: shape, step: step, text: t.text, audio: url)
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
    private func noteTone(shape: [Double], step: Double, text: String,
                          audio: URL? = nil) async {
        var f = VoiceProsody.features(samples: shape, interval: step, text: text)
        guard f.usable else { return }
        // 音高：从录音本体里算（振幅序列里没有音高这件事）。
        // **套 300ms 硬预算**——`VoiceProsody` 顶上那段留的规矩：
        // 超时就当没这一项，绝不允许挡住她把话发出去。
        if let audio, let t = await VoiceTimbre.analyzeWithBudget(audio) {
            f.pitch = t.pitch
            // 顺手记一句「她的声音什么样」。
            //
            // 描述是分档的（偏低／起伏不大／温厚…），所以同一个人录十条
            // 出来的多半是同一句话——**写回去不会把缓存前缀搞脏**。
            let me = app.settings.userName.isEmpty ? "她" : app.settings.userName
            let line = VoiceTimbre.describe(t, who: me)
            if line != app.settings.herVoiceNote { app.settings.herVoiceNote = line }
        }
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
        // 开了「我分段发」的话，**什么都先攒着**——
        // 文字、图、文件、语音、表情、引用，一样都不例外。
        //
        // 她说的：「我有时候给他发语音想跟他先说下话，
        // 不然只有一个语音他可能不能很好地理解。」
        // 以前一带附件就绕过这条路直接发，于是「先说一句再发语音」
        // 得赶在六秒之内，「先发语音再补一句」根本做不到。
        if app.settings.segmentUser {
            let line = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasStuff = !pendingImages.isEmpty || !pendingGIFs.isEmpty
                || !pendingFiles.isEmpty || pendingSticker != nil || pendingVoice != nil
                || pendingVideo != nil
            guard !line.isEmpty || hasStuff else { return }
            app.queueSend(text: line,
                          images: pendingImages,
                          imageNames: pendingGIFs,
                          files: pendingFiles,
                          sticker: pendingSticker,
                          quoting: quoting,
                          voiceName: pendingVoice ?? "",
                          voiceTone: pendingTone,
                          videoName: pendingVideo ?? "",
                          videoFrames: pendingVideoFrames,
                          videoNote: pendingVideoNote,
                          in: conv.id)
            draft = ""
            mentioning = false
            pendingVoice = nil
            pendingTone = ""
            pendingImages = []
            pendingGIFs = []
            pendingFiles = []
            pickedItems = []
            pendingSticker = nil
            pendingVideo = nil
            pendingVideoFrames = []
            pendingVideoNote = ""
            quoting = nil
            // ⚠️ **暂存完把光标留在输入框里。**
            //
            // 攒着的时候那条「已暂存…」会出现／消失在输入框上面，
            // 输入栏一改结构，SwiftUI 就把 TextField 重建了一遍，
            // 焦点跟着掉——她说「每发送一句就会关闭输入法，
            // 要我重新再点开，有点麻烦」。
            //
            // 分段发本来就是**一句接一句打**的用法，
            // 每打一句都要重新点一下输入框，这个功能就白做了。
            inputFocused = true
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
        let video = pendingVideo ?? ""
        let frames = pendingVideoFrames
        let videoNote = pendingVideoNote
        draft = ""
        pendingVoice = nil
        pendingTone = ""
        pendingImages = []
        pendingGIFs = []
        pendingFiles = []
        pickedItems = []
        pendingSticker = nil
        pendingVideo = nil
        pendingVideoFrames = []
        pendingVideoNote = ""
        quoting = nil
        mentioning = false
        app.send(text: text, images: images, in: conv.id,
                 imageNames: gifs,
                 files: files, sticker: sticker, quoting: quoted,
                 voiceName: voice, voiceTone: tone,
                 videoName: video, videoFrames: frames, videoNote: videoNote)
    }

    /// 看一段视频。
    ///
    /// **两边看到的不是同一样东西**（这是这个功能的整个要点）：
    /// · 她那边 —— `Videos/` 里那份原件，一张封面加播放键，点开就放
    /// · 他那边 —— 均匀抽的十几帧 + 一段说明（「这是静止画面，别当作看过」）
    ///
    /// 以前两样都往她那边塞：输入框里摆着十二张缩略图，
    /// 底下跟着那段本来只说给他听的话。她说「把对他说的话都放在我脸上了」。
    /// 新功能能接在现成的路上就别另开一条——
    /// 另开一条就得把“发图”那一整套（存盘、气泡、重试、备份）
    /// 再走一遍，而那一整套现在是对的。
    ///
    /// ⚠️ **不自己发出去。** 抽完就停在这儿，
    /// 让她看一眼、想说什么再添一句，按发送的是她。
    private func loadVideo(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        pickedVideo = []
        videoBusy = "正在读视频…"
        Task {
            // 先落成一份临时文件。`AVAsset` 要的是一个 URL，
            // 而 PhotosPicker 给的是字节。
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run { videoBusy = nil }
                return
            }
            // ⚠️ 原件**留下来**，别抽完帧就删。
            // 帧是给他看的，原件是给她看的——她发的是一段视频，
            // 她那边就该是一段能点开放的视频。
            let saved = VideoStore.save(data)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("要看的-" + UUID().uuidString + ".mov")
            try? data.write(to: tmp, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tmp) }

            // 回调本身就是 `@MainActor` 的（见 `VideoDigest.digest`），
            // 所以这儿直接改就行，不用再包一层 `Task { @MainActor in }`
            let r = await VideoDigest.digest(of: tmp) { line in
                videoBusy = line
            }

            await MainActor.run {
                videoBusy = nil
                // 换行统一走这个常量，别在底下散写。
                // ⚠️ 反斜杠第十次栽在「heredoc → Python 字符串 → 文件」
                // 那条路上，就是在这几行。写一次、用三遍，
                // 下次再有人拿脚本改这一段也少三个机会写错。
                let br = "\n"
                guard !r.frames.isEmpty, let saved else {
                    // 一帧都没抽出来。**别闷声**——
                    // 什么都不发生的话她只会觉得点坏了。
                    // 存下来的那份原件也一起清掉，别留个放不出内容的孤儿。
                    if let saved { VideoStore.delete(saved) }
                    draft += (draft.isEmpty ? "" : br) + (r.trouble.isEmpty
                        ? "〈这段视频读不出来〉" : "〈" + r.trouble + "〉")
                    return
                }
                // ⚠️ **帧不进 `pendingImages`，说明不进 `draft`。**
                //
                // 以前是两样都往她那边塞：输入框里摆着十二张缩略图，
                // 底下跟着一段「均匀抽了 12 帧给你看，你看到的是静止画面…」——
                // 那段话是**说给他听的**，却印在了她的气泡上。
                // 她的原话：「把对他说的话都放在我脸上了。」
                //
                // 现在两边各拿各的：她拿原件（一张封面 + 播放键），
                // 他拿帧和那段说明。见 `ChatMessage.videoName`。
                pendingVideo = saved
                pendingVideoFrames = r.frames.compactMap { ImageStore.save($0) }
                pendingVideoNote = r.note
                if !r.trouble.isEmpty { pendingVideoNote += br + "〈" + r.trouble + "〉" }
                typingTick += 1
            }
        }
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
    var onOpenMenu: (ChatMessage, Int) -> Void = { _, _ in }
    var onCloseMenu: () -> Void = {}
    var onEdit: (ChatMessage) -> Void = { _ in }
    var onRetry: (ChatMessage) -> Void = { _ in }
    /// 点了「过程」那条。弹窗归聊天页挂，不挂在气泡上。
    var onOpenProcess: (ChatMessage) -> Void = { _ in }
    var onOpenLibrary: (String) -> Void = { _ in }
    /// 长按头像 @ 这个人
    var onMention: (String) -> Void = { _ in }
    /// 这个窗口是不是正在等他回话
    var running: Bool = false
    /// 她每敲一下这个数就变。变了就滚到底——
    /// 打字的时候最后几条会被键盘顶上去，不滚就看不见自己在回哪一句。
    var typingTick: Int = 0
    /// 底下要留多高的空。输入栏浮在消息上面，不留的话
    /// 最后一条会永远压在那块玻璃底下。由 `ChatView` 量出来传进来。
    var bottomInset: CGFloat = 106
    /// 从聊天记录搜索点进来的那一条：滚过去，别停在最底下
    var jumpTo: UUID? = nil
    var onJumped: () -> Void = {}

    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    /// 离底还远不远。**只记一个布尔**，理由见下面那个 onScrollGeometryChange。
    @State private var awayFromBottom = false

    /// 这一条是不是「这一天的第一条」。是就返回那天，好横一道分隔。
    private func daybreak(at index: Int) -> Date? {
        let msgs = conversation.messages
        guard index >= 0, index < msgs.count else { return nil }
        let now = msgs[index].createdAt
        guard index > 0 else { return now }
        return Calendar.current.isDate(now, inSameDayAs: msgs[index - 1].createdAt)
            ? nil : now
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if conversation.messages.isEmpty {
                        emptyHint.padding(.top, 100)
                    }
                    ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                        // 换天了就横一道。以前一整条时间线是连着的，
                        // 昨晚睡前那句和今早第一句挨在一起，看着像同一段话。
                        if let day = daybreak(at: index) {
                            DayMark(date: day)
                        }
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
                            onOpenMenu: { page in onOpenMenu(message, page) },
                            onRetry: { onRetry(message) },
                            onOpenProcess: { onOpenProcess(message) },
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

                    // 这一格既是滚动的锚点，也负责上报「底还在不在视野里」。
                    //
                    // ⚠️ **不用 `onScrollGeometryChange`**——那个要 iOS 18，
                    // 这个工程的部署目标是 17。
                    //
                    // ⚠️ 而且**只在布尔翻转的时候才写 state**。
                    // 每滚一像素写一次的话，就是每一帧重建整个列表——
                    // 那正是她报过好几次的那种卡。
                    Color.clear.frame(height: 1).id("__bottom")
                        .background {
                            GeometryReader { g -> Color in
                                let y = g.frame(in: .global).minY
                                let far = y > UIScreen.main.bounds.height + 300
                                if far != awayFromBottom {
                                    DispatchQueue.main.async {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            awayFromBottom = far
                                        }
                                    }
                                }
                                return Color.clear
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.top, 100)
                // 底下留出输入栏那么高的空。
                // 消息现在会**铺到输入栏背后**（它是浮在上面的一块玻璃），
                // 不留这一段的话最后一条会永远压在它底下。
                .padding(.bottom, bottomInset)
            }
            .scrollDismissesKeyboard(.interactively)
            // 回到底部。她要的：「一个圈圈上面一个↓就行，跟着玻璃变换。」
            //
            // ⚠️ 只在**离底还远**的时候出现——一直挂着的话它就成了
            // 输入栏上方一块永远在挡字的东西。
            .overlay(alignment: .bottomTrailing) {
                if awayFromBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.28)) {
                            proxy.scrollTo("__bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.app(14, weight: .semibold))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(width: 38, height: 38)
                            .glassBackground(radius: 19,
                                             strength: app.settings.glassOpacity)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                    .padding(.bottom, bottomInset + 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            // 正文、思考链、工具调用，只要有一样在往外冒字，就跟着滚
            .onChange(of: conversation.scrollTick) { _, _ in
                proxy.scrollTo("__bottom", anchor: .bottom)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
            // ⚠️ 这一条要**等布局先稳下来**。
            //
            // 她报的：「有时候分段发送的时候，会突然所有气泡
            // 全部上升到屏幕外面，消息发送后恢复。」
            //
            // 暂存那一下有两件事**同时**发生：
            //   ① `typingTick` 变了 → 这儿立刻滑到底
            //   ② 「已暂存」那条出现 → 输入栏变高 → 列表可用高度跟着变
            //
            // 于是 `scrollTo` 拿的是**变化前**那套布局，
            // 滑到一个马上就失效的位置；而 `withAnimation` 又把这个
            // 中间态**放大成一段看得见的飞出去**。
            //
            // `Task { @MainActor }` 把它挤到下一轮：那时候输入栏已经量完了、
            // `composerHeight` 也更新完了，滑的才是真的底。
            //
            // ⚠️ 记一句：**布局正在变的时候别滑，更别带动画滑。**
            .onChange(of: typingTick) { _, _ in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("__bottom", anchor: .bottom)
                    }
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
                    // 改过好几版的，删除分两条。
                    //
                    // 她定的：「应该只删掉一版，而不是整个都删掉。」
                    // 一条改过三版的消息，她想拿掉的往往只是写坠了的那一版，
                    // 而不是这句话本身。
                    if !msg.edits.isEmpty {
                        menuItem("删这一版", "trash") {
                            if let cid {
                                app.deleteEdit(msg.id, in: cid, page: menuEditPage)
                            }
                        }
                    }
                    menuItem(msg.edits.isEmpty ? "删除" : "整条删掉", "trash") {
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
