import SwiftUI

/// 放歌的时候那个小窗。
///
/// 以前是顶上一条横贯全屏的 bar，两个毛病：
///   · 右端压在三条杠底下，关闭叉点不着（她说的「重合了、关不掉」）
///   · 它一直霸占着顶部那一条，聊天内容被顶下去
///
/// 现在是**能拖的悬浮窗**：想放哪儿放哪儿，位置记着；
/// 点一下进歌词页，往边上一甩就收成一颗小圆点。
struct MusicFloatingView: View {

    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 停在屏幕的哪个位置（比例）
    @AppStorage("musicDockX") private var dockX: Double = 0.5
    @AppStorage("musicDockY") private var dockY: Double = 0.12
    /// 收起来了没有
    @AppStorage("musicMini") private var mini = false

    @State private var drag: CGSize = .zero
    @State private var showingLyrics = false

    var body: some View {
        GeometryReader { geo in
            if let track = player.current {
                Group {
                    if mini { dot(track) } else { card(track) }
                }
                .position(
                    x: min(max(46, geo.size.width * dockX + drag.width),
                           geo.size.width - 46),
                    y: min(max(70, geo.size.height * dockY + drag.height),
                           geo.size.height - 120)
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: mini)
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { v in
                            // 落在哪儿就记在哪儿
                            dockX = min(0.92, max(0.08,
                                (geo.size.width * dockX + v.translation.width)
                                    / geo.size.width))
                            dockY = min(0.86, max(0.06,
                                (geo.size.height * dockY + v.translation.height)
                                    / geo.size.height))
                            drag = .zero
                        }
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85),
                   value: player.current?.id)
        .fullScreenCover(isPresented: $showingLyrics) {
            NowPlayingView()
        }
    }

    // MARK: 展开的样子

    private func card(_ track: Track) -> some View {
        HStack(spacing: 9) {
            cover(track, side: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                // 有歌词就把正在唱的那句摆出来，没有就写「一起听着」。
                // 这一行是她最常瞟的地方，放最有信息量的东西。
                Text(nowLine ?? (track.artist.isEmpty ? "一起听着" : track.artist))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: 132, alignment: .leading)

            Button {
                player.playing ? player.pause() : player.resume()
            } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { mini = true }
            } label: {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                player.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassBackground(radius: 20, strength: app.settings.glassOpacity, extra: 0.2)
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.12), radius: 12, y: 5)
        // 点封面和标题那一片进歌词页
        .onTapGesture { showingLyrics = true }
    }

    /// 收起来的样子：一颗会转的封面
    private func dot(_ track: Track) -> some View {
        cover(track, side: 40)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1)
            }
            .clipShape(Circle())
            .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.16), radius: 8, y: 4)
            .onTapGesture { withAnimation { mini = false } }
    }

    @ViewBuilder
    private func cover(_ track: Track, side: CGFloat) -> some View {
        if let url = URL(string: track.artworkURL), !track.artworkURL.isEmpty {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.softFillDeep)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side / 4, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: side * 0.4))
                .foregroundStyle(app.settings.accentColor)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                    .fill(Theme.softFillDeep))
        }
    }

    private var nowLine: String? {
        guard let i = player.currentLine,
              player.lines.indices.contains(i) else { return nil }
        return player.lines[i].text
    }
}
