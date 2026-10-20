import SwiftUI

/// 「这个月能自由花的」：这个月的收入画成一张张纸币，
/// 先拿走固定开支（房租、通勤、每月先存……），再拿走已经花掉的，亮着的就是还能自由花的。
/// 点一下重新播一遍拿走的过程。
struct MoneyCard: View {
    let accent: Color

    @ObservedObject private var book = AccountBook.shared
    @ObservedObject private var wage = WageStore.shared
    @Environment(\.colorScheme) private var scheme
    /// 0 = 全亮，1 = 固定的拿走了，2 = 花掉的也拿走了
    @State private var phase = 2
    @State private var editing = false

    private let cash = Color(red: 0.90, green: 0.55, blue: 0.53)

    private var main: Color { Theme.textMain(scheme) }
    private var muted: Color { Theme.textMuted(scheme) }

    /// 一张纸币算多少钱：张数控制在一百六十张以内
    private func unit(_ income: Double) -> Double {
        income <= 16000 ? 100 : (income / 160 / 100).rounded(.up) * 100
    }

    var body: some View {
        let m = book.moneyThisMonth()
        let free = m.income - m.fixed - m.spent
        let u = unit(m.income)
        let total = max(0, Int((m.income / u).rounded(.up)))
        let fixedN = min(total, Int((m.fixed / u).rounded()))
        let spentN = min(total - fixedN, Int((m.spent / u).rounded()))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("这个月能自由花的")
                    .font(.app(12))
                    .foregroundStyle(muted)
                Spacer()
                Button { editing = true } label: {
                    Text("固定开支")
                        .font(.app(11.5, weight: .medium))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(free < 0 ? "超出 ¥" : "¥")
                    .font(.app(free < 0 ? 13 : 16, weight: .medium))
                    .foregroundStyle(free < 0 ? Color.red : cash)
                RollingNumber(text: WageStore.money(abs(free)), font: HomeType.number(28, weight: .semibold),
                              color: main)
            }
            Text("收入 \(BookFormat.money(m.income)) · 固定拿走 \(BookFormat.money(m.fixed)) · 已经花了 \(BookFormat.money(m.spent))")
                .font(.app(11))
                .foregroundStyle(muted)
                .lineLimit(2)

            if total == 0 {
                Text("工资页排了班、或者记了收入以后，这里按这个月一共能进多少钱来算")
                    .font(.app(12))
                    .foregroundStyle(muted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 24, maximum: 30), spacing: 5)], spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        note(state(i, total: total, fixedN: fixedN, spentN: spentN))
                            .animation(.easeOut(duration: 0.28).delay(Double(i) * 0.008), value: phase)
                    }
                }
                HStack(spacing: 12) {
                    legend(.free, "还能花")
                    legend(.fixed, "固定")
                    legend(.spent, "花掉了")
                    Spacer()
                    Text("一张 = ¥\(WageStore.money(u))")
                        .font(.app(10))
                        .foregroundStyle(muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .contentShape(Rectangle())
        .onTapGesture { replay() }
        .onAppear { replay() }
        .sheet(isPresented: $editing) { FixedEditor(accent: accent) }
    }

    private enum NoteState { case free, fixed, spent }

    private func state(_ i: Int, total: Int, fixedN: Int, spentN: Int) -> NoteState {
        if phase >= 1 && i >= total - fixedN { return .fixed }
        if phase >= 2 && i >= total - fixedN - spentN { return .spent }
        return .free
    }

    /// 一张纸币。拿走的时候不是直接变灰：**钞票从上边折起来翻过去**，底下露出留下的那个位置
    @ViewBuilder
    private func note(_ s: NoteState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        ZStack {
            // 底下：固定开支是一块灰，花掉的留一圈虚线
            shape.fill(main.opacity(s == .fixed ? 0.16 : 0))
            shape.strokeBorder(main.opacity(s == .spent ? 0.25 : 0), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
            // 钞票本身
            ZStack {
                shape.fill(LinearGradient(colors: [cash.opacity(0.95), cash.opacity(0.7)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.inset(by: 1.5).stroke(Color.white.opacity(0.55), lineWidth: 0.6)
                Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.6).frame(width: 6, height: 6).offset(x: 5)
                // 折起来的时候背面暗一点
                shape.fill(Color.black.opacity(s == .free ? 0 : 0.25))
            }
            .rotation3DEffect(.degrees(s == .free ? 0 : -100), axis: (x: 1, y: 0, z: 0),
                              anchor: .top, perspective: 0.6)
            .opacity(s == .free ? 1 : 0)
        }
        .frame(height: 14)
    }

    private func legend(_ s: NoteState, _ t: String) -> some View {
        HStack(spacing: 4) {
            note(s).frame(width: 18)
            Text(t).font(.app(10)).foregroundStyle(muted)
        }
    }

    private func replay() {
        phase = 0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation { phase = 1 }
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation { phase = 2 }
        }
    }
}

/// 固定开支：每个月一开始就要拿走的（房租、通勤、话费、每月先存）
struct FixedEditor: View {
    let accent: Color

    @ObservedObject private var book = AccountBook.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [Row] = []

    struct Row: Identifiable {
        var id = UUID()
        var name = ""
        var amount = ""
        var saving = false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        Text("每个月一开始就要拿走的钱。填在这里的不用再在记账里记一笔。")
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach($rows) { $r in
                            HStack(spacing: 10) {
                                TextField("名字，比如：房租", text: $r.name)
                                    .font(.app(14))
                                TextField("金额", text: $r.amount)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.app(14, weight: .medium))
                                    .frame(width: 80)
                                Button { r.saving.toggle() } label: {
                                    Text(r.saving ? "存下" : "花掉")
                                        .font(.app(11))
                                        .foregroundStyle(r.saving ? .white : accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(r.saving ? accent : accent.opacity(0.1)))
                                }
                                .buttonStyle(.plain)
                                Button { rows.removeAll { $0.id == r.id } } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                .buttonStyle(.plain)
                            }
                            .glassCard(padding: 12)
                        }
                        Button { rows.append(Row()) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("加一项")
                            }
                            .font(.app(14, weight: .medium))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("固定开支")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存") { save() }
                        .foregroundStyle(accent)
                }
            }
        }
        .onAppear {
            rows = book.fixed.map { Row(id: $0.id, name: $0.name, amount: WageStore.money($0.amount), saving: $0.saving) }
            if rows.isEmpty { rows = [Row(name: "房租"), Row(name: "每月先存", saving: true)] }
        }
    }

    private func save() {
        let keep = Set(rows.map(\.id))
        for f in book.fixed where !keep.contains(f.id) { book.deleteFixed(f.id) }
        for r in rows {
            let name = r.name.trimmingCharacters(in: .whitespaces)
            let amt = Double(r.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            if name.isEmpty || amt <= 0 {
                book.deleteFixed(r.id)
                continue
            }
            book.saveFixed(FixedItem(id: r.id, name: name, amount: amt, saving: r.saving))
        }
        dismiss()
    }
}
