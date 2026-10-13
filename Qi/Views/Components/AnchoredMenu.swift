import SwiftUI

/// 贴着点的那个东西弹出来的小菜单。
///
/// 系统的 confirmationDialog 在大块画面上会弹成一个挂在正中间的气泡，
/// 跟她点的那件东西隔得老远。这一个记下手指点的位置（全局坐标），
/// 在那个点正上方弹出、带一个小尖角指着它；上面放不下就放下面。
struct AnchorMenuItem: Identifiable {
    let id = UUID()
    let title: String
    var destructive = false
    let action: () -> Void
}

struct AnchorMenuState {
    var title: String
    var items: [AnchorMenuItem]
    /// 手指点的位置（全局坐标）
    var at: CGPoint
}

private struct AnchoredMenuView: View {
    let menu: AnchorMenuState
    let local: CGPoint
    let area: CGSize
    let dismiss: () -> Void

    @Environment(\.colorScheme) private var scheme

    private let width: CGFloat = 220
    private let rowH: CGFloat = 40

    var body: some View {
        let listH = min(area.height * 0.6, CGFloat(menu.items.count) * rowH)
        let h = listH + 38
        let above = local.y - h - 14 > 8
        let y = above ? local.y - 12 - h / 2 : local.y + 12 + h / 2
        let x = min(area.width - width / 2 - 10, max(width / 2 + 10, local.x))
        ZStack(alignment: .topLeading) {
            // 点外面任何地方收起来
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            VStack(spacing: 0) {
                Text(menu.title)
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(1)
                    .frame(height: 36)
                Divider().opacity(0.4)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(menu.items) { item in
                            Button {
                                dismiss()
                                item.action()
                            } label: {
                                Text(item.title)
                                    .font(.app(14))
                                    .foregroundStyle(item.destructive ? Color.red : Theme.textMain(scheme))
                                    .frame(maxWidth: .infinity, minHeight: rowH)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if item.id != menu.items.last?.id { Divider().opacity(0.25).padding(.horizontal, 12) }
                        }
                    }
                }
                .frame(height: listH)
                .scrollDisabled(CGFloat(menu.items.count) * rowH <= listH)
            }
            .frame(width: width)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.12 : 0.5), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .position(x: x, y: y)
            // 小尖角指着她点的那个点
            Triangle(up: !above)
                .fill(.regularMaterial)
                .frame(width: 16, height: 9)
                .position(x: min(x + width / 2 - 18, max(x - width / 2 + 18, local.x)),
                          y: above ? local.y - 12 + 4 : local.y + 12 - 4)
        }
        .frame(width: area.width, height: area.height)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct Triangle: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

extension View {
    /// 把贴着点击位置的小菜单挂在这一层（这一层要盖住整个画面）
    func anchoredMenu(_ menu: Binding<AnchorMenuState?>) -> some View {
        overlay {
            GeometryReader { g in
                if let m = menu.wrappedValue {
                    let o = g.frame(in: .global).origin
                    AnchoredMenuView(menu: m, local: CGPoint(x: m.at.x - o.x, y: m.at.y - o.y),
                                     area: g.size, dismiss: { menu.wrappedValue = nil })
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: menu.wrappedValue == nil)
    }
}
