import SwiftUI

/// 日记的另一种看法：一天一叠，像夹在板子上的便签。
///
/// 一条条列着看，日子是平的；叠起来才有"那天发生了这些"的感觉。
/// 每张的角度、位置都固定，不会每次刷新都乱跳——
/// 用条目自己的 id 算出来的偏移，同一条永远落在同一个地方。
struct DiaryStackView: View {

    let entries: [MCPEntry]

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var opened: MCPEntry?
    @State private var dayOffset = 0

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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(dayOffset < days.count - 1
                                             ? Theme.textSoft(scheme)
                                             : Theme.textMuted(scheme).opacity(0.3))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                    .disabled(dayOffset >= days.count - 1)

                    Text(day.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))

                    Button {
                        if dayOffset > 0 { dayOffset -= 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(dayOffset > 0
                                             ? Theme.textSoft(scheme)
                                             : Theme.textMuted(scheme).opacity(0.3))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                    .disabled(dayOffset == 0)
                }

                // 那一叠
                ZStack {
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, entry in
                        note(entry, index: index, total: day.items.count)
                    }
                }
                .frame(height: 400)
                .frame(maxWidth: .infinity)

                Text("这一天写了 \(day.items.count) 条 · 点开看全文")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                Text("还没有日记")
                    .font(.system(size: 12))
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
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(app.settings.accentColor)
                                }
                                Text(entry.dateText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            if !entry.title.isEmpty {
                                Text(entry.title)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Theme.textMain(scheme))
                            }
                            Text(entry.body)
                                .font(.system(size: 15))
                                .lineSpacing(7)
                                .foregroundStyle(Theme.textSoft(scheme))
                                .textSelection(.enabled)
                            if !entry.tags.isEmpty {
                                HStack(spacing: 5) {
                                    ForEach(entry.tags, id: \.self) { t in
                                        Text(t)
                                            .font(.system(size: 10))
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

    /// 一张便签
    private func note(_ entry: MCPEntry, index: Int, total: Int) -> some View {
        // 用 id 算偏移，同一条永远落在同一个位置
        let seed = abs(entry.id.hashValue)
        let angle = Double((seed % 9) - 4) * 0.9
        let dx = CGFloat((seed / 7) % 60) - 30
        let dy = CGFloat(index) * 34 - CGFloat(total) * 12
        let paper = papers[abs(entry.id.hashValue) % papers.count]

        return VStack(alignment: .leading, spacing: 7) {
            Text(entry.displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hexString: "3A362E")!)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hexString: "6B655A")!)
                    .lineLimit(2)
            }

            if !entry.tags.isEmpty {
                Text(entry.tags.prefix(4).joined(separator: "、"))
                    .font(.system(size: 10))
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
        .shadow(color: .black.opacity(0.13), radius: 6, x: 1, y: 4)
        .rotationEffect(.degrees(angle))
        .offset(x: dx, y: dy)
        .zIndex(Double(index))
        .onTapGesture { opened = entry }
    }
}
