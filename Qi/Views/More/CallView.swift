import SwiftUI

/// 他打过来的那一屏。
/// 做得扁一点，像微信那种，不要满屏的大图。
struct IncomingCallView: View {

    let call: CallRecord
    var onAnswer: () -> Void
    var onDecline: () -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var breathing = false

    var body: some View {
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(call.reason.isEmpty ? "邀请你语音通话" : call.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button {
                onDecline()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(hexString: "E5544B")!))
            }
            .buttonStyle(.plain)

            Button {
                onAnswer()
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(hexString: "4CAF6E")!))
            }
            .buttonStyle(.plain)
            .scaleEffect(breathing ? 1.05 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassBackground(radius: 20, strength: app.settings.glassOpacity, extra: 0.25)
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - 通话中

struct CallView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CallStore.shared
    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var speech = SpeechRecognizer()

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
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.bottom, 4)
                }

                if farewell > 0 {
                    Text("他说完了。\(farewell) 秒后自动挂断——你现在开口或者打字，都还能接着聊。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.bottom, 8)
                }

                if let notice {
                    Text(notice)
                        .font(.system(size: 11))
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))

            Text(thinking ? "\(him)正在回应" : clock(elapsed))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(.bottom, 8)
    }

    /// 通话里的气泡也是圆的，跟聊天页一个调子
    private func bubble(_ line: CallLine) -> some View {
        HStack {
            if line.fromMe { Spacer(minLength: 50) }
            VStack(alignment: line.fromMe ? .trailing : .leading, spacing: 3) {
                Text(line.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassBackground(radius: 18,
                                     strength: app.settings.glassOpacity,
                                     extra: line.fromMe ? 0.3 : 0)
                if !line.voiceName.isEmpty {
                    Button {
                        VoicePlayer.shared.toggle(line.voiceName)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: VoicePlayer.shared.playingName == line.voiceName
                                  ? "stop.fill" : "play.fill")
                                .font(.system(size: 8))
                            Text("听")
                                .font(.system(size: 9))
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
                            .font(.system(size: 14, weight: .semibold))
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
                        .font(.system(size: 17))
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
                                .font(.system(size: 17))
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
                        .font(.system(size: 19))
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

    private func startListening() {
        listening = true
        if app.settings.voiceInput == .onDevice {
            speech.start()
        } else {
            try? recorder.start()
        }
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func stopListening() async {
        defer { listening = false }
        var text = ""
        if app.settings.voiceInput == .onDevice {
            text = speech.stop()
        } else {
            guard let url = recorder.stop(), recorder.seconds > 0.4 else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let t: Transcript
                if app.settings.voiceInput == .senseVoice {
                    t = try await SenseVoiceAPI.transcribe(url, key: app.settings.siliconKey)
                } else {
                    let v = app.activeVoice ?? app.voices.first
                    t = try await ElevenSTT.transcribe(url, key: v?.apiKey ?? "",
                                                       baseURL: v?.baseURL ?? "")
                }
                text = t.briefForModel
            } catch {
                notice = error.localizedDescription
                return
            }
        }
        guard !text.isEmpty else { return }
        await send(text)
    }

    private func send(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft = ""
        farewell = 0     // 你一开口，那个倒计时就取消
        store.addLine(CallLine(fromMe: true, text: clean))

        thinking = true
        let reply = await app.speakOnCall(store.active?.lines ?? [])
        thinking = false

        guard !reply.text.isEmpty else {
            notice = reply.error
            return
        }

        var line = CallLine(fromMe: false, text: reply.text)
        // 有语音就一起存下来，挂了之后还能回听
        if let file = reply.voiceFile { line.voiceName = file }
        store.addLine(line)
        if let file = reply.voiceFile {
            VoicePlayer.shared.toggle(file)
        }

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
        Task { @MainActor in
            while farewell > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if farewell == 0 { return }   // 你开口了
                farewell -= 1
            }
            if farewell == 0, store.active != nil {
                hangUp(by: "him")
            }
        }
    }

    private func hangUp(by who: String) {
        guard let call = store.active else { return }
        let lines = call.lines
        let id = call.id
        store.hangUp(by: who)
        ticker?.cancel()
        VoicePlayer.shared.stop()
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        // 通话不是孤立的日志，整理一句写回你们的记录里
        if lines.count >= 2 {
            Task { await app.summarizeCall(id, lines: lines) }
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if store.records.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "phone")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(app.settings.accentColor.opacity(0.5))
                        Text("还没通过话")
                            .font(.system(size: 13))
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
                                .font(.system(size: 11))
                                .foregroundStyle(r.answered
                                                 ? StatusTone.done.color
                                                 : Color(hexString: "E5544B")!)
                            Text(r.caller == "me" ? "我打的" : "他打的")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            Spacer()
                            Text(stamp(r.startedAt))
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        if !r.reason.isEmpty {
                            Text("「\(r.reason)」")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        Text(r.resultText)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSoft(scheme))

                        if !r.summary.isEmpty {
                            Text(r.summary)
                                .font(.system(size: 12))
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
                    CallStore.shared.dial()
                } label: {
                    Image(systemName: "phone.fill")
                }
            }
        }
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}
