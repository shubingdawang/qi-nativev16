import SwiftUI

/// 日记的另一种看法：一天一叠，像夹在板子上的便签。
///
/// 一条条列着看，日子是平的；叠起来才有「那天发生了这些」的感觉。
///
/// **长按能把便签拎起来挪到任何地方，位置记着，下次进来还在那儿。**
///
/// 上一版这里写着"位置固定，不会每次刷新都乱跳"，其实是错的：
/// 它用的是 `entry.id.hashValue`，而 Swift 的 `String.hashValue`
/// **每个进程换一次随机种子**——同一条日记这次落在左边、下次可能在右边。
/// 而且偏移只有 ±30 点，一天写三条就叠成一坨（她说的「全挤在一起」）。
/// 现在默认位置走 `DiaryLayout` 里那个自己写的稳定散列，两列摊开。
struct DiaryStackView: View {

    let entries: [MCPEntry]

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var layout = DiaryLayout.shared
    @State private var opened: MCPEntry?
    @State private var dayOffset = 0
    /// 正被拎在手上的那张
    @State private var dragging: String?
    /// 从按下的地方挪了多远
    @State private var dragBy: CGSize = .zero

    /// 便签的几种颜色。按内容里的情绪挑，挑不出来就按顺序轮。
    private let papers: [Color] = [
        Color(hexString: "F3E7C8")!,   // 米黄
        Color(hexString: "E4EBDE")!,   // 淡绿
        Color(hexString: "F7E3E6")!,   // 浅粉
        Color(hexString: "EDEAE3")!,   // 灰白
        Color(hexString: "E8EDF2")!    // 淡蓝
    ]

    /// 按日期分组，最近的在前
    private var days: [(label: String, items: [MCPEntry])] {
        var buckets: [String: [MCPEntry]] = [:]
        var order: [String] = []
        for e in entries {
            let key = e.dateText.isEmpty ? "没写日期" : e.dateText
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(e)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private var currentDay: (label: String, items: [MCPEntry])? {
        guard !days.isEmpty else { return nil }
        let i = min(max(0, dayOffset), days.count - 1)
        return days[i]
    }

    var body: some View {
        VStack(spacing: 14) {

            if let day = currentDay {
                // 翻天
                HStack(spacing: 18) {
                    Button {
                        if dayOffset < days.count - 1 { dayOffset += 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.app(12, weight: .semibold))
                            .foregroundStyle(dayOffset < days.count - 1
                                             ? Theme.textSoft(scheme)
                                             : Theme.textMuted(scheme).opacity(0.3))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                    .disabled(dayOffset >= days.count - 1)

                    Text(day.label)
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))

                    Button {
                        if dayOffset > 0 { dayOffset -= 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.app(12, weight: .semibold))
                            .foregroundStyle(dayOffset > 0
                                             ? Theme.textSoft(scheme)
                                             : Theme.textMuted(scheme).opacity(0.3))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                    .disabled(dayOffset == 0)
                }

                // 那一叠。
                //
                // 高度跟着条数长——以前钉死 400，一天写六条就全叠在一起
                // 露不出来；两列摆开之后，行数多了得给它地方。
                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(day.items.enumerated()), id: \.element.id) { index, entry in
                            note(entry, index: index, width: geo.size.width)
                        }
                    }
                    .frame(width: geo.size.width, height: stackHeight(day.items.count))
                }
                .frame(height: stackHeight(day.items.count))
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    Text("这一天写了 \(day.items.count) 条 · 点开看全文 · 长按能挪")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    if day.items.contains(where: { layout.spot($0.id) != nil }) {
                        Button {
                            for e in day.items { layout.reset(e.id) }
                        } label: {
                            Text("摊回去")
                                .font(.app(10))
                                .foregroundStyle(app.settings.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("还没有日记")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.top, 40)
            }
        }
        .sheet(item: $opened) { entry in
            NavigationStack {
                ZStack {
                    WallpaperBackground()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                if !entry.author.isEmpty {
                                    Text(entry.author)
                                        .font(.app(12, weight: .semibold))
                                        .foregroundStyle(app.settings.accentColor)
                                }
                                Text(entry.dateText)
                                    .font(.app(11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            if !entry.title.isEmpty {
                                Text(entry.title)
                                    .font(.app(18, weight: .medium))
                                    .foregroundStyle(Theme.textMain(scheme))
                            }
                            Text(entry.body)
                                .font(.app(15))
                                .lineSpacing(7)
                                .foregroundStyle(Theme.textSoft(scheme))
                                .textSelection(.enabled)
                            if !entry.tags.isEmpty {
                                HStack(spacing: 5) {
                                    ForEach(entry.tags, id: \.self) { t in
                                        Text(t)
                                            .font(.app(10))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule()
                                                .fill(app.settings.accentColor.opacity(0.16)))
                                            .foregroundStyle(Theme.textSoft(scheme))
                                    }
                                }
                            }
                        }
                        .padding(18)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关上") { opened = nil }
                    }
                }
            }
        }
    }

    /// 这一叠要多高。两列一行，一行 118 点，上下再留点富余。
    /// 她拖到下面去的那些也得算进来，不然会被裁掉。
    private func stackHeight(_ count: Int) -> CGFloat {
        let rows = (count + 1) / 2
        let base = max(400, CGFloat(rows) * 118 + 150)
        let lowest = layout.spots.values.map(\.y).max() ?? 0
        return max(base, lowest + 260)
    }

    /// 一张便签。
    ///
    /// **长按拎起来，拖到哪儿放哪儿，位置记着。**
    /// 点一下还是打开看全文，两个手势不冲突。
    private func note(_ entry: MCPEntry, index: Int, width: CGFloat) -> some View {
        // 位置：她拖过就用她拖的，没拖过用默认摊开的那个。
        //
        // 默认位置和歪的角度都走**自己写的稳定散列**，不是 String.hashValue——
        // 后者每个进程换一次种子，用它算位置等于每次重开 App 都重新洗牌，
        // 同一条日记这次在左边下次在右边。
        let home = DiaryLayout.defaultSpot(id: entry.id, index: index, width: width)
        let saved = layout.spot(entry.id) ?? home
        let live = dragging == entry.id
            ? CGPoint(x: saved.x + dragBy.width, y: saved.y + dragBy.height)
            : saved
        let angle = DiaryLayout.angle(id: entry.id)
        let paper = papers[DiaryLayout.steadyHash(entry.id) % papers.count]

        return VStack(alignment: .leading, spacing: 7) {
            Text(entry.displayTitle)
                .font(.app(14, weight: .semibold))
                .foregroundStyle(Color(hexString: "3A362E")!)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.app(11))
                    .foregroundStyle(Color(hexString: "6B655A")!)
                    .lineLimit(2)
            }

            if !entry.tags.isEmpty {
                Text(entry.tags.prefix(4).joined(separator: "、"))
                    .font(.app(10))
                    .foregroundStyle(Color(hexString: "8A8375")!)
                    .lineLimit(1)
            }
        }
        .padding(13)
        .frame(width: 168, alignment: .leading)
        .background {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(paper)
                // 顶上那个小夹子
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hexString: "E5DCC8")!)
                    .frame(width: 20, height: 26)
                    .offset(y: -11)
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
            }
        }
        // 拎在手上的时候抬高一点、影子散开、别再歪着
        .shadow(color: .black.opacity(dragging == entry.id ? 0.26 : 0.13),
                radius: dragging == entry.id ? 12 : 6,
                x: 1, y: dragging == entry.id ? 9 : 4)
        .rotationEffect(.degrees(dragging == entry.id ? 0 : angle))
        .scaleEffect(dragging == entry.id ? 1.06 : 1)
        .offset(x: live.x, y: live.y)
        // 手上那张永远压在最上面，不然会被别的盖住
        .zIndex(dragging == entry.id ? 999 : Double(index))
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: dragging)
        .onTapGesture { opened = entry }
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    dragging = entry.id
                    dragBy = .zero
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(_, let drag?) = value {
                        dragBy = drag.translation
                    }
                }
                .onEnded { _ in
                    guard dragging == entry.id else { return }
                    layout.move(entry.id,
                                to: CGPoint(x: saved.x + dragBy.width,
                                            y: saved.y + dragBy.height))
                    dragging = nil
                    dragBy = .zero
                }
        )
    }
}
