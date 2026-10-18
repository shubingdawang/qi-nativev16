import SwiftUI

/// 遮挡截图：往聊天上贴自己的表情，盖住不想给别人看的地方，点「完成」把按钮都藏起来再截图。
///
/// 贴纸**贴在聊天内容上**（`MaskStickersOverlay` 挂在消息列表里面），跟着聊天一起滚，
/// 盖住哪句就一直盖着哪句。底下那一排表情和按钮（`ChatMaskLayer`）浮在屏幕上。
@MainActor
final class MaskBoard: ObservableObject {
    static let shared = MaskBoard()

    struct Item: Identifiable {
        let id = UUID()
        let image: UIImage
        /// 在聊天内容里的位置（不是屏幕位置）
        var pos: CGPoint
        var size: CGFloat = 110
        var angle: Angle = .zero
    }

    @Published var active = false
    @Published var items: [Item] = []
    @Published var selected: UUID?
    @Published var done = false

    /// 聊天内容左上角此刻在屏幕上的位置。滚一下变一次，**不发通知**（只在贴新的一张时读）
    var origin: CGPoint = .zero

    func add(_ sticker: Sticker, atScreen p: CGPoint) {
        let url = StickerStore.shared.url(of: sticker)
        guard let img = UIImage(contentsOfFile: url.path) else { return }
        let k = CGFloat(items.count % 5)
        let item = Item(image: img, pos: CGPoint(x: p.x - origin.x + k * 14, y: p.y - origin.y + k * 18))
        items.append(item)
        selected = item.id
    }

    func reset() {
        items = []
        selected = nil
        done = false
        active = false
    }
}

/// 贴在聊天内容上的那几张（挂在消息列表的内容里，跟着一起滚）
struct MaskStickersOverlay: View {
    @ObservedObject private var board = MaskBoard.shared
    let accent: Color

    var body: some View {
        if board.active {
            GeometryReader { g in
                let origin = g.frame(in: .global).origin
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .onAppear { board.origin = origin }
                        .onChange(of: origin) { _, o in board.origin = o }
                    ForEach($board.items) { $item in
                        MaskSticker(item: $item,
                                    selected: board.selected == item.id && !board.done,
                                    done: board.done,
                                    accent: accent,
                                    onTap: { if !board.done { board.selected = item.id } },
                                    onDelete: {
                                        board.items.removeAll { $0.id == item.id }
                                        board.selected = nil
                                    },
                                    onLong: {
                                        if board.done { withAnimation(.easeOut(duration: 0.2)) { board.done = false } }
                                    })
                    }
                }
            }
        }
    }
}

/// 浮在屏幕上的那一排表情和按钮
struct ChatMaskLayer: View {
    let accent: Color
    let onExit: () -> Void

    @ObservedObject private var board = MaskBoard.shared
    @ObservedObject private var library = StickerStore.shared
    @Environment(\.colorScheme) private var scheme
    @State private var hint = false

    /// 自己的表情在前，他的在后
    private var palette: [Sticker] {
        library.stickers.filter(\.isUser) + library.stickers.filter { !$0.isUser }
    }

    var body: some View {
        GeometryReader { g in
            let center = CGPoint(x: g.frame(in: .global).midX, y: g.frame(in: .global).minY + g.size.height * 0.4)
            ZStack {
                if !board.done {
                    VStack {
                        Spacer()
                        tray(center: center)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if hint {
                    VStack {
                        Text("可以截图了 · 长按任意一个表情回到编辑")
                            .font(.app(12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(.top, 10)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: board.done)
        .animation(.easeOut(duration: 0.25), value: hint)
    }

    private func tray(center: CGPoint) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(board.items.isEmpty ? "点一个表情贴上去，拖动换位置，拉右下角的圆点缩放，两指旋转"
                                         : "表情跟着聊天一起滚 · 选中的右上角 × 可以撕掉")
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(palette) { s in
                        Button {
                            board.add(s, atScreen: center)
                        } label: {
                            StickerImage(sticker: s, size: 52)
                                .frame(width: 56, height: 56)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.textMain(scheme).opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                    if palette.isEmpty {
                        Text("表情库里还没有表情")
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
            }
            HStack(spacing: 10) {
                Button { onExit() } label: {
                    Text("退出")
                        .font(.app(14))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Button {
                    board.items.removeAll()
                    board.selected = nil
                } label: {
                    Text("清空")
                        .font(.app(14))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(board.items.isEmpty)
                Button {
                    board.selected = nil
                    board.done = true
                    hint = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        hint = false
                    }
                } label: {
                    Text("完成")
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
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// 贴上去的一张：拖着走、拉右下角圆点缩放、两指捏合缩放旋转
private struct MaskSticker: View {
    @Binding var item: MaskBoard.Item
    let selected: Bool
    let done: Bool
    let accent: Color
    let onTap: () -> Void
    let onDelete: () -> Void
    let onLong: () -> Void

    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var turn: Angle = .zero
    @State private var grow: CGFloat = 0

    private var side: CGFloat { min(480, max(30, item.size * pinch + grow)) }

    var body: some View {
        Image(uiImage: item.image)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(accent, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.white, accent)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 11, y: -11)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    // 拉这个圆点放大缩小
                    Circle()
                        .fill(accent)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .frame(width: 22, height: 22)
                        .offset(x: 11, y: 11)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in grow = (v.translation.width + v.translation.height) / 2 }
                                .onEnded { _ in
                                    item.size = min(480, max(30, item.size + grow))
                                    grow = 0
                                }
                        )
                }
            }
            .rotationEffect(item.angle + turn)
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.5, perform: onLong)
            .gesture(
                SimultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { v in
                            onTap()
                            drag = v.translation
                        }
                        .onEnded { v in
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                item.pos.x += v.translation.width
                                item.pos.y += v.translation.height
                                drag = .zero
                            }
                        },
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { v in pinch = v.magnification }
                            .onEnded { v in
                                item.size = min(480, max(30, item.size * v.magnification))
                                pinch = 1
                            },
                        RotateGesture()
                            .onChanged { v in turn = v.rotation }
                            .onEnded { v in
                                item.angle += v.rotation
                                turn = .zero
                            }
                    )
                ),
                including: done ? .subviews : .all
            )
            .position(x: item.pos.x + drag.width, y: item.pos.y + drag.height)
            .transaction { $0.animation = nil }
    }
}
