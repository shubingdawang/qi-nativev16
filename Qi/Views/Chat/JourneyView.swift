import SwiftUI

/// 一趟"旅行"。他从相册里挑几张图，给每张配一个地名和一段话，
/// 拼成一个可以点进去慢慢看的东西。
struct Journey: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// 大标题，比如「带你去了意大利」
    var title: String = ""
    /// 副标题那行，比如 2026 · 6 处停留
    var subtitle: String = ""
    /// 卡片最底下那句话
    var quote: String = ""
    var stops: [JourneyStop] = []
    /// 这趟配的歌，点进去会自己放起来
    var track: Track? = nil
    var createdAt: Date = Date()
}

struct JourneyStop: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// 地名
    var place: String = ""
    /// 地名下面那行小字，比如 Giorno 2
    var caption: String = ""
    /// 本地图片
    var imageName: String = ""
    /// 到了这儿他要讲的那段话
    var narration: String = ""
}

// MARK: - 聊天里的那张卡

struct JourneyCard: View {

    let journey: Journey
    var onOpen: () -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 5) {
                Text("JOURNEYS")
                    .font(.app(9, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(app.settings.accentColor.opacity(0.75))
                Text(journey.title)
                    .font(.app(19, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.textMain(scheme))
                    .multilineTextAlignment(.center)
                if !journey.subtitle.isEmpty {
                    Text(journey.subtitle)
                        .font(.app(10))
                        .tracking(2)
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(.top, 16)

            // 一排竖条照片，最后一张会被裁掉一点，暗示还能往右
            HStack(spacing: 6) {
                ForEach(journey.stops.prefix(6)) { stop in
                    if let img = ImageStore.load(stop.imageName) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 118)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.softFillDeep)
                            .frame(width: 36, height: 118)
                    }
                }
            }

            if !journey.quote.isEmpty {
                Text(journey.quote)
                    .font(.app(11, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.textMuted(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }

            Text("点进去看看")
                .font(.app(10))
                .foregroundStyle(app.settings.accentColor.opacity(0.7))
                .padding(.bottom, 14)
        }
        .frame(width: 285)
        .glassBackground(radius: 18, strength: app.settings.glassOpacity)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpen)
    }
}

// MARK: - 点进去之后

/// 全屏一张一张地走。图会很慢地推近，他讲的话一句一句浮出来。
struct JourneyPlayerView: View {

    let journey: Journey

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var shown = ""          // 已经念出来的部分
    @State private var finished = false    // 这一段念完了
    @State private var expanded = false
    @State private var zoom = false
    @State private var typing: Task<Void, Never>?

    private var stop: JourneyStop? {
        journey.stops.indices.contains(index) ? journey.stops[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let stop {
                // 图本身很缓地推近，看久了不会觉得是张死图
                if let img = ImageStore.load(stop.imageName) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(zoom ? 1.12 : 1.0)
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 14), value: zoom)
                }

                // 上下压暗，不然白天的图上什么字都看不清
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack {
                    // 地名。点一下重念这一段。
                    Button {
                        startTyping(stop.narration)
                    } label: {
                        VStack(spacing: 4) {
                            Text(stop.place)
                                .font(.app(22, weight: .medium, design: .serif))
                                .italic()
                                .foregroundStyle(.white)
                            if !stop.caption.isEmpty {
                                Text(stop.caption)
                                    .font(.app(11))
                                    .tracking(2)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 54)

                    Spacer()

                    // 念到一半就浮在中间，念完了收到左下角
                    if !finished {
                        Text(shown)
                            .font(.app(17, design: .serif))
                            .italic()
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .padding(.horizontal, 34)
                            .shadow(color: .black.opacity(0.5), radius: 8)
                        Spacer()
                    }

                    if finished {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stop.narration)
                                .font(.app(13, design: .serif))
                                .italic()
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(4)
                                .lineLimit(expanded ? nil : 4)
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
                            } label: {
                                Text(expanded ? "收起 ↑" : "展开全文 ↓")
                                    .font(.app(11))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                        .transition(.opacity)
                    }

                    // 底下那条歌
                    if let track = journey.track {
                        MusicCard(track: track, caption: "这趟的歌")
                            .padding(.bottom, 14)
                    }

                    // 页码
                    HStack(spacing: 6) {
                        ForEach(journey.stops.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? Color.white.opacity(0.9) : Color.white.opacity(0.3))
                                .frame(width: i == index ? 18 : 6, height: 6)
                        }
                    }
                    .padding(.bottom, 26)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                typing?.cancel()
                dismiss()
            } label: {
                Image(systemName: Icon.close)
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.black.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .padding(.top, 6)
        }
        // 左右滑翻页
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    if v.translation.width < -50 { go(index + 1) }
                    else if v.translation.width > 50 { go(index - 1) }
                }
        )
        .statusBarHidden()
        .onAppear {
            go(0)
            // 进来就把歌放上，出去就停——不然退出了还在响
            if let track = journey.track { MusicPlayer.shared.start(track) }
        }
        .onDisappear {
            typing?.cancel()
            if journey.track != nil { MusicPlayer.shared.stop() }
        }
    }

    private func go(_ i: Int) {
        guard journey.stops.indices.contains(i) else { return }
        index = i
        expanded = false
        zoom = false
        // 让缩放从头开始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { zoom = true }
        startTyping(journey.stops[i].narration)
    }

    /// 一个字一个字地出来。太快就没有"他在讲"的感觉，
    /// 标点后面多停一下，像换气。
    private func startTyping(_ text: String) {
        typing?.cancel()
        shown = ""
        finished = false
        guard !text.isEmpty else { finished = true; return }

        typing = Task { @MainActor in
            for ch in text {
                if Task.isCancelled { return }
                shown.append(ch)
                let pause: UInt64 = "。！？\n".contains(ch) ? 420_000_000
                    : "，、；：".contains(ch) ? 220_000_000
                    : 62_000_000
                try? await Task.sleep(nanoseconds: pause)
            }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeInOut(duration: 0.35)) { finished = true }
        }
    }
}
