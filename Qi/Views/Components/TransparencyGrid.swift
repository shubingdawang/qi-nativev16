import SwiftUI

/// 透明底的棋盘格（看图有没有透明的地方）
struct TransparencyGrid: View {
    var side: CGFloat = 10
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let light = scheme == .dark
                ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
            let dark = scheme == .dark
                ? Color.white.opacity(0.02) : Color.black.opacity(0.015)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : side
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: side, height: side)),
                             with: .color(light))
                    x += side * 2
                }
                y += side
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}
