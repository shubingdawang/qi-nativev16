import SwiftUI

/// 他自己醒来的历史。
///
/// ## 她说的
///
/// 「加一个历史记录，我能直接看见他自己醒来说过的话。
/// **抽屉式且固定显示 10 条的高度**，超出高度的记录我手势上滑查看，
/// **最新的在上面**，按照日期查看可以翻页。」
///
/// 逐条对着做：
///   · 抽屉         —— 点标题那行拉开／收起，不占着地方
///   · 十条的高度   —— `viewport` 写死，多的在里面滚
///   · 最新在上面   —— `WakeLog.entries` 本来就是插在头上的
///   · 按日期翻页   —— 左右两个箭头走 `WakeLog.days`
///
/// ⚠️ **翻页只翻有记录的那些天**，不是从今天一天天往回退——
/// 中间空着的日子会翻出一串空页，翻十下才看到上一条。
struct WakeHistoryDrawer: View {

    @ObservedObject private var log = WakeLog.shared
    @Environment(\.colorScheme) private var scheme
    let tint: Color

    @State private var open = false
    /// 现在看的是 `log.days` 里的第几天。0 = 最近有记录的那天
    @State private var page = 0

    /// ⚠️ **十条的高度写死在这儿。** 34 是一行的行高，
    /// 加上行距正好十条——多的往上滑。
    private var viewport: CGFloat { 10 * 34 }

    private var days: [Date] { log.days }
    private var day: Date? {
        guard !days.isEmpty else { return nil }
        return days[min(page, days.count - 1)]
    }
    private var shown: [WakeLogEntry] {
        guard let day else { return [] }
        return log.entries(on: day)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    open.toggle()
                }
            } label: {
                HStack {
                    Text("他自己说过的话")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer()
                    Text("\(log.entries.count) 条")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                if days.isEmpty {
                    Text("还没有记录。他自己醒来说的话会记在这儿。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else {
                    pager.padding(.top, 12)
                    list
                }
            }
        }
    }

    // MARK: 按日期翻页

    private var pager: some View {
        HStack(spacing: 12) {
            // ⚠️ **左边是"更早"。** days 是从新到旧排的，
            // 所以往更早翻是 page + 1，别照着数字大小想。
            arrow("chevron.left", on: page + 1 < days.count) { page += 1 }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(day.map { dayText($0) } ?? "")
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("\(shown.count) 条 · 共 \(days.count) 天有记录")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Spacer(minLength: 0)
            arrow("chevron.right", on: page > 0) { page -= 1 }
        }
    }

    private func arrow(_ icon: String, on: Bool,
                       _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(scheme == .dark
                                          ? Color.white.opacity(0.08)
                                          : Color.black.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? tint : Theme.textMuted(scheme).opacity(0.4))
        .disabled(!on)
    }

    // MARK: 那一天的记录

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { e in
                    row(e)
                    if e.id != shown.last?.id {
                        Divider().opacity(0.25)
                    }
                }
            }
        }
        // ⚠️ 高度是**写死的十条**，不是 `maxHeight` ——
        // 用 maxHeight 的话只有一两条时抽屉会缩成一条缝，
        // 每翻一天高度都在跳。
        .frame(height: viewport)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func row(_ e: WakeLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timeText(e.at))
                .font(.app(11).monospacedDigit())
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(width: 42, alignment: .leading)

            switch e.kind {
            case .spoke:
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.text)
                        .font(.app(13))
                        .foregroundStyle(Theme.textMain(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if e.from == "服务端" {
                        Text("来自电脑那边")
                            .font(.app(9.5))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
            case .silent:
                Text("醒了，没说话")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
            case .failed:
                // ⚠️ **这一档是这次加历史的起因。**
                // 她说：「昨天他醒了六次都没说话，我一问才发现上游 503 了，
                // 不是他不想说话。」——没这一行她就只能靠问才知道。
                VStack(alignment: .leading, spacing: 2) {
                    Text("没醒成 · 试了 \(e.tries) 次")
                        .font(.app(12, weight: .medium))
                        .foregroundStyle(Color.orange)
                    Text(e.text)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    // MARK: 零件

    private func dayText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year)
            ? "M月d日 EEEE" : "yyyy年M月d日"
        return f.string(from: d)
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
