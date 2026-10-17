import SwiftUI

/// 摊销的那几样东西：隔几天在 App 顶上问一句「还在用吗」。
///
/// 挂在根视图上，哪一页都会出来；五秒没碰就自己收起来。
/// 点它（或者「编辑」）直接打开那一笔；「已用完」就把剩下没摊完的那份记在今天。
struct BookReminderLayer: View {
    let accent: Color

    @ObservedObject private var book = AccountBook.shared
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @State private var current: Expense?
    @State private var editing: ExpenseRef?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack {
            if let e = current {
                banner(e)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: current?.id)
        .task {
            // 开着的时候隔一阵看一眼（跨过零点、到了该问的那天）
            while !Task.isCancelled {
                check()
                try? await Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)
            }
        }
        .onChange(of: phase) { _, p in if p == .active { check() } }
        .sheet(item: $editing) { ref in
            ExpenseEditor(start: ref.expense, isNew: false, accent: accent)
        }
    }

    private func check() {
        guard current == nil, editing == nil, phase == .active,
              let e = book.dueReminder() else { return }
        book.asked(e.id)
        current = e
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            current = nil
        }
    }

    private func edit(_ e: Expense) {
        hideTask?.cancel()
        current = nil
        editing = ExpenseRef(expense: book.expense(e.id) ?? e, isNew: false)
    }

    private func banner(_ e: Expense) -> some View {
        let c = book.category(e.category)
        let used = book.daysUsed(e)
        var sub = "已经用了 \(used) 天"
        if let per = book.perDay(e) { sub += " · 每天 " + BookFormat.money(per) }
        return HStack(spacing: 12) {
            CategoryIcon(category: c, size: 36, tint: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("「\(e.name.isEmpty ? c.name : e.name)」还在用吗？")
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                Text(sub)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("编辑") { edit(e) }
                .font(.app(12.5, weight: .medium))
                .foregroundStyle(accent)
                .buttonStyle(.plain)
            Button {
                hideTask?.cancel()
                book.markUsedUp(e.id)
                current = nil
            } label: {
                Text("已用完")
                    .font(.app(12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.5), lineWidth: 0.6))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { edit(e) }
        .gesture(DragGesture(minimumDistance: 10).onEnded { v in
            if v.translation.height < -12 { hideTask?.cancel(); current = nil }
        })
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// 他提了一笔账：卡片摆在屏幕下半，同意 / 修改（写一句哪里不对）/ 先放着
struct BookAskLayer: View {
    let proposal: BookProposal
    let accent: Color
    let answer: (AppState.BookAnswer) -> Void

    @State private var revising = false
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { if !revising { answer(.later) } else { focused = false } }
            VStack(spacing: 10) {
                if revising {
                    reviseBox
                } else {
                    ProposalCard(proposal: proposal, accent: accent, reviseTitle: "修改",
                                 onApprove: { answer(.approved) },
                                 onRevise: {
                                     withAnimation(.easeOut(duration: 0.2)) { revising = true }
                                     focused = true
                                 })
                    Button { answer(.later) } label: {
                        Text("先放着，回头在记账页确认")
                            .font(.app(12))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var reviseBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("哪里要改？")
                .font(.app(15, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            TextField("比如：是 18 块，分类算零食", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .focused($focused)
                .font(.app(14))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.textMain(scheme).opacity(0.05)))
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { revising = false }
                } label: {
                    Text("返回")
                        .font(.app(14))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Button {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    answer(.revise(t))
                } label: {
                    Text("让他改")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }
}
