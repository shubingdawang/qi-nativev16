import SwiftUI

struct MessageBubbleView: View {

    let message: ChatMessage
    let conversationID: UUID
    /// 现在是不是在挑句子
    var selecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: () -> Void = {}
    var onQuote: () -> Void = {}
    var onChoice: (String) -> Void = { _ in }
    var onSpeak: () -> Void = {}
    var onOpenReader: () -> Void = {}
    /// 点开这趟旅行的第几处。她在卡片上停在哪张就从哪张进
    var onOpenJourney: (Journey, Int) -> Void = { _, _ in }
    var onEdit: () -> Void = {}
    /// 同一时刻只有一条开着菜单，所以这个状态放在外面统一管
    var menuOpenID: UUID? = nil
    var onOpenMenu: () -> Void = {}
    /// 重来一次（报错卡住的时候全靠它）
    var onRetry: () -> Void = {}
    /// 点他存图那张卡 → 打开相册。参数是存到哪儿（表情包 / 动图 / 文件夹名）
    var onOpenLibrary: (String) -> Void = { _ in }
    var onCloseMenu: () -> Void = {}
    /// 这条上面要不要挂头像、名字和时间。
    /// 同一个人连着说的几句只在第一句上挂，不然一屏全是头像。
    var showsHeader: Bool = true
    /// 长按头像，把这个人 @ 进输入框。群聊里才接。
    var onMention: (String) -> Void = { _ in }
    /// 翻到第几版。0 = 现在这版，1 起是改之前的旧版。
    /// **放在存储属性后面**——夹在中间会把外面那个按顺序传参的调用搞乱。
    @State private var editPage = 0
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    /// 「他刚才干了什么」那张卡展开了没有
    @State private var showProcess = false
    @State private var pulse = false
    /// 点开的是第几张图
    @State private var previewing = false
    @State private var playingVideo = false
    @State private var previewFile: PreviewFile?
    @State private var openingGame: LocalGame?
    @State private var previewIndex = 0
    @Environment(\.openURL) private var openURL

    private var isUser: Bool { message.role == .user }

    var body: some View {
        // 旁白（她戳他那一下）不套气泡、不挂头像：
        // **那句话不是她说的，是那件事发生了**。
        // 摆在整行正中，跟两边的对话分开。
        if message.narration {
            Text(message.content)
                .font(.app(12))
                .italic()
                .foregroundStyle(Theme.textMuted(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
        } else {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                if showsHeader { header }
                content
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
    }

    // MARK: 头上那一行

    /// 头像 + 名字 + 时间。自己说的话这一行是右对齐的，
    /// 头像在最右边，跟气泡一个边。
    private var header: some View {
        HStack(spacing: 7) {
            if isUser { Spacer(minLength: 0) }
            if !isUser {
                AvatarView(name: displayName, image: avatarImage, size: 26)
                    // 群聊里长按头像，名字直接进输入框——
                    // 比在候选条里翻名字快，也是她原本习惯的那个动作
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration: 0.32) {
                        guard app.conversation(conversationID)?.isGroup == true else { return }
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        onMention(displayName)
                    }
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 1) {
                // ⚠️ 名字**不换衬线**，她要苹果自带那套。
                // （我上一版给它换成了宋体，她说不用——名字天天在眼前，
                //   那不是"标题"，是她看惯的东西。别再改回去。）
                Text(displayName)
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(Self.stamp.string(from: message.createdAt))
                    .font(.app(9.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            if isUser { AvatarView(name: displayName, image: avatarImage, size: 26) }
            if !isUser { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 2)
    }

    private var displayName: String {
        if isUser {
            return app.settings.userName.isEmpty ? "我" : app.settings.userName
        }
        if !message.senderName.isEmpty { return message.senderName }
        return app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName
    }

    /// 群聊里每位可以有自己的头像，没设就退回全局那两张
    private var avatarImage: UIImage? {
        if isUser {
            return app.settings.userAvatarName.flatMap { ImageStore.cached($0) }
        }
        if !message.senderName.isEmpty,
           let member = app.conversation(conversationID)?.members
            .first(where: { $0.name == message.senderName }),
           let name = member.avatarName,
           let img = ImageStore.cached(name) {
            return img
        }
        return app.settings.aiAvatarName.flatMap { ImageStore.cached($0) }
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    @ViewBuilder
    private var content: some View {
        // 歌是单独一张卡
        if let track = message.track {
            HStack {
                if isUser { Spacer(minLength: 20) }
                MusicCard(track: track,
                          caption: message.trackCaption.isEmpty ? "给你放的" : message.trackCaption)
                    .contextMenu {
                        Button(role: .destructive) {
                            app.deleteMessage(message.id, in: conversationID)
                        } label: {
                            Label("删掉", systemImage: Icon.trash)
                        }
                    }
                if !isUser { Spacer(minLength: 20) }
            }
        }
        // 娃娃那张挂件卡删了（她说「有点无聊」）。
        // 老聊天记录里可能还留着 widget == "doll" 的消息，
        // 现在它们就是一条普通空消息，不再画卡片。
        // 旅行是单独一张卡，不套气泡
        else
        if let journey = message.journey {
            HStack {
                if isUser { Spacer(minLength: 20) }
                JourneyCard(journey: journey) { at in onOpenJourney(journey, at) }
                if !isUser { Spacer(minLength: 20) }
            }
        }
        // 笔记单独一张卡，不套气泡
        else
        if message.noteLoading {
            HStack {
                if isUser { Spacer(minLength: 30) }
                noteSkeleton
                if !isUser { Spacer(minLength: 30) }
            }
        }
        else if let note = message.note {
            HStack {
                if isUser { Spacer(minLength: 30) }
                noteCard(note)
                if !isUser { Spacer(minLength: 30) }
            }
        }
        // 一通电话。**单独一张卡，不是气泡**——
        // 她说「语音通话的卡片框不对，只有气泡」。
        if message.callSeconds > 0 {
            HStack {
                if isUser { Spacer(minLength: 40) }
                callCard
                if !isUser { Spacer(minLength: 40) }
            }
        }
        // 他写的那个能玩的东西。点一下就在 App 里跑起来。
        if !message.gameID.isEmpty {
            HStack {
                if isUser { Spacer(minLength: 40) }
                gameCard
                if !isUser { Spacer(minLength: 40) }
            }
        }
        // 视频也是单独一条：一张封面 + 播放键，点开就放。
        //
        // ⚠️ **这儿不摆那十几帧，也不摆那段说明。**
        // 帧和说明是发给他的（他读不了视频），
        // 她这边看到的应该就是「一段视频」这一件东西。
        // 她的原话：「在我的视角应该就是一个视频带着播放键可以点开查看的。」
        if !message.videoName.isEmpty {
            HStack {
                if isUser { Spacer(minLength: 40) }
                videoCard
                if !isUser { Spacer(minLength: 40) }
            }
        }
        // 语音是单独一条：一个毛玻璃的条，下面一行小字是他说的原话。
        // 不套气泡——语音本身就已经是一块了，再包一层会显得很闷。
        else if !message.voiceName.isEmpty {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                voiceBar
                if !message.content.isEmpty {
                    Text("\u{201C}" + message.content + "\u{201D}")
                        .font(.app(12))
                        .italic()
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: 250, alignment: isUser ? .trailing : .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
        // 表情消息不带气泡、不带底框，只显示动图本身
        else if let sid = message.stickerID,
           let sticker = StickerStore.shared.sticker(id: sid) {
            HStack {
                if isUser { Spacer(minLength: 40) }
                StickerImage(sticker: sticker, size: 116)
                    .contextMenu {
                        Text(sticker.name)
                        Button(role: .destructive) {
                            app.deleteMessage(message.id, in: conversationID)
                        } label: {
                            Label("删掉", systemImage: Icon.trash)
                        }
                    }
                if !isUser { Spacer(minLength: 40) }
            }
        } else {
        HStack(alignment: .top, spacing: 8) {
            if selecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.app(19))
                    .foregroundStyle(isSelected ? app.settings.accentColor : Theme.textMuted(scheme).opacity(0.5))
                    .padding(.top, 6)
            }
            // 留白只留一点点：说的话该按文字长短自己撑开，
            // 长句子就该几乎铺满一屏，不是被硬掐在半屏宽
            if isUser { Spacer(minLength: 24) }

            // 一条消息里各块之间的间距，跟消息与消息之间**取同一个数**（10），
            // 这样整屏看下来所有气泡的缝都是一样宽的，不会有的挤有的松
            VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {

                // 幕外那几行：动作／神态 + 心里话。气泡上方淡淡地摞着，
                // 不带气泡也不带底。**有几条摆几条**，按他写的先后。
                if !shownBeats.isEmpty {
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                        // ⚠️ 按**位置**认，不按 id 认。
                        // 现抠出来的那几条每重画一次就是一批新 UUID，
                        // 按 id 认的话 SwiftUI 会当成「整批换了」，
                        // 流式的时候这几行会一直闪。
                        ForEach(Array(shownBeats.enumerated()), id: \.offset) { _, beat in
                            BeatLine(beat: beat, isUser: isUser)
                        }
                    }
                    .padding(.leading, 2)
                    .padding(.bottom, 1)
                }

                // 说话的人不在这儿标了——上面那行头像已经写着名字，
                // 再标一次是同一句话说两遍

                // 他自己浮上来的那一条，标一行淡淡的小字。
                //
                // ⚠️ 只是个记号——这条**在上下文里跟普通回复一样**。
                // 她回一句「你刚才怎么突然找我」，他接得上。
                if message.wokeUp {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.app(8))
                        Text("他自己找来的")
                            .font(.app(9.5))
                    }
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.75))
                    .padding(.leading, 2)
                }

                // 引用了谁的哪句话
                if !message.quotedText.isEmpty {
                    quoteBlock
                }

                if !message.imageNames.isEmpty {
                    imageRow
                }

                if !message.files.isEmpty {
                    fileRow
                }

                // 思考链和工具**合成一张卡**（她给的 p5–p6 那种）。
                // 以前是上下两块各带一个标题，一轮里他想一下、调三个工具，
                // 屏幕上就先出一条「想了一会儿」再出一条「叮叮咣咣了 3 下」——
                // 两条都在说同一件事：他刚才干了什么。
                processBlock

                // 存了图的话，先出一张小卡，比那行工具日志好看得多
                ForEach(message.toolRuns.filter { $0.hasCard }) { run in
                    // 点一下直接进相册那一页（她要的）。
                    // 存完只给一张看不了的小卡，等于告诉她「存好了，自己去找」。
                    // 存的那张点进去看；**删的那张不点**——
                    // 东西已经不在那儿了，跳过去只会让她扑个空
                    if run.cardDeleted {
                        saveCard(run)
                    } else {
                        Button { onOpenLibrary(run.cardPlace) } label: {
                            saveCard(run)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // （工具那一块已经并进上面那张卡了）

                if !message.choices.isEmpty {
                    choiceBlock
                }

                if let error = message.errorText {
                    // 报错气泡以前是块**死的**红方块：不能长按、没有按钮，
                    // 网断一次这一窗就再也接不下去了。现在底下挂两个按钮。
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.white)
                        HStack(spacing: 10) {
                            Button("重试") { onRetry() }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("·").foregroundStyle(.white.opacity(0.5))
                            Button("删掉这条") {
                                app.deleteMessage(message.id, in: conversationID)
                            }
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.85)))
                } else if message.callSeconds > 0 {
                    // 通话那条的正文是小结，**已经画在通话卡里面了**。
                    // 不挡一道的话它会在卡底下再来一个气泡，
                    // 同一段话出现两遍。
                    EmptyView()
                } else if !message.content.isEmpty {
                    // 一段一段分开发，跟原来那样，不是糊成一大坨
                    ForEach(Array(contentSegments.enumerated()), id: \.offset) { _, seg in
                        bubble(seg)
                    }
                } else if message.isStreaming {
                    TypingIndicator()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(bubbleShape)
                }

                // 改过的话，底下挂一个 ‹1/3› ——翻得回去看原来写的什么。
                // **只是看**，翻到旧版不会改数据，松手回到最新那版。
                if !message.edits.isEmpty {
                    editHistoryBar
                }

                if let tokens = message.totalTokens, !isUser {
                    Text("\(tokens) tokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !isUser { Spacer(minLength: 24) }
        }
        .overlay {
            // 挑句子的时候，整条都能点
            if selecting {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .onTapGesture { onToggleSelect() }
            }
        }
        .overlay(alignment: .topTrailing) {
            if message.starred && !selecting {
                Image(systemName: "star.fill")
                    .font(.app(9))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        }
    }

    // MARK: 组件

    private func bubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // fillWidth: false —— 气泡跟着字数走，不再一律撑成最长的那行
            MarkdownText(text: text, fontSize: app.settings.fontSize, fillWidth: false)
                .foregroundStyle(Theme.textMain(scheme))

            // 译文贴在原文下面，中间一条虚线隔开
            if message.isTranslating {
                Text("正在读取…")
                    .font(.system(size: max(11, app.settings.fontSize - 3)))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else if let t = message.translation, !t.isEmpty {
                DashedLine()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.45))
                    .frame(height: 1)
                Text(t)
                    .font(.system(size: max(11, app.settings.fontSize - 2)))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(bubbleShape)
        // ⚠️ 这儿以前有一句 .textSelection(.enabled)。**它把长按吃掉了**——
        // iOS 的文字选择自带长按手势，优先级比我们这条高，
        // 于是长按弹出来的是系统那个「拷贝 | 分享…」，
        // 我们的横条菜单（编辑/收藏/引用/念出来/翻译/删除）一个都出不来。
        // 想选字就双击进全屏那一页，那边的 textSelection 还留着。
        // 顺手把「复制」补进横条里，省得没了系统菜单反而拷不了。
        // 双击进全屏，长按出横条菜单。
        // 双击写在前面，不然长按会先把它吃掉。
        .onTapGesture(count: 2) {
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onOpenReader()
        }
        .onLongPressGesture(minimumDuration: 0.32) {
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onOpenMenu()
        }
        // ⚠️ 这儿原来挂着那条横菜单，**两个毛病**：
        //   ① 八个按钮排成一条，长得出屏幕；
        //   ② 点了没反应——菜单开着的时候 ChatView 在整屏上盖了一层
        //      「点别处就关掉」的透明层，那层在气泡**上面**，
        //      所以手指先碰到的是它，菜单只是被关掉，按钮从没被点到。
        // 现在整块挪到 ChatView 那层去了（在透明层之上），排成微信那样的格子。
    }

    /// 改过几版的翻页条。第 n 版里 n = edits.count + 1 是现在这版。
    private var editHistoryBar: some View {
        HStack(spacing: 8) {
            Button {
                editPage = max(0, editPage - 1)
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 10))
            }
            .disabled(editPage == 0)

            Text("\(editPage + 1)/\(message.edits.count + 1)")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted(scheme))

            Button {
                editPage = min(message.edits.count, editPage + 1)
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 10))
            }
            .disabled(editPage >= message.edits.count)

            if editPage < message.edits.count {
                Text("改之前的第 \(editPage + 1) 版")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMuted(scheme))
    }

    /// 他存图之后的那张小卡
    private func saveCard(_ run: ToolRun) -> some View {
        HStack(spacing: 10) {
            if let img = ImageStore.cached(run.cardThumb) ?? StickerStore.shared.stickers
                .first(where: { $0.fileName == run.cardThumb })
                .flatMap({ UIImage(contentsOfFile: StickerStore.shared.url(of: $0).path) }) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                let him = app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName
                Text(run.cardDeleted ? "\(him) 删掉了" : "\(him) 存图了")
                    .font(.app(12, weight: .semibold))
                    // 删的用暖橘，存的用主题色。**一眼分得开**——
                    // 存和删长成一个样子，她扫过去只会当成又存了一张。
                    .foregroundStyle(run.cardDeleted ? .orange : app.settings.accentColor)
                Text(run.cardDeleted
                     ? "从「\(run.cardPlace)」里删掉了"
                     : "往「\(run.cardPlace)」里存了一张图")
                    .font(.app(13))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                if !run.cardThought.isEmpty {
                    Text(run.cardThought)
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(2)
                }
                // **撤销。** 只报个丧不给回头路，那张卡就只是讣告。
                // 回收站里没有了（三十天到期清掉）就不再显示这个按钮，
                // 免得她按下去什么也没发生。
                if run.cardDeleted, TrashStore.shared.has(run.cardTrashID) {
                    Button {
                        if TrashStore.shared.restore(run.cardTrashID) {
                            if app.settings.haptics {
                                UINotificationFeedbackGenerator()
                                    .notificationOccurred(.success)
                            }
                        }
                    } label: {
                        Text("撤销")
                            .font(.app(12, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 280, alignment: .leading)
        .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.85)
    }

    /// 读笔记的时候先摆一个同样大小的骨架，别让屏幕空着。
    /// 会呼吸的灰块，比转圈更让人觉得"在动"。
    private var noteSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.textMuted(scheme).opacity(pulse ? 0.18 : 0.09))
                .frame(height: 150)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.textMuted(scheme).opacity(pulse ? 0.18 : 0.09))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.textMuted(scheme).opacity(pulse ? 0.14 : 0.07))
                    .frame(width: 160, height: 10)
                Text(message.noteHint)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.top, 2)
            }
            .padding(11)
        }
        .frame(width: 265)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(red: 1, green: 0.35, blue: 0.4).opacity(0.28), lineWidth: 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    /// 每家一个色，卡片边框和名字都用它。
    /// 一眼能认出这是哪儿来的，比多写一行「来自哔哩哔哩」省地方。
    private func brandColor(_ source: LinkSource) -> Color {
        switch source {
        case .xhs:      return Color(red: 1, green: 0.32, blue: 0.37)
        case .bilibili: return Color(red: 0.98, green: 0.45, blue: 0.62)
        case .douyin:   return Color(red: 0.16, green: 0.86, blue: 0.83)
        }
    }

    /// 链接预览卡（小红书笔记 / B 站视频 / 抖音视频）
    private func noteCard(_ note: XHSNote) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let first = note.localImages.first, let img = ImageStore.cached(first) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 265, height: 150)
                        .clipped()
                    // 视频的封面上盖一个播放三角——不然跟一张图片没区别。
                    // ⚠️ 小红书的视频笔记也要盖：它跟图文笔记是同一个 source，
                    // 只有 `isVideo` 分得开（她说「小红书有纯文字帖子、
                    // 图片帖子、视频帖子」）。
                    if note.source != .xhs || note.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 4)
                            .frame(width: 265, height: 150)
                    }
                    if note.imageCount > 1 {
                        Text("\(note.imageCount) 张")
                            .font(.app(10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(8)
                    }
                    if !note.duration.isEmpty {
                        Text(note.duration)
                            .font(.app(10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(8)
                            .frame(width: 265, height: 150, alignment: .bottomTrailing)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.app(14, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if !note.desc.isEmpty {
                    Text(MD.inline(note.desc))
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    Text(note.author.isEmpty ? note.source.rawValue : note.author)
                        .font(.app(10))
                        .foregroundStyle(brandColor(note.source))
                        .lineLimit(1)
                    if !note.playCount.isEmpty {
                        Label(note.playCount, systemImage: "play.rectangle")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Spacer(minLength: 0)
                    if !note.likedCount.isEmpty {
                        Label(note.likedCount, systemImage: "heart")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    if !note.commentCount.isEmpty {
                        Label(note.commentCount, systemImage: "bubble.left")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .labelStyle(.titleAndIcon)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 265)
        // ⚠️ **封面要跟着卡片一起圆角。**
        //
        // 卡片自己是圆的（`glassBackground(radius: 16)`），可顶上那张封面
        // 是方的，四个直角就从圆角里**扎出来**——她报的就是这个。
        // `clipped()` 只把图裁到 265×150 那个方框，裁不出圆角。
        //
        // 记一句：**圆角的容器里放图，图要自己也圆一次。**
        // 背景圆了不等于内容圆了，它们是两层。
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(brandColor(note.source).opacity(0.3), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if let u = URL(string: note.url) { openURL(u) }
        }
        .contextMenu {
            Button(role: .destructive) {
                app.deleteMessage(message.id, in: conversationID)
            } label: {
                Label("删掉", systemImage: Icon.trash)
            }
        }
    }

    /// 他写的那个能玩的东西。
    ///
    /// ⚠️ 卡上**不显示代码**。她要的是点开就玩，
    /// 代码摆出来只是把「一段贴在聊天里的 HTML」换了个更好看的框。
    private var gameCard: some View {
        let game = GameStore.shared.games.first { $0.id.uuidString == message.gameID }
        return Button {
            if let game { openingGame = game }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: game == nil ? "questionmark.square.dashed" : "gamecontroller.fill")
                    .font(.app(17))
                    .foregroundStyle(app.settings.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.gameName.isEmpty ? "他做的东西" : message.gameName)
                        .font(.app(14, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    // 删掉了就说删掉了，**别摆一个点下去没反应的卡**
                    Text(game == nil ? "已经从游戏间里删掉了" : "点一下就玩")
                        .font(.app(10.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                Spacer(minLength: 0)
                if game != nil {
                    Image(systemName: "chevron.right")
                        .font(.app(10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: 240, alignment: .leading)
            .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.85)
        }
        .buttonStyle(.plain)
        .fullScreenCover(item: $openingGame) { g in
            GamePlayerView(game: g)
        }
    }

    /// 一通电话那张卡。
    ///
    /// ⚠️ **通话记录不该长得跟他说的话一样。** 那不是一句话，是一件事。
    /// 正文（小结）是彩头：写成功了摆在下面，没写成功这张卡照样在。
    private var callCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .font(.app(13))
                    .foregroundStyle(app.settings.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(app.settings.accentColor.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("语音通话")
                        .font(.app(13.5, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(callLength)
                        .font(.app(10.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                Spacer(minLength: 0)
            }
            // 小结。**跟标题之间横一道线**——那是两件事：
            // 上面是「打了一通电话」，下面是「都聊了什么」。
            let said = parsed.clean.trimmingCharacters(in: .whitespacesAndNewlines)
            if !said.isEmpty {
                Hairline()
                MD.inline(said)
                    .font(.app(12.5))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: 265, alignment: .leading)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity * 0.9)
        .contextMenu {
            Button(role: .destructive) {
                app.deleteMessage(message.id, in: conversationID)
            } label: {
                Label("删掉", systemImage: Icon.trash)
            }
        }
    }

    /// 讲了多久。**过一分钟就说「几分几秒」**，
    /// 光说「137 秒」她还得自己心算。
    private var callLength: String {
        let s = Int(message.callSeconds.rounded())
        if s < 60 { return "\(s) 秒" }
        let m = s / 60, r = s % 60
        return r == 0 ? "\(m) 分钟" : "\(m) 分 \(r) 秒"
    }

    /// 视频卡。封面用抽出来的第一帧——那一帧本来就有，不用再解一次码。
    ///
    /// ⚠️ 原件不在了（换机、备份没带上）就摆一句实话，
    /// **别摆一个点下去没反应的播放键**。
    private var videoCard: some View {
        let cover = message.videoFrames.first.flatMap { ImageStore.cached($0) }
        let playable = VideoStore.exists(message.videoName)
        return Button {
            guard playable else { return }
            playingVideo = true
        } label: {
            ZStack {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 220, height: 150)
                        .clipped()
                } else {
                    Color.black.opacity(0.35)
                        .frame(width: 220, height: 150)
                }
                if playable {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Text("这段视频的原件不在了")
                        .font(.app(11))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.45)))
                }
            }
            .frame(width: 220, height: 150)
            // 圆角要自己切一次——`clipped()` 只裁方框，裁不出圆角
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $playingVideo) {
            VideoPlayerSheet(name: message.videoName)
        }
        .contextMenu {
            Button(role: .destructive) {
                app.deleteMessage(message.id, in: conversationID)
            } label: {
                Label("删掉", systemImage: Icon.trash)
            }
        }
    }

    /// 语音条。点一下放，再点停。
    private var voiceBar: some View {
        let playing = VoicePlayer.shared.playingName == message.voiceName
        let seconds = Int(VoiceStore.duration(message.voiceName))
        return Button {
            VoicePlayer.shared.toggle(message.voiceName)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.app(12))
                    .foregroundStyle(app.settings.accentColor)

                // 几根高低不一的竖条，装个声波的样子。
                // 根数跟着时长走——三秒和四十秒不该长得一样。
                HStack(spacing: 2.5) {
                    ForEach(0..<waveCount(seconds), id: \.self) { i in
                        Capsule()
                            .fill(app.settings.accentColor.opacity(playing ? 0.85 : 0.45))
                            .frame(width: 2, height: waveHeight(i))
                    }
                }

                Text("\(seconds)″")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(width: voiceWidth(seconds), alignment: .leading)
            .glassBackground(radius: 22, strength: app.settings.glassOpacity)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 语音条多宽。**按时长长短**（她说的第 5 条）——
    /// 以前一律 230，三秒和四十秒长得一模一样，看不出哪条更长。
    ///
    /// 微信那种是「越长越宽，但有上限」：
    /// 一秒起步 120，之后每秒加 5，最宽到 260 就不再长了。
    /// 再宽就顶到屏幕边，反而不好看。
    private func voiceWidth(_ seconds: Int) -> CGFloat {
        let s = max(1, min(60, seconds))
        return min(260, 120 + CGFloat(s) * 5)
    }

    /// 波形画几根。跟着宽度走，不然短条子里挤 14 根、长条子里又空着一截。
    private func waveCount(_ seconds: Int) -> Int {
        let usable = voiceWidth(seconds) - 100      // 减掉按钮、秒数和留白
        return max(5, min(22, Int(usable / 4.5)))
    }

    /// 固定的一组高度，看着像波形又不会每次刷新都乱跳
    private func waveHeight(_ i: Int) -> CGFloat {
        let pattern: [CGFloat] = [6, 11, 8, 15, 10, 18, 12, 16, 9, 14, 7, 12, 8, 5]
        return pattern[i % pattern.count]
    }

    /// 他抛过来的几个选项，点一下那句话就成了你的下一条消息
    private var choiceBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !message.choiceQuestion.isEmpty {
                Text(message.choiceQuestion)
                    .font(.app(14))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            if !message.chosenOption.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.app(11))
                        .foregroundStyle(app.settings.accentColor)
                    Text("已选：\(message.chosenOption)")
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .padding(.top, 2)
            } else {
            ForEach(message.choices, id: \.self) { option in
                Button {
                    onChoice(option)
                } label: {
                    HStack {
                        Text(option)
                            .font(.app(13))
                            .foregroundStyle(Theme.textMain(scheme))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.app(10, weight: .semibold))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(app.settings.accentColor.opacity(0.16))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
        .padding(12)
        .glassBackground(radius: 18, strength: app.settings.glassOpacity * 0.85)
    }

    /// 引用条：左边一道竖线，上面是被引用者的名字
    ///
    /// ⚠️ 她报的第 11 条：「引用句子间隔太大了，根据文字长短决定宽度就行」。
    /// 两处毛病：
    /// · 里面塞了个 `Spacer(minLength: 0)`，**它会把这条撑到 240 满宽**——
    ///   引一句「嗯」也占一整条，看着像一块空板子。
    /// · 竖线没给高度，容器一被撑高它就跟着拉长，中间全是空的。
    /// 现在：宽度按字走（240 只当上限），高度只包住字。
    private var quoteBlock: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(app.settings.accentColor.opacity(0.6))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.quotedName)
                    .font(.app(10, weight: .medium))
                    .foregroundStyle(Theme.textMuted(scheme))
                Text(MD.inline(message.quotedText))
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 240, alignment: .leading)
        .glassBackground(radius: 12, strength: app.settings.glassOpacity * 0.8)
    }

    /// 按空行把回复切成几段，每段单独一个气泡。
    /// 段与段的间距跟思考链、工具卡片之间是同一个值。
    ///
    /// 开关在「设置 → 通用设置 → 他分段发」。关着就一整段一个气泡——
    /// 有人就是喜欢一大块读完，不喜欢消息一条条弹。
    /// 现在屏幕上该显示哪一版。翻到旧版就显示旧版，翻回 0 就是最新的。
    private var shownContent: String {
        guard editPage > 0, editPage <= message.edits.count else { return message.content }
        // edits 里最早的在最前面，而 ‹› 是往回翻，所以要倒着数
        return message.edits[message.edits.count - editPage]
    }

    /// 正文里的标记，**在这儿再抠一遍**。
    ///
    /// 落库那一遍在 `finishStreaming`，一轮只跑一次，所以有三种情况漏网：
    /// · 字还在一个个蹦出来的时候（那一遍还没跑）
    /// · 那一轮中途断了（那一遍根本没跑到）
    /// · `[[cot:]]` 写在正文里（那一遍只在 thinking 里认）
    /// 三种她都截到了。**摆出来之前先抠，比在落库那边补分支稳。**
    ///
    /// 抠干净的正文和抠出来的东西都从这儿走，底下不再直接用 `shownContent`。
    /// ⚠️ 这个属性**每次重画都会跑**，而流式的时候一秒重画好多次。
    /// 所以先拿 `contains` 挡一道：没有标记就原样退回去，
    /// 别为了一条没有标记的长消息把正则跑上几百遍。
    private var parsed: (clean: String, beats: [MessageBeat], cot: String) {
        let raw = shownContent
        guard raw.contains("[[") || raw.contains("*") || raw.contains("〔")
        else { return (raw, [], "") }
        return MessageBeats.extract(raw)
    }

    /// 幕外那几行。落库那一遍跑过了就用存下来的（老消息的 `actionText` 也在里面），
    /// 没跑过就用刚抠出来的。**两边不会同时有**——落库那一遍会把正文洗干净。
    private var shownBeats: [MessageBeat] {
        message.displayBeats.isEmpty ? parsed.beats : message.displayBeats
    }

    private var contentSegments: [String] {
        let shownContent = parsed.clean
        guard app.settings.segmentAssistant || isUser else { return [shownContent] }
        let parts = shownContent
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [shownContent] : parts
    }

    /// 思考卡片上的那行字。
    ///
    /// 优先用他自己写的——他在想的过程里可以随时写 [[cot:在想怎么说才不吓着她]]，
    /// 后写的盖掉先写的。写了什么就显示什么，不写才退回秒数。
    /// 报秒数其实没什么意思，"想了 5.6 秒"跟他在想什么毫无关系。

    /// 把思考里最后一个 [[cot:...]] 抠出来
    static func cotLabel(from reasoning: String) -> String? {
        let pattern = #"\[\[cot:\s*([^\]]{1,40})\s*\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = reasoning as NSString
        let matches = regex.matches(in: reasoning, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last, last.numberOfRanges > 1 else { return nil }
        return ns.substring(with: last.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: 他刚才干了什么（思考链 + 工具，一张卡）
    //
    // 出处：她给的参考图里那个 ThoughtProcess——
    // **一个他自己定的标题，点开是一条时间线**，
    // 想的和做的按先后串在一起。
    //
    // 为什么合并：这两块回答的是同一个问题（「他刚才干了什么」），
    // 分成两张卡，一轮就顶掉半屏，而且她要看全还得点两次。

    /// 有没有东西可展开
    private var hasProcess: Bool {
        !(message.reasoning ?? "").isEmpty || !message.toolRuns.isEmpty
    }

    @ViewBuilder
    private var processBlock: some View {
        if hasProcess {
            // ⚠️ spacing 必须是 0，那 6 点的缝**由展开的那一块自己带**。
            //
            // 以前写的是 `VStack(spacing: 6)` + `if showProcess { … }`：
            // 收起来的时候里面只剩一个按钮，可那道缝**是 VStack 记着的**，
            // 收合的动画跑完它还在——她说的「思考链收回会留一段空白」就是它。
            //
            // 记一句：**会消失的那一块，它的间距要跟着它一起消失。**
            // 间距记在容器上，容器不会跟着消失。
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showProcess.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkle")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text(processTitle)
                            .font(.app(13.5, weight: .medium))
                            .lineLimit(1)
                        if message.toolRuns.contains(where: { $0.failed }) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.app(10))
                                .foregroundStyle(.orange)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.app(10, weight: .semibold))
                            .rotationEffect(.degrees(showProcess ? 90 : 0))
                    }
                    .foregroundStyle(Theme.textSoft(scheme))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    // ⚠️ 这里以前写着「附属卡片一律铺满可用宽度」——**改了**。
                    // 她报的第 11 条：宽度该跟着字走。
                    // 「想了 3.2s · 动了 3 下手」就那么几个字，
                    // 铺满一整行之后右边一大块空，看着像加载失败。
                    .fixedSize(horizontal: false, vertical: true)
                    .glassBackground(radius: 16, strength: app.settings.glassOpacity * 0.8)
                }
                .buttonStyle(.plain)

                if showProcess {
                    processTimeline.padding(.top, 6)
                }
            }
        }
    }

    /// 标题。**他自己写的那句优先**——`[[cot:…]]` 是他给这一轮起的名字，
    /// 比我们数出来的「3 步」有意思得多。
    private var processTitle: String {
        if let mine = Self.cotLabel(from: message.reasoning ?? ""), !mine.isEmpty {
            return mine
        }
        // 写在正文里的也算。以前只认 thinking 里的那一句，
        // 所以他写在正文里的时候，标题退回「想了 28.5s · 动了 1 下手」，
        // 而那句名字原样留在气泡上（她报的第一条 cot 没生效）。
        if !message.cotTitle.isEmpty { return message.cotTitle }
        if !parsed.cot.isEmpty { return parsed.cot }
        if message.isStreaming { return "正在想…" }
        var bits: [String] = []
        if !(message.reasoning ?? "").isEmpty {
            if let sec = message.reasoningSeconds, sec > 0 {
                bits.append(String(format: "想了 %.1fs", sec))
            } else {
                bits.append("想了一会儿")
            }
        }
        if !message.toolRuns.isEmpty {
            bits.append("动了 \(message.toolRuns.count) 下手")
        }
        return bits.isEmpty ? "过程" : bits.joined(separator: " · ")
    }

    /// 展开之后那条时间线。左边一条竖线串起来，一步一个点。
    private var processTimeline: some View {
        // spacing 6：横线画在每一段**字完的地方**（见 `step` 底下那个 overlay），
        // 线跟下一段之间再留这么一点，就是她要的「隔一个换行，不要多」。
        VStack(alignment: .leading, spacing: 6) {
            if let r = message.reasoning, !cleanReasoning(r).isEmpty {
                step(icon: "brain", tint: Theme.textMuted(scheme), title: "想了想") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(MD.inline(cleanReasoning(r)))
                            .font(.system(size: max(11, app.settings.fontSize - 3)))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        // 译文。**接在原文底下，不把原文顶掉**——
                        // 她要看懂他想了什么，不是要把原文换掉。
                        if message.isTranslatingReasoning {
                            Text("在翻…")
                                .font(.app(10.5))
                                .foregroundStyle(Theme.textMuted(scheme))
                        } else if let t = message.reasoningTranslation, !t.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Capsule()
                                    .fill(app.settings.accentColor.opacity(0.4))
                                    .frame(width: 2)
                                Text(MD.inline(t))
                                    .font(.system(size: max(11, app.settings.fontSize - 3)))
                                    .foregroundStyle(Theme.textSoft(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    // 她定的：「思考链也需要长按翻译。」
                    //
                    // 他想事情的时候常常整段是英文，
                    // 而那一段恰恰是她最想看懂的（正文他至少会说中文）。
                    //
                    // ⚠️ 用 `contextMenu` 而不是那个横条菜单：
                    // 横条那个是挂在整条消息上的，而这儿要翻的是里面那一块。
                    .contextMenu {
                        Button {
                            app.translate(message.id, in: conversationID, reasoning: true)
                        } label: {
                            Label(message.reasoningTranslation == nil ? "翻译" : "重新翻",
                                  systemImage: "character.book.closed")
                        }
                        if message.reasoningTranslation != nil {
                            Button {
                                app.clearReasoningTranslation(message.id, in: conversationID)
                            } label: {
                                Label("收起译文", systemImage: "chevron.up")
                            }
                        }
                        Button {
                            UIPasteboard.general.string = cleanReasoning(r)
                        } label: {
                            Label("拷贝", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            ForEach(Array(message.toolRuns.enumerated()), id: \.element.id) { i, run in
                step(icon: run.failed ? "xmark" : "wrench.and.screwdriver",
                     tint: run.failed ? .red : app.settings.accentColor,
                     title: run.toolName,
                     note: run.serverName,
                     isLast: i == message.toolRuns.count - 1) {
                    VStack(alignment: .leading, spacing: 3) {
                        if !run.arguments.isEmpty, run.arguments != "{}" {
                            Text(tidy(run.arguments))
                                .font(.app(10.5, design: .monospaced))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // ⚠️ 这两块**都不掐行数**。
                        //
                        // 她说「思考链显示不完全……不是说要把行高固定，
                        // 是根据他们的字数来画横线」——`lineLimit` 就是在固定行高：
                        // 卡片撑到那个数就不再长了，底下的字看不见，
                        // 而那道横线也就画在了「第 12 行」而不是「这段话完的地方」。
                        //
                        // 长会不会太长？`tidy` 已经把空行收到一行以内了，
                        // 而且整张卡默认是收起来的——**是她点开才看的**，
                        // 点开就该看得见全部。
                        Text(MD.inline(tidy(run.result)))
                            .font(.app(11.5))
                            .foregroundStyle(run.failed ? .red : Theme.textSoft(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.7)
    }

    /// 工具回的那段话，摆出来之前先收拾一下。
    ///
    /// 两件事：首尾的空白去掉；**连着两个以上的换行压成一个空行**。
    ///
    /// 记忆搜索那类工具回的是一条条拼起来的清单，
    /// 拼的时候很容易多出几个换行。那几个换行在屏幕上
    /// 就是一大片空白，看着就像“两个工具之间隔得特别远”。
    private func tidy(_ s: String) -> String {
        // ⚠️ 换行走这个常量，不在底下散写 —— 反斜杠已经栽第十一次了。
        // 写一次用两遍，下次拿脚本改这一段也少两个写错的机会。
        let br = "\n"
        var out = ""
        var blanks = 0
        for line in s.components(separatedBy: br) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blanks += 1
                // 最多留一个空行，多出来的一律丢掉
                if blanks > 1 { continue }
            } else {
                blanks = 0
            }
            out += (out.isEmpty ? "" : br) + line
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 时间线上的一步
    @ViewBuilder
    private func step(icon: String, tint: Color, title: String, note: String = "",
                      isLast: Bool = false,
                      @ViewBuilder body: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 9) {
            // 左边那根线和点。**线要连着**——断开的点看着像几件不相干的事
            VStack(spacing: 0) {
                Circle()
                    .fill(tint.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                Rectangle()
                    .fill(Theme.textMuted(scheme).opacity(0.22))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.app(9.5))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.app(12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textMain(scheme))
                    if !note.isEmpty {
                        Text(note)
                            .font(.app(9.5))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                body()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 步与步之间留一行的空 + **一道淡线**。
            //
            // 她说「工具的间隔貌似没改」——上一版我只是把间距从 11 调到 10，
            // 那点差别她当然看不出来。她要的不是「隔远一点」，
            // 是**看得出这是两件事**。所以补一道线：
            // 间距不用再往大调，一道线比十个点的空白管用得多。
            // 她第三次说这个：「使用工具的间隔太大了，
            // 只留一行的距离就行，或者干脆不留。」
            //
            // 前两次我都去调这个 `padding`（11 → 10 → 9），
            // 调了等于没调——**因为那个大空白根本不是间距。**
            // 它是工具回的那段文本自己带回来的一串空行，
            // 而 `lineLimit` 不会替我们收拾它（空行也算行）。
            // 真正的修法在 `tidy` 那儿；这一行顺带收到一行以内。
            //
            // ⚠️ 记一句：**她报「间隔大」的时候，先查内容里有没有空行，
            // 再去动 padding。** 调错地方的后果是“改了三次都没变”。
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                if !isLast { Hairline().padding(.trailing, 30) }
            }
        }
    }

    // ⚠️ 老的 `toolBlock` 删了：它跟思考链那一块**说的是同一件事**
    // （他刚才干了什么），现在并进上面那张 `processBlock` 了。
    // 留着两份的话，改一处另一处就长歪。

    /// 气泡就是一块玻璃。自己和对方的区别靠左右位置，
    /// 不靠颜色——整块染色会变成不透光的塑料片。
    @ViewBuilder
    private var bubbleShape: some View {
        // 有的主题气泡不是玻璃（「家」＝claude.ai 就是）：
        // **她说的话**是一块实心的浅面板，**他说的话根本没有气泡**——
        // 就直接印在纸上。这一档不走 GlassSurface。
        if app.settings.preset.skin.bubbles == .panel {
            if isUser {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(app.settings.preset.skin.cardFill.c(scheme))
            } else {
                Color.clear
            }
        } else {
            ZStack {
                GlassSurface(
                    radius: 18,
                    strength: app.settings.glassOpacity * app.settings.bubbleOpacity,
                    extra: isUser ? 0.35 : 0,
                    // 她定的：**气泡不该有边框**。
                    // 卡片要边（得从背景里分出来），
                    // 气泡不要（本来就有形状，而且一屏几十个）。
                    edge: false
                )
                // 想要一点色的时候才染，默认是 0
                if isUser && app.settings.bubbleTint > 0.01 {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(app.settings.accentColor.opacity(0.30 * app.settings.bubbleTint))
                }
            }
        }
    }

    private var imageRow: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            // 一次发好几张的话，摞成一张能翻的卡——
            // 竖着排下来的话，九张图能把整屏聊天记录顶掉。
            if message.imageNames.count > 1 {
                PhotoStackView(names: message.imageNames) { i in
                    previewIndex = i
                    previewing = true
                }
                // 探边那两张会露到卡片外面去，两边留出地方
                .padding(.horizontal, 30)
                .padding(.vertical, 4)
            } else {
                singleImages
            }
        }
        .fullScreenCover(isPresented: $previewing) {
            ImagePreviewView(names: message.imageNames, index: previewIndex)
        }
    }

    private var singleImages: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            ForEach(Array(message.imageNames.enumerated()), id: \.offset) { idx, name in
                // 会动的走 AnimatedImageView 逐帧播。
                // `Image(uiImage:)` 只画第一帧——她发进来的 gif 在聊天里
                // 会变成一张静图（第 8 条的另一半）。
                Group {
                    if name.lowercased().hasSuffix(".gif") {
                        AnimatedImageView(url: ImageStore.url(for: name))
                            .frame(maxWidth: 220)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if let image = ImageStore.cached(name) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                // 点开看大图：能放大、能看细节。以前聊天里的图点了没反应，
                // 想看清楚只能去相册里找同一张。
                .onTapGesture {
                    previewIndex = idx
                    previewing = true
                }
            }
        }
    }

    private var fileRow: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            ForEach(message.files) { f in
                HStack(spacing: 9) {
                    Image(systemName: f.icon)
                        .font(.app(17))
                        .foregroundStyle(app.settings.accentColor)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.displayName)
                            .font(.app(13, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                            .lineLimit(1)
                        Text(f.sizeText)
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Spacer(minLength: 0)
                    // 摆一个箭头，告诉她这张卡能点。
                    // 光把手势挂上去是不够的——看不出能点就不会有人去点。
                    Image(systemName: "chevron.right")
                        .font(.app(10, weight: .semibold))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 240, alignment: .leading)
                .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.85)
                // 她报的：「点击文件无法预览。」
                // 以前这张卡**根本没挂点击**，纯展示。
                //
                // ⚠️ `contentShape` 不能省：不写的话能点的只有图标和字本身那几个像素，
                // 中间那大片空白是点不到的（跟表情那个图标同一个坑）。
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    let u = FileStore.url(for: f)
                    guard FileManager.default.fileExists(atPath: u.path) else { return }
                    previewFile = PreviewFile(url: u, name: f.displayName)
                }
            }
        }
        .sheet(item: $previewFile) { p in
            FilePreview(url: p.url).ignoresSafeArea()
        }
    }

    /// 思考正文里把标记去掉，那是给卡片标题用的
    private func cleanReasoning(_ text: String) -> String {
        // ⚠️ 空行也要收。思考过程里连着好几个换行很常见，
        // 摆出来就是一大片白——她会当成「这儿断了」。
        // 跟工具那段走**同一个** `tidy`：上一条和下一条之间只留一个空行。
        tidy(text.replacingOccurrences(
            of: #"\[\[cot:[^\]]*\]\]"#,
            with: "", options: .regularExpression
        ))
    }

    // ⚠️ 老的 `reasoningBlock` 删了，理由同 `toolBlock`：两块说的是同一件事，
    // 现在是一张 `processBlock`。
    //
    // 它当年那条注释还是算数的，抄在这儿免得下一窗又改回去：
    // 这张卡**要老老实实往下撑**，别做成"浮起来的气泡"——
    // 浮起来高度是定的，就看不见字在一个一个蹦出来了。
    // （列表会跟着自己滚到底，靠 `conversation.scrollTick`，
    //   那个数把 reasoning 的字数也算进去了。）
}

/// 一枚圆头像。没设图就用名字第一个字顶上，
/// 别摆一个灰色的人形轮廓——那个比什么都不放还难看。
struct AvatarView: View {

    var name: String
    var image: UIImage?
    var size: CGFloat = 26

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(app.settings.accentColor.opacity(0.28))
                    Text(String(name.prefix(1)))
                        .font(.app(size * 0.46, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// 等待回复时的三个跳动小点
struct TypingIndicator: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.secondary)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

/// 译文上面那条虚线
struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}


/// 正在输入。他已经开始回、但一个字还没出来的那几秒，
/// 屏幕上不该是空的——那几秒最容易让人以为断了。
struct TypingBubble: View {

    var name: String = ""
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.32, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if !name.isEmpty {
                    Text(name)
                        .font(.app(11, weight: .medium))
                        .foregroundStyle(app.settings.accentColor)
                        .padding(.leading, 4)
                }
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Theme.textMuted(scheme).opacity(phase == i ? 0.85 : 0.3))
                            .frame(width: 6, height: 6)
                            .offset(y: phase == i ? -2.5 : 0)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .glassBackground(radius: 18, strength: app.settings.glassOpacity)
            }
            Spacer(minLength: 40)
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.22)) {
                phase = (phase + 1) % 3
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
