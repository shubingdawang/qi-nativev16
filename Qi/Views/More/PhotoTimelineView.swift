import SwiftUI

/// 相册的「时间线」：所有图片按存进来的日子排，跟抽屉那页一样——
/// 左边一条线，每一天一个点，点旁边是这一天的日期和这一天存的所有图（新的在上）。
/// 点一张看大图，能左右翻整条时间线。
struct PhotoTimelineView: View {
    @ObservedObject private var store = MediaStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var preview: MediaItem?

    private var all: [MediaItem] { store.list("photo").filter { !$0.fileName.isEmpty } }

    /// 按天分组：[(这一天, 这一天的图)]，新的在前
    private var days: [(Date, [MediaItem])] {
        let cal = Calendar.current
        var groups: [Date: [MediaItem]] = [:]
        for it in all { groups[cal.startOfDay(for: it.createdAt), default: []].append(it) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.createdAt > $1.createdAt }) }
    }

    private static func dayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        f.dateFormat = cal.component(.year, from: d) == cal.component(.year, from: Date()) ? "M月d日 EEEE" : "yyyy年M月d日 EEEE"
        return f.string(from: d)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if all.isEmpty {
                    EmptyNote(icon: "photo.on.rectangle.angled", title: "还没有图片",
                              hint: "存进相册的图会按日子排在这里：甜品屋的分享海报、从手机相册加进来的、聊天里存下来的。")
                        .padding(.top, 40)
                }
                let list = days
                ForEach(Array(list.enumerated()), id: \.element.0) { i, day in
                    row(day.0, day.1, first: i == 0, last: i == list.count - 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .fullScreenCover(item: $preview) { (item: MediaItem) in
            let items = all
            ImagePreviewView(items: items, index: items.firstIndex(where: { $0.id == item.id }) ?? 0, store: store)
        }
    }

    private func row(_ day: Date, _ items: [MediaItem], first: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 线：上一天接下来、往下接到下一天；第一天从点开始，最后一天到点为止
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(first ? Color.clear : Theme.textMuted(scheme).opacity(0.3))
                        .frame(width: 1.5, height: 14)
                    Rectangle()
                        .fill(last ? Color.clear : Theme.textMuted(scheme).opacity(0.3))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
                Circle()
                    .fill(app.settings.accentColor.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
                    .padding(.top, 9)
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(Self.dayLabel(day))
                        .font(.app(13, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("\(items.count) 张")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(.top, 5)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(items) { it in
                        thumb(it)
                            .onTapGesture { preview = it }
                    }
                }
            }
            .padding(.bottom, 22)
        }
    }

    private func thumb(_ it: MediaItem) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = ImageStore.thumb(it.fileName, maxPixel: 300) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Theme.textMuted(scheme).opacity(0.12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if !it.folder.isEmpty {
                    Text(it.folder)
                        .font(.app(9.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(Capsule().fill(.black.opacity(0.35)))
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
    }
}
