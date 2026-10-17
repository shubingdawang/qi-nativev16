import SwiftUI

/// 遮挡截图：往聊天页上贴自己的表情，盖住不想给别人看的地方，点「完成」把按钮都藏起来再截图。
///
/// 表情贴在屏幕上不跟着聊天滚——先把要截的那一段翻到屏幕上，再贴。
/// 空白的地方照样能滑聊天。完成以后长按任意一个表情回到编辑。
struct ChatMaskLayer: View {
    let accent: Color
    let onExit: () -> Void

    struct Item: Identifiable {
        let id = UUID()
        let sticker: Sticker
        var pos: CGPoint
        var size: CGFloat = 110
        var angle: Angle = .zero
    }

    @ObservedObject private var library = StickerStore.shared
    @Environment(\.colorScheme) private var scheme
    @State private var items: [Item] = []
    @State private var selected: UUID?
    @State private var done = false
    @State private var hint = false

    /// 自己的表情在前，他的在后
    private var palette: [Sticker] {
        library.stickers.filter(\.isUser) + library.stickers.filter { !$0.isUser }
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                ForEach($items) { $item in
                    MaskSticker(item: $item,
                                selected: selected == item.id && !done,
                                done: done,
                                accent: accent,
                                onTap: { if !done { selected = item.id } },
                                onDelete: {
                                    items.removeAll { $0.id == item.id }
                                    selected = nil
                                },
                                onLong: {
                                    if done { withAnimation(.easeOut(duration: 0.2)) { done = false } }
                                })
                }

                if !done {
                    VStack {
                        Spacer()
                        tray(center: CGPoint(x: g.size.width / 2, y: g.size.height * 0.4))
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
        .animation(.easeOut(duration: 0.2), value: done)
        .animation(.easeOut(duration: 0.25), value: hint)
    }

    private func tray(center: CGPoint) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(items.isEmpty ? "点一个表情贴上去，拖动换位置，两指缩放旋转" : "选中的表情右上角 × 可以撕掉")
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(palette) { s in
                        Button {
                            // 一张一张往下错开一点，不全叠在正中间
                            let k = CGFloat(items.count % 5)
                            let item = Item(sticker: s, pos: CGPoint(x: center.x + k * 14, y: center.y + k * 18))
                            items.append(item)
                            selected = item.id
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
                Button {
                    onExit()
                } label: {
                    Text("退出")
                        .font(.app(14))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Button {
                    items.removeAll()
                    selected = nil
                } label: {
                    Text("清空")
                        .font(.app(14))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)
                Button {
                    selected = nil
                    done = true
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

/// 贴上去的一张：拖、两指缩放旋转、选中时虚线框和 ×
private struct MaskSticker: View {
    @Binding var item: ChatMaskLayer.Item
    let selected: Bool
    let done: Bool
    let accent: Color
    let onTap: () -> Void
    let onDelete: () -> Void
    let onLong: () -> Void

    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var turn: Angle = .zero

    var body: some View {
        let side = min(420, max(30, item.size * pinch))
        ZStack {
            Rectangle().fill(Color.white.opacity(0.001))
            StickerImage(sticker: item.sticker, size: side)
        }
        .frame(width: side, height: side)
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
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white, accent)
                }
                .buttonStyle(.plain)
                .offset(x: 10, y: -10)
            }
        }
        .rotationEffect(item.angle + turn)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.5, perform: onLong)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    guard !done else { return }
                    onTap()
                    drag = v.translation
                }
                .onEnded { v in
                    guard !done else { return }
                    item.pos.x += v.translation.width
                    item.pos.y += v.translation.height
                    drag = .zero
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { v in if !done { pinch = v.magnification } }
                .onEnded { v in
                    guard !done else { return }
                    item.size = min(420, max(30, item.size * v.magnification))
                    pinch = 1
                }
        )
        .simultaneousGesture(
            RotateGesture()
                .onChanged { v in if !done { turn = v.rotation } }
                .onEnded { v in
                    guard !done else { return }
                    item.angle += v.rotation
                    turn = .zero
                }
        )
        .position(x: item.pos.x + drag.width, y: item.pos.y + drag.height)
    }
}
