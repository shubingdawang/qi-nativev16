import SwiftUI

// MARK: - 记忆星图
//
// 见 `MemoryGraph.swift` 开头那段：为什么画、怎么算的。
// 这一页只管画和点。
//
// ## 两个刻意的选择
//
// · **位置是算出来的、不是仿真出来的。** 力导向每次跑出来都不一样，
//   她今天记住「日本在右上角」，明天进来它跑到左下去了——那张图就没法用了。
// · **点一颗星，底下出的是一条时间线**，不是一堆搜索结果。
//   她想看的是「这件事怎么一路变过来的」，那正是 `recall_entity` 那套。

struct ConstellationView: View {

    @ObservedObject private var store = MemoryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var graph = MemoryGraph()
    @State private var picked: StarNode?
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    var body: some View {
        ZStack {
            WallpaperBackground()

            GeometryReader { geo in
                ZStack {
                    // 连线在底下，星星压在上面
                    edges(in: geo.size)
                    galaxyLabels(in: geo.size)
                    stars(in: geo.size)
                    core(in: geo.size)
                }
                .scaleEffect(zoom)
                .offset(pan)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { zoom = min(3, max(0.6, lastZoom * $0)) }
                            .onEnded { _ in lastZoom = zoom },
                        DragGesture()
                            .onChanged { v in
                                pan = CGSize(width: lastPan.width + v.translation.width,
                                             height: lastPan.height + v.translation.height)
                            }
                            .onEnded { _ in lastPan = pan }
                    )
                )
            }

            if graph.nodes.isEmpty { empty }

            // 点中的那颗，底下出一张卡
            if let picked {
                VStack {
                    Spacer()
                    StarSheet(node: picked, graph: graph) { self.picked = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("星图")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        zoom = 1; lastZoom = 1
                        pan = .zero; lastPan = .zero
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
        .onAppear { graph = MemoryMap.build(store.memories) }
    }

    // MARK: 画

    /// 连线。**只画前 60 条**——全画出来就是一张蜘蛛网，
    /// 什么都看不出来。次数多的那些才是真的「常常一起被提起」。
    private func edges(in size: CGSize) -> some View {
        Canvas { ctx, _ in
            let byName = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.name, $0) })
            for e in graph.edges.prefix(60) {
                guard let a = byName[e.a], let b = byName[e.b] else { continue }
                var path = Path()
                path.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
                path.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height))
                // 一起出现得越多，线越实
                let strength = min(0.42, 0.07 + Double(e.times) * 0.05)
                ctx.stroke(path,
                           with: .color(app.settings.accentColor.opacity(strength)),
                           lineWidth: min(2.4, 0.6 + Double(e.times) * 0.28))
            }
        }
        .allowsHitTesting(false)
    }

    private func galaxyLabels(in size: CGSize) -> some View {
        ForEach(graph.galaxies, id: \.name) { g in
            Text(g.name)
                .font(.app(10, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme).opacity(0.75))
                .position(x: g.x * size.width, y: g.y * size.height)
                .allowsHitTesting(false)
        }
    }

    private func stars(in size: CGSize) -> some View {
        ForEach(graph.nodes) { n in
            let r = radius(n.weight)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    picked = picked?.name == n.name ? nil : n
                }
            } label: {
                VStack(spacing: 3) {
                    Circle()
                        .fill(tone(n).opacity(picked?.name == n.name ? 1 : 0.82))
                        .frame(width: r, height: r)
                        .overlay {
                            Circle().strokeBorder(
                                picked?.name == n.name ? Theme.textMain(scheme) : .clear,
                                lineWidth: 1.5)
                        }
                        .shadow(color: tone(n).opacity(0.6), radius: r * 0.4)
                    Text(n.name)
                        .font(.app(9))
                        .foregroundStyle(Theme.textMain(scheme).opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: n.x * size.width, y: n.y * size.height)
        }
    }

    /// 正中间那个核。她和他——**整张图是绕着这一点长出来的**。
    private func core(in size: CGSize) -> some View {
        let me = app.settings.userName.isEmpty ? "我" : app.settings.userName
        let him = app.settings.aiName.isEmpty ? "他" : app.settings.aiName
        return VStack(spacing: 2) {
            Circle()
                .fill(app.settings.accentColor)
                .frame(width: 13, height: 13)
                .shadow(color: app.settings.accentColor.opacity(0.7), radius: 7)
            Text(me + " · " + him)
                .font(.app(9, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
        }
        .position(x: size.width / 2, y: size.height / 2)
        .allowsHitTesting(false)
    }

    /// 星星多大。出现得越多越大，但**开方压一下**——
    /// 不压的话「饼饼」会大得像颗太阳，别的全成了沙子。
    private func radius(_ w: Int) -> CGFloat {
        min(26, 8 + sqrt(Double(w)) * 3.2)
    }

    /// 星星什么颜色。按星系（也就是她自己的 tag）算一个固定色相——
    /// **同一个星系永远同一个颜色**，跟书脊那套一个道理。
    private func tone(_ n: StarNode) -> Color {
        let seed = abs(n.galaxy.hashValue)
        return Color(hue: Double(seed % 360) / 360, saturation: 0.5, brightness: 0.78)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.app(30, weight: .light))
                .foregroundStyle(app.settings.accentColor.opacity(0.5))
            Text("还连不成一张图")
                .font(.app(13))
                .foregroundStyle(Theme.textMuted(scheme))
            Text(MD.inline("星星是记忆里提到过的人和东西，**至少被提过两次**才上图。\n再攒一阵子就有了。"))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme).opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}


// MARK: - 点中那颗星

/// 底下弹出来的那张卡：这颗星是怎么一路长出来的。
///
/// **给的是一条时间线，不是一堆搜索结果**——
/// 她点「日本」想知道的是「日本这件事怎么变过来的」，
/// 那正是 `recall_entity` 那套：按时间排，作废的也列出来。
struct StarSheet: View {

    let node: StarNode
    let graph: MemoryGraph
    var onClose: () -> Void

    @ObservedObject private var store = MemoryStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 这颗星牵着的记忆，**按时间排**
    private var line: [MemoryItem] {
        store.memories.filter {
            ($0.entities ?? []).contains(node.name)
        }
        .sorted { MemoryRecall.itemDate($0) < MemoryRecall.itemDate($1) }
    }

    /// 这条线上还牵着谁
    private var neighbours: [String] {
        graph.edges
            .filter { $0.a == node.name || $0.b == node.name }
            .sorted { $0.times > $1.times }
            .prefix(6)
            .map { $0.a == node.name ? $0.b : $0.a }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(node.name)
                    .heading(16)
                    .foregroundStyle(Theme.textMain(scheme))
                Text(node.galaxy)
                    .font(.app(10))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(app.settings.accentColor.opacity(0.16)))
                    .foregroundStyle(app.settings.accentColor)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.app(17))
                        .foregroundStyle(Theme.textMuted(scheme).opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            if !neighbours.isEmpty {
                Text("这条线上还牵着：" + neighbours.joined(separator: "、"))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(line) { m in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(String(repeating: "★",
                                            count: max(1, min(5, m.level))))
                                    .font(.app(9))
                                    .foregroundStyle(app.settings.accentColor)
                                Text(String(m.created_at.prefix(10)))
                                    .font(.app(9))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                // 后面接着一条新的，标一句**它是哪个时候的**。
                                // 不写「不算数」——她说过，此前的记忆全都算数。
                                if m.superseded_by != nil {
                                    Text("后来还有一条")
                                        .font(.app(9))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                            }
                            // 改过的那条要画出删除线，所以走 MarkdownText
                            MarkdownText(text: m.display, fontSize: 13)
                                .foregroundStyle(Theme.textMain(scheme))
                        }
                    }
                    if line.isEmpty {
                        Text("这颗星底下还没有记忆。")
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 260)
        }
        .padding(16)
        .glassBackground(radius: 22, strength: app.settings.glassOpacity)
        .padding(.horizontal, 10)
        .padding(.bottom, 22)
    }
}
