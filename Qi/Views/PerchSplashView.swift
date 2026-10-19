import SwiftUI

/// 开屏「枝头」：栖，就是鸟落在枝头。
///
/// 一根细枝从左边长出来，冒几片叶子；clawd 从右边蹦上来落在枝头，枝子被压得弯一下再弹回去；
/// 「栖」字像墨落在纸上那样晕开；停一会儿整屏淡出进 App。轻点任何地方直接进。
struct PerchSplashView: View {

    var onEnter: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var grow: CGFloat = 0
    @State private var leaves = false
    @State private var landed = false
    @State private var hop: CGFloat = 0
    @State private var dip: CGFloat = 0
    @State private var ink = false
    @State private var blink = false
    @State private var leaving = false

    private var paper: Color {
        scheme == .dark ? Color(red: 0.11, green: 0.12, blue: 0.16) : Color(red: 0.97, green: 0.955, blue: 0.93)
    }
    private var branchInk: Color {
        scheme == .dark ? Color(red: 0.62, green: 0.55, blue: 0.47) : Color(red: 0.42, green: 0.33, blue: 0.25)
    }
    private var leaf: Color {
        scheme == .dark ? Color(red: 0.52, green: 0.64, blue: 0.52) : Color(red: 0.55, green: 0.66, blue: 0.52)
    }
    private var textInk: Color {
        scheme == .dark ? Color(red: 0.92, green: 0.90, blue: 0.86) : Color(red: 0.2, green: 0.18, blue: 0.16)
    }

    private static let dateText: String = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 · EEEE"
        return f.string(from: Date())
    }()

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let y0 = h * 0.42
            // 枝头那一点（clawd 落脚的地方）
            let perch = CGPoint(x: w * 0.62, y: y0 - 6 + dip)
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                paper.opacity(0.9)

                // 枝子：从左边长出来，往右上微微翘
                BranchShape(dip: dip)
                    .trim(from: 0, to: grow)
                    .stroke(branchInk, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .frame(width: w, height: h)
                // 两根小杈
                Group {
                    TwigShape(at: CGPoint(x: w * 0.30, y: y0 + 8), to: CGPoint(x: w * 0.36, y: y0 - 18))
                        .trim(from: 0, to: max(0, (grow - 0.4) / 0.6))
                        .stroke(branchInk, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    TwigShape(at: CGPoint(x: w * 0.48, y: y0 + 2), to: CGPoint(x: w * 0.52, y: y0 + 22))
                        .trim(from: 0, to: max(0, (grow - 0.55) / 0.45))
                        .stroke(branchInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
                .frame(width: w, height: h)
                // 叶子
                ForEach(Array(leafSpots(w: w, y0: y0).enumerated()), id: \.offset) { i, s in
                    LeafShape()
                        .fill(leaf.opacity(0.9))
                        .frame(width: 18, height: 10)
                        .rotationEffect(.degrees(s.angle))
                        .scaleEffect(leaves ? 1 : 0.01, anchor: .leading)
                        .animation(.spring(response: 0.42, dampingFraction: 0.6).delay(Double(i) * 0.09), value: leaves)
                        .position(x: s.x, y: s.y + dip * (s.x / w))
                }

                // clawd：从右边蹦上来，落在枝头
                PixelSpriteView(sprite: blink ? ClawdSprites.blink : ClawdSprites.idle, scale: 2.2)
                    .frame(width: 36 * 2.2, height: 36 * 2.2)
                    .scaleEffect(x: -1, y: 1)
                    .position(x: landed ? perch.x : w + 60,
                              y: (landed ? perch.y : y0 - 40) - 36 * 2.2 * 0.38 - hop)

                // 栖
                VStack(spacing: 10) {
                    Text("栖")
                        .font(.system(size: 64, weight: .regular, design: .serif))
                        .foregroundStyle(textInk)
                        .blur(radius: ink ? 0 : 10)
                        .opacity(ink ? 1 : 0)
                        .scaleEffect(ink ? 1 : 1.12)
                    Text(Self.dateText)
                        .font(.system(size: 12, design: .serif))
                        .tracking(3)
                        .foregroundStyle(textInk.opacity(0.55))
                        .opacity(ink ? 1 : 0)
                }
                .position(x: w / 2, y: h * 0.64)
            }
            .opacity(leaving ? 0 : 1)
            .scaleEffect(leaving ? 1.04 : 1)
            .contentShape(Rectangle())
            .onTapGesture { leave() }
            .onAppear { play() }
        }
        .ignoresSafeArea()
    }

    private struct LeafSpot { let x: CGFloat; let y: CGFloat; let angle: Double }

    private func leafSpots(w: CGFloat, y0: CGFloat) -> [LeafSpot] {
        [LeafSpot(x: w * 0.36 + 6, y: y0 - 20, angle: -50),
         LeafSpot(x: w * 0.22, y: y0 + 4, angle: 25),
         LeafSpot(x: w * 0.52 + 6, y: y0 + 24, angle: 40),
         LeafSpot(x: w * 0.44, y: y0 - 6, angle: -30)]
    }

    private func play() {
        withAnimation(.easeOut(duration: 0.75)) { grow = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { leaves = true }
        // 蹦过来：横着滑过去，竖着先高后低
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.42)) { landed = true }
            withAnimation(.easeOut(duration: 0.2)) { hop = 46 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeIn(duration: 0.22)) { hop = 0 }
            }
        }
        // 落地：枝子被压弯一下再弹回来，眨一下眼
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.22) {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { dip = 7 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { dip = 0 }
            }
            blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { blink = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            withAnimation(.easeOut(duration: 0.7)) { ink = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) { leave() }
    }

    private func leave() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: 0.35)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { onEnter() }
    }
}

/// 主枝：从左边出来，微微往上翘，枝头一点被压得往下（`dip`）
private struct BranchShape: Shape {
    var dip: CGFloat
    var animatableData: CGFloat {
        get { dip }
        set { dip = newValue }
    }

    func path(in r: CGRect) -> Path {
        let y0 = r.height * 0.42
        var p = Path()
        p.move(to: CGPoint(x: -10, y: y0 + 18))
        p.addCurve(to: CGPoint(x: r.width * 0.70, y: y0 - 8 + dip),
                   control1: CGPoint(x: r.width * 0.25, y: y0 + 6),
                   control2: CGPoint(x: r.width * 0.5, y: y0 + 2 + dip * 0.5))
        return p
    }
}

private struct TwigShape: Shape {
    let at: CGPoint
    let to: CGPoint
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: at)
        p.addQuadCurve(to: to, control: CGPoint(x: (at.x + to.x) / 2 + 6, y: (at.y + to.y) / 2))
        return p
    }
}

/// 一片叶子：两头尖、中间鼓，从左端（叶柄）长出来
private struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.3))
        return p
    }
}
