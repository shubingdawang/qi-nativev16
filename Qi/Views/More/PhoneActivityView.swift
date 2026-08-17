import SwiftUI
import UniformTypeIdentifiers

/// 今天手机上干了什么。
struct PhoneActivityView: View {

    @ObservedObject private var store = PhoneActivityStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var picking = false
    @State private var showHelp = false
    /// 往回翻了几天。0 是今天。
    @State private var dayOffset = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                if store.bookmark == nil && store.events.isEmpty {
                    setupCard
                } else {
                    dayPager
                    summary
                    ranking
                    Text("一共读到 \(store.events.count) 条记录")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                if let err = store.lastError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                Button {
                    showHelp.toggle()
                } label: {
                    Text(showHelp ? "收起说明" : "快捷指令怎么配")
                        .font(.system(size: 12))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)

                if showHelp { help }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("手机")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.reload()
                } label: {
                    Image(systemName: Icon.refresh)
                }
            }
        }
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: [.plainText, .text, .data]) { result in
            if case .success(let url) = result {
                store.remember(url)
            }
        }
        .onAppear { store.reload() }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没连上")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            Text("让快捷指令把记录写进一个 txt，栖直接读那个文件——**全程不走网络**，不会再报网络错误。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSoft(scheme))
            Button {
                picking = true
            } label: {
                Text("选那个 txt")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 13)
                        .fill(app.settings.accentColor.opacity(0.28)))
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SCREEN TIME")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                Button {
                    picking = true
                } label: {
                    Text("换文件")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("总时长")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text(store.clock(store.total(on: shownDay)))
                        .font(HomeType.number(21, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    // 「正在用」只有看今天才成立，翻回昨天再说这个就是假的
                    if isToday, let now = store.currentApp {
                        Text("正在用：" + now)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                VStack(alignment: .leading, spacing: 3) {
                    Text("拿起次数")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text("\(store.pickups(on: shownDay))")
                        .font(HomeType.number(21, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("次")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            }
        }
        .glassCard()
    }

    // MARK: 翻天

    /// 现在看的是哪一天。`dayOffset` 是「往回数第几个有记录的日子」，
    /// 不是「往回数几天」——中间没记录的日子直接跳过，
    /// 不然一路翻过去全是空的。
    private var shownDay: Date {
        let list = store.days
        guard !list.isEmpty else { return Date() }
        return list[min(max(0, dayOffset), list.count - 1)]
    }

    private var isToday: Bool { Calendar.current.isDateInToday(shownDay) }

    private var dayPager: some View {
        HStack(spacing: 18) {
            Button {
                if dayOffset < store.days.count - 1 { dayOffset += 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(dayOffset < store.days.count - 1
                                     ? Theme.textSoft(scheme)
                                     : Theme.textMuted(scheme).opacity(0.3))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
            .disabled(dayOffset >= store.days.count - 1)

            VStack(spacing: 1) {
                Text(dayLabel(shownDay))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                if store.days.count > 1 {
                    Text("有记录的第 \(min(dayOffset, store.days.count - 1) + 1) / \(store.days.count) 天")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                if dayOffset > 0 { dayOffset -= 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(dayOffset > 0
                                     ? Theme.textSoft(scheme)
                                     : Theme.textMuted(scheme).opacity(0.3))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
            .disabled(dayOffset == 0)
        }
        // 左右滑也能翻，跟按钮一个效果
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    if v.translation.width > 0 {
                        if dayOffset < store.days.count - 1 { dayOffset += 1 }
                    } else {
                        if dayOffset > 0 { dayOffset -= 1 }
                    }
                }
        )
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year)
            ? "M月d日 EEEE" : "yyyy年M月d日"
        return f.string(from: d)
    }

    private var ranking: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最常使用")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))

            let list = store.byApp(on: shownDay)
            if list.isEmpty {
                Text(isToday ? "今天还没有记录" : "这天没有记录")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            let longest = list.first?.seconds ?? 1

            ForEach(list.prefix(8), id: \.app) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.app)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMain(scheme))
                        if isToday, item.app == store.currentApp {
                            Text("使用中")
                                .font(.system(size: 9))
                                .foregroundStyle(StatusTone.done.color)
                        }
                        Spacer()
                        Text(store.clock(item.seconds))
                            .font(HomeType.number(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.textMuted(scheme).opacity(0.12))
                            Capsule()
                                .fill(app.settings.accentColor.opacity(0.55))
                                .frame(width: geo.size.width
                                       * max(0.02, item.seconds / max(longest, 1)))
                        }
                    }
                    .frame(height: 4)
                    Text("\(item.times) 次")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
        }
        .glassCard()
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在「快捷指令」App 里：")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            ForEach([
                "1. 自动化 → 新建 → 打开 App → 挑你想记的那些",
                "2. 加动作「文本」，内容写成：当前日期|App名字|open",
                "3. 加动作「追加到文件」，存成 phone-activity.txt",
                "4. 关掉「运行前询问」，不然每次都要点一下",
                "5. 回到这里，选那个 txt"
            ], id: \.self) { line in
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSoft(scheme))
            }
            Text("想要更准的时长，就再建一组「关闭 App」的自动化，把 open 换成 close。只有 open 也能用，那样时长是按相邻两次打开的间隔估的。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.top, 4)
        }
        .glassCard()
    }
}
