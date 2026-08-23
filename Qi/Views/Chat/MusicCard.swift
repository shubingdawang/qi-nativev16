import SwiftUI

/// 他放的歌，在聊天里是一张卡。
/// 浅色下是毛玻璃，深色下压成一块深底——参考图里就是这两种。
struct MusicCard: View {

    let track: Track
    var caption: String = "零点的歌"

    @EnvironmentObject var app: AppState
    @ObservedObject private var player = MusicPlayer.shared
    @Environment(\.colorScheme) private var scheme

    /// 卡片上显示、以及点下去要放的，**是库里现在最好的那一版**，
    /// 不是他当初放的时候那份快照。她后来导进来的完整版会自动顶上来。
    private var shown: Track { MusicLibrary.shared.best(for: track) }
    /// 认歌名+歌手，不认 id——导进来那份的 id 跟卡片里这份天生不一样，
    /// 认 id 的话「明明在放」卡片上也不会亮。
    private var isCurrent: Bool { MusicLibrary.sameSong(player.current, shown) }
    private var isPlaying: Bool { isCurrent && player.playing }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.app(9))
                        Text(caption)
                            .font(.app(10))
                    }
                    .foregroundStyle(labelColor.opacity(0.7))

                    Text(shown.title)
                        .font(.app(18, weight: .semibold, design: .serif))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)

                    if !shown.subtitle.isEmpty {
                        Text(shown.subtitle)
                            .font(.app(11))
                            .foregroundStyle(labelColor.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                artwork

                Button {
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    player.toggle(shown)
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.app(14))
                        .foregroundStyle(labelColor)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(labelColor.opacity(0.16)))
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            // 放着的时候才出进度条，平时不占地方
            if isCurrent, player.duration > 0 {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(labelColor.opacity(0.2))
                                .frame(height: 3)
                            Capsule()
                                .fill(labelColor.opacity(0.75))
                                .frame(width: geo.size.width * ratio, height: 3)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let target = (location.x / geo.size.width) * player.duration
                            player.seek(to: target)
                        }
                    }
                    .frame(height: 3)

                    HStack {
                        Text(clock(player.progress))
                        Spacer()
                        if shown.isPreview {
                            Text("试听片段")
                        }
                        Spacer()
                        Text(clock(player.duration))
                    }
                    .font(.app(9))
                    .foregroundStyle(labelColor.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
            }
        }
        // 参考图里那张是**铺开的**：卡片占满气泡这一栏，封面和播放键都大。
        // 以前钉死 275，摆在一屏里像张小票；340 是给它一个上限，
        // 小屏上会自己缩到那一栏放得下的宽度。
        .frame(maxWidth: 340)
        .background(cardBackground)
    }

    private var ratio: Double {
        guard player.duration > 0 else { return 0 }
        return min(1, max(0, player.progress / player.duration))
    }

    private func clock(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    private var labelColor: Color {
        scheme == .dark ? .white : Theme.textMain(scheme)
    }

    private var artwork: some View {
        TrackArtwork(track: shown, side: 56)
            .clipShape(Circle())
    }

    @ViewBuilder
    private var cardBackground: some View {
        if scheme == .dark {
            // 深色下用一块沉下去的底，比毛玻璃更像参考图里那张
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
        } else {
            GlassSurface(radius: 16, strength: app.settings.glassOpacity)
        }
    }
}
