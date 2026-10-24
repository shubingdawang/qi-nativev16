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
    @State private var importing = false
    /// 班表抽屉开着没
    @State private var showDrawer = false
    /// 正在换照片的那张班表
    @State private var replacing: WageRoster?
    @State private var replacePick = false
    @State private var replaceItem: PhotosPickerItem?

    private let cal = Calendar.current

    /// 日历上那个红字的颜色。**写死一个红**，她要的就是红字，不跟主题色走。
    static let payRed = Color(hexString: "E5484D") ?? .red
    /// 请假那天的颜色：低饱和的灰蓝
    static let leaveTint = Color(hexString: "8A97AD") ?? .gray

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
                rosterCard
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

            if showDrawer {
                rosterDrawer
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(12)
            }

            // 放大看一张图。**画在同一层 ZStack 里，不走 sheet / fullScreenCover**——
            // 这一页订阅着 AppState，挂 presentation 会被重建撤掉（PickHosts.swift 里记过）。
            if let name = preview {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    if let img = ImageStore.cached(name) {
                        WageZoomImage(image: img)
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
        .animation(.easeOut(duration: 0.18), value: showDrawer)
        .background(SinglePhotoPickHost(open: $replacePick, picked: $replaceItem))
        .onChange(of: replaceItem) { _, it in
            guard let it, let old = replacing else { return }
            Task { @MainActor in
                if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data),
                   let name = ImageStore.save(img, quality: 0.92) {
                    store.replaceRoster(old.id, with: name)
                    flash("原班表已收入抽屉")
                }
                replaceItem = nil
                replacing = nil
            }
        }
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
        .sheet(isPresented: $importing) {
            WageRosterImport(start: rosterStartGuess)
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
                // 金额一位一位滚到新的值
                RollingNumber(text: WageStore.money(t.pay), font: HomeType.number(32, weight: .semibold),
                              color: Theme.textMain(scheme))
                // 实发：下个月发薪日记下的到手钱加起来
                let real = store.actualPay(forWorkMonth: month)
                Text("实发")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.leading, 8)
                if real.recorded > 0 {
                    Text("¥" + WageStore.money(real.sum))
                        .font(HomeType.number(16, weight: .bold))
                        .foregroundStyle(Theme.textMain(scheme))
                    if real.recorded < real.paydays {
                        Text("已发 \(real.recorded)/\(real.paydays) 次")
                            .font(.app(10.5))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                } else {
                    Text("未发放")
                        .font(.app(12, weight: .bold))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
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
            breakdown
            reminders
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// 这个月的钱怎么来的：底薪、全勤、加班、绩效、请假。只有时薪工资的话不占地方
    @ViewBuilder
    private var breakdown: some View {
        let b = store.monthBreakdown(month)
        let parts: [(String, String)] = {
            var out: [(String, String)] = []
            if b.fullTime {
                out.append(("底薪", "¥" + WageStore.money(b.base)))
                if store.settings.attendanceBonus > 0 {
                    out.append(("全勤", b.leaveDays == 0 ? "¥" + WageStore.money(b.attendance) : "无"))
                }
                if b.shiftPay > 0 { out.append(("节假日", "¥" + WageStore.money(b.shiftPay))) }
            }
            if b.overtimeHours > 0 {
                out.append(("加班 " + String(format: "%.1f", b.overtimeHours) + "h", "¥" + WageStore.money(b.overtimePay)))
            }
            if b.performance > 0 { out.append(("绩效", "¥" + WageStore.money(b.performance))) }
            if b.leaveDays > 0 {
                out.append(("请假 \(b.leaveDays) 天", b.fullTime ? "-¥" + WageStore.money(b.leaveDeduct) : "不计"))
            }
            return out
        }()
        if !parts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(parts, id: \.0) { p in
                        HStack(spacing: 4) {
                            Text(p.0).foregroundStyle(Theme.textMuted(scheme))
                            Text(p.1).foregroundStyle(Theme.textMain(scheme)).fontWeight(.semibold)
                        }
                        .font(.app(11))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.softFillDeep))
                    }
                }
            }
        }
    }

    /// 下次发薪、最近的纪念日。都没设就不占地方
    @ViewBuilder
    private var reminders: some View {
        let pay = store.nextPayday()
        let ann = store.nextAnniversary()
        if pay != nil || ann != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let p = pay {
                    let amount = store.expectedPay(on: p).map { " · 应发 ¥" + WageStore.money($0.amount) } ?? ""
                    reminderRow("yensign.circle", Self.payRed, "下次发薪 " + Self.md(p) + amount, Self.until(p))
                }
                if let n = ann {
                    reminderRow("heart", Color(hexString: "E8758F")!,
                                n.0.name + (n.2 > 0 && n.0.yearly ? " · \(n.2) 周年" : "") + " · " + Self.md(n.1), Self.until(n.1))
                }
            }
            .padding(.top, 2)
        }
    }

    private func reminderRow(_ icon: String, _ tint: Color, _ text: String, _ tail: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(tint)
            Text(text)
                .font(.app(12))
                .foregroundStyle(Theme.textSoft(scheme))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(tail)
                .font(.app(11.5, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private static let mdFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M月d日"; return f }()
    static func md(_ d: Date) -> String { mdFormat.string(from: d) }

    /// 「今天」「明天」「还有 N 天」
    static func until(_ d: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        return n == 0 ? "今天" : (n == 1 ? "明天" : "还有 \(n) 天")
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
            // 设过的那一天点进去**直接是总结**；空的那一天有班表就先看班表，没有才进编辑
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
                let plus = (rec.map { store.dayPay($0, on: date) } ?? 0) + (rec?.earnedExtra ?? 0)
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
            .overlay(alignment: .topTrailing) {
                let pay = store.isPayday(date), ann = !store.anniversaries(on: date).isEmpty
                if pay || ann {
                    HStack(spacing: 1) {
                        if pay { Image(systemName: "yensign").foregroundStyle(Self.payRed) }
                        if ann { Image(systemName: "heart.fill").foregroundStyle(Color(hexString: "E8758F")!) }
                    }
                    .font(.system(size: 6, weight: .bold))
                    .padding(.trailing, 3)
                    .padding(.top, 2)
                }
            }
            .overlay(alignment: .bottom) {
                if store.roster(on: date) != nil {
                    Capsule()
                        .fill(app.settings.accentColor.opacity(0.45))
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if rec?.leave == true {
                    Text("假")
                        .font(.app(8, weight: .semibold))
                        .foregroundStyle(WageView.leaveTint)
                        .padding(.leading, 7)
                        .padding(.top, 3)
                } else if rec?.hasBonusRate == true {
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

    // MARK: 班表

    /// 导入时默认从哪天开始：这个月里最后一张班表的后一天；没有就今天
    private var rosterStartGuess: Date {
        let cal = Calendar(identifier: .gregorian)
        if let last = store.file.rosters.max(by: { $0.start < $1.start }),
           let s = WageStore.date(last.start),
           let e = cal.date(byAdding: .day, value: last.days, to: s), e > Date().addingTimeInterval(-86400 * 3) {
            return e
        }
        return cal.startOfDay(for: Date())
    }

    private var rosterCard: some View {
        let list = store.rosters(in: month)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("班表")
                    .font(.app(13.5, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Button { showDrawer = true } label: {
                    Label("抽屉" + (store.stashedRosters.isEmpty ? "" : " \(store.stashedRosters.count)"),
                          systemImage: "tray")
                        .font(.app(12.5))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                Button { importing = true } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                        .font(.app(12.5))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }
            if list.isEmpty {
                Text("选好开始日期和天数，导入一张班表图，日历上那几天会标出来，点一下就能看。")
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                ForEach(list) { r in
                    HStack(spacing: 10) {
                        Button { preview = r.image } label: {
                            HStack(spacing: 10) {
                                WageThumb(name: r.image, size: 46)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rosterRange(r))
                                        .font(.app(13))
                                        .foregroundStyle(Theme.textMain(scheme))
                                    Text("\(r.days) 天")
                                        .font(.app(11))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // 班表临时换了：这张收进抽屉，挑一张新照片顶上
                        Button {
                            replacing = r
                            replacePick = true
                        } label: {
                            Label("收进抽屉", systemImage: "tray.and.arrow.down")
                                .font(.app(11.5))
                                .foregroundStyle(app.settings.accentColor)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        Button {
                            replacing = r
                            replacePick = true
                        } label: {
                            Label("收入抽屉并替换", systemImage: "tray.and.arrow.down")
                        }
                        Button(role: .destructive) { store.removeRoster(r.id) } label: {
                            Label("删除这张班表", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .glassCard()
    }

    /// 抽屉：换下来的班表。放出来就顶替外面管着同样那几天的那张（那张收进来）
    private var rosterDrawer: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { showDrawer = false }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "tray").foregroundStyle(app.settings.accentColor)
                    Text("班表抽屉").font(.app(15, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                    Spacer()
                    Button { showDrawer = false } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
                let list = store.stashedRosters
                if list.isEmpty {
                    Text("还没有换下来的班表。班表临时换了，点那张旁边的「收进抽屉」，旧的就收在这儿。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(list) { r in
                                HStack(spacing: 10) {
                                    Button { preview = r.image } label: { WageThumb(name: r.image, size: 50) }
                                        .buttonStyle(.plain)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(rosterRange(r)).font(.app(13)).foregroundStyle(Theme.textMain(scheme))
                                        Text("\(r.days) 天 · " + Self.md(r.addedAt) + " 收进来")
                                            .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                                    }
                                    Spacer(minLength: 0)
                                    Button {
                                        store.unstashRoster(r.id)
                                        flash("已取出，原班表已收入抽屉")
                                    } label: {
                                        Text("取出")
                                            .font(.app(12, weight: .medium))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(app.settings.accentColor))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contextMenu {
                                    Button(role: .destructive) { store.removeRoster(r.id) } label: {
                                        Label("删掉这张", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }
            }
            .padding(18)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial))
            .padding(.horizontal, 22)
        }
    }

    private func rosterRange(_ r: WageRoster) -> String {
        guard let s = WageStore.date(r.start),
              let e = Calendar(identifier: .gregorian).date(byAdding: .day, value: r.days - 1, to: s) else { return r.start }
        return Self.md(s) + " – " + Self.md(e)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10, alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                ForEach(store.settings.kinds) { k in
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
            Text("点击空白日期排班或记账；已设置的日期点击后显示当日总结。右上角设置时薪、各班次时间，可添加班次。")
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
                if day.leave {
                    row("请假") { value("这一天不算工资") }
                } else if let k = day.shift {
                    row("班次") {
                        HStack(spacing: 6) {
                            Circle().fill(k.tint).frame(width: 7, height: 7)
                            value(k.rawValue)
                            // 她要的那颗小胶囊：「小卡片显示一个小胶囊上面写 3x 工资」
                            if day.hasBonusRate { WageRatePill(text: day.rateLabel) }
                        }
                    }
                    row("时长") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach([day.work] + day.extra) { w in value(w.text) }
                        }
                    }
                    row("休息") {
                        if day.breaks.isEmpty {
                            value("无")
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(day.breaks) { b in value(b.text) }
                            }
                        }
                    }
                    if !WageStore.shared.isFullTime(date) || WageStore.shared.dayPay(day, on: date) > 0 {
                    row(WageStore.shared.isFullTime(date) ? "当日额外" : "总薪资") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(WageStore.money(WageStore.shared.dayPay(day, on: date)))
                                .font(.app(14, weight: .semibold))
                                .foregroundStyle(WageView.payRed)
                            // 三倍那天把「平常是多少」也写出来，好对账
                            if day.hasBonusRate && !WageStore.shared.isFullTime(date) {
                                Text("平常 " + WageStore.money(day.basePay)
                                     + " × " + day.rateLabel.replacingOccurrences(
                                        of: " 工资", with: ""))
                                    .font(.app(10.5))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                        }
                    }
                    }
                }

                if day.overtime > 0 && !day.leave {
                    row("加班") {
                        value(String(Int(day.overtimeHours)) + " 小时 · "
                              + (day.overtimeHourly > 0 ? WageStore.money(day.overtimeHourly) + " 元/小时"
                                 : WageStore.money(day.overtimeRate) + "x"))
                    }
                }
                if Calendar.current.component(.day, from: date) == 15,
                   let p = WageStore.shared.performance(for: date) {
                    row("当月绩效") {
                        Text(WageStore.money(p))
                            .font(.app(14, weight: .semibold))
                            .foregroundStyle(WageView.payRed)
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

                if let pay = WageStore.shared.expectedPay(on: date) {
                    row("发薪") {
                        VStack(alignment: .leading, spacing: 2) {
                            value("应发 " + WageStore.money(pay.amount))
                            if let a = WageStore.shared.payRecord(on: date)?.actual {
                                let diff = a - pay.amount
                                HStack(spacing: 6) {
                                    value("实发 " + WageStore.money(a))
                                    Text((diff >= 0 ? "+" : "-") + WageStore.money(abs(diff)))
                                        .font(.app(12.5, weight: .semibold))
                                        .foregroundStyle(diff >= 0 ? WagePayCard.green : WagePayCard.red)
                                }
                            }
                        }
                    }
                }

                if !day.note.isEmpty {
                    row("备注") {
                        Text(day.note)
                            .font(.app(13))
                            .foregroundStyle(Theme.textMain(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let r = WageStore.shared.roster(on: date) {
                    row("班表") {
                        Button { onOpenImage(r.image) } label: {
                            WageThumb(name: r.image, size: 92)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if day.shift == nil && day.entries.isEmpty && day.note.isEmpty {
                    value("这一天还没有记录")
                }
            }
            // 内容少的时候也别成一条扁扁的长条：内容区至少这么高（卡片大约是 4:5，不细长也不扁）
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)

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
        .fixedSize(horizontal: false, vertical: true)
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
            if let img = ImageStore.thumb(name, maxPixel: size * 3) {
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

// MARK: - 自己管字的输入框

/// 格子里的字。普通类、不发通知：改它不会叫外面那一页重画
final class TextBox {
    var text = ""
}

/// 字只在这一格里动，打字时外面那一页不重画；外面要用时直接读 `box.text`
struct QuietField: View {
    let title: String
    let box: TextBox
    var focus: FocusState<Bool>.Binding? = nil
    var onEdit: () -> Void = {}

    @State private var text: String

    init(title: String, box: TextBox, focus: FocusState<Bool>.Binding? = nil,
         onEdit: @escaping () -> Void = {}) {
        self.title = title
        self.box = box
        self.focus = focus
        self.onEdit = onEdit
        _text = State(initialValue: box.text)
    }

    var body: some View {
        Group {
            if let focus {
                TextField(title, text: $text).focused(focus)
            } else {
                TextField(title, text: $text)
            }
        }
        .onChange(of: text) { _, v in
            box.text = v
            onEdit()
        }
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
    /// 15 号那天填的当月绩效
    @State private var perfText = ""
    /// 这一天的加班时薪
    @State private var overtimeText = ""

    // 记账那两个方格子
    // ⚠️ 这两个格子的字放在盒子里、由格子自己管，不放在这一页的 @State 上：
    // 放在这儿的话每打一个字整页（班次、时间、每一笔账和图）都要重画一遍，
    // 她报的「输入数据有明显的卡顿延迟」就是这个
    @State private var whatBox = TextBox()
    @State private var amountBox = TextBox()
    /// 备注的字也放盒子里，打字时整页不重画
    @State private var noteBox = TextBox()
    @State private var rosterShown: String?
    /// 从外面换格子里的字（改某一笔、记完清空）时 +1，让格子按盒子重新起
    @State private var fieldsToken = 0
    /// 「记一笔」能不能点。只在能/不能翻转的那一下更新
    @State private var canAddNow = false
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

    /// 记账里按用量算的那几样（卫生巾、药）：这一天用了几。点「完成」才写回去
    @State private var usageList: [Expense] = []
    @State private var usage: [UUID: Int] = [:]

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
                            if let r = store.roster(on: date) { rosterCard(r) }
                            if store.isPayday(date) { WagePayCard(date: date) { rosterShown = $0 } }
                            WageAnniversaryCard(date: date)
                            if !usageList.isEmpty { usageCard }
                            noteCard
                            if isPerformanceDay { performanceCard }
                            shiftCard
                            if day.shift != nil && !day.leave { rateCard }
                            if day.shift != nil && !day.leave { timeCard }
                            if !day.leave { overtimeCard }
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
            .onAppear {
                hourlyText = WageStore.money(day.hourly)
                perfText = store.performance(for: date).map(WageStore.money) ?? ""
                overtimeText = day.overtimeHourly > 0 ? WageStore.money(day.overtimeHourly) : ""
                noteBox.text = day.note
                let book = AccountBook.shared
                usageList = book.usageItems(on: date)
                usage = Dictionary(uniqueKeysWithValues: usageList.map { ($0.id, book.used($0, on: date)) })
            }
            .fullScreenCover(item: Binding(get: { rosterShown.map { WageImageRef(name: $0) } },
                                           set: { rosterShown = $0?.name })) { ref in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let img = ImageStore.cached(ref.name) { WageZoomImage(image: img).padding(20) }
                }
                .onTapGesture { rosterShown = nil }
            }
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

    /// 这一天的班表：点开看大图（能放大）
    private func rosterCard(_ r: WageRoster) -> some View {
        Button { rosterShown = r.image } label: {
            HStack(spacing: 12) {
                WageThumb(name: r.image, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("这天的班表").font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                    Text("轻点查看大图").font(.app(11.5)).foregroundStyle(Theme.textMuted(scheme))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.textMuted(scheme))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard()
    }

    /// 今天用了吗：记账里按用量算的东西，买了以后每天问一句，用完就不再出现
    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").foregroundStyle(Theme.textMuted(scheme))
                Text("今日用量").font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
            }
            ForEach(usageList) { e in
                usageRow(e)
            }
        }
        .glassCard()
    }

    private func usageRow(_ e: Expense) -> some View {
        let p = e.packCount ?? 0
        let before = AccountBook.shared.usedBefore(e, date)
        let n = usage[e.id] ?? 0
        let room = max(1, p - before)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { n > 0 },
                                 set: { on in withAnimation(.easeOut(duration: 0.2)) { usage[e.id] = on ? 1 : 0 } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(.app(13.5)).foregroundStyle(Theme.textMain(scheme))
                    Text("剩 \(max(0, p - before - n))/\(p) " + e.unit)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            if n > 0 {
                Stepper(value: Binding(get: { usage[e.id] ?? 1 }, set: { usage[e.id] = $0 }),
                        in: 1...room) {
                    Text("用了 \(n) " + e.unit)
                        .font(.app(12.5))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
            }
        }
    }

    /// 备注：写这一天想记的话，会显示在当天的卡片里
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft").foregroundStyle(Theme.textMuted(scheme))
                Text("备注").font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
            }
            WageNoteField(box: noteBox)
        }
        .glassCard()
    }

    /// 写回去，并把这一次里被拿掉的图（新挑的、原来就有的都算）删文件。
    private func save() {
        day.note = noteBox.text.trimmingCharacters(in: .whitespacesAndNewlines)
        commitDraftEntry()
        store.put(day, on: date)
        if isPerformanceDay { store.setPerformance(Double(perfText), for: date) }
        for e in usageList { AccountBook.shared.setUsage(e.id, on: date, count: usage[e.id] ?? 0) }
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
            HStack {
                Text("班次").heading(14)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { day.leave.toggle() }
                    if app.settings.haptics { UISelectionFeedbackGenerator().selectionChanged() }
                } label: {
                    Label(day.leave ? "已请假" : "请假", systemImage: day.leave ? "checkmark" : "moon.zzz")
                        .font(.app(12, weight: day.leave ? .semibold : .regular))
                        .foregroundStyle(day.leave ? Color.white : Theme.textSoft(scheme))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(day.leave ? WageView.leaveTint : Theme.softFillDeep))
                }
                .buttonStyle(.plain)
            }
            if day.leave {
                Text(store.isFullTime(date)
                     ? "请假这天不算工资，按日薪扣 ¥" + WageStore.money(store.settings.dailyWage) + "，这个月没有全勤。"
                     : "请假这天不算工资。")
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                          spacing: 8) {
                    ForEach(store.settings.kinds) { k in
                        shiftChip(k.rawValue, tint: k.tint, on: day.shift == k) { pick(k) }
                    }
                    shiftChip("不排班", tint: Theme.textMuted(scheme), on: day.shift == nil) {
                        day.shift = nil
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 加班

    private var overtimeCard: some View {
        let full = store.isFullTime(date)
        let pay = full ? store.fullTimeOvertime(day) : day.overtimePay
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("加班").heading(14)
                Spacer()
                if day.overtime > 0 {
                    Text("+" + WageStore.money(pay))
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(WageView.payRed)
                }
            }
            HStack(spacing: 10) {
                Text("时长").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                stepButton("minus") { setOvertime(day.overtime / 60 * 60 - 60) }
                Text("\(day.overtime / 60) 小时")
                    .font(HomeType.number(15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(minWidth: 64)
                    .contentTransition(.numericText())
                stepButton("plus") { setOvertime(day.overtime / 60 * 60 + 60) }
                Spacer(minLength: 0)
            }
            if day.overtime > 0 {
                HStack(spacing: 8) {
                    Text("加班时薪").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                    TextField(full ? WageStore.money(store.settings.dailyWage / 8) : WageStore.money(day.hourly),
                              text: $overtimeText)
                        .keyboardType(.decimalPad)
                        .font(.app(14))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(width: 90)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.softFillDeep))
                        .onChange(of: overtimeText) { _, v in day.overtimeHourly = Double(v) ?? 0 }
                    Text("元/小时").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                    Spacer(minLength: 0)
                }
                Text("只计整小时，不足一小时不计。")
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func setOvertime(_ m: Int) {
        if day.overtime == 0 {
            day.overtimeRate = store.settings.overtimeRate
            if day.overtimeHourly == 0 && store.settings.overtimeHourly > 0 {
                day.overtimeHourly = store.settings.overtimeHourly
                overtimeText = WageStore.money(store.settings.overtimeHourly)
            }
        }
        withAnimation(.easeOut(duration: 0.15)) { day.overtime = min(24 * 60, max(0, m)) }
        if app.settings.haptics { UISelectionFeedbackGenerator().selectionChanged() }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    // MARK: 绩效（15 号那天填）

    private var isPerformanceDay: Bool { Calendar.current.component(.day, from: date) == 15 }

    private var performanceCard: some View {
        let f = DateFormatter()
        f.dateFormat = "M月"
        return VStack(alignment: .leading, spacing: 10) {
            Text(f.string(from: date) + "绩效").heading(14)
            HStack(spacing: 8) {
                Text("金额").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                TextField("0", text: $perfText)
                    .keyboardType(.decimalPad)
                    .font(.app(14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: 110)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.softFillDeep))
                Text("元").font(.app(12)).foregroundStyle(Theme.textMuted(scheme))
                Spacer(minLength: 0)
            }
            Text("计入本月收入。")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
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
        day.extra = t.extra
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
                if !store.isFullTime(date) {
                    Text("+" + WageStore.money(day.pay - day.overtimePay))
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(WageView.payRed)
                }
            }

            HStack(spacing: 8) {
                Text("上班").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                MinutePicker(minutes: $day.work.start)
                Text("至").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                MinutePicker(minutes: $day.work.end)
                Spacer(minLength: 0)
            }

            ForEach($day.extra) { $w in
                HStack(spacing: 8) {
                    Text("上班").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                    MinutePicker(minutes: $w.start)
                    Text("至").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                    MinutePicker(minutes: $w.end)
                    Spacer(minLength: 0)
                    Button {
                        day.extra.removeAll { $0.id == w.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                let last = (day.extra.last ?? day.work).end
                day.extra.append(TimeSpan(start: last + 60, end: last + 4 * 60))
            } label: {
                Label("添加工作时段", systemImage: "plus")
                    .font(.app(12.5))
                    .foregroundStyle(app.settings.accentColor)
            }
            .buttonStyle(.plain)

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
                QuietField(title: "干了什么，如：吃了一个汉堡", box: whatBox, focus: $whatFocused,
                           onEdit: refreshCanAdd)
                    .id(fieldsToken)
                    .font(.app(13.5))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.softFillDeep))
                QuietField(title: "金额", box: amountBox, onEdit: refreshCanAdd)
                    .id(fieldsToken)
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
                        .foregroundStyle(canAddNow ? app.settings.accentColor : Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(canAddNow
                            ? app.settings.accentColor.opacity(0.16) : Theme.softFillDeep))
                }
                .buttonStyle(.plain)
                .disabled(!canAddNow)
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
        !whatBox.text.trimmingCharacters(in: .whitespaces).isEmpty && Double(amountBox.text) != nil
    }

    private func refreshCanAdd() {
        let v = canAdd
        if v != canAddNow { canAddNow = v }
    }

    /// 把两个方格子里的那一笔记进去。
    ///
    /// ⚠️ 「完成」的时候也调一次：填好了两个格子没点「记一笔」就直接点完成，
    /// 那一笔不该悄悄丢掉。
    private func commitDraftEntry() {
        guard canAdd, let amt = Double(amountBox.text) else { return }
        let text = whatBox.text.trimmingCharacters(in: .whitespaces)
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
        whatBox.text = e.what
        amountBox.text = WageStore.money(e.amount)
        fieldsToken += 1
        refreshCanAdd()
        income = e.income
        meal = e.meal
        draftImages = e.images
    }

    /// 清空格子。改到一半取消的话，这一笔原样不动；
    /// 改的过程中新挑的图在 addedNow 里，保存时没挂上的会被清掉
    private func clearDraft() {
        editingEntry = nil
        whatBox.text = ""
        amountBox.text = ""
        fieldsToken += 1
        refreshCanAdd()
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
    @State private var baseText = WageStore.shared.settings.baseSalary > 0
        ? WageStore.money(WageStore.shared.settings.baseSalary) : ""
    @State private var bonusText = WageStore.shared.settings.attendanceBonus > 0
        ? WageStore.money(WageStore.shared.settings.attendanceBonus) : ""
    @State private var overtimeHourlyText = WageStore.shared.settings.overtimeHourly > 0
        ? WageStore.money(WageStore.shared.settings.overtimeHourly) : ""
    @State private var adding = false
    @State private var newName = ""

    /// 新班先抄中班的时间，她再改
    private func addShift() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "不排班", draft.kind(named: name) == nil else { return }
        draft.custom.append(name)
        draft.templates[name] = draft.template(.middle)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        modeCard

                        paydayCard
                        anniversaryCard

                        ForEach(draft.kinds) { k in
                            templateCard(k)
                        }

                        Button {
                            newName = ""
                            adding = true
                        } label: {
                            Label("添加班次", systemImage: "plus.circle")
                                .font(.app(14, weight: .medium))
                                .foregroundStyle(app.settings.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)

                        SettingsNote("修改后对之后排的班生效；已排好的日期保留排班时的时间与时薪，可在当天单独修改。")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("工资设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert("添加班次", isPresented: $adding) {
                TextField("班次名称，如：夜班", text: $newName)
                Button("取消", role: .cancel) {}
                Button("添加") { addShift() }
            } message: {
                Text("添加后可设置上班与休息时间，排班时出现在班次里。")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        // 没起名字的纪念日叫「纪念日」
                        for i in draft.anniversaries.indices where draft.anniversaries[i].name.trimmingCharacters(in: .whitespaces).isEmpty {
                            draft.anniversaries[i].name = "纪念日"
                        }
                        // 刚切成全职：从这个月起按底薪算，之前的月份还按时薪
                        if draft.fullTime && !store.settings.fullTime {
                            draft.fullTimeSince = WageStore.monthKey(Date())
                        }
                        store.updateSettings(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: 全职 / 兼职

    private var modeCard: some View {
        SettingsCard(title: "工作方式") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $draft.fullTime) {
                    Text("兼职").tag(false)
                    Text("全职").tag(true)
                }
                .pickerStyle(.segmented)

                if draft.fullTime {
                    moneyField("底薪", $baseText, unit: "元/月") { draft.baseSalary = $0 }
                    moneyField("全勤", $bonusText, unit: "元/月") { draft.attendanceBonus = $0 }
                    HStack(spacing: 6) {
                        Text("日薪计算")
                            .font(.app(13))
                            .foregroundStyle(Theme.textSoft(scheme))
                        ForEach([21.75, 22, 26, 30], id: \.self) { n in
                            let on = abs(draft.payDays - n) < 0.01
                            Button { draft.payDays = n } label: {
                                Text("÷" + WageStore.money(n))
                                    .font(.app(12, weight: on ? .semibold : .regular))
                                    .foregroundStyle(on ? Color.white : Theme.textMain(scheme))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(on ? app.settings.accentColor : Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    Text("每月结算：底薪 + 全勤。这个月没请假就加上全勤，请了假就不加，请假一天扣一天日薪（底薪 ÷ 上面选的天数，不确定的话看工资条或问一下人事）。排班只记哪天上班。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                } else {
                    moneyField("时薪", $hourlyText, unit: "元/小时") { draft.hourly = $0 }
                }

                moneyField("加班", $overtimeHourlyText, unit: "元/小时") { draft.overtimeHourly = $0 }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func moneyField(_ label: String, _ text: Binding<String>, unit: String,
                            set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.app(13))
                .foregroundStyle(Theme.textSoft(scheme))
                .frame(width: 34, alignment: .leading)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .font(.app(16, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 120)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.softFillDeep))
                .onChange(of: text.wrappedValue) { _, v in set(Double(v) ?? 0) }
            Text(unit)
                .font(.app(13))
                .foregroundStyle(Theme.textMuted(scheme))
            Spacer(minLength: 0)
        }
    }

    // MARK: 发薪日

    private var paydayCard: some View {
        SettingsCard(title: "发薪日") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(1...31, id: \.self) { d in
                        let on = draft.paydays.contains(d)
                        Button {
                            if on { draft.paydays.removeAll { $0 == d } } else { draft.paydays = (draft.paydays + [d]).sorted() }
                        } label: {
                            Text(String(d))
                                .font(.app(12.5, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Color.white : Theme.textSoft(scheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(on ? app.settings.accentColor : Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 每个发薪日发上个月工资的几成
                ForEach(draft.paydays, id: \.self) { d in
                    HStack(spacing: 8) {
                        Text("\(d) 号发").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                        TextField(ratioPlaceholder(d), text: Binding(
                            get: { draft.payRatios[String(d)].map { WageStore.money($0 * 100) } ?? "" },
                            set: { v in draft.payRatios[String(d)] = Double(v).map { min(100, max(0, $0)) / 100 } }))
                            .keyboardType(.decimalPad)
                            .font(.app(14, weight: .medium))
                            .multilineTextAlignment(.trailing)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(width: 90)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.softFillDeep))
                        Text("%").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                        Spacer(minLength: 0)
                    }
                }
                Text(draft.paydays.isEmpty
                     ? "点选每月发工资的日子，可以选多天。日历上会标出来，首页显示还有几天。"
                     : "每月 " + draft.paydays.map(String.init).joined(separator: "、") + " 号发上个月的工资；比例空着的那几天平分剩下的。当月没有这一天时按最后一天算。")
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// 比例格子里的灰字：没填时这一天会分到多少
    private func ratioPlaceholder(_ d: Int) -> String {
        let unset = draft.paydays.filter { draft.payRatios[String($0)] == nil }
        let used = draft.paydays.compactMap { draft.payRatios[String($0)] }.reduce(0, +)
        let share = unset.isEmpty ? 0 : max(0, 1 - used) / Double(unset.count)
        return "剩下的 " + WageStore.money(share * 100)
    }

    // MARK: 纪念日

    private var anniversaryCard: some View {
        SettingsCard(title: "纪念日") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach($draft.anniversaries) { $a in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("名字，如：入职纪念日", text: $a.name)
                                .font(.app(14))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.softFillDeep))
                            DatePicker("", selection: Binding(
                                get: { WageStore.date(a.date) ?? Date() },
                                set: { a.date = WageStore.key($0) }), displayedComponents: .date)
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "zh_CN"))
                            Button {
                                let id = a.id
                                draft.anniversaries.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                        }
                        Toggle("每年这一天都提醒", isOn: $a.yearly)
                            .font(.app(12.5))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .tint(app.settings.accentColor)
                    }
                }
                Button {
                    draft.anniversaries.append(WageAnniversary(name: "", date: WageStore.key(Date())))
                } label: {
                    Label("添加纪念日", systemImage: "plus.circle")
                        .font(.app(13.5, weight: .medium))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                Text("入职、转正这样的日子。日历上那天有一颗小心，首页显示还有几天、第几周年。")
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
                ForEach(binding.extra) { $w in
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 8, height: 8)
                        Text("上班").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                        MinutePicker(minutes: $w.start)
                        Text("至").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                        MinutePicker(minutes: $w.end)
                        Spacer(minLength: 0)
                        Button {
                            binding.wrappedValue.extra.removeAll { $0.id == w.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        .buttonStyle(.plain)
                    }
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
                    let last = (binding.wrappedValue.extra.last ?? binding.wrappedValue.work).end
                    binding.wrappedValue.extra.append(TimeSpan(start: last + 60, end: last + 4 * 60))
                } label: {
                    Label("添加工作时段", systemImage: "plus")
                        .font(.app(12.5))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                HStack {
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
                    Spacer(minLength: 0)
                    // 自己加的班可以删；已经排过这个班的日子不受影响（存的是快照）
                    if !k.isBuiltin {
                        Button(role: .destructive) {
                            draft.custom.removeAll { $0 == k.rawValue }
                            draft.templates[k.rawValue] = nil
                        } label: {
                            Label("删除班次", systemImage: "trash")
                                .font(.app(12.5))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
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

// MARK: - 导入班表

/// 导入班表：挑一张班表图，选从哪天开始、管几天，这几天在日历上标出来，点一下看图
struct WageRosterImport: View {

    @ObservedObject private var store = WageStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var days = 7
    @State private var image: UIImage?
    @State private var item: PhotosPickerItem?

    init(start: Date) {
        _start = State(initialValue: start)
    }

    private var cal: Calendar { Calendar(identifier: .gregorian) }

    private var rangeText: String {
        guard let e = cal.date(byAdding: .day, value: days - 1, to: start) else { return "" }
        return WageView.md(start) + " – " + WageView.md(e) + "，共 \(days) 天"
    }

    /// 这几天里已经有班表的天数
    private var overlap: Int {
        (0..<days).filter { i in cal.date(byAdding: .day, value: i, to: start).flatMap { store.roster(on: $0) } != nil }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsCard(title: "班表图") {
                            PhotosPicker(selection: $item, matching: .images) {
                                Group {
                                    if let image {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 280)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo.badge.plus")
                                                .font(.system(size: 26, weight: .light))
                                            Text("选一张班表图")
                                                .font(.app(13))
                                        }
                                        .foregroundStyle(app.settings.accentColor)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 140)
                                    }
                                }
                                .padding(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsCard(title: "从哪天开始") {
                            DatePicker("开始日期", selection: $start, displayedComponents: .date)
                                .font(.app(14))
                                .environment(\.locale, Locale(identifier: "zh_CN"))
                                .tint(app.settings.accentColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }

                        SettingsCard(title: "持续几天") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    ForEach([4, 7, 14], id: \.self) { n in
                                        Button { days = n } label: {
                                            Text("\(n) 天")
                                                .font(.app(12.5, weight: days == n ? .semibold : .regular))
                                                .foregroundStyle(days == n ? Color.white : Theme.textSoft(scheme))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(days == n ? app.settings.accentColor : Theme.softFillDeep))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Spacer(minLength: 0)
                                    Stepper("", value: $days, in: 1...31)
                                        .labelsHidden()
                                }
                                Text(rangeText)
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textSoft(scheme))
                                if overlap > 0 {
                                    Text("其中 \(overlap) 天已经有班表了，导入后这几天看这一张。")
                                        .font(.app(11.5))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("导入班表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入") { save() }
                        .fontWeight(.semibold)
                        .disabled(image == nil)
                }
            }
            .onChange(of: item) { _, it in
                guard let it else { return }
                Task { @MainActor in
                    if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        image = img
                    }
                }
            }
        }
    }

    private func save() {
        // 班表要看得清字：长边留到 2048、质量高一点
        guard let image, let name = ImageStore.save(image, quality: 0.92) else { return }
        store.addRoster(start: start, days: days, image: name)
        dismiss()
    }
}

/// 放大看的图：两指放大（看清班表上的小字）、放大后拖动、双击放大 / 还原
struct WageZoomImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetBase: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(5, max(1, base * v.magnification)) }
                    .onEnded { _ in
                        base = scale
                        if scale <= 1 { reset() }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { v in
                            guard scale > 1 else { return }
                            offset = CGSize(width: offsetBase.width + v.translation.width,
                                            height: offsetBase.height + v.translation.height)
                        }
                        .onEnded { _ in offsetBase = offset })
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if scale > 1 { reset() } else { scale = 2.5; base = 2.5 }
                }
            }
    }

    private func reset() {
        scale = 1; base = 1; offset = .zero; offsetBase = .zero
    }
}

// MARK: - 发薪日那一天

/// 发薪日：应发多少（上个月工资 × 比例）、实发多少，差多少（多了绿、少了红），为什么——文字和图
struct WagePayCard: View {
    let date: Date
    /// 点缩略图看大图
    var onOpen: (String) -> Void = { _ in }

    @ObservedObject private var store = WageStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var actualText = ""
    @State private var note = ""
    @State private var images: [String] = []
    @State private var pick: [PhotosPickerItem] = []
    @State private var loaded = false
    /// 打字时先不存：停手半秒再存（每打一个字就存，整页都跟着重画，打字会卡）
    @State private var saveLater: Task<Void, Never>?

    static let green = Color(hexString: "4FA36B")!
    static let red = Color(hexString: "D9566B")!

    private var expected: (amount: Double, base: Double, ratio: Double)? { store.expectedPay(on: date) }
    private var actual: Double? { Double(actualText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "yensign.circle").foregroundStyle(WageView.payRed)
                Text("发薪日").font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                Spacer()
            }
            if let e = expected {
                HStack {
                    Text("应发").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                    Spacer()
                    Text("¥" + WageStore.money(e.amount)).font(.app(15, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                }
                Text("上个月工资 ¥\(WageStore.money(e.base)) × \(WageStore.money(e.ratio * 100))%")
                    .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
            }
            HStack(spacing: 8) {
                Text("实发").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                Spacer()
                Text("¥").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                TextField("到手多少", text: $actualText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.app(15, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(width: 130)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.softFillDeep))
            }
            if let a = actual, let e = expected {
                let diff = a - e.amount
                HStack {
                    Text(diff >= 0 ? "多了" : "少了").font(.app(13)).foregroundStyle(Theme.textSoft(scheme))
                    Spacer()
                    Text((diff >= 0 ? "+" : "-") + WageStore.money(abs(diff)))
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(diff >= 0 ? Self.green : Self.red)
                }
            }
            TextField("为什么多了 / 少了（扣了什么、补了什么）", text: $note, axis: .vertical)
                .font(.app(13))
                .lineLimit(1...4)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.softFillDeep))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(images, id: \.self) { n in
                        WageThumb(name: n, size: 54)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(n) }
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    images.removeAll { $0 == n }
                                    ImageStore.delete(n)
                                    persist()
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                                        .foregroundStyle(.white, .black.opacity(0.45))
                                }
                                .offset(x: 5, y: -5)
                            }
                    }
                    PhotosPicker(selection: $pick, maxSelectionCount: 4, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(app.settings.accentColor)
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.softFillDeep))
                    }
                }
                .padding(.top, 5)
            }
        }
        .glassCard()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let r = store.payRecord(on: date)
            actualText = r?.actual.map(WageStore.money) ?? ""
            note = r?.note ?? ""
            images = r?.images ?? []
        }
        .onChange(of: actualText) { _, _ in persistSoon() }
        .onChange(of: note) { _, _ in persistSoon() }
        .onDisappear { if saveLater != nil { saveLater?.cancel(); persist() } }
        .onChange(of: pick) { _, items in
            guard !items.isEmpty else { return }
            Task { @MainActor in
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d),
                       let n = ImageStore.save(ImageStore.downscale(img, maxSide: 1600)) { images.append(n) }
                }
                pick = []
                persist()
            }
        }
    }

    private func persist() {
        saveLater = nil
        store.setPayRecord(WagePayRecord(actual: Double(actualText), note: note, images: images), on: date)
    }

    private func persistSoon() {
        guard loaded else { return }
        saveLater?.cancel()
        saveLater = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
    }
}

// MARK: - 这一天的纪念日

/// 在编辑页直接把这一天记成纪念日：写个名字，选每年提醒，加上
struct WageAnniversaryCard: View {
    let date: Date

    @ObservedObject private var store = WageStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var name = ""
    @State private var yearly = true
    @State private var open = false

    var body: some View {
        let here = store.anniversaries(on: date)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "heart").foregroundStyle(Color(hexString: "E8758F")!)
                Text(here.isEmpty ? "纪念日" : here.map(\.name).joined(separator: "、"))
                    .font(.app(14, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
                Spacer()
                if !open {
                    Button(here.isEmpty ? "记成纪念日" : "再加一个") { open = true }
                        .font(.app(12.5)).foregroundStyle(app.settings.accentColor)
                }
            }
            ForEach(here) { a in
                HStack {
                    Text(a.yearly ? "每年这一天" : "只这一天").font(.app(11.5)).foregroundStyle(Theme.textMuted(scheme))
                    Spacer()
                    Button { store.removeAnniversary(a.id) } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            if open {
                TextField("名字，如：入职纪念日、转正", text: $name)
                    .font(.app(14))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.softFillDeep))
                Toggle("每年这一天都提醒", isOn: $yearly)
                    .font(.app(12.5)).tint(app.settings.accentColor)
                HStack {
                    Spacer()
                    Button("取消") { open = false; name = "" }
                        .font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                    Button("加上") {
                        store.addAnniversary(name.trimmingCharacters(in: .whitespaces), on: date, yearly: yearly)
                        name = ""; open = false
                    }
                    .font(.app(13, weight: .semibold)).foregroundStyle(app.settings.accentColor)
                    .padding(.leading, 12)
                }
            }
        }
        .glassCard()
    }
}

/// 备注那一格：几行字，字只在这一格里动（见 `QuietField`）
struct WageNoteField: View {
    let box: TextBox
    @State private var text = ""
    @State private var ready = false

    var body: some View {
        TextField("这一天想记点什么", text: $text, axis: .vertical)
            .font(.app(14))
            .lineLimit(2...6)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.softFillDeep))
            .onAppear { if !ready { text = box.text; ready = true } }
            .onChange(of: text) { _, v in box.text = v }
    }
}

/// 全屏看的那张图
struct WageImageRef: Identifiable {
    let name: String
    var id: String { name }
}
