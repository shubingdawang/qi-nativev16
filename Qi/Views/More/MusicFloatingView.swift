import SwiftUI

/// 放歌的时候那个小窗。
///
/// 她要的样子（原话）：
/// 「默认收在侧边，点击后弹出可以暂停或者叉掉，右滑收回剩一个专辑封面，
///   可以长按在侧边拖动到任意位置，当然要避开输入框和右上角的三杠，
///   然后增加一点播放音乐的动画。」
///
/// 所以这一版：
/// · **默认是收着的**——只有一颗贴边的封面，转着
/// · 点一下弹出来：封面 + 歌名/正在唱的那句 + 暂停 + 叉掉
/// · 往右一划收回去（左边那侧就是往左划）
/// · **长按**才能拖，而且只沿着侧边上下走——
///   随手一碰就把它拖跑，比拖不动更烦
/// · 上下都留了禁区：顶上是三条杠，底下是输入框
struct MusicFloatingView: View {

    @ObservedObject private var player = MusicPlayer.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 贴在哪一侧、贴在多高（比例）
    @AppStorage("musicDockRight") private var dockRight = true
    @AppStorage("musicDockY") private var dockY: Double = 0.42
    /// 收起来了没有。**默认收着**
    @AppStorage("musicMini") private var mini = true

    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var showingLyrics = false
    @State private var spin: Double = 0

    /// 顶上留给三条杠的地方
    private let topGuard: CGFloat = 132
    /// 底下留给输入框的地方
    private let bottomGuard: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            if let track = player.current {
                let side: CGFloat = mini ? 46 : 210
                let x = dockRight
                    ? geo.size.width - side / 2 - 12
                    : side / 2 + 12
                let minY = topGuard
                let maxY = max(topGuard + 40, geo.size.height - bottomGuard)
                let y = min(max(minY, geo.size.height * dockY + drag.height), maxY)

                Group {
                    if mini { pill(track) } else { card(track) }
                }
                .frame(width: side, alignment: dockRight ? .trailing : .leading)
                .position(x: x + (dragging ? drag.width * 0.25 : 0), y: y)
                .scaleEffect(dragging ? 1.08 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: mini)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
                // 长按之后才能拖。拖的是「贴边的高度」，左右只用来换边。
                .gesture(
                    LongPressGesture(minimumDuration: 0.32)
                        .onEnded { _ in
                            dragging = true
                            if app.settings.haptics {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        }
                        .sequenced(before: DragGesture())
                        .onChanged { value in
                            if case .second(true, let d?) = value { drag = d.translation }
                        }
                        .onEnded { value in
                            if case .second(true, let d?) = value {
                                let landed = (geo.size.height * dockY + d.translation.height)
                                dockY = min(0.92, max(0.06, landed / geo.size.height))
                                // 横着拖过半个屏就换边
                                if abs(d.translation.width) > geo.size.width * 0.28 {
                                    dockRight = d.translation.width < 0 ? false : true
                                }
                            }
                            drag = .zero
                            dragging = false
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
        // 转起来。**三个时机都要管**：进来、开始放、换了一首——
        // 以前只管前两个，所以她看到的常常是「一直没动」
        .onAppear { startSpin() }
        .onChange(of: player.playing) { _, on in if on { startSpin() } }
        .onChange(of: player.current?.id) { _, _ in startSpin() }
        // 展开再收回来也要重新转。
        //
        // 收着的那颗封面（pill）在展开的时候整个从界面上撤掉了，
        // SwiftUI 会把它身上那条 repeatForever 一起取消；收回来是**新建**一个视图，
        // 上面什么动画都没有——她看到的就是「展开后再收起就不转了」。
        // 这三个 onChange 少一个都会有一种「不转」的情况。
        .onChange(of: mini) { _, _ in startSpin() }
    }

    /// 转封面。放着才转，停了就停在原地——一眼能看出它是不是活的。
    private func startSpin() {
        guard player.playing else { return }
        // 先把角度归零再起，不然第二次调用时 spin 已经是 360，
        // 「从 360 转到 360」= 一动不动（她说的「动画貌似没有正常播放」）
        spin = 0
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
            spin = 360
        }
    }

    // MARK: 收着的样子：一颗贴边的封面

    private func pill(_ track: Track) -> some View {
        ZStack {
            // 放着的时候外面有一圈会呼吸的光
            if player.playing {
                Circle()
                    .stroke(app.settings.accentColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 46, height: 46)
                    .scaleEffect(dragging ? 1 : 1.14)
                    .opacity(0.5)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                               value: player.playing)
            }
            TrackArtwork(track: track, side: 42)
                .clipShape(Circle())
                .rotationEffect(.degrees(player.playing ? spin : spin))
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1)
                }
                .overlay(alignment: .center) {
                    // 中间那个小孔，像张唱片
                    Circle()
                        .fill(scheme == .dark ? Color.black.opacity(0.55)
                                              : Color.white.opacity(0.75))
                        .frame(width: 9, height: 9)
                }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.16), radius: 8, y: 4)
        .contentShape(Circle())
        .onTapGesture { withAnimation { mini = false } }
    }

    // MARK: 弹出来的样子

    private func card(_ track: Track) -> some View {
        HStack(spacing: 9) {
            // **不转**。方的封面一转就成了菱形（她说的「点开悬浮窗封面图变成菱形」）——
            // 转只留给收起来时那颗圆的，圆的怎么转都还是圆的。
            TrackArtwork(track: track, side: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                // 有歌词就把正在唱的那句摆出来。这一行是她最常瞟的地方。
                Text(nowLine ?? (track.artist.isEmpty ? "一起听着" : track.artist))
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { showingLyrics = true }

            // 那三根竖线以前只是个「在放着」的装饰，她问「不知道有什么作用」——
            // 装饰占着一个位置却什么都不干，那就换成有用的：
            // **点它切「放完之后干什么」**（停 / 单曲循环 / 随机）。
            Button {
                player.repeatMode = player.repeatMode.next
                if app.settings.haptics {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                Image(systemName: player.repeatMode.icon)
                    .font(.app(11))
                    .foregroundStyle(player.repeatMode == .off
                                     ? Theme.textMuted(scheme)
                                     : app.settings.accentColor)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                player.playing ? player.pause() : player.resume()
            } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                player.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.app(10, weight: .medium))
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
        // 往边上划就收回去。贴右边往右划，贴左边往左划。
        .highPriorityGesture(
            DragGesture(minimumDistance: 26)
                .onEnded { v in
                    let outward = dockRight ? v.translation.width : -v.translation.width
                    if outward > 26 { withAnimation { mini = true } }
                }
        )
    }

    private var nowLine: String? {
        guard let i = player.currentLine,
              player.lines.indices.contains(i) else { return nil }
        return player.lines[i].text
    }
}

// MARK: - 封面

/// 一首歌的封面。**三条路，按这个顺序**：
///   1. 本机存下来的那张（自己导进来的音频，从文件的 APIC 帧扒出来的）
///   2. 网上那张（网易云 / iTunes 给的地址）
///   3. 都没有，画个音符
///
/// 以前只有第 2 条，所以她导进来的歌永远是个音符——
/// 明明文件里就带着封面。
struct TrackArtwork: View {

    let track: Track
    var side: CGFloat = 44

    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if !track.artworkName.isEmpty,
               let image = ImageStore.cached(track.artworkName) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = URL(string: track.artworkURL), !track.artworkURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: side, height: side)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Theme.softFillDeep)
            Image(systemName: "music.note")
                .font(.app(side * 0.36))
                .foregroundStyle(app.settings.accentColor.opacity(0.8))
        }
    }
}
