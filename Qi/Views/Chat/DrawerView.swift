import SwiftUI

/// 抽屉那一页：他留下的便签、像素小画、贺卡，按时间排成一条时间线（左边一条线，每一样一个点）。
/// 打开就算看过了。
///
/// - 长按左边那条线上下拖：挑一个月，只看那个月的
/// - 点贺卡：放大到中间，封面翻开
struct DrawerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DrawerStore.shared
    /// 这一次打开之前就没看过的（这一次里还标着「新」）
    @State private var fresh: Set<UUID> = []
    @Namespace private var cardNS
    /// 正在看的那张贺卡
    @State private var openCard: DrawerItem?
    /// 只看哪一种（nil = 全部）
    @State private var kindFilter: String?
    /// 只看哪个月（yyyy-MM）
    @State private var monthFilter: String?
    /// 长按拖时间线的时候：手指停在哪个月、在哪个高度
    @State private var scrub: (month: String, y: CGFloat)?

    private var him: String { app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName }
    private var accent: Color { app.settings.accentColor }

    private static let kinds: [(String, String)] = [("card", "贺卡"), ("note", "便签"), ("pixel", "画"), ("riddle", "谜")]

    private static func monthKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: d)
    }

    private static func monthLabel(_ k: String) -> String {
        let p = k.split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return k }
        let thisYear = Calendar.current.component(.year, from: Date())
        return (y == thisYear ? "" : "\(y)年") + "\(m)月"
    }

    private static func dayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        let cal = Calendar.current
        f.dateFormat = cal.component(.year, from: d) == cal.component(.year, from: Date())
            ? "M月d日 EEEE HH:mm" : "yyyy年M月d日 EEEE HH:mm"
        return f.string(from: d)
    }

    /// 按种类挑过的（时间线上能拖到的月份从这里来）
    private var byKind: [DrawerItem] {
        store.items
            .filter { kindFilter == nil || $0.kind == kindFilter }
            .sorted { $0.at > $1.at }
    }

    private var months: [String] {
        var seen = Set<String>(), out: [String] = []
        for i in byKind {
            let k = Self.monthKey(i.at)
            if seen.insert(k).inserted { out.append(k) }
        }
        return out
    }

    private var shown: [DrawerItem] {
        guard let m = monthFilter else { return byKind }
        return byKind.filter { Self.monthKey($0.at) == m }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    filterBar
                        .padding(.bottom, 14)
                    if store.items.isEmpty {
                        EmptyNote(icon: "tray", title: "抽屉还是空的",
                                  hint: "他想留给你、又不用你马上回的话，一幅很小的画，或者一张贺卡，会悄悄放在这里。")
                            .padding(.top, 40)
                    } else if shown.isEmpty {
                        EmptyNote(icon: "line.3.horizontal.decrease", title: "无内容")
                            .padding(.top, 30)
                    }
                    let list = shown
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                        row(item, first: i == 0, last: i == list.count - 1)
                            .contextMenu {
                                Button(role: .destructive) { store.remove(item.id) } label: {
                                    Label("移出抽屉", systemImage: Icon.trash)
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .overlay(alignment: .leading) { scrubRail }

            if let c = openCard {
                GreetingCardViewer(item: c, from: him, ns: cardNS) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { openCard = nil }
                }
                .zIndex(10)
                .transition(.opacity)
            }
        }
        .navigationTitle("抽屉")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(openCard == nil ? .automatic : .hidden, for: .navigationBar)
        .onAppear {
            fresh = Set(store.items.filter { !$0.seen }.map(\.id))
            store.markSeen()
        }
    }

    // MARK: 筛选

    private var filterBar: some View {
        let present = Set(store.items.map(\.kind))
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("全部", on: kindFilter == nil) { kindFilter = nil }
                    ForEach(Self.kinds.filter { present.contains($0.0) }, id: \.0) { k in
                        chip(k.1, on: kindFilter == k.0) {
                            kindFilter = kindFilter == k.0 ? nil : k.0
                            if let m = monthFilter, !months.contains(m) { monthFilter = nil }
                        }
                    }
                    if let m = monthFilter {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { monthFilter = nil }
                        } label: {
                            HStack(spacing: 4) {
                                Text(Self.monthLabel(m))
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .font(.app(12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Capsule().fill(accent))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if months.count > 1 {
                Text("长按左侧时间线并上下拖动，可按月份筛选")
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
    }

    private func chip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } label: {
            Text(title)
                .font(.app(12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? accent : Theme.textSoft(scheme))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(on ? accent.opacity(0.16) : Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    /// 时间线左边那一条：长按以后上下拖，手指在哪个高度就是第几个月（最新的在上面）
    @ViewBuilder
    private var scrubRail: some View {
        if months.count > 1 {
            GeometryReader { g in
                let h = max(1, g.size.height)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.35)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { v in
                                guard case .second(true, let drag) = v else { return }
                                let y = drag?.location.y ?? h / 2
                                let i = min(months.count - 1, max(0, Int(y / h * CGFloat(months.count))))
                                let m = months[i]
                                if scrub?.month != m {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                                scrub = (m, min(h - 20, max(20, y)))
                            }
                            .onEnded { _ in
                                if let s = scrub {
                                    withAnimation(.easeOut(duration: 0.25)) { monthFilter = s.month }
                                }
                                scrub = nil
                            }
                    )
                    .overlay(alignment: .topLeading) {
                        if let s = scrub {
                            let n = byKind.filter { Self.monthKey($0.at) == s.month }.count
                            HStack(spacing: 6) {
                                Text(Self.monthLabel(s.month)).font(.app(14, weight: .semibold))
                                Text("\(n) 样").font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                            }
                            .foregroundStyle(Theme.textMain(scheme))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(.regularMaterial))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                            .fixedSize()
                            .offset(x: 44, y: s.y - 18)
                            .allowsHitTesting(false)
                        }
                    }
                    // 拖的时候那条线亮起来
                    .background(alignment: .leading) {
                        if scrub != nil {
                            Capsule().fill(accent.opacity(0.35)).frame(width: 3).padding(.leading, 24)
                        }
                    }
            }
            .frame(width: 40)
        }
    }

    // MARK: 一行

    private func row(_ item: DrawerItem, first: Bool, last: Bool) -> some View {
        let isCard = item.kind == "card"
        let dot = isCard ? GreetingCardStyle.named(item.style).foil[1] : accent.opacity(0.75)
        return HStack(alignment: .top, spacing: 12) {
            // 线：上一项接下来、往下接到下一项；第一项从点开始，最后一项到点为止
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
                    .fill(dot)
                    .frame(width: isCard ? 11 : 9, height: isCard ? 11 : 9)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                    .padding(.top, isCard ? 9 : 10)
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(Self.dayLabel(item.at))
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    if fresh.contains(item.id) {
                        Text("新").font(.app(10.5, weight: .medium)).foregroundStyle(accent)
                    }
                }
                .padding(.top, 6)
                content(item)
            }
            .padding(.bottom, 20)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func content(_ item: DrawerItem) -> some View {
        if item.kind == "card" {
            HStack(alignment: .bottom, spacing: 14) {
                Group {
                    if openCard?.id == item.id {
                        Color.clear
                    } else {
                        GreetingCardFront(item: item)
                            .matchedGeometryEffect(id: item.id, in: cardNS)
                    }
                }
                .frame(width: 128, height: 128 / GreetingCardViewer.ratio)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { openCard = item }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "贺卡" : item.title)
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("轻点查看")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(.bottom, 6)
                Spacer(minLength: 0)
            }
        } else {
            card(item)
        }
    }

    private func card(_ item: DrawerItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.kind == "pixel" {
                DrawerPixel(item: item)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else if item.kind == "riddle" && !item.unlocked {
                DrawerLock(item: item, accent: accent)
            } else {
                Text(item.text)
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .glassCard(padding: 0)
    }
}

/// 一幅像素小画：每个数字画成一个色块，放大不糊
struct DrawerPixel: View {
    let item: DrawerItem

    var body: some View {
        let side = min(240, CGFloat(max(item.w, item.h)) * 12)
        Canvas { gc, size in
            let k = min(size.width / CGFloat(item.w), size.height / CGFloat(item.h))
            let ox = (size.width - k * CGFloat(item.w)) / 2, oy = (size.height - k * CGFloat(item.h)) / 2
            for y in 0..<item.h {
                for x in 0..<item.w {
                    let i = y * item.w + x
                    guard i < item.grid.count else { continue }
                    let ci = item.grid[i]
                    guard ci > 0, ci < item.palette.count, let c = DrawerMarker.color(item.palette[ci]) else { continue }
                    gc.fill(Path(CGRect(x: ox + CGFloat(x) * k, y: oy + CGFloat(y) * k, width: k + 0.3, height: k + 0.3)),
                            with: .color(c))
                }
            }
        }
        .frame(width: side, height: side * CGFloat(item.h) / CGFloat(max(1, item.w)))
    }
}

/// 上了谜语锁的那张：封着，写着谜面；猜中谜底才拆开
struct DrawerLock: View {
    let item: DrawerItem
    let accent: Color

    @ObservedObject private var store = DrawerStore.shared
    @Environment(\.colorScheme) private var scheme
    @State private var guess = ""
    @State private var shake: CGFloat = 0
    @State private var opening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: opening ? "envelope.open" : "envelope")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(accent)
                    .contentTransition(.symbolEffect(.replace))
                Text("已封存")
                    .font(.app(12.5, weight: .medium))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Text(item.riddle)
                .font(.app(15))
                .foregroundStyle(Theme.textMain(scheme))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                TextField("谜底", text: $guess)
                    .font(.app(14))
                    .submitLabel(.done)
                    .onSubmit(tryOpen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.textMain(scheme).opacity(0.05)))
                Button(action: tryOpen) {
                    Text("开启")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent))
                }
                .buttonStyle(.plain)
            }
            .offset(x: shake)
            if item.tries > 0 {
                Text(hintText)
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
    }

    private var hintText: String {
        if item.tries >= 3, let first = item.answer.first {
            return "猜了 \(item.tries) 次了 · 第一个字是「\(first)」，一共 \(item.answer.count) 个字"
        }
        return "不对，再想想（猜了 \(item.tries) 次）"
    }

    private func tryOpen() {
        let g = guess.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.isEmpty else { return }
        if store.guess(item.id, g) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.25)) { opening = true }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.default) { shake = 10 }
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 8).delay(0.05)) { shake = 0 }
            guess = ""
        }
    }
}
