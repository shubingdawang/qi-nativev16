import SwiftUI
import PhotosUI

/// 工资页：一个月的排班日历，每格标当天挣多少；点进去排班、记账、看总结。
///
/// 数据和算法在 `WageStore`，这个文件只管画。
struct WageView: View {

    @ObservedObject private var store = WageStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var month = Date()
    /// 点开来编辑的那一天
    @State private var editing: WageDayRef?
    /// 点开来看总结的那一天（圆角弹窗）
    @State private var summary: WageDayRef?
    @State private var showSettings = false
    /// 总结里点开放大的那张图
    @State private var preview: String?
    /// 正在挪的那一天。有值的时候，日历进入「点一下目标日期」的状态
    @State private var moving: Date?
    /// 底下飘一下的那句提示
    @State private var notice: String?

    private let cal = Calendar.current

    /// 日历上那个红字的颜色。**写死一个红**，她要的就是红字，不跟主题色走。
    static let payRed = Color(hexString: "E5484D") ?? .red

    /// 日历格子上那个很小的角标：`3x`。整数不拖小数点。
    static func rateTag(_ m: Double) -> String {
        (abs(m - m.rounded()) < 0.05
            ? String(Int(m.rounded())) : String(format: "%.1f", m)) + "x"
    }

    var body: some View {
        ZStack {
            PaneScroll {
                overview
                if moving != nil { moveBanner }
                calendar
                legend
            }

            if let n = notice {
                VStack {
                    Spacer()
                    Text(n)
                        .font(.app(13))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.regularMaterial))
                        .padding(.bottom, Layout.tabBarExpanded + 20)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
                .zIndex(30)
            }

            if let s = summary {
                summaryOverlay(s)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }

            // 放大看一张图。**画在同一层 ZStack 里，不走 sheet / fullScreenCover**——
            // 这一页订阅着 AppState，挂 presentation 会被重建撤掉（PickHosts.swift 里记过）。
            if let name = preview {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    if let img = ImageStore.cached(name) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(20)
                    }
                }
                .onTapGesture { preview = nil }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeOut(duration: 0.18), value: summary?.id)
        .animation(.easeOut(duration: 0.18), value: preview)
        .animation(.easeOut(duration: 0.18), value: notice)
        .animation(.easeOut(duration: 0.18), value: moving)
        .navigationTitle("工资")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(app.settings.accentColor)
                }
            }
        }
        .sheet(item: $editing) { ref in
            WageDayEditor(date: ref.date, editEntry: ref.entry, onMove: { moving = ref.date })
        }
        .sheet(isPresented: $showSettings) {
            WageSettingsSheet()
        }
    }

    // MARK: 顶上那张：这个月

    private var overview: some View {
        let t = store.monthTotals(month)
        return VStack(alignment: .leading, spacing: 10) {
            Text(monthTitle + "收入")
                .font(.app(12))
                .foregroundStyle(Theme.textMuted(scheme))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Self.payRed)
                Text(WageStore.money(t.pay))
                    .font(HomeType.number(32, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                    .contentTransition(.numericText())
            }
            HStack(spacing: 0) {
                stat("上班", String(t.days) + " 天")
                divider
                stat("工时", String(format: "%.1f 小时", t.hours))
                divider
                stat("花费", "¥" + WageStore.money(t.spent))
                divider
                stat("结余", "¥" + WageStore.money(t.pay - t.spent))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.app(13, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.textMuted(scheme).opacity(0.25))
            .frame(width: 0.5, height: 24)
    }

    // MARK: 日历

    private var calendar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(app.settings.accentColor)
                        .frame(width: 44, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(monthTitle)
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                    .contentTransition(.numericText())
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(app.settings.accentColor)
                        .frame(width: 44, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { d in
                    Text(d)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                }
            }

            let days = monthDays
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7),
                      spacing: 5) {
                ForEach(days.indices, id: \.self) { i in
                    if let day = days[i] {
                        cell(day)
                    } else {
                        Color.clear.frame(height: 60)
                    }
                }
            }
        }
        .glassCard()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    shift(v.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private func cell(_ date: Date) -> some View {
        let rec = store.day(date)
        let isToday = cal.isDateInToday(date)
        let isSource = moving.map { cal.isDate($0, inSameDayAs: date) } ?? false
        return Button {
            if app.settings.haptics { UISelectionFeedbackGenerator().selectionChanged() }
            // 挪日期的状态下，点哪天就是挪到哪天
            if let from = moving {
                finishMove(from: from, to: date)
                return
            }
            // 设过的那一天点进去**直接是总结**；空的那一天才进编辑
            if rec != nil {
                summary = WageDayRef(date: date)
            } else {
                editing = WageDayRef(date: date)
            }
        } label: {
            VStack(spacing: 1) {
                // 日期。**班次是它右下角的一个小圆点**，不再单独占一行。
                //
                // 她要的：「中班可以用点的形式在日期的右下角，中间只显示 +- 金额。」
                // 点用 overlay 挂在数字上，不改数字本身的位置——
                // 有班没班的格子，日期都在同一条线上。
                Text(String(cal.component(.day, from: date)))
                    .font(.app(13, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? app.settings.accentColor : Theme.textMain(scheme))
                    .overlay(alignment: .bottomTrailing) {
                        if let k = rec?.shift {
                            Circle()
                                .fill(k.tint)
                                .frame(width: 6, height: 6)
                                .offset(x: 6, y: 1)
                        }
                    }
                    .frame(height: 20)

                // 中间只放金额：进来的红字 +，花出去的 -。
                // ⚠️ + 算的是**薪资加上记成收入的那几笔**，不只是薪资。
                let plus = (rec?.pay ?? 0) + (rec?.earnedExtra ?? 0)
                let minus = rec?.spent ?? 0
                amountLine(plus > 0 ? "+" + WageStore.money(plus) : nil, Self.payRed)
                amountLine(minus > 0 ? "-" + WageStore.money(minus) : nil,
                           Theme.textSoft(scheme))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rec?.shift?.tint.opacity(0.10) ?? Color.clear)
            )
            // 三倍那天：**整格的左上角**一个很小的「3x」。
            //
            // ⚠️ 别挂在日期那个数字旁边——她报的「这个 3x 的位置太奇怪了」就是那一版：
            // 数字是居中的，角标贴着它往左伸，看上去像跟日期连成了一个词。
            // 挂在格子角上就跟右下角那颗班次的点对称了，各占一角。
            .overlay(alignment: .topLeading) {
                if rec?.hasBonusRate == true {
                    Text(WageView.rateTag(rec?.multiplier ?? 1))
                        .font(.app(8, weight: .semibold))
                        .foregroundStyle(WageView.payRed)
                        // 往里挪一点，别贴着格子的圆角（她说「再往右移动一点」）
                        .padding(.leading, 7)
                        .padding(.top, 3)
                }
            }
            .overlay {
                if isSource {
                    // 正在挪的那一天：虚线框出来，她知道自己在挪哪一格
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(app.settings.accentColor,
                                      style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(app.settings.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 挪日期

    private var moveBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(app.settings.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("挪到哪一天？")
                    .font(.app(13.5, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("点击目标日期，可左右滑动切换月份")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Spacer(minLength: 0)
            Button { moving = nil } label: {
                Text("取消")
                    .font(.app(13))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private func finishMove(from: Date, to: Date) {
        if cal.isDate(from, inSameDayAs: to) {
            moving = nil
            return
        }
        guard store.day(to) == nil else {
            flash("那一天已经有记录了，先删掉或者换一天")
            return
        }
        store.moveDay(from: from, to: to)
        moving = nil
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        flash("挪到 " + f.string(from: to) + " 了")
        if app.settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func flash(_ text: String) {
        notice = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if notice == text { notice = nil }
        }
    }

    /// 格子里一行金额。没有就留一行空，格子高度不跳。
    @ViewBuilder
    private func amountLine(_ text: String?, _ color: Color) -> some View {
        if let t = text {
            Text(t)
                .font(.app(9.5, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 13)
        } else {
            Color.clear.frame(height: 13)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(ShiftKind.allCases) { k in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(k.tint)
                            .frame(width: 8, height: 8)
                        Text(k.rawValue)
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
            }
            Text("点击空白日期排班或记账；已设置的日期点击后显示当日总结。右上角设置时薪与各班次时间。")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: 总结弹窗

    private func summaryOverlay(_ ref: WageDayRef) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { summary = nil }

            if let day = store.day(ref.date) {
                WageSummaryCard(date: ref.date, day: day,
                                onEdit: {
                                    summary = nil
                                    editing = ref
                                },
                                onClose: { summary = nil },
                                onOpenImage: { preview = $0 },
                                onEditEntry: { id in
                                    summary = nil
                                    editing = WageDayRef(date: ref.date, entry: id)
                                },
                                onDelete: {
                                    store.deleteDay(on: ref.date)
                                    summary = nil
                                },
                                onMove: {
                                    summary = nil
                                    moving = ref.date
                                })
                    .padding(.horizontal, 28)
            }
        }
    }

    // MARK: 零件

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f.string(from: month)
    }

    private func shift(_ n: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            month = cal.date(byAdding: .month, value: n, to: month) ?? month
        }
        if app.settings.haptics { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// 这个月的格子：前面补空位对齐星期几，后面是每一天
    private var monthDays: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }
        let lead = cal.component(.weekday, from: first) - 1
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in range {
            out.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        return out
    }
}

/// sheet(item:) 要一个 Identifiable 的东西，日期本身不是。
struct WageDayRef: Identifiable, Equatable {
    let date: Date
    /// 打开编辑页时直接进入改这一笔（总结卡里点了某一笔）
    var entry: UUID? = nil
    var id: String { WageStore.key(date) }
}

// MARK: - 总结卡片

/// 「x月x日总结」那个圆角弹窗。
///
/// 照她给的样子排：左边是「·班次：」这种标签，右边是内容；
/// 同一顿饭有好几笔的，右边一行一笔竖着排。
struct WageSummaryCard: View {

    let date: Date
    let day: WorkDay
    var onEdit: () -> Void
    var onClose: () -> Void
    var onOpenImage: (String) -> Void = { _ in }
    /// 点某一笔：进编辑页直接改它
    var onEditEntry: (UUID) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onMove: () -> Void = {}

    /// 点了「删除」之后，按钮那一行换成「确认删除 / 取消」。
    ///
    /// ⚠️ **不用 `confirmationDialog`**：这张卡画在订阅着 AppState 的页面里，
    /// 挂系统弹窗会被页面重建撤掉（PickHosts.swift 里记过四回）。
    /// 就地换一行按钮，没有这个问题，而且手指不用挪地方。
    @State private var confirming = false

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private var title: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: date) + "总结"
    }

    /// 花费按顿分组，顺序固定：早餐、午餐、晚餐、其他
    private var spendGroups: [(MealKind, [LedgerEntry])] {
        let order: [MealKind] = [.breakfast, .lunch, .dinner, .lateSnack, .none]
        return order.compactMap { m in
            let items = day.entries.filter { !$0.income && $0.meal == m }
            return items.isEmpty ? nil : (m, items)
        }
    }

    private var incomes: [LedgerEntry] { day.entries.filter { $0.income } }

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 9) {
                if let k = day.shift {
                    row("班次") {
                        HStack(spacing: 6) {
                            Circle().fill(k.tint).frame(width: 7, height: 7)
                            value(k.rawValue)
                            // 她要的那颗小胶囊：「小卡片显示一个小胶囊上面写 3x 工资」
                            if day.hasBonusRate { WageRatePill(text: day.rateLabel) }
                        }
                    }
                    row("时长") { value(day.work.text) }
                    row("休息") {
                        if day.breaks.isEmpty {
                            value("无")
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(day.breaks) { b in value(b.text) }
                            }
                        }
                    }
                    row("总薪资") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(WageStore.money(day.pay))
                                .font(.app(14, weight: .semibold))
                                .foregroundStyle(WageView.payRed)
                            // 三倍那天把「平常是多少」也写出来，好对账
                            if day.hasBonusRate {
                                Text("平常 " + WageStore.money(day.basePay)
                                     + " × " + day.rateLabel.replacingOccurrences(
                                        of: " 工资", with: ""))
                                    .font(.app(10.5))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                        }
                    }
                }

                if !incomes.isEmpty {
                    row("收入") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(incomes) { e in
                                item(e, e.what + "收入" + WageStore.money(e.amount) + "元")
                            }
                        }
                    }
                }

                ForEach(spendGroups, id: \.0) { group in
                    row("花费（" + group.0.rawValue + "）") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(group.1) { e in
                                item(e, e.what + "花费" + WageStore.money(e.amount) + "元")
                            }
                        }
                    }
                }

                if day.shift == nil && day.entries.isEmpty {
                    value("这一天还没有记录")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if confirming {
                VStack(spacing: 8) {
                    Text("删除这一天的班次和全部记账（含图片）？")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                    HStack(spacing: 10) {
                        pill("取消", Theme.textSoft(scheme), Theme.softFillDeep) {
                            confirming = false
                        }
                        pill("确认删除", Color.white, WageView.payRed, bold: true, action: onDelete)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    pill("删除", WageView.payRed, WageView.payRed.opacity(0.12)) {
                        confirming = true
                    }
                    pill("挪日期", Theme.textSoft(scheme), Theme.softFillDeep, action: onMove)
                    pill("关闭", Theme.textSoft(scheme), Theme.softFillDeep, action: onClose)
                    pill("编辑", app.settings.accentColor,
                         app.settings.accentColor.opacity(0.16), bold: true, action: onEdit)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 340)
        // ⚠️ 弹窗要读得清，底不能太透：用系统材质，**不套 `.shadow`**——
        // 阴影会让 Material 离屏渲染，玻璃就退化成一块近似纯色（Theme.swift 里记过）。
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.10 : 0.45), lineWidth: 0.8)
        )
    }

    private func row<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("·" + label + "：")
                .font(.app(14))
                .foregroundStyle(Theme.textSoft(scheme))
                .fixedSize()
            content()
            Spacer(minLength: 0)
        }
    }

    private func value(_ s: String) -> some View {
        Text(s)
            .font(.app(14))
            .foregroundStyle(Theme.textMain(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, _ fg: Color, _ bg: Color, bold: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(14, weight: bold ? .medium : .regular))
                .foregroundStyle(fg)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(bg))
        }
        .buttonStyle(.plain)
    }

    /// 一笔：那一行字，**下面一行**是它的缩略图（她要的排法）。
    private func item(_ e: LedgerEntry, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                value(line)
                Image(systemName: "pencil")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .contentShape(Rectangle())
            .onTapGesture { onEditEntry(e.id) }
            if !e.images.isEmpty {
                // ⚠️ 34 点：五张加四道缝正好 190，卡片右边那一栏放得下，不折行
                HStack(spacing: 5) {
                    ForEach(e.images, id: \.self) { name in
                        WageThumb(name: name, size: 34)
                            .onTapGesture { onOpenImage(name) }
                    }
                }
            }
        }
    }
}

/// 「3x 工资」那颗小胶囊。她定的：「小卡片显示一个小胶囊上面写 3x 工资。」
///
/// 用薪资那个红（`WageView.payRed`），跟卡片上的金额是同一个颜色——
/// 它说的本来就是同一件事：这一天的钱不一样。
struct WageRatePill: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.app(9.5, weight: .semibold))
            .foregroundStyle(WageView.payRed)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(WageView.payRed.opacity(0.14))
            )
            .overlay(Capsule().strokeBorder(WageView.payRed.opacity(0.35), lineWidth: 0.5))
    }
}

/// 圆角正方形的缩略图。
///
/// ⚠️ 走 `ImageStore.cached`，别用 `load`：总结和编辑页每次重画都会跑 body，
/// `load` 每次都从磁盘读、重新解码一遍 JPEG。
struct WageThumb: View {
    let name: String
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let img = ImageStore.cached(name) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - 当天编辑

/// 排班 + 记账。改的是一份副本，点「完成」才写回去。
struct WageDayEditor: View {

    let date: Date
    /// 点「挪到另一天」：先把这一次的改动存下，关掉编辑页，回日历上点目标日期
    var onMove: () -> Void = {}

    @ObservedObject private var store = WageStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var day: WorkDay
    @State private var hourlyText = ""

    // 记账那两个方格子
    @State private var what = ""
    @State private var amountText = ""
    @State private var meal: MealKind = .none
    @State private var income = false
    /// 两个方格子那一笔还没记进去时，先挑好的图
    @State private var draftImages: [String] = []
    /// 正在改的那一笔。nil = 上面的格子是在记新的一笔
    @State private var editingEntry: UUID?

    // 挑图
    @State private var picking = false
    @State private var pickedItems: [PhotosPickerItem] = []
    /// 这一次挑的图挂到哪：`nil` = 还没记的那一笔；否则是那一笔的 id
    @State private var pickTarget: UUID?
    @State private var pickLimit = LedgerEntry.maxImages

    /// ⚠️ 这一次打开期间**新存下的图**。点「取消」或者下滑关掉，这些要删——
    /// 不删的话挑了图又反悔，`Images/` 里就攒下没人认领的文件。
    @State private var addedNow: Set<String> = []
    /// 打开时这一天本来就挂着的图。点「完成」时被删掉了的，才真的去删文件。
    private let original: Set<String>
    @State private var committed = false
    /// 打开时这一天是不是本来就有记录。空的那一天没什么可删，不摆删除。
    private let existed: Bool
    @State private var confirmingDelete = false

    /// 打开时直接改的那一笔
    private let editEntry: UUID?
    @FocusState private var whatFocused: Bool

    init(date: Date, editEntry: UUID? = nil, onMove: @escaping () -> Void = {}) {
        self.date = date
        self.editEntry = editEntry
        self.onMove = onMove
        let s = WageStore.shared
        let t = s.settings.template(.middle)
        let d = s.day(date)
            ?? WorkDay(shift: nil, work: t.work, breaks: t.breaks, hourly: s.settings.hourly)
        _day = State(initialValue: d)
        original = Set(d.entries.flatMap(\.images))
        existed = s.day(date) != nil
    }

    private var title: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            shiftCard
                            if day.shift != nil { rateCard }
                            if day.shift != nil { timeCard }
                            ledgerCard
                            if existed { deleteBar }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    // 开始改某一笔：滚到上面那两个格子、光标放进去——
                    // 以前点了那一行，格子在屏幕外面悄悄变了，看着就是「点了没反应」
                    .onChange(of: editingEntry) { _, id in
                        guard id != nil else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("ledgerInput", anchor: .top)
                        }
                        whatFocused = true
                    }
                    .onAppear {
                        if let id = editEntry, let e = day.entries.first(where: { $0.id == id }) {
                            beginEdit(e)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { hourlyText = WageStore.money(day.hourly) }
            // 没点「完成」就走了（取消、下滑）：这一次新存的图全删，原来的一张不动
            .onDisappear {
                if !committed { for n in addedNow { ImageStore.delete(n) } }
            }
            .background(PhotoPickHost(open: $picking, picked: $pickedItems,
                                      maxCount: pickLimit))
            .onChange(of: pickedItems) { _, items in
                guard !items.isEmpty else { return }
                let target = pickTarget
                Task { @MainActor in
                    for it in items {
                        guard let data = try? await it.loadTransferable(type: Data.self),
                              let raw = UIImage(data: data),
                              let name = ImageStore.save(ImageStore.downscale(raw, maxSide: 1600))
                        else { continue }
                        addedNow.insert(name)
                        attach(name, to: target)
                    }
                    pickedItems = []
                }
            }
        }
    }

    /// 写回去，并把这一次里被拿掉的图（新挑的、原来就有的都算）删文件。
    private func save() {
        commitDraftEntry()
        store.put(day, on: date)
        committed = true
        let kept = Set(day.entries.flatMap(\.images))
        for n in addedNow.union(original).subtracting(kept) {
            ImageStore.delete(n)
        }
    }

    /// 挂一张图上去。**超过 5 张的直接删掉那个文件**，不留孤儿。
    private func attach(_ name: String, to target: UUID?) {
        if let id = target, let i = day.entries.firstIndex(where: { $0.id == id }) {
            guard day.entries[i].images.count < LedgerEntry.maxImages else {
                ImageStore.delete(name); addedNow.remove(name); return
            }
            day.entries[i].images.append(name)
        } else {
            guard draftImages.count < LedgerEntry.maxImages else {
                ImageStore.delete(name); addedNow.remove(name); return
            }
            draftImages.append(name)
        }
    }

    private func openPicker(for target: UUID?, has: Int) {
        pickTarget = target
        pickLimit = max(1, LedgerEntry.maxImages - has)
        picking = true
    }

    /// 一排缩略图 + 末尾一个加号。每张右上角一个叉。
    private func thumbRow(_ names: [String], size: CGFloat,
                          onAdd: @escaping () -> Void,
                          onRemove: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(names, id: \.self) { n in
                WageThumb(name: n, size: size)
                    .overlay(alignment: .topTrailing) {
                        Button { onRemove(n) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.app(14))
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                    }
            }
            if names.count < LedgerEntry.maxImages {
                Button(action: onAdd) {
                    VStack(spacing: 1) {
                        Image(systemName: "photo.badge.plus")
                            .font(.app(size > 40 ? 15 : 12))
                        Text(String(names.count) + "/5")
                            .font(.app(9))
                    }
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(Theme.textMuted(scheme).opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: 班次

    private var shiftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("班次").heading(14)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                      spacing: 8) {
                ForEach(ShiftKind.allCases) { k in
                    shiftChip(k.rawValue, tint: k.tint, on: day.shift == k) { pick(k) }
                }
                shiftChip("不排班", tint: Theme.textMuted(scheme), on: day.shift == nil) {
                    day.shift = nil
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func shiftChip(_ label: String, tint: Color, on: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.app(12.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : Theme.textMain(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? tint : Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    /// 选一个班：**套用那个班在设置里的默认时间和当前时薪**。
    /// 已经是这个班了就不重套，免得把她在这一天里手改过的时间冲掉。
    private func pick(_ k: ShiftKind) {
        guard day.shift != k else { return }
        let t = store.settings.template(k)
        day.shift = k
        day.work = t.work
        day.breaks = t.breaks
        day.hourly = store.settings.hourly
        // 法定节假日那天**预先把三倍打开**（她关掉就是关掉了，不会再自动开回来：
        // 这一下只发生在「换班次」那一刻，见 `WorkDay.multiplier`）
        if holidayName != nil { day.multiplier = 3 }
        hourlyText = WageStore.money(day.hourly)
        if app.settings.haptics { UISelectionFeedbackGenerator().selectionChanged() }
    }

    // MARK: 三倍工资

    /// 这一天算几倍。
    ///
    /// 她定的：「给我一个三倍工资的按钮我自己打开。」——**开关归她**，
    /// 我们只在法定节假日那天把它预先打开（见 `pick`），她随时能关。
    /// 不自动算，是因为调休年年不同，猜错了就是替她把工资算错。
    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("三倍工资").heading(14)
                if day.hasBonusRate { WageRatePill(text: day.rateLabel) }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { day.multiplier > 1.001 },
                    set: { on in
                        day.multiplier = on ? 3 : 1
                        if app.settings.haptics {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }))
                    .labelsHidden()
                    .tint(app.settings.accentColor)
            }
            Text(holidayName.map { $0 + "，按三倍计算。" }
                 ?? "开启后这一天的薪资按时薪的三倍计算。")
                .font(.app(11.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// 这一天是不是法定节假日（是就把名字写在说明里）
    private var holidayName: String? { Festivals.statutory(date) }

    // MARK: 时间

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("时间").heading(14)
                Spacer()
                Text("时长 " + String(format: "%.1f", Double(day.workedMinutes) / 60) + " 小时")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                Text("+" + WageStore.money(day.pay))
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(WageView.payRed)
            }

            HStack(spacing: 8) {
                Text("上班").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                MinutePicker(minutes: $day.work.start)
                Text("至").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                MinutePicker(minutes: $day.work.end)
                Spacer(minLength: 0)
            }

            ForEach($day.breaks) { $b in
                HStack(spacing: 8) {
                    Text("休息").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                    MinutePicker(minutes: $b.start)
                    Text("至").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                    MinutePicker(minutes: $b.end)
                    Spacer(minLength: 0)
                    Button {
                        day.breaks.removeAll { $0.id == b.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                let last = day.breaks.last?.end ?? day.work.start + 4 * 60
                day.breaks.append(TimeSpan(start: last, end: last + 30))
            } label: {
                Label("添加休息时段", systemImage: "plus")
                    .font(.app(12.5))
                    .foregroundStyle(app.settings.accentColor)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Text("时薪").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                TextField("20", text: $hourlyText)
                    .keyboardType(.decimalPad)
                    .font(.app(14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: 90)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.softFillDeep))
                    .onChange(of: hourlyText) { _, v in
                        if let n = Double(v) { day.hourly = n }
                    }
                Text("元/小时").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                Spacer(minLength: 0)
            }
            Text("此处修改只作用于当天。")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 删除这一天

    /// ⚠️ 同总结卡片那边：**就地换一行确认，不挂 `confirmationDialog`**。
    private var deleteBar: some View {
        VStack(spacing: 8) {
            if confirmingDelete {
                Text("删除这一天的班次和全部记账（含图片）？")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                HStack(spacing: 10) {
                    Button { confirmingDelete = false } label: {
                        Text("取消")
                            .font(.app(14))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                    Button {
                        // 这一次新挑的图也不留（删整天之后没人认领它们）
                        for n in addedNow { ImageStore.delete(n) }
                        store.deleteDay(on: date)
                        committed = true
                        dismiss()
                    } label: {
                        Text("确认删除")
                            .font(.app(14, weight: .medium))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(WageView.payRed))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        // ⚠️ 先存再走：她在这一页改了一半，挪日期不该把改动丢掉
                        save()
                        dismiss()
                        onMove()
                    } label: {
                        Label("挪到另一天", systemImage: "arrow.right.circle")
                            .font(.app(13.5))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                    Button { confirmingDelete = true } label: {
                        Label("删除", systemImage: "trash")
                            .font(.app(13.5))
                            .foregroundStyle(WageView.payRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(WageView.payRed.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: 记账

    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingEntry == nil ? "记账" : "正在修改这一笔").heading(14)
                Spacer()
            }
            .id("ledgerInput")

            // 两个方格子：干了什么 + 多少钱
            HStack(spacing: 8) {
                TextField("干了什么，如：吃了一个汉堡", text: $what)
                    .focused($whatFocused)
                    .font(.app(13.5))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.softFillDeep))
                TextField("金额", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.app(13.5))
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .frame(width: 92)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.softFillDeep))
            }

            thumbRow(draftImages, size: 48,
                     onAdd: { openPicker(for: nil, has: draftImages.count) },
                     onRemove: { n in
                         draftImages.removeAll { $0 == n }
                         // 还挂在某一笔上的不删文件（改到一半取消，那一笔还要用它）
                         if addedNow.contains(n),
                            !day.entries.contains(where: { $0.images.contains(n) }) {
                             ImageStore.delete(n)
                             addedNow.remove(n)
                         }
                     })

            HStack(spacing: 6) {
                ForEach(MealKind.allCases) { m in
                    Button { meal = m } label: {
                        Text(m.rawValue)
                            .font(.app(12))
                            .foregroundStyle(meal == m ? app.settings.accentColor : Theme.textSoft(scheme))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(meal == m
                                ? app.settings.accentColor.opacity(0.16) : Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Picker("", selection: $income) {
                    Text("支出").tag(false)
                    Text("收入").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }

            HStack(spacing: 8) {
                if editingEntry != nil {
                    Button { clearDraft() } label: {
                        Text("取消修改")
                            .font(.app(13.5))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    commitDraftEntry()
                } label: {
                    Text(editingEntry == nil ? "记一笔" : "保存修改")
                        .font(.app(13.5, weight: .medium))
                        .foregroundStyle(canAdd ? app.settings.accentColor : Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(canAdd
                            ? app.settings.accentColor.opacity(0.16) : Theme.softFillDeep))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }

            if !day.entries.isEmpty {
                Text("点某一笔或铅笔可修改")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            if !day.entries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(day.entries) { e in
                        HStack(spacing: 8) {
                            if !e.income {
                                Text(e.meal.rawValue)
                                    .font(.app(10.5))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.softFillDeep))
                            }
                            Text(e.what)
                                .font(.app(13.5))
                                .foregroundStyle(Theme.textMain(scheme))
                                .lineLimit(2)
                            Spacer(minLength: 6)
                            Text((e.income ? "+" : "-") + WageStore.money(e.amount))
                                .font(.app(13.5, weight: .medium))
                                .foregroundStyle(e.income ? WageView.payRed : Theme.textSoft(scheme))
                            Button { beginEdit(e) } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(app.settings.accentColor.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            Button {
                                if editingEntry == e.id { clearDraft() }
                                day.entries.removeAll { $0.id == e.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .padding(.horizontal, editingEntry == e.id ? 6 : 0)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(editingEntry == e.id
                                  ? app.settings.accentColor.opacity(0.12) : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture { beginEdit(e) }
                        // 那一行字的**下面一行**：这一笔的图。
                        // 正在改的这一笔，图在上面的格子里改，这儿不摆（两处改会互相覆盖）
                        if editingEntry != e.id {
                            thumbRow(e.images, size: 40,
                                     onAdd: { openPicker(for: e.id, has: e.images.count) },
                                     onRemove: { n in
                                         if let i = day.entries.firstIndex(where: { $0.id == e.id }) {
                                             day.entries[i].images.removeAll { $0 == n }
                                         }
                                     })
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 8)
                        }
                        if e.id != day.entries.last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var canAdd: Bool {
        !what.trimmingCharacters(in: .whitespaces).isEmpty && Double(amountText) != nil
    }

    /// 把两个方格子里的那一笔记进去。
    ///
    /// ⚠️ 「完成」的时候也调一次：填好了两个格子没点「记一笔」就直接点完成，
    /// 那一笔不该悄悄丢掉。
    private func commitDraftEntry() {
        guard canAdd, let amt = Double(amountText) else { return }
        let text = what.trimmingCharacters(in: .whitespaces)
        if let id = editingEntry, let i = day.entries.firstIndex(where: { $0.id == id }) {
            // 原地改，id 不变，顺序不变
            day.entries[i].what = text
            day.entries[i].amount = amt
            day.entries[i].income = income
            day.entries[i].meal = meal
            day.entries[i].images = draftImages
        } else {
            day.entries.append(LedgerEntry(
                what: text, amount: amt, income: income, meal: meal, images: draftImages))
        }
        clearDraft()
    }

    /// 把某一笔搬进上面的格子里改
    private func beginEdit(_ e: LedgerEntry) {
        editingEntry = e.id
        what = e.what
        amountText = WageStore.money(e.amount)
        income = e.income
        meal = e.meal
        draftImages = e.images
    }

    /// 清空格子。改到一半取消的话，这一笔原样不动；
    /// 改的过程中新挑的图在 addedNow 里，保存时没挂上的会被清掉
    private func clearDraft() {
        editingEntry = nil
        what = ""
        amountText = ""
        meal = .none
        income = false
        draftImages = []
    }
}

// MARK: - 设置

/// 时薪 + 四个班的默认时间。**改这里只影响之后排的班。**
struct WageSettingsSheet: View {

    @ObservedObject private var store = WageStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var draft = WageStore.shared.settings
    @State private var hourlyText = WageStore.money(WageStore.shared.settings.hourly)

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsCard(title: "时薪") {
                            HStack(spacing: 8) {
                                TextField("20", text: $hourlyText)
                                    .keyboardType(.decimalPad)
                                    .font(.app(16, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(width: 110)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Theme.softFillDeep))
                                    .onChange(of: hourlyText) { _, v in
                                        if let n = Double(v) { draft.hourly = n }
                                    }
                                Text("元/小时")
                                    .font(.app(13))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        ForEach(ShiftKind.allCases) { k in
                            templateCard(k)
                        }

                        SettingsNote("修改后对之后排的班生效；已排好的日期保留排班时的时间与时薪，可在当天单独修改。")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("工资设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        store.updateSettings(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func templateCard(_ k: ShiftKind) -> some View {
        let binding = Binding<ShiftTemplate>(
            get: { draft.template(k) },
            set: { draft.templates[k.rawValue] = $0 })
        return SettingsCard(title: k.rawValue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(k.tint).frame(width: 8, height: 8)
                    Text("上班").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                    MinutePicker(minutes: binding.work.start)
                    Text("至").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                    MinutePicker(minutes: binding.work.end)
                    Spacer(minLength: 0)
                }
                ForEach(binding.breaks) { $b in
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 8, height: 8)
                        Text("休息").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                        MinutePicker(minutes: $b.start)
                        Text("至").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                        MinutePicker(minutes: $b.end)
                        Spacer(minLength: 0)
                        Button {
                            binding.wrappedValue.breaks.removeAll { $0.id == b.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    let t = binding.wrappedValue
                    let last = t.breaks.last?.end ?? t.work.start + 4 * 60
                    binding.wrappedValue.breaks.append(TimeSpan(start: last, end: last + 30))
                } label: {
                    Label("添加休息时段", systemImage: "plus")
                        .font(.app(12.5))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - 选钟点

/// 按「当天零点起第几分钟」存的钟点，用系统的时间选择器改。
struct MinutePicker: View {
    @Binding var minutes: Int

    private static let base: Date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))

    var body: some View {
        DatePicker("", selection: Binding(
            get: {
                let v = ((minutes % 1440) + 1440) % 1440
                return Self.base.addingTimeInterval(TimeInterval(v * 60))
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }),
            displayedComponents: .hourAndMinute)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "zh_CN"))
    }
}
