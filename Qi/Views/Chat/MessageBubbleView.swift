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
    var onOpenJourney: (Journey) -> Void = { _ in }
    var onEdit: () -> Void = {}
    /// 同一时刻只有一条开着菜单，所以这个状态放在外面统一管
    var menuOpenID: UUID? = nil
    var onOpenMenu: () -> Void = {}
    var onCloseMenu: () -> Void = {}
    /// 这条上面要不要挂头像、名字和时间。
    /// 同一个人连着说的几句只在第一句上挂，不然一屏全是头像。
    var showsHeader: Bool = true
    /// 长按头像，把这个人 @ 进输入框。群聊里才接。
    var onMention: (String) -> Void = { _ in }
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showReasoning = false
    @State private var showTools = false
    @State private var pulse = false
    @Environment(\.openURL) private var openURL

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
            if showsHeader { header }
            content
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
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
                Text(displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(Self.stamp.string(from: message.createdAt))
                    .font(.system(size: 9.5))
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
            return app.settings.userAvatarName.flatMap { ImageStore.load($0) }
        }
        if !message.senderName.isEmpty,
           let member = app.conversation(conversationID)?.members
            .first(where: { $0.name == message.senderName }),
           let name = member.avatarName,
           let img = ImageStore.load(name) {
            return img
        }
        return app.settings.aiAvatarName.flatMap { ImageStore.load($0) }
    }

    nonisolated(unsafe) static let stamp: DateFormatter = {
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
        // 旅行是单独一张卡，不套气泡
        else
        if let journey = message.journey {
            HStack {
                if isUser { Spacer(minLength: 20) }
                JourneyCard(journey: journey) { onOpenJourney(journey) }
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
        // 语音是单独一条：一个毛玻璃的条，下面一行小字是他说的原话。
        // 不套气泡——语音本身就已经是一块了，再包一层会显得很闷。
        if !message.voiceName.isEmpty {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                voiceBar
                if !message.content.isEmpty {
                    Text("\u{201C}" + message.content + "\u{201D}")
                        .font(.system(size: 12))
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
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? app.settings.accentColor : Theme.textMuted(scheme).opacity(0.5))
                    .padding(.top, 6)
            }
            // 留白只留一点点：说的话该按文字长短自己撑开，
            // 长句子就该几乎铺满一屏，不是被硬掐在半屏宽
            if isUser { Spacer(minLength: 24) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {

                // 动作／神态：气泡上方淡淡一行，不带气泡也不带底
                if !message.actionText.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                        Text(message.actionText)
                            .font(.system(size: 12))
                            .italic()
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .padding(.leading, 2)
                    .padding(.bottom, 1)
                }

                // 说话的人不在这儿标了——上面那行头像已经写着名字，
                // 再标一次是同一句话说两遍

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

                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    reasoningBlock(cleanReasoning(reasoning))
                }

                // 存了图的话，先出一张小卡，比那行工具日志好看得多
                ForEach(message.toolRuns.filter { $0.hasCard }) { run in
                    saveCard(run)
                }

                if !message.toolRuns.isEmpty {
                    toolBlock
                }

                if !message.choices.isEmpty {
                    choiceBlock
                }

                if let error = message.errorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.85)))
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
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        }
    }

    // MARK: 组件

    private func bubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MarkdownText(text: text, fontSize: app.settings.fontSize)
                .foregroundStyle(Theme.textMain(scheme))

            // 译文贴在原文下面，中间一条虚线隔开
            if message.isTranslating {
                Text("正在翻…")
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
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(bubbleShape)
        .textSelection(.enabled)
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
        .overlay(alignment: isUser ? .topTrailing : .topLeading) {
            if menuOpenID == message.id {
                actionBar
                    .offset(y: -48)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
    }

    /// 长按弹出来的那条横菜单：一条细胶囊，不像系统那个糊住半屏
    private var actionBar: some View {
        HStack(spacing: 0) {
            barItem("编辑") { onEdit() }
            barDivider
            barItem("收藏") { app.toggleStar([message.id], in: conversationID) }
            barDivider
            barItem("引用") { onQuote() }
            barDivider
            barItem(message.voiceName.isEmpty ? "念出来" : "听") { onSpeak() }
            barDivider
            barItem(message.translation == nil ? "翻译" : "收起") {
                if message.translation == nil {
                    app.translate(message.id, in: conversationID)
                } else {
                    app.clearTranslation(message.id, in: conversationID)
                }
            }
            barDivider
            barItem("删除") { app.deleteMessage(message.id, in: conversationID) }
        }
        .padding(.horizontal, 4)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
        .fixedSize()
    }

    private func barItem(_ title: String, run: @escaping () -> Void) -> some View {
        Button {
            onCloseMenu()
            run()
        } label: {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.22))
            .frame(width: 1, height: 14)
    }


    /// 他存图之后的那张小卡
    private func saveCard(_ run: ToolRun) -> some View {
        HStack(spacing: 10) {
            if let img = ImageStore.load(run.cardThumb) ?? StickerStore.shared.stickers
                .first(where: { $0.fileName == run.cardThumb })
                .flatMap({ UIImage(contentsOfFile: StickerStore.shared.url(of: $0).path) }) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName) 存图了")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(app.settings.accentColor)
                Text("往「\(run.cardPlace)」里存了一张图")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                if !run.cardThought.isEmpty {
                    Text(run.cardThought)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(2)
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
                    .font(.system(size: 11))
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

    /// 笔记预览卡
    private func noteCard(_ note: XHSNote) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let first = note.localImages.first, let img = ImageStore.load(first) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 265, height: 150)
                        .clipped()
                    if note.imageCount > 1 {
                        Text("\(note.imageCount) 张")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(8)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if !note.desc.isEmpty {
                    Text(note.desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    Text(note.author.isEmpty ? "小红书" : note.author)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.35))
                    Spacer(minLength: 0)
                    if !note.likedCount.isEmpty {
                        Label(note.likedCount, systemImage: "heart")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    if !note.commentCount.isEmpty {
                        Label(note.commentCount, systemImage: "bubble.left")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .labelStyle(.titleAndIcon)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 265)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(red: 1, green: 0.35, blue: 0.4).opacity(0.3), lineWidth: 1)
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

    /// 语音条。点一下放，再点停。
    private var voiceBar: some View {
        let playing = VoicePlayer.shared.playingName == message.voiceName
        let seconds = Int(VoiceStore.duration(message.voiceName))
        return Button {
            VoicePlayer.shared.toggle(message.voiceName)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(app.settings.accentColor)

                // 几根高低不一的竖条，装个声波的样子
                HStack(spacing: 2.5) {
                    ForEach(0..<14, id: \.self) { i in
                        Capsule()
                            .fill(app.settings.accentColor.opacity(playing ? 0.85 : 0.45))
                            .frame(width: 2, height: waveHeight(i))
                    }
                }

                Text("\(seconds)″")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(width: 230, alignment: .leading)
            .glassBackground(radius: 22, strength: app.settings.glassOpacity)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            if !message.chosenOption.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(app.settings.accentColor)
                    Text("已选：\(message.chosenOption)")
                        .font(.system(size: 12))
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
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMain(scheme))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
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
    private var quoteBlock: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(app.settings.accentColor.opacity(0.6))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.quotedName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textMuted(scheme))
                Text(message.quotedText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 240, alignment: .leading)
        .glassBackground(radius: 12, strength: app.settings.glassOpacity * 0.8)
    }

    /// 按空行把回复切成几段，每段单独一个气泡。
    /// 段与段的间距跟思考链、工具卡片之间是同一个值。
    ///
    /// 开关在「设置 → 通用设置 → 他分段发」。关着就一整段一个气泡——
    /// 有人就是喜欢一大块读完，不喜欢消息一条条弹。
    private var contentSegments: [String] {
        guard app.settings.segmentAssistant || isUser else { return [message.content] }
        let parts = message.content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [message.content] : parts
    }

    /// 思考卡片上的那行字。
    ///
    /// 优先用他自己写的——他在想的过程里可以随时写 [[cot:在想怎么说才不吓着她]]，
    /// 后写的盖掉先写的。写了什么就显示什么，不写才退回秒数。
    /// 报秒数其实没什么意思，"想了 5.6 秒"跟他在想什么毫无关系。
    private var reasoningTitle: String {
        if let mine = Self.cotLabel(from: message.reasoning ?? ""), !mine.isEmpty {
            return mine
        }
        if message.isStreaming { return "正在想…" }
        if let sec = message.reasoningSeconds, sec > 0 {
            return String(format: "想了一会儿（%.1fs）", sec)
        }
        return "想了一会儿"
    }

    /// 把思考里最后一个 [[cot:...]] 抠出来
    static func cotLabel(from reasoning: String) -> String? {
        let pattern = #"\[\[cot:\s*([^\]]{1,40})\s*\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = reasoning as NSString
        let matches = regex.matches(in: reasoning, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last, last.numberOfRanges > 1 else { return nil }
        return ns.substring(with: last.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: 工具调用

    private var toolBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showTools.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("叮叮咣咣了 \(message.toolRuns.count) 下")
                        .font(.system(size: 14, weight: .medium))
                    if message.toolRuns.contains(where: { $0.failed }) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showTools ? 90 : 0))
                }
                .foregroundStyle(Theme.textSoft(scheme))
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                // 这类卡片是**固定宽度**的。它跟说了多长的话没关系，
                // 让它跟着内容伸缩，一屏里就会长长短短参差不齐。
                .frame(width: Layout.sideCardWidth, alignment: .leading)
                .glassBackground(radius: 18, strength: app.settings.glassOpacity * 0.85)
            }
            .buttonStyle(.plain)

            if showTools {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(message.toolRuns) { run in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: run.failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(run.failed ? .red : .green)
                                Text(run.toolName)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                if !run.serverName.isEmpty {
                                    Text(run.serverName)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            if !run.arguments.isEmpty, run.arguments != "{}" {
                                Text(run.arguments)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            Text(run.result)
                                .font(.system(size: 12))
                                .foregroundStyle(run.failed ? .red : Theme.textSoft(scheme))
                                .lineLimit(12)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .frame(width: Layout.sideCardWidth, alignment: .leading)
                .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.75)
            }
        }
    }

    /// 气泡就是一块玻璃。自己和对方的区别靠左右位置，
    /// 不靠颜色——整块染色会变成不透光的塑料片。
    private var bubbleShape: some View {
        ZStack {
            GlassSurface(
                radius: 18,
                strength: app.settings.glassOpacity * app.settings.bubbleOpacity,
                extra: isUser ? 0.35 : 0
            )
            // 想要一点色的时候才染，默认是 0
            if isUser && app.settings.bubbleTint > 0.01 {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(app.settings.accentColor.opacity(0.30 * app.settings.bubbleTint))
            }
        }
    }

    private var imageRow: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            ForEach(message.imageNames, id: \.self) { name in
                if let image = ImageStore.load(name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private var fileRow: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            ForEach(message.files) { f in
                HStack(spacing: 9) {
                    Image(systemName: f.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(app.settings.accentColor)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                            .lineLimit(1)
                        Text(f.sizeText)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 240, alignment: .leading)
                .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.85)
            }
        }
    }

    /// 思考正文里把标记去掉，那是给卡片标题用的
    private func cleanReasoning(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\[\[cot:[^\]]*\]\]"#,
            with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 思考链那一条。
    ///
    /// 展开的时候**不往下撑**，而是单独一个气泡浮在它上面——照她画的那张图。
    /// 为什么这么做：思考经常有几百上千字，塞回原位会把底下说的话
    /// 整个顶出屏幕，你为了看一眼他在想什么，就得丢掉他说了什么。
    /// 浮起来就没这个问题：底下那句话一动不动，看完点一下收掉。
    private func reasoningBlock(_ text: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                showReasoning.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(reasoningTitle)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 8)
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(showReasoning ? 180 : 0))
            }
            .foregroundStyle(Theme.textSoft(scheme))
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            // 折起来的这一条是固定宽的，跟工具那条对齐
            .frame(width: Layout.sideCardWidth, alignment: .leading)
            .glassBackground(radius: 18, strength: app.settings.glassOpacity * 0.85)
        }
        .buttonStyle(.plain)
        // 浮起来的那个气泡挂在这一条的**上边**，用 overlay 所以不占布局位置
        .overlay(alignment: .bottomLeading) {
            if showReasoning {
                floatingThought(text)
                    // 往上顶开自己那条的高度，再留 8 点缝
                    .offset(y: -(collapsedHeight + 8))
                    .transition(.scale(scale: 0.9, anchor: .bottom)
                        .combined(with: .opacity))
            }
        }
        // 展开的时候不让它被上面那条消息裁掉
        .zIndex(showReasoning ? 10 : 0)
    }

    /// 折起来那条大概多高：上下 13 的内边距 + 一行 14 号字
    private var collapsedHeight: CGFloat { 13 * 2 + 18 }

    private func floatingThought(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: max(11, app.settings.fontSize - 3)))
                .foregroundStyle(Theme.textSoft(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        // 想得再多也就这么高，超了自己滚——
        // 不封顶的话一条长思考能盖住整个屏幕
        .frame(width: Layout.sideCardWidth + 46)
        .frame(maxHeight: 260)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
        // 浮起来就得有影子，不然跟底下那条糊成一块，看不出是"浮"着的
        .shadow(color: .black.opacity(scheme == .dark ? 0.42 : 0.16),
                radius: 18, x: 0, y: 8)
        .overlay(alignment: .bottomLeading) {
            // 一个朝下的小尖，指着自己那一条，说明这团是从哪儿冒出来的
            Triangle()
                .fill(Theme.softFill)
                .frame(width: 14, height: 7)
                .offset(x: 26, y: 6)
        }
    }
}

/// 浮起来那个气泡底下那个朝下的小尖
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        p.closeSubpath()
        return p
    }
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
                        .font(.system(size: size * 0.46, weight: .medium))
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
                        .font(.system(size: 11, weight: .medium))
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
