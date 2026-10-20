import SwiftUI
import CoreMotion

// MARK: - 几个小动效
//
// 思路参考 bencho.dev 那一批交互（滚动数字、跟着手机倾斜的卡片……），按「栖」的样子重新写：
// 动得轻、慢一点、不抢内容。

/// 金额滚动：每一位数字像老式计数器那样上下滚到新的值。第一次出现时从 0 滚上来
struct RollingNumber: View {
    let text: String
    let font: Font
    var color: Color = .primary

    @State private var shown = ""

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, ch in
                if let d = ch.wholeNumberValue {
                    Text("8")
                        .font(font)
                        .monospacedDigit()
                        .hidden()
                        .overlay {
                            GeometryReader { g in
                                VStack(spacing: 0) {
                                    ForEach(0..<10, id: \.self) { n in
                                        Text("\(n)")
                                            .font(font)
                                            .monospacedDigit()
                                            .frame(height: g.size.height)
                                    }
                                }
                                .offset(y: -CGFloat(d) * g.size.height)
                            }
                            .clipped()
                        }
                } else {
                    Text(String(ch)).font(font)
                }
            }
        }
        .foregroundStyle(color)
        .onAppear {
            shown = String(text.map { $0.isNumber ? "0" : $0 })
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.spring(response: 0.9, dampingFraction: 0.86)) { shown = text }
            }
        }
        .onChange(of: text) { _, t in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) { shown = t }
        }
    }
}

/// 手机怎么歪：左右、前后各一个 -1…1，开始看的那一刻算正
@MainActor
final class DeviceTilt: ObservableObject {
    @Published private(set) var x: Double = 0
    @Published private(set) var y: Double = 0
    private let mm = CMMotionManager()
    private var base: (roll: Double, pitch: Double)?

    func start() {
        guard mm.isDeviceMotionAvailable, !mm.isDeviceMotionActive else { return }
        base = nil
        mm.deviceMotionUpdateInterval = 1.0 / 30
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            if self.base == nil { self.base = (a.roll, a.pitch) }
            guard let b = self.base else { return }
            // 歪 0.35 弧度（20 度）就到头
            self.x = max(-1, min(1, (a.roll - b.roll) / 0.35))
            self.y = max(-1, min(1, (a.pitch - b.pitch) / 0.35))
        }
    }

    func stop() {
        mm.stopDeviceMotionUpdates()
    }
}

// MARK: - clawd 看你点的地方

private struct ClawdLookAtKey: EnvironmentKey {
    static let defaultValue: CGPoint? = nil
}

extension EnvironmentValues {
    /// 她刚点的地方（全局坐标）。clawd 的眼睛往那边挪一格；nil = 平视
    var clawdLookAt: CGPoint? {
        get { self[ClawdLookAtKey.self] }
        set { self[ClawdLookAtKey.self] = newValue }
    }
}

/// 点哪儿他就往哪儿看一会儿：挂在房间那一层上
struct ClawdGazeHost: ViewModifier {
    @State private var point: CGPoint?
    @State private var token = 0

    func body(content: Content) -> some View {
        content
            .environment(\.clawdLookAt, point)
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .global).onEnded { v in
                    withAnimation(.easeOut(duration: 0.18)) { point = v.location }
                    token += 1
                    let t = token
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        if token == t { withAnimation(.easeInOut(duration: 0.3)) { point = nil } }
                    }
                }
            )
    }
}
