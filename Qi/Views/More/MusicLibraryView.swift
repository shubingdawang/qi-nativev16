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

    private var mine: [Track] { library.search(keyword) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: Icon.search)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted(scheme))
                        TextField("找歌，或者搜网上的", text: $keyword)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
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
                            .font(.system(size: 16))
                            .foregroundStyle(app.settings.accentColor)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }

                if let notice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                if library.tracks.isEmpty && webResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(app.settings.accentColor.opacity(0.5))
                        Text("还没有歌")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text("点右上角从「文件」导入 mp3、m4a、flac。\n网易云会员下载的歌，先存进「文件」App 再导进来就是整首。\n上面直接搜是网上的三十秒试听。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted(scheme).opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
                }

                if !mine.isEmpty {
                    Text("我的")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    ForEach(mine) { track in
                        row(track, local: true)
                    }
                }

                if searching {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("在搜…").font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }

                if !webResults.isEmpty {
                    Text("网上的（三十秒试听）")
                        .font(.system(size: 13, weight: .medium))
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

    private func row(_ track: Track, local: Bool) -> some View {
        let isCurrent = player.current?.id == track.id
        return Button {
            player.toggle(track)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isCurrent && player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(app.settings.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(app.settings.accentColor.opacity(0.16)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    if !track.subtitle.isEmpty {
                        Text(track.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)

                if !local {
                    Text("试听")
                        .font(.system(size: 9))
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
        do {
            webResults = try await MusicSearch.search(keyword, limit: 8)
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
                if let url = URL(string: track.artworkURL), !track.artworkURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Theme.softFillDeep)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 13))
                        .foregroundStyle(app.settings.accentColor)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.softFillDeep))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .lineLimit(1)
                    Text("一起听着")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                Spacer(minLength: 4)

                Button {
                    player.playing ? player.pause() : player.resume()
                } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
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
