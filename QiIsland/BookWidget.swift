import WidgetKit
import SwiftUI

/// 桌面上的记账小组件：小的看本月和今天，中的多几个分类，大的再加一张按天深浅的日历。
/// 数据是 App 记完账写进钥匙串的那份（见 `BookWidgetShared.swift`）。
struct BookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QiBook", provider: BookProvider()) { entry in
            BookWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(white: 0.99), Color(white: 0.955)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("记账")
        .description("这个月花了多少、今天花了多少、钱都花在哪儿")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BookEntry: TimelineEntry {
    let date: Date
    let snap: BookWidgetSnapshot?
}

struct BookProvider: TimelineProvider {
    func placeholder(in context: Context) -> BookEntry { BookEntry(date: Date(), snap: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (BookEntry) -> Void) {
        completion(BookEntry(date: Date(), snap: Self.load() ?? (context.isPreview ? Self.sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BookEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        // 过了零点「今天」要清零：零点再来一次
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        let entries = [BookEntry(date: now, snap: Self.load()), BookEntry(date: midnight, snap: Self.load())]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(3600))))
    }

    static func load() -> BookWidgetSnapshot? {
        guard let data = SharedKeychain.read(key: "book") else { return nil }
        return try? JSONDecoder().decode(BookWidgetSnapshot.self, from: data)
    }

    static let sample: BookWidgetSnapshot = {
        var s = BookWidgetSnapshot()
        s.monthTitle = "10月"
        s.total = 1286.5
        s.categories = [.init(name: "餐饮", symbol: "fork.knife", amount: 642),
                        .init(name: "购物", symbol: "bag", amount: 318),
                        .init(name: "交通", symbol: "tram", amount: 126.5),
                        .init(name: "零食饮品", symbol: "cup.and.saucer", amount: 88)]
        s.days = (0..<30).map { i in i < 18 ? Double((i * 37) % 160) : 0 }
        return s
    }()
}

struct BookWidgetView: View {
    let entry: BookEntry
    @Environment(\.widgetFamily) private var family

    private let ink = Color(red: 0.2, green: 0.18, blue: 0.16)
    private let soft = Color(red: 0.55, green: 0.51, blue: 0.47)

    private var accent: Color { Color(hex: entry.snap?.accentHex ?? "C47A5A") }

    /// 这张汇总还是不是这个月的；不是的话按新的一个月算
    private var current: BookWidgetSnapshot? {
        guard let s = entry.snap else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: entry.date) == s.month ? s : nil
    }

    private var todayAmount: Double {
        guard let s = current else { return 0 }
        let d = Calendar.current.component(.day, from: entry.date) - 1
        return d >= 0 && d < s.days.count ? s.days[d] : 0
    }

    private static func money(_ v: Double) -> String {
        abs(v - v.rounded()) < 0.005 ? String(Int(v.rounded())) : String(format: "%.2f", v)
    }

    var body: some View {
        if entry.snap == nil {
            VStack(spacing: 6) {
                Image(systemName: "yensign.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(accent)
                Text("打开栖同步一次")
                    .font(.system(size: 12))
                    .foregroundStyle(soft)
            }
        } else {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
    }

    // MARK: 头

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((current?.monthTitle ?? monthTitleNow) + "支出")
                .font(.system(size: 11))
                .foregroundStyle(soft)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
                Text(Self.money(current?.total ?? 0))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    private var monthTitleNow: String { "\(Calendar.current.component(.month, from: entry.date))月" }

    private var todayLine: some View {
        HStack(spacing: 4) {
            Circle().fill(accent).frame(width: 5, height: 5)
            Text("今天 ¥" + Self.money(todayAmount))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ink.opacity(0.8))
        }
    }

    // MARK: 小

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 6)
            if let top = current?.categories.first {
                HStack(spacing: 4) {
                    Image(systemName: top.symbol)
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(accent)
                    Text("\(top.name)最多 ¥\(Self.money(top.amount))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(soft)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)
            }
            todayLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: 中

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 4)
                todayLine
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            categoryList(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func categoryList(_ n: Int) -> some View {
        let cats = Array((current?.categories ?? []).prefix(n))
        let top = cats.first?.amount ?? 1
        return VStack(alignment: .leading, spacing: 7) {
            if cats.isEmpty {
                Text("这个月还没有花销")
                    .font(.system(size: 11))
                    .foregroundStyle(soft)
            }
            ForEach(cats, id: \.self) { c in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: c.symbol)
                            .font(.system(size: 9.5, weight: .light))
                            .foregroundStyle(accent)
                            .frame(width: 12)
                        Text(c.name)
                            .font(.system(size: 10.5))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("¥" + Self.money(c.amount))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(ink)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ink.opacity(0.06))
                            Capsule().fill(accent.opacity(0.6))
                                .frame(width: max(3, g.size.width * CGFloat(c.amount / max(top, 0.01))))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
    }

    // MARK: 大

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                header
                Spacer()
                todayLine
            }
            heatmap
            categoryList(4)
            Spacer(minLength: 0)
        }
    }

    private func heat(_ v: Double, levels: [Double]) -> Color {
        guard v > 0.0001 else { return ink.opacity(0.05) }
        let lv = (levels.firstIndex(where: { v < $0 }) ?? levels.count) + 1
        let t = Double(lv - 1) / Double(max(1, levels.count))
        return accent.opacity(0.16 + 0.7 * t)
    }

    private var heatmap: some View {
        let s = current
        let days = s?.days ?? []
        let lead = max(0, (s?.firstWeekday ?? 1) - 1)
        let cells: [Double?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        let today = Calendar.current.component(.day, from: entry.date)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 8.5))
                        .foregroundStyle(soft)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells.indices, id: \.self) { i in
                    if let v = cells[i] {
                        let day = i - lead + 1
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(heat(v, levels: s?.levels ?? [50, 100, 200, 500]))
                            .frame(height: 17)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(day == today ? accent : Color.clear, lineWidth: 1)
                            )
                    } else {
                        Color.clear.frame(height: 17)
                    }
                }
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
