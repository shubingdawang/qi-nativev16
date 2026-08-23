import SwiftUI
import UniformTypeIdentifiers

/// 音乐库。
///
/// 说明一下跟图标的区别：**歌是随时导入的，不用重新构建。**
/// 图标那个是特例——iOS 规定备用图标必须打包时就在，所以只能走仓库。
/// 除了图标，App 里所有东西（歌、书、表情包、文件）都是运行时导进来的。
struct MusicLibraryView: View {

    @ObservedObject private var library = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var importing = false
    @State private var keyword = ""
    @State private var searching = false
    @State private var webResults: [Track] = []
    @State private var notice: String?
    @State private var showingLyrics = false

    private var mine: [Track] { library.search(keyword) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // 正在放的那首。**点它进歌词页**——她指名的那个入口。
                if let now = player.current {
                    nowPlayingRow(now)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: Icon.search)
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                        TextField("找歌，或者搜网上的", text: $keyword)
                            .textFieldStyle(.plain)
                            .font(.app(14))
                            .submitLabel(.search)
                            .onSubmit { Task { await searchWeb() } }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.softFillDeep))

                    Button {
                        importing = true
                    } label: {
                        Image(systemName: Icon.add)
                            .font(.app(16))
                            .foregroundStyle(app.settings.accentColor)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }

                if let notice {
                    Text(notice)
                        .font(.app(11))
                        .foregroundStyle(.orange)
                }

                if library.tracks.isEmpty && webResults.isEmpty {
                    EmptyNote(icon: "music.note.list",
                              title: "还没有歌",
                              hint: "点右上角从「文件」导入 mp3、m4a、flac。\n"
                                  + "网易云会员下载的歌，先存进「文件」App 再导进来就是整首。\n"
                                  + "上面直接搜是网上的三十秒试听。")
                        .padding(.top, 20)
                }

                if !mine.isEmpty {
                    Text("我的")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    ForEach(mine) { track in
                        row(track, local: true)
                    }
                }

                if searching {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("在搜…").font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }

                if !webResults.isEmpty {
                    Text("网上的（三十秒试听）")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.top, 6)
                    ForEach(webResults) { track in
                        row(track, local: false)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("音乐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PlayCountView()
                } label: {
                    Image(systemName: "chart.bar")
                }
            }
        }
        .fullScreenCover(isPresented: $showingLyrics) { NowPlayingView() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .data],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            var added = 0
            for u in urls {
                if let t = MusicStore.importFile(from: u) {
                    library.add(t)
                    added += 1
                }
            }
            notice = added > 0 ? "导进来 \(added) 首" : "这些文件读不出来"
        }
    }

    /// 正在放的那一条。整条都能点，进歌词页。
    private func nowPlayingRow(_ track: Track) -> some View {
        Button {
            showingLyrics = true
        } label: {
            HStack(spacing: 11) {
                // 那个「正在播放的音乐头像」。转起来，一眼看出它是活的。
                TrackArtwork(track: track, side: 46)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.app(14, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    Text(nowLine ?? (track.subtitle.isEmpty ? "一起听着" : track.subtitle))
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(12)
            .glassCard(padding: 0)
        }
        .buttonStyle(.plain)
    }

    private var nowLine: String? {
        guard let i = player.currentLine,
              player.lines.indices.contains(i) else { return nil }
        return player.lines[i].text
    }

    private func row(_ track: Track, local: Bool) -> some View {
        let isCurrent = player.current?.id == track.id
        return Button {
            player.toggle(track)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isCurrent && player.playing ? "pause.fill" : "play.fill")
                    .font(.app(12))
                    .foregroundStyle(app.settings.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(app.settings.accentColor.opacity(0.16)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.app(14))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    if !track.subtitle.isEmpty {
                        Text(track.subtitle)
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)

                if !local {
                    Text("试听")
                        .font(.app(9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(padding: 0)
        .contextMenu {
            if local {
                Button(role: .destructive) {
                    library.remove(track)
                } label: {
                    Label("删掉", systemImage: Icon.trash)
                }
            }
        }
    }

    private func searchWeb() async {
        guard !keyword.isEmpty else { return }
        searching = true
        notice = nil

        // 三条路，从好到差依次退。
        //
        // ① 她要是配了电脑上那套，先走它——**只有那条能放 VIP**
        // ② 没配（或者没通）就**手机直连网易云**：整首 + 歌词，不用电脑、
        //    不用登录、不用配任何东西。这条是常态
        // ③ 直连也不成，才退回 iTunes 那三十秒
        //
        // 一路退到底也不报错让她一首都听不成——
        // **有得听比有个错误提示强。**

        let base = app.settings.neteaseBaseURL.trimmingCharacters(in: .whitespaces)
        if !base.isEmpty {
            if let r = try? await MusicSearch.searchNetease(keyword, base: base, limit: 8),
               !r.isEmpty {
                webResults = r
                searching = false
                return
            }
            notice = "你电脑那套没通，用直连的"
        }

        if let r = try? await MusicSearch.searchNeteaseDirect(keyword, limit: 10),
           !r.isEmpty {
            webResults = r
            searching = false
            return
        }

        do {
            webResults = try await MusicSearch.search(keyword, limit: 8)
            if notice == nil, !webResults.isEmpty {
                notice = "网易云没搜到能放的，这些是 iTunes 的三十秒试听"
            }
        } catch {
            notice = error.localizedDescription
            webResults = []
        }
        searching = false
    }
}

// MARK: - 一起听

/// 聊天页顶上的那条。放着歌的时候才出现，写着「一起听着」。
struct ListeningBar: View {

    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let track = player.current {
            HStack(spacing: 10) {
                TrackArtwork(track: track, side: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.app(12, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    Text("一起听着")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                Spacer(minLength: 4)

                Button {
                    player.playing ? player.pause() : player.resume()
                } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.app(10, weight: .medium))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassBackground(radius: 18, strength: app.settings.glassOpacity, extra: 0.15)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
