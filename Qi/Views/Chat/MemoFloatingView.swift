import SwiftUI

/// 置顶的备忘会缩在聊天页边上，只露出一小节。
/// 拉出来是个能拖的浮窗：
///   · 在左边就往右划完成，在右边就往左划完成——手往外推，方向是顺的
///   · 划完显示五秒「已完成」，点一下能说"手误"，立刻挂回去
///   · 长按三秒是取消这条，会进历史，记着是谁取消的
///   · 点叉是收起来，会先问一句，不然太容易误碰
struct MemoFloatingView: View {

    @ObservedObject private var store = MemoStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 停在左边还是右边
    @AppStorage("memoDockLeft") private var dockLeft = false
    @AppStorage("memoDockY") private var dockY: Double = 0.42

    @State private var open = false
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var justDone: Memo?
    @State private var doneTimer: Task<Void, Never>?
    @State private var pressProgress: Double = 0
    @State private var pressTask: Task<Void, Never>?
    @State private var confirmClose = false

    private var list: [Memo] { store.pinned }
    private var current: Memo? {
        list.indices.contains(index) ? list[index] : list.first
    }
    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let memo = current {
                    Group {
                        if let done = justDone {
                            doneChip(done)
                        } else if open {
                            panel(memo, width: min(geo.size.width * 0.62, 250))
                        } else {
                            handle(memo)
                        }
                    }
                    .position(
                        x: dockLeft ? edgeX(true, geo) : edgeX(false, geo),
                        y: min(max(90, geo.size.height * dockY + drag.height), geo.size.height - 120)
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: open)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: dockLeft)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .confirmationDialog("把这条收起来？", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("收起来", role: .destructive) {
                if let m = current { store.togglePin(m.id) }
                open = false
            }
            Button("算了", role: .cancel) {}
        } message: {
            Text("收起来只是不挂在聊天页了，备忘页里还在。")
        }
    }

    private func edgeX(_ left: Bool, _ geo: GeometryProxy) -> CGFloat {
        if open {
            let w = min(geo.size.width * 0.62, 250)
            return left ? w / 2 + 14 : geo.size.width - w / 2 - 14
        }
        return left ? 16 : geo.size.width - 16
    }

    // MARK: 收起来的样子：只露一小节

    private func handle(_ memo: Memo) -> some View {
        let label = memo.badge.isEmpty ? String(memo.text.prefix(4)) : memo.badge
        return VStack(spacing: 3) {
            ForEach(Array(label.prefix(5)).indices, id: \.self) { i in
                Text(String(Array(label.prefix(5))[i]))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(memo.color ?? Theme.textSoft(scheme))
            }
            if list.count > 1 {
                Text("\(list.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 10)
        .glassBackground(radius: 11, strength: app.settings.glassOpacity, extra: 0.2)
        .contentShape(Rectangle())
        .onTapGesture {
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            open = true
        }
        .gesture(dockGesture)
    }

    // MARK: 拉出来的浮窗

    private func panel(_ memo: Memo, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !memo.badge.isEmpty {
                    Text(memo.badge)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(app.settings.accentColor.opacity(0.22)))
                }
                Spacer(minLength: 0)
                if list.count > 1 {
                    Text("\(index + 1)/\(list.count)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                Button {
                    confirmClose = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            Text(memo.text)
                .font(.system(size: 14))
                .foregroundStyle(memo.color ?? Theme.textMain(scheme))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !memo.author.isEmpty {
                Text(memo.author + " 写的")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            // 长按取消的那圈进度
            if pressProgress > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.textMuted(scheme).opacity(0.18))
                        Capsule()
                            .fill(Color.red.opacity(0.6))
                            .frame(width: g.size.width * pressProgress)
                    }
                }
                .frame(height: 2.5)
            }

            HStack(spacing: 4) {
                Image(systemName: dockLeft ? "arrow.right" : "arrow.left")
                    .font(.system(size: 8))
                Text(dockLeft ? "往右划完成" : "往左划完成")
                Spacer(minLength: 0)
                Text("长按取消")
            }
            .font(.system(size: 9))
            .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity, extra: 0.15)
        .offset(x: drag.width)
        .gesture(panelGesture(memo, width: width))
        .onTapGesture {
            // 多条的时候点一下翻到下一条
            if list.count > 1 {
                index = (index + 1) % list.count
            }
        }
    }

    // MARK: 完成之后那五秒

    private func doneChip(_ memo: Memo) -> some View {
        Button {
            // 手误的话，点它就能挂回去
            doneTimer?.cancel()
            store.undoComplete(memo.id)
            justDone = nil
            open = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.green.opacity(0.8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("已完成")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("点一下说手误")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassBackground(radius: 14, strength: app.settings.glassOpacity, extra: 0.15)
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: 手势

    /// 收起来的时候：上下拖换位置，横着拖换边
    private var dockGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in drag = CGSize(width: 0, height: v.translation.height) }
            .onEnded { v in
                if let h = currentHeight {
                    dockY = min(0.86, max(0.12, dockY + v.translation.height / h))
                }
                if abs(v.translation.width) > 60 {
                    dockLeft = v.translation.width < 0
                }
                drag = .zero
            }
    }

    /// 拉开之后：往屏幕外那侧划就是完成
    private func panelGesture(_ memo: Memo, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                // 只认往外的方向，往里拖不动
                let outward = dockLeft ? max(0, v.translation.width) : min(0, v.translation.width)
                drag = CGSize(width: outward, height: 0)
            }
            .onEnded { v in
                let far = abs(v.translation.width) > width * 0.42
                let rightDirection = dockLeft ? v.translation.width > 0 : v.translation.width < 0
                if far && rightDirection {
                    finish(memo)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = .zero }
                }
            }
            .simultaneously(with:
                LongPressGesture(minimumDuration: 3)
                    .onChanged { _ in startPress() }
                    .onEnded { _ in cancelMemo(memo) }
            )
    }

    private func startPress() {
        guard pressTask == nil else { return }
        pressTask = Task { @MainActor in
            for step in 1...30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                pressProgress = Double(step) / 30
            }
        }
    }

    private func finish(_ memo: Memo) {
        pressTask?.cancel(); pressTask = nil; pressProgress = 0
        store.complete(memo.id, by: me)
        if app.settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        drag = .zero
        open = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { justDone = memo }

        doneTimer?.cancel()
        doneTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) { justDone = nil }
        }
    }

    private func cancelMemo(_ memo: Memo) {
        pressTask?.cancel(); pressTask = nil
        withAnimation { pressProgress = 0 }
        store.cancel(memo.id, by: me)
        if app.settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        open = false
        drag = .zero
    }

    private var currentHeight: CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.height
    }
}
