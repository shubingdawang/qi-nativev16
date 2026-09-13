import SwiftUI

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

    private let cal = Calendar.current

    /// 日历上那个红字的颜色。**写死一个红**，她要的就是红字，不跟主题色走。
    static let payRed = Color(hexString: "E5484D") ?? .red

    var body: some View {
        ZStack {
            PaneScroll {
                overview
                calendar
                legend
            }

            if let s = summary {
                summaryOverlay(s)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: summary?.id)
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
            WageDayEditor(date: ref.date)
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
        return Button {
            if app.settings.haptics { UISelectionFeedbackGenerator().selectionChanged() }
            // 设过的那一天点进去**直接是总结**；空的那一天才进编辑
            if rec != nil {
                summary = WageDayRef(date: date)
            } else {
                editing = WageDayRef(date: date)
            }
        } label: {
            VStack(spacing: 2) {
                Text(String(cal.component(.day, from: date)))
                    .font(.app(13, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? app.settings.accentColor : Theme.textMain(scheme))

                if let k = rec?.shift {
                    Text(k.short)
                        .font(.app(9.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 15)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(k.tint))
                } else {
                    Color.clear.frame(height: 15)
                }

                // 红字：当天时长 × 时薪
                if let r = rec, r.shift != nil {
                    Text("+" + WageStore.money(r.pay))
                        .font(.app(9.5, weight: .semibold))
                        .foregroundStyle(Self.payRed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else if let r = rec, !r.entries.isEmpty {
                    // 没排班、只记了账：一个小点
                    Circle()
                        .fill(Theme.textMuted(scheme).opacity(0.6))
                        .frame(width: 4, height: 4)
                        .frame(height: 12)
                } else {
                    Color.clear.frame(height: 12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rec?.shift?.tint.opacity(0.10) ?? Color.clear)
            )
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(app.settings.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(ShiftKind.allCases) { k in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(k.tint)
                            .frame(width: 10, height: 10)
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
                                onClose: { summary = nil })
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

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private var title: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: date) + "总结"
    }

    /// 花费按顿分组，顺序固定：早餐、午餐、晚餐、其他
    private var spendGroups: [(MealKind, [LedgerEntry])] {
        let order: [MealKind] = [.breakfast, .lunch, .dinner, .none]
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
                        Text(WageStore.money(day.pay))
                            .font(.app(14, weight: .semibold))
                            .foregroundStyle(WageView.payRed)
                    }
                }

                if !incomes.isEmpty {
                    row("收入") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(incomes) { e in
                                value(e.what + "收入" + WageStore.money(e.amount) + "元")
                            }
                        }
                    }
                }

                ForEach(spendGroups, id: \.0) { group in
                    row(group.0 == .none ? "花费" : "花费（" + group.0.rawValue + "）") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(group.1) { e in
                                value(e.what + "花费" + WageStore.money(e.amount) + "元")
                            }
                        }
                    }
                }

                if day.shift == nil && day.entries.isEmpty {
                    value("这一天还没有记录")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(action: onClose) {
                    Text("关闭")
                        .font(.app(14))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.softFillDeep))
                }
                .buttonStyle(.plain)
                Button(action: onEdit) {
                    Text("编辑")
                        .font(.app(14, weight: .medium))
                        .foregroundStyle(app.settings.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(app.settings.accentColor.opacity(0.16)))
                }
                .buttonStyle(.plain)
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
}

// MARK: - 当天编辑

/// 排班 + 记账。改的是一份副本，点「完成」才写回去。
struct WageDayEditor: View {

    let date: Date

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

    init(date: Date) {
        self.date = date
        let s = WageStore.shared
        let t = s.settings.template(.middle)
        _day = State(initialValue: s.day(date)
            ?? WorkDay(shift: nil, work: t.work, breaks: t.breaks, hourly: s.settings.hourly))
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        shiftCard
                        if day.shift != nil { timeCard }
                        ledgerCard
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        commitDraftEntry()
                        store.put(day, on: date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { hourlyText = WageStore.money(day.hourly) }
        }
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
        hourlyText = WageStore.money(day.hourly)
        if app.settings.haptics { UISelectionFeedbackGenerator().selectionChanged() }
    }

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

    // MARK: 记账

    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("记账").heading(14)

            // 两个方格子：干了什么 + 多少钱
            HStack(spacing: 8) {
                TextField("干了什么，如：吃了一个汉堡", text: $what)
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

            HStack(spacing: 6) {
                ForEach(MealKind.allCases) { m in
                    Button { meal = m } label: {
                        Text(m.rawValue)
                            .font(.app(12))
                            .foregroundStyle(meal == m ? app.settings.accentColor : Theme.textSoft(scheme))
                            .padding(.horizontal, 10)
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

            Button {
                commitDraftEntry()
            } label: {
                Text("记一笔")
                    .font(.app(13.5, weight: .medium))
                    .foregroundStyle(canAdd ? app.settings.accentColor : Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(canAdd
                        ? app.settings.accentColor.opacity(0.16) : Theme.softFillDeep))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)

            if !day.entries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(day.entries) { e in
                        HStack(spacing: 8) {
                            if e.meal != .none {
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
                            Button {
                                day.entries.removeAll { $0.id == e.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
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
        day.entries.append(LedgerEntry(
            what: what.trimmingCharacters(in: .whitespaces),
            amount: amt, income: income, meal: meal))
        what = ""
        amountText = ""
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
