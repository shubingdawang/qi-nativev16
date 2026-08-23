import SwiftUI

/// 听得最多的那些。
///
/// 她要的「每首歌播放次数统计」。计数只在**一首真的放完**时 +1——
/// 点开听两秒就切走不算数，那不叫听过。
struct PlayCountView: View {

    @ObservedObject private var library = MusicLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let list = library.mostPlayed
                if list.isEmpty {
                    EmptyNote(icon: "chart.bar",
                              title: "还没有听完过一整首",
                              hint: "一首完整放完才记一次。听两秒就切走的不算。")
                        .padding(.top, 40)
                } else {
                    let top = list.first?.1 ?? 1
                    ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                        row(rank: i + 1, track: item.0, count: item.1, top: top)
                    }
                    Text("一共听完过 \(list.reduce(0) { $0 + $1.1 }) 次。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("听得最多")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(rank: Int, track: Track, count: Int, top: Int) -> some View {
        HStack(spacing: 11) {
            Text("\(rank)")
                .font(.app(13, weight: .semibold, design: .monospaced))
                .foregroundStyle(rank <= 3 ? app.settings.accentColor : Theme.textMuted(scheme))
                .frame(width: 22, alignment: .trailing)

            TrackArtwork(track: track, side: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                // 一条按最高那首等比的小横条，一眼看出差多少
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.softFillDeep)
                        Capsule()
                            .fill(app.settings.accentColor.opacity(0.7))
                            .frame(width: geo.size.width * CGFloat(count) / CGFloat(max(1, top)))
                    }
                }
                .frame(height: 5)
            }

            Text("\(count) 次")
                .font(.app(11, design: .monospaced))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { player.start(track) }
    }
}
