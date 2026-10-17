import SwiftUI

/// 抽屉那一页：他留下的便签和像素小画，按时间倒着排。打开就算看过了
struct DrawerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DrawerStore.shared
    /// 这一次打开之前就没看过的（这一次里还标着「新」）
    @State private var fresh: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if store.items.isEmpty {
                    EmptyNote(icon: "tray", title: "抽屉还是空的",
                              hint: "他想留给你、又不用你马上回的话，或者一幅很小的画，会悄悄放在这里。")
                        .padding(.top, 50)
                }
                ForEach(store.items) { item in
                    card(item)
                        .contextMenu {
                            Button(role: .destructive) { store.remove(item.id) } label: {
                                Label("拿出抽屉", systemImage: Icon.trash)
                            }
                        }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .navigationTitle("抽屉")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fresh = Set(store.items.filter { !$0.seen }.map(\.id))
            store.markSeen()
        }
    }

    private func card(_ item: DrawerItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.kind == "pixel" {
                DrawerPixel(item: item)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else if item.kind == "riddle" && !item.unlocked {
                DrawerLock(item: item, accent: app.settings.accentColor)
            } else {
                Text(item.text)
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            HStack {
                Text(item.at.formatted(date: .abbreviated, time: .shortened))
                    .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                if fresh.contains(item.id) {
                    Text("新").font(.app(10.5, weight: .medium)).foregroundStyle(app.settings.accentColor)
                }
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
                Text("封着的一张")
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
                    Text("拆开")
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
