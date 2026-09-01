import SwiftUI

/// 承诺页 —— 他答应过的事。
///
/// 为什么单独一页、不并进记忆库：**记忆是发生过什么，承诺是还欠着什么**。
/// 后者有状态（做没做到），而且没做到的那些每次醒来都该重新摆到他面前。
/// 混进记忆库就沉底了——一条五百分之一，翻不到。
///
/// 记录有两条路，都落进同一个盒子：
///   · 他说话时随手写 `[[promise:...]]`，标记会被剥掉，她看到的还是正常一句话
///   · 他主动调 `make_promise` 郑重记一笔
struct PromiseView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = MemoryStore.shared

    @State private var showDone = false
    @State private var adding = false
    @State private var draft = ""
    @State private var due = ""

    private var open: [Promise] { store.openPromises }
    private var kept: [Promise] {
        store.promises.filter(\.done).sorted { ($0.doneAt ?? "") > ($1.doneAt ?? "") }
    }

    var body: some View {
        ZStack {
            WallpaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    if open.isEmpty && kept.isEmpty {
                        empty
                    }

                    if !open.isEmpty {
                        header("还欠着的", count: open.count)
                        ForEach(open) { p in card(p) }
                    }

                    if !kept.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                showDone.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("做到了的")
                                    .font(.app(12, weight: .medium))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                Text("\(kept.count)")
                                    .font(.app(11))
                                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                                Image(systemName: "chevron.right")
                                    .font(.app(10, weight: .semibold))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .rotationEffect(.degrees(showDone ? 90 : 0))
                                Spacer()
                            }
                            .padding(.leading, 6)
                            .padding(.top, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showDone {
                            ForEach(kept) { p in card(p) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("承诺")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draft = ""; due = ""; adding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $adding) { addSheet }
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
            Text("\(count)")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
            Spacer()
        }
        .padding(.leading, 6)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有欠着的事")
                .font(.app(15, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            Text("模型在对话中作出承诺时自动记入。也可点击右上角手动添加。")
                .font(.app(12))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassBackground(radius: 18, strength: app.settings.glassOpacity)
        .padding(.top, 40)
    }

    private func card(_ p: Promise) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                toggle(p)
            } label: {
                Image(systemName: p.done ? "checkmark.circle.fill" : "circle")
                    .font(.app(20))
                    .foregroundStyle(p.done
                                     ? app.settings.accentColor
                                     : Theme.textMuted(scheme).opacity(0.55))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(p.text)
                    .font(.app(14))
                    .foregroundStyle(p.done ? Theme.textMuted(scheme) : Theme.textMain(scheme))
                    .strikethrough(p.done, color: Theme.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(String(p.madeAt.prefix(10)) + " 答应的")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    if let d = p.due, !d.isEmpty {
                        Text(dueLabel(d, done: p.done))
                            .font(.app(10, weight: .medium))
                            .foregroundStyle(overdue(d) && !p.done
                                             ? Color.red.opacity(0.85)
                                             : Theme.textMuted(scheme))
                    }
                    if p.done, let at = p.doneAt {
                        Text("· " + String(at.prefix(10)) + " 做到了")
                            .font(.app(10))
                            .foregroundStyle(app.settings.accentColor.opacity(0.8))
                    }
                }
            }
        }
        .padding(13)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
        // ⚠ `contextMenu` 认的是真画出来的那几个像素，内容少的那几条底下是空的、长按收不到。
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                toggle(p)
            } label: {
                Label(p.done ? "标成还欠着" : "标成做到了",
                      systemImage: p.done ? "arrow.uturn.backward" : "checkmark")
            }
            Button(role: .destructive) {
                store.promises.removeAll { $0.id == p.id }
                store.savePromises()
            } label: {
                Label("删掉", systemImage: "trash")
            }
        }
    }

    private func dueLabel(_ due: String, done: Bool) -> String {
        if done { return "说好 \(due) 之前" }
        return overdue(due) ? "\(due) 已经过了" : "说好 \(due) 之前"
    }

    private func overdue(_ due: String) -> Bool {
        due < MemoryStore.today
    }

    private func toggle(_ p: Promise) {
        guard let i = store.promises.firstIndex(where: { $0.id == p.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            store.promises[i].done.toggle()
            store.promises[i].doneAt = store.promises[i].done ? MemoryStore.now : nil
        }
        store.savePromises()
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: 自己加一条

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("他答应了什么")
                                .font(.app(14, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            TextField("例如：周末一起去那家花店", text: $draft, axis: .vertical)
                                .lineLimit(2...5)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.softFillDeep))
                        }
                        .glassCard()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("说好什么时候之前（可不填）")
                                .font(.app(14, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            TextField("2026-09-01", text: $due)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.softFillDeep))
                        }
                        .glassCard()
                    }
                    .padding(16)
                }
            }
            .navigationTitle("记一条")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { adding = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("记下") {
                        store.addPromise(draft, due: due.isEmpty ? nil : due)
                        adding = false
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
