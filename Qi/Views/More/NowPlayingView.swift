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
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Button {
                        draftLyrics = player.current?.lyrics ?? ""
                        editingLyrics = true
                    } label: {
                        Text("粘一段进来")
                            .font(.system(size: 13))
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
    }

    // MARK: 底

    @ViewBuilder
    private var backdrop: some View {
        if let t = player.current, let url = URL(string: t.artworkURL),
           !t.artworkURL.isEmpty {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                }
            }
            .blur(radius: 60)
            .overlay(Color.black.opacity(scheme == .dark ? 0.55 : 0.25))
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .medium))
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
                        .font(.system(size: 14))
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
        let t = player.current
        Group {
            if let t, let url = URL(string: t.artworkURL), !t.artworkURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Theme.softFillDeep)
                    }
                }
            } else {
                ZStack {
                    Rectangle().fill(Theme.softFillDeep)
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.26))
                        .foregroundStyle(app.settings.accentColor)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
    }

    // MARK: 歌词

    private var lyrics: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    // 上下各垫一段，第一句和最后一句也能滚到屏幕正中
                    Color.clear.frame(height: 90)
                    ForEach(player.lines) { line in
                        Text(line.text)
                            .font(.system(size: line.index == player.currentLine ? 17 : 15,
                                          weight: line.index == player.currentLine
                                            ? .semibold : .regular))
                            .foregroundStyle(line.index == player.currentLine
                                             ? Theme.textMain(scheme)
                                             : Theme.textMuted(scheme))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(line.index)
                            .animation(.easeOut(duration: 0.25),
                                       value: player.currentLine)
                            // 点一句就跳到那儿。**歌词是能用的导航**，
                            // 不只是给人看的字。
                            .onTapGesture {
                                guard line.at > 0 else { return }
                                player.seek(to: line.at)
                            }
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    Text(t.subtitle.isEmpty ? "一起听着" : t.subtitle)
                        .font(.system(size: 11))
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
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)

                Button {
                    player.playing ? player.pause() : player.resume()
                } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(app.settings.primaryColor.opacity(0.9)))
                }
                .buttonStyle(.plain)

                Button {
                    player.seek(to: min(player.duration, player.progress + 15))
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                .buttonStyle(.plain)
            }

            if player.current?.isPreview == true {
                Text("这是三十秒的试听。整首得自己把文件导进来——网易云、QQ 音乐下载的歌存在它们自己的沙盒里，别的 App 读不到，这是 iOS 的硬规矩。")
                    .font(.system(size: 10))
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
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    TextEditor(text: $draftLyrics)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 13, design: .monospaced))
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
