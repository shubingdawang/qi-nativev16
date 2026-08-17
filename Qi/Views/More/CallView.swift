import SwiftUI

/// 他打过来的那一屏。
/// 做得扁一点，像微信那种，不要满屏的大图。
struct IncomingCallView: View {

    let call: CallRecord
    var onAnswer: () -> Void
    /// 带上她随手回的那一句。什么都没回就是空字符串。
    var onDecline: (String) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var breathing = false
    /// 正在自己写一句
    @State private var writing = false
    @State private var note = ""

    /// 随手能点的三句。
    /// 照参考里那个意思：**他该知道的是"她为什么没接"，不只是"她没接"**。
    private let quick = ["在忙", "在外面", "想打字聊"]

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                // clawd 顶上来当头像
                ClawdView(mood: .idle, scale: 1.1)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle().fill(app.settings.accentColor.opacity(0.16))
                    )
                    .scaleEffect(breathing ? 1.06 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName)
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(call.reason.isEmpty ? "邀请你语音通话" : call.reason)
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Button {
                    onDecline("")
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.app(15))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color(hexString: "E5544B")!))
                }
                .buttonStyle(.plain)

                Button {
                    onAnswer()
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.app(15))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color(hexString: "4CAF6E")!))
                }
                .buttonStyle(.plain)
                .scaleEffect(breathing ? 1.05 : 1)
            }

            // 不接，但回一句。
            //
            // 直接摁红键也行——那就是纯粹的不接。这一排是给"不是不想理你，
            // 是现在不方便"留的口子：点哪句，哪句就当成她说的话回到聊天里。
            if writing {
                HStack(spacing: 8) {
                    TextField("回他一句…", text: $note)
                        .font(.app(13))
                        .textFieldStyle(.plain)
                        .submitLabel(.send)
                        .onSubmit { send(note) }
                    Button {
                        send(note)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.app(20))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                HStack(spacing: 7) {
                    ForEach(quick, id: \.self) { q in
                        Button { send(q) } label: {
                            Text(q)
                                .font(.app(11))
                                .foregroundStyle(Theme.textSoft(scheme))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(scheme == .dark
                                                   ? Color.white.opacity(0.13)
                                                   : Color.white.opacity(0.55))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { writing = true }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(scheme == .dark
                                               ? Color.white.opacity(0.13)
                                               : Color.white.opacity(0.55))
                            )
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassBackground(radius: 20, strength: app.settings.glassOpacity, extra: 0.25)
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .animation(.easeOut(duration: 0.2), value: writing)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// 回一句就挂。太长的截掉——这是一句话，不是一条消息。
    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onDecline(String(clean.prefix(60)))
    }
}

// MARK: - 通话中

struct CallView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CallStore.shared
    // 只留录音机。实时识别那条撤了——见 startListening 上面那段。
    @StateObject private var recorder = VoiceRecorder()

    @State private var draft = ""
    @State private var muted = false
    @State private var listening = false
    @State private var thinking = false
    @State private var elapsed: TimeInterval = 0
    @State private var ticker: Task<Void, Never>?
    @State private var notice: String?
    /// 他说完再见之后，留几秒给你反悔
    @State private var farewell = 0

    private var call: CallRecord? { store.active }
    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }
    private var him: String { app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName }

    var body: some View {
        ZStack {
            // 背景跟着 App 走，不另做一套
            WallpaperBackground()

            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(call?.lines ?? []) { line in
                                bubble(line).id(line.id)
                            }
                            if thinking {
                                HStack {
                                    TypingBubble()
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }
                    .onChange(of: call?.lines.count ?? 0) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                if muted {
                    Text("闭麦了，打字他一样听得到")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.bottom, 4)
                }

                if farewell > 0 {
                    Text("他说完了。\(farewell) 秒后自动挂断——你现在开口或者打字，都还能接着聊。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.bottom, 8)
                }

                if let notice {
                    Text(notice)
                        .font(.app(11))
                        .foregroundStyle(.orange)
                        .padding(.bottom, 6)
                }

                controls
            }
        }
        .onAppear { startTicking() }
        .onDisappear {
            ticker?.cancel()
            recorder.discard()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            ClawdView(mood: thinking ? .thinking : .idle, scale: 1.4)
                .frame(height: 40)
                .padding(.top, 10)

            Text(him)
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))

            Text(thinking ? "\(him)正在回应" : clock(elapsed))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))

            // 接的是**谁**，摆在这儿。以前这通电话抓的是供应商列表第一个模型，
            // 跟聊天页选的那个不是一回事，接起来当然不像他。现在两边同一个。
            if let m = app.activeHim?.model {
                Text(m)
                    .font(.app(9))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
            }

            // 没配音色也能打，只是他不出声。**得说清楚**，
            // 不然只有字会像是坏了。
            if app.activeVoice == nil {
                Text("没配音色，这通只有字")
                    .font(.app(9))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
            }
        }
        .padding(.bottom, 8)
    }

    /// 通话里的气泡也是圆的，跟聊天页一个调子
    private func bubble(_ line: CallLine) -> some View {
        HStack {
            if line.fromMe { Spacer(minLength: 50) }
            VStack(alignment: line.fromMe ? .trailing : .leading, spacing: 3) {
                Text(line.text)
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassBackground(radius: 18,
                                     strength: app.settings.glassOpacity,
                                     extra: line.fromMe ? 0.3 : 0)
                // 她这句是怎么说的。摆出来她自己也看得见——
                // 这是他"听"到的东西，不该只有他知道。
                if !line.tone.isEmpty {
                    Text(line.tone)
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                if !line.voiceName.isEmpty {
                    Button {
                        VoicePlayer.shared.toggle(line.voiceName)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: VoicePlayer.shared.playingName == line.voiceName
                                  ? "stop.fill" : "play.fill")
                                .font(.app(8))
                            Text("听")
                                .font(.app(9))
                        }
                        .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !line.fromMe { Spacer(minLength: 50) }
        }
        .padding(.horizontal, 16)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            // 输入框**一直都在**。
            //
            // 之前我把它藏在"没闭麦"里面，那是想错了：
            // 不方便说话、但戴着耳机能听——这才是最需要打字的时候。
            // 闭麦只该管住嘴，不该把手也捆上。
            HStack(spacing: 8) {
                    TextField(muted ? "打字说给他听…" : "说点什么…",
                              text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassBackground(radius: 20, strength: app.settings.glassOpacity)

                    Button {
                        Task { await send(draft) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.app(14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(app.settings.primaryColor.opacity(0.9)))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 26) {
                // 闭麦。只是不用语音了，字照打、他的话照听。
                Button {
                    muted.toggle()
                    if muted, listening { Task { await stopListening() } }
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                } label: {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.app(17))
                        .foregroundStyle(muted ? .white : Theme.textMain(scheme))
                        .frame(width: 54, height: 54)
                        .background(
                            Circle().fill(muted
                                ? Color(hexString: "8A8378")!
                                : Color.white.opacity(scheme == .dark ? 0.16 : 0.85))
                        )
                }
                .buttonStyle(.plain)

                // 按住说话
                if !muted {
                    Circle()
                        .fill(listening
                              ? app.settings.accentColor.opacity(0.4)
                              : Color.white.opacity(scheme == .dark ? 0.16 : 0.85))
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: "waveform")
                                .font(.app(17))
                                .foregroundStyle(Theme.textMain(scheme))
                        }
                        .scaleEffect(listening ? 1 + recorder.level * 0.3 : 1)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    guard !listening, !thinking else { return }
                                    startListening()
                                }
                                .onEnded { _ in
                                    Task { await stopListening() }
                                }
                        )
                }

                // 挂断
                Button {
                    hangUp(by: "me")
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.app(19))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Color(hexString: "E5544B")!))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 26)
        }
    }

    // MARK: 说话

    /// 按住说话。
    ///
    /// **不管走哪条识别，都先录成文件**——聊天页早就是这么做的，
    /// 这儿一直没跟上。改过来有三个好处：
    ///
    ///   · `.onDevice` 那档以前走的是 AVAudioEngine，没有文件也没有电平，
    ///     所以**打电话的时候一点语气都读不到**（她问的就是这件事）
    ///   · 边录边实时识别，两个东西抢同一个麦克风输入，谁都录不干净。
    ///     参考里那句话说得很实在：「录完再转只多等一两秒，稳得多」
    ///   · 录下来的那段还能存进这一句，挂了之后回听
    private func startListening() {
        listening = true
        do {
            try recorder.start()
        } catch {
            notice = "开不了录音：" + error.localizedDescription
            listening = false
            return
        }
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func stopListening() async {
        defer { listening = false }

        // 先把振幅序列拿走，下一次按住说话就重置了
        let shape = recorder.samples
        let step = recorder.sampleInterval

        guard let url = recorder.stop(), recorder.seconds > 0.4 else { return }
        defer { try? FileManager.default.removeItem(at: url) }

        var text = ""
        switch app.settings.voiceInput {
        case .onDevice:
            text = await SpeechRecognizer.recognizeFile(url)
        case .senseVoice:
            do {
                text = try await SenseVoiceAPI
                    .transcribe(url, key: app.settings.siliconKey).briefForModel
            } catch {
                notice = error.localizedDescription
                return
            }
        default:
            do {
                let v = app.activeVoice ?? app.voices.first
                text = try await ElevenSTT.transcribe(url, key: v?.apiKey ?? "",
                                                      baseURL: v?.baseURL ?? "").briefForModel
            } catch {
                notice = error.localizedDescription
                return
            }
        }
        guard !text.isEmpty else { return }

        // 她这一句是**怎么说**的。本机纯算术，不花钱不上传。
        let f = VoiceProsody.features(samples: shape, interval: step, text: text)
        var tone = ""
        if f.usable {
            tone = VoiceBaseline.shared.note(for: f)
            VoiceBaseline.shared.remember(f)
        }
        await send(text, tone: tone)
    }

    private func send(_ text: String, tone: String = "") async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft = ""
        farewell = 0     // 你一开口，那个倒计时就取消

        // **把这次请求绑在这一通电话上。**
        //
        // 他要回一句得花好几秒，而这几秒里她可能已经挂了、甚至又拨了一通。
        // 以前这里什么都不认：回来照样播放语音、照样往 store.addLine——
        // 于是挂断之后音箱里还会冒出他的声音，紧接着拨的那一通里
        // 会凭空多出上一通的回复。
        //
        // 参考里管这个叫身份协议：**异步结果回来先验身份，再改状态**，
        // 光有一个「正在说话」的布尔值是不够的。我们这条链路简单，
        // 一个通话 id 就够——但检查的位置一个都不能少。
        guard let mine = store.active?.id else { return }
        var mineLine = CallLine(fromMe: true, text: clean)
        mineLine.tone = tone
        store.addLine(mineLine)

        thinking = true
        let reply = await app.speakOnCall(store.active?.lines ?? [])

        // 回来了，先看看这通电话还在不在、还是不是刚才那一通
        guard store.active?.id == mine else { return }
        thinking = false

        guard !reply.text.isEmpty else {
            notice = reply.error
            return
        }

        var line = CallLine(fromMe: false, text: reply.text)
        // 有语音就一起存下来，挂了之后还能回听
        if let file = reply.voiceFile { line.voiceName = file }
        // 他这句演了什么，摆在气泡角落。
        // **不然配了音色的人听得出来，没配的人完全不知道有这回事。**
        if !reply.acting.isEmpty { line.tone = reply.acting.joined(separator: "·") }
        store.addLine(line)

        if let file = reply.voiceFile {
            VoicePlayer.shared.toggle(file)
        } else if reply.systemVoice {
            // 退到系统合成这一档**拿不到音频文件**——那套是直接出声的。
            // 所以这句没有语音条可以回听，当场念完就没了。
            SystemVoice.shared.speak(reply.text)
        }
        // 换了谁念、退到系统音了，都照实说一声。
        // 悄悄换一个声音而不说，比没声音更让人错乱。
        if !reply.voiceNote.isEmpty { notice = reply.voiceNote }

        // 他说了再见的话，别立刻挂——留十五秒
        if reply.saidGoodbye {
            startFarewell()
        }
    }

    // MARK: 挂断

    /// 说完再见之后不立刻断线。
    /// 你这十五秒里开口，倒计时就取消——真实的电话就是这样，
    /// 说完"那我挂了"还会再黏一会儿。
    private func startFarewell() {
        farewell = 15
        // 这个倒计时也得认电话。不然它挂的可能是**下一通**——
        // 上一通说完再见，她马上挂了又拨一通，十五秒后这个计时器醒过来，
        // 一句话没说就把新的那通掐了。
        guard let mine = store.active?.id else { return }
        Task { @MainActor in
            while farewell > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if farewell == 0 { return }   // 你开口了
                guard store.active?.id == mine else { return }
                farewell -= 1
            }
            if farewell == 0, store.active?.id == mine {
                hangUp(by: "him")
            }
        }
    }

    private func hangUp(by who: String) {
        guard store.active != nil else { return }
        guard let done = store.hangUp(by: who) else { return }
        ticker?.cancel()
        VoicePlayer.shared.stop()
        SystemVoice.shared.stop()
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        // 通话不是孤立的日志，落回你们的记录里。
        //
        // **顺序反过来了**：先落 `📞 语音通话 · 2 分 17 秒` 这一行，
        // 小结回来了再补到同一条上。以前是小结成功才有记录，
        // 小结一失败这通电话在聊天里就等于没发生过。
        let mid = app.logCall(done)
        // 太短的不值得再花一次钱去总结（参考里那个数：二十秒）
        if done.lines.count >= 2, done.duration >= 20 {
            let id = done.id
            let lines = done.lines
            Task { await app.summarizeCall(id, lines: lines, messageID: mid) }
        }
        dismiss()
    }

    private func startTicking() {
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let start = store.active?.connectedAt {
                    elapsed = Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func clock(_ s: TimeInterval) -> String {
        let n = Int(s)
        return String(format: "%02d:%02d", n / 60, n % 60)
    }
}

// MARK: - 通话记录

struct CallHistoryView: View {

    @ObservedObject private var store = CallStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var cantDial = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if store.records.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "phone")
                            .font(.app(30, weight: .light))
                            .foregroundStyle(app.settings.accentColor.opacity(0.5))
                        Text("还没通过话")
                            .font(.app(13))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .padding(.top, 60)
                }

                ForEach(store.records) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Image(systemName: r.answered
                                  ? (r.caller == "me" ? "phone.arrow.up.right" : "phone.arrow.down.left")
                                  : "phone.down")
                                .font(.app(11))
                                .foregroundStyle(r.answered
                                                 ? StatusTone.done.color
                                                 : Color(hexString: "E5544B")!)
                            Text(r.caller == "me" ? "我打的" : "他打的")
                                .font(.app(13, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            Spacer()
                            Text(stamp(r.startedAt))
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        if !r.reason.isEmpty {
                            Text("「\(r.reason)」")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        Text(r.resultText)
                            .font(.app(11))
                            .foregroundStyle(Theme.textSoft(scheme))

                        if !r.summary.isEmpty {
                            Text(r.summary)
                                .font(.app(12))
                                .foregroundStyle(Theme.textSoft(scheme))
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassCard(padding: 0)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.records.removeAll { $0.id == r.id }
                        } label: {
                            Label("删掉", systemImage: Icon.trash)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("通话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // 没模型就别拨。以前这儿一按就往电话本里塞一条记录，
                    // 通话那一屏却压根弹不出来。
                    guard app.activeHim != nil else {
                        cantDial = true
                        return
                    }
                    CallStore.shared.dial()
                } label: {
                    Image(systemName: "phone.fill")
                }
                .disabled(app.activeHim == nil)
            }
        }
        .alert("还没选模型", isPresented: $cantDial) {
            Button("好") { }
        } message: {
            Text("这通电话是真的要问他的，没挂模型就没人接。去絮语页输入框上那颗胶囊选一个。")
        }
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}
