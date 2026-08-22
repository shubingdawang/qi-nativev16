import SwiftUI

/// 歌词页。
///
/// 封面、歌手、会滚的歌词，以及一条能拖的进度。
/// 从悬浮窗点进来，也能从「音乐」那页正在放的那首点进来。
///
/// 歌词跟着播放走：唱到哪句哪句亮起来，并且**自己滚到屏幕中间**。
/// 没歌词的时候不摆一个空框，把封面放大占满——
/// 缺东西的地方不该留一块显眼的空白说「这儿本来有东西」。
struct NowPlayingView: View {

    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 她手动滚过歌词之后，先别抢着把它拉回去
    @State private var userScrolledAt: Date?
    @State private var editingLyrics = false
    @State private var draftLyrics = ""

    // 划歌词那一摊（Duetto 那条「quote any lyric」）
    @ObservedObject private var marks = SongMarkStore.shared
    @State private var aiming: LyricLine?
    @State private var noteDraft = ""
    @State private var writingNote = false
    @State private var openedMark: SongMark?

    private var hasLyrics: Bool { !player.lines.isEmpty }

    var body: some View {
        ZStack {
            WallpaperBackground()
            // 封面拉大糊掉当底。放歌这一屏该有点氛围，
            // 但不能盖过歌词，所以糊得很狠又压了一层。
            backdrop

            VStack(spacing: 0) {
                header
                if hasLyrics {
                    cover(side: 150).padding(.top, 4)
                    lyrics
                } else {
                    Spacer(minLength: 0)
                    cover(side: 260)
                    Spacer(minLength: 0)
                    Text("这首还没有歌词")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Button {
                        draftLyrics = player.current?.lyrics ?? ""
                        editingLyrics = true
                    } label: {
                        Text("粘一段进来")
                            .font(.app(13))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    Spacer(minLength: 0)
                }
                controls
            }
        }
        .sheet(isPresented: $editingLyrics) { lyricsEditor }
        .sheet(item: $openedMark) { m in SongMarkSheet(mark: m) }
        .alert("划下这一句", isPresented: $writingNote) {
            TextField("想说点什么，留空也行", text: $noteDraft)
            Button("取消", role: .cancel) { aiming = nil }
            Button("画起来") { commitMark() }
        } message: {
            Text(aiming.map { "「" + $0.text + "」" } ?? "")
        }
    }

    // MARK: 底

    @ViewBuilder
    private var backdrop: some View {
        if let t = player.current, !t.artworkName.isEmpty || !t.artworkURL.isEmpty {
            TrackArtwork(track: t, side: 400)
                .blur(radius: 60)
                .overlay(Color.black.opacity(scheme == .dark ? 0.55 : 0.25))
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if hasLyrics {
                Button {
                    draftLyrics = player.current?.lyrics ?? ""
                    editingLyrics = true
                } label: {
                    Image(systemName: "text.quote")
                        .font(.app(14))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func cover(side: CGFloat) -> some View {
        // 走统一那个（本机封面优先，再网上的，再音符）——
        // 她导进来的歌封面在文件里，以前这儿只看网址，所以永远是音符
        if let t = player.current {
            TrackArtwork(track: t, side: side)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
        }
    }

    // MARK: 歌词

    /// 一句歌词。
    ///
    /// 平时点一下＝跳到那儿听（歌词是能用的导航，不只是给人看的字）。
    /// **按住**＝划下来跟他聊——这是 Duetto 那条「quote any lyric」，
    /// 跟书房里划句子是同一件事，只是对象换成了歌词。
    @ViewBuilder
    private func lyricLine(_ line: LyricLine) -> some View {
        let now = line.index == player.currentLine
        let mark = player.current.flatMap { marks.mark(at: line.text, in: $0) }

        HStack(spacing: 4) {
            Text(line.text)
                .font(.app(now ? 17 : 15, weight: now ? .semibold : .regular))
                .foregroundStyle(now ? Theme.textMain(scheme) : Theme.textMuted(scheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 3)
                // 划过的垫一层马克笔（半透明，字还看得见）
                .background(mark?.color.opacity(0.28) ?? .clear)

            // 聊过的挂个小气泡，点开看当时说了什么
            if let mark, mark.discussed {
                Button { openedMark = mark } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(app.settings.accentColor.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .id(line.index)
        .animation(.easeOut(duration: 0.25), value: player.currentLine)
        .contentShape(Rectangle())
        .onTapGesture {
            guard line.at > 0 else { return }
            player.seek(to: line.at)
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if let mark {
                openedMark = mark          // 划过的，按住是打开看
            } else {
                aiming = line
                noteDraft = ""
                writingNote = true
            }
        }
    }

    /// 把瞄准的那一句真的划下来
    private func commitMark() {
        guard let line = aiming, let track = player.current else { return }
        marks.add(line, in: track,
                  author: app.settings.userName.isEmpty ? "我" : app.settings.userName,
                  note: noteDraft,
                  colorHex: app.settings.markerHex)
        aiming = nil
        noteDraft = ""
    }

    private var lyrics: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    // 上下各垫一段，第一句和最后一句也能滚到屏幕正中
                    Color.clear.frame(height: 90)
                    ForEach(player.lines) { line in
                        lyricLine(line)
                    }
                    Color.clear.frame(height: 140)
                }
                .padding(.horizontal, 28)
            }
            .onChange(of: player.currentLine) { _, i in
                // 她刚自己滚过就别抢，等几秒再接管
                if let at = userScrolledAt, Date().timeIntervalSince(at) < 5 { return }
                guard let i else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(i, anchor: .center)
                }
            }
            .simultaneousGesture(
                DragGesture().onChanged { _ in userScrolledAt = Date() }
            )
        }
    }

    // MARK: 底下那排

    private var controls: some View {
        VStack(spacing: 10) {
            if let t = player.current {
                VStack(spacing: 2) {
                    Text(t.title)
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    Text(t.subtitle.isEmpty ? "一起听着" : t.subtitle)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                }
            }

            if player.duration > 0 {
                VStack(spacing: 2) {
                    Slider(value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ), in: 0...player.duration)
                        .tint(app.settings.accentColor)
                    HStack {
                        Text(clock(player.progress))
                        Spacer()
                        Text(clock(player.duration))
                    }
                    .font(HomeType.number(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 30) {
                Button {
                    player.seek(to: max(0, player.progress - 15))
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.app(19))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)

                Button {
                    player.playing ? player.pause() : player.resume()
                } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.app(22))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(app.settings.primaryColor.opacity(0.9)))
                }
                .buttonStyle(.plain)

                Button {
                    player.seek(to: min(player.duration, player.progress + 15))
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.app(19))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)
            }

            // 放完之后干什么。**以前一首放完就停了**，她说的就是这个。
            // 一个按钮轮着切：停 → 单曲循环 → 随机。
            Button {
                player.repeatMode = player.repeatMode.next
                if app.settings.haptics {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: player.repeatMode.icon)
                        .font(.app(11))
                    Text(player.repeatMode.label)
                        .font(.app(11))
                }
                .foregroundStyle(player.repeatMode == .off
                                 ? Theme.textMuted(scheme)
                                 : app.settings.accentColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)

            if player.current?.isPreview == true {
                Text("这是三十秒的试听。整首得自己把文件导进来——网易云、QQ 音乐下载的歌存在它们自己的沙盒里，别的 App 读不到，这是 iOS 的硬规矩。")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 30)
        .padding(.top, 10)
    }

    // MARK: 自己粘歌词

    private var lyricsEditor: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack(alignment: .leading, spacing: 10) {
                    Text("粘 LRC 或者纯文字都行。带 `[00:12.34]` 时间戳的会跟着歌走，没有时间戳的就一句句排着。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    TextEditor(text: $draftLyrics)
                        .scrollContentBackground(.hidden)
                        .font(.app(13, design: .monospaced))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.softFillDeep))
                }
                .padding(16)
            }
            .navigationTitle("歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { editingLyrics = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("存下") {
                        MusicLibrary.shared.setLyrics(draftLyrics,
                                                      for: player.current?.id)
                        editingLyrics = false
                    }
                }
            }
        }
    }

    private func clock(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let n = Int(s)
        return String(format: "%d:%02d", n / 60, n % 60)
    }
}


// MARK: - 划下的那句歌词，点开看

/// 跟书房那张 `AnnotationSheet` 是一个样子——
/// 上面是划下的那一句，底下是围绕它的往来，
/// 聊过的话可以顺着记号跳回当时那一轮。
struct SongMarkSheet: View {

    @State var mark: SongMark

    @ObservedObject private var store = SongMarkStore.shared
    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var jumpFailed = false

    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }
    private var fresh: SongMark { store.marks.first { $0.id == mark.id } ?? mark }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("《\(fresh.title)》"
                                 + (fresh.artist.isEmpty ? "" : " · " + fresh.artist))
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))

                            HStack(alignment: .top, spacing: 9) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(fresh.color.opacity(0.75))
                                    .frame(width: 3)
                                Text(fresh.quote)
                                    .font(.app(15, design: .serif))
                                    .foregroundStyle(Theme.textMain(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            // 点一下回到歌里那个位置。**划下的句子是能用的书签**。
                            Button {
                                player.seek(to: fresh.at)
                                dismiss()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "play.circle").font(.app(12))
                                    Text("从这句听（\(Int(fresh.at)) 秒）").font(.app(12))
                                }
                                .foregroundStyle(app.settings.accentColor)
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.4)

                            ForEach(fresh.notes) { n in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(n.author)
                                        .font(.app(10))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                    Text(n.text)
                                        .font(.app(14))
                                        .foregroundStyle(Theme.textMain(scheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if fresh.notes.isEmpty {
                                Text("还没说什么。这一句为什么停下来了？")
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }

                            if !fresh.talkIDs.isEmpty {
                                Divider().opacity(0.4)
                                Button { jump() } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bubble.left.and.text.bubble.right")
                                            .font(.app(12))
                                        Text("看当时聊了什么").font(.app(13))
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.app(10))
                                    }
                                    .foregroundStyle(app.settings.accentColor)
                                }
                                .buttonStyle(.plain)
                                if jumpFailed {
                                    Text("那一轮的记录找不着了（可能被清过）。")
                                        .font(.app(11))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(18)
                    }

                    HStack(spacing: 8) {
                        TextField("再说一句…", text: $draft, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                        Button {
                            let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            store.reply(to: fresh.id, text: t, by: me)
                            draft = ""
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.app(24))
                                .foregroundStyle(app.settings.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                }
            }
            .navigationTitle("划下的这句")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        store.remove(fresh.id)
                        dismiss()
                    } label: {
                        Image(systemName: Icon.trash)
                    }
                }
            }
        }
    }

    /// 跳回当时聊的那一轮。跳不成要说实话。
    private func jump() {
        guard let turn = fresh.talkIDs.last else { return }
        if app.jumpToTurn(turn) { dismiss() } else { jumpFailed = true }
    }
}
