import SwiftUI
import UIKit

/// 微信那种「合并照片」卡：一叠图摞在一起，跟着手指翻。
///
/// 这一份是照她发来的 PhotoStack（Wren036 对微信原版逐帧测出来的规格）
/// 一比一搬到 SwiftUI 的，参数一个没改：
/// 探边 15 / 每层再探 12 / 每层转 2.2° / 每层缩 0.08 / 快甩 0.4 px·ms⁻¹。
///
/// 三条它测出来、我照抄的规矩（改了就不像微信了）：
///
/// 1. **恒定三张可见**：顶卡 + 两张探边。到头的时候探边配额挪到另一边，
///    还是三张——不是「左边没了就只剩两张」。
/// 2. **手指是进度条，不是位移**：拖的距离映射到一段预定义动画的 0→1。
///    前半程顶卡跟着手指滑出去，**后半程它自己往回落**进对侧探边位，
///    不再跟手。所以任何时刻松手都是合法状态，全程可逆。
/// 3. **快甩也走同一条轨迹**：不是直接跳到终态，是把剩下的行程播完。
struct PhotoStackView: View {

    let names: [String]
    var width: CGFloat = 160
    var height: CGFloat = 213
    /// 点当前这张。查看器是宿主的事，组件不自带。
    var onTap: (Int) -> Void = { _ in }

    @State private var cur = 0
    /// -1 = 往左甩（翻到下一张），+1 = 往右甩（翻回上一张），0 = 没在翻
    @State private var dir = 0
    @State private var p: Double = 0
    @State private var flipping = false

    var body: some View {
        StackBody(names: names, cur: cur, dir: dir, p: p,
                  width: width, height: height)
            .frame(width: width, height: height)
            .overlay {
                // 手势走 UIKit 的 pan：竖着划要**原样交还给聊天列表**，
                // 用 SwiftUI 的 DragGesture 的话，手指一落在卡片上
                // 整个聊天就滚不动了（等价于 photo-stack 里那句 touch-action: pan-y）。
                PhotoStackGesture(
                    onChange: { dx, startX in scrub(dx: dx, startX: startX) },
                    onEnd: { dx, startX, vel in release(dx: dx, startX: startX, vel: vel) },
                    onTap: { onTap(cur) }
                )
            }
    }

    // MARK: 手指

    /// 起点到屏幕左边的行程当分母——**两个方向用同一个分母**，
    /// 这样左右滑的阻力一致（原版就是这么做的）。
    private func progress(_ dx: CGFloat, _ startX: CGFloat) -> Double {
        min(1, Double(abs(dx)) / max(120, Double(startX)))
    }

    private func scrub(dx: CGFloat, startX: CGFloat) {
        guard names.count > 1 else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            // 上一次的完成动画还没播完就又划——先把页码结算掉，
            // 保证连甩每次翻且只翻一页（不然会吞页）。
            if flipping { settle() }
            dir = dx < 0 ? -1 : 1
            p = progress(dx, startX)
        }
    }

    private func release(dx: CGFloat, startX: CGFloat, vel: CGFloat) {
        guard names.count > 1, dir != 0 else { return }
        let prog = progress(dx, startX)
        let canFlip = dir < 0 ? cur < names.count - 1 : cur > 0
        // 两条翻页判定：慢拖过半，或者快甩（速度过阈值 + 位移超过约 10px 防误触）
        let fling = abs(vel) > 0.4 && (vel < 0) == (dx < 0) && prog > 0.04

        if canFlip && (prog > 0.5 || fling) {
            flipping = true
            let dur = max(0.14, (1 - prog) * 0.34)
            withAnimation(.easeOut(duration: dur)) {
                p = 1
            } completion: {
                // p=1 那一帧跟结算后的静止态**长得一模一样**，
                // 所以这里瞬时切过去，零跳变。
                if flipping { settle() }
            }
        } else {
            // 没过判定线：回弹归位。`dir` 不用清——`p` 回到 0 就是静止态了，
            // 清它反而会跟「回弹没播完她又划了一下」打架。
            withAnimation(.easeOut(duration: 0.22)) { p = 0 }
        }
    }

    /// 翻页结算：页码 +1/-1，回到静止态。**必须不带动画**。
    private func settle() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if dir < 0 { cur = min(cur + 1, names.count - 1) }
            else if dir > 0 { cur = max(cur - 1, 0) }
            dir = 0
            p = 0
            flipping = false
        }
    }
}

// MARK: - 摆位

/// 一张卡此刻长什么样
struct PhotoStackLayout {
    var x: CGFloat = 0
    var rot: Double = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
    var z: Double = 0
}

/// 摆位算术。**只有这一份**——静止态和擦洗态都从这儿出，
/// 两处各算一套的话，松手那一下必然对不上（原版的坑之一）。
enum PhotoStackGeometry {

    static let peek: CGFloat = 15
    static let peekStep: CGFloat = 12
    static let rotStep: Double = 2.2
    static let scaleStep: CGFloat = 0.08

    /// 可见探边配额：常态左右各 1；到边界时配额转给另一侧，凑够两张。
    static func quota(_ cur: Int, _ n: Int) -> (Int, Int) {
        let la = cur, ra = n - 1 - cur
        var L = min(la, 1), R = min(ra, 1)
        if L + R < 2 {
            L = min(la, 2 - R)
            R = min(ra, 2 - L)
        }
        return (L, R)
    }

    /// 静止摆位。擦洗的时候也先铺这一层当底座，防中间态残留。
    static func settled(_ i: Int, cur: Int, n: Int) -> PhotoStackLayout {
        let (L, R) = quota(cur, n)
        var l = PhotoStackLayout()
        if i < cur {
            let d = cur - i
            l.x = -peek - CGFloat(d - 1) * peekStep
            l.rot = -rotStep * Double(d)
            l.scale = 1 - scaleStep * CGFloat(d)
            l.z = Double(40 - d)
            l.opacity = d > L ? 0 : 1
        } else if i == cur {
            l.z = 100
        } else {
            let d = i - cur
            l.x = peek + CGFloat(d - 1) * peekStep
            l.rot = rotStep * Double(d)
            l.scale = 1 - scaleStep * CGFloat(d)
            l.z = Double(100 - d)
            l.opacity = d > R ? 0 : 1
        }
        return l
    }

    /// 擦洗态：`p` 是这一次翻页动画的进度（0→1），由手指或完成动画喂进来。
    static func scrub(_ i: Int, cur: Int, n: Int,
                      dir: Int, p: Double, stageWidth: CGFloat) -> PhotoStackLayout {
        var l = settled(i, cur: cur, n: n)
        let d = Double(dir)
        let maxX = stageWidth * 0.52

        // 边界弹性预览：第一张还能往右拖、最后一张还能往左拖，
        // 但只走 24px（带微旋），下面两层跟着轻轻动一点——
        // 手里那叠实体照片就是这个手感。
        if (dir < 0 && cur >= n - 1) || (dir > 0 && cur <= 0) {
            if i == cur {
                l.x = CGFloat(d * 24 * p)
                l.rot = d * 2.5 * p
                l.scale = 1
                l.z = 110
            } else if i == cur + dir {
                l.x = CGFloat(d) * (peek + CGFloat(8 * p))
                l.rot = d * rotStep
                l.scale = 1 - scaleStep
            } else if i == cur + dir * 2 {
                l.x = CGFloat(d) * (peek + peekStep + CGFloat(5 * p))
                l.rot = d * rotStep * 2
                l.scale = 1 - scaleStep * 2
            }
            return l
        }

        // 顶卡的峰形轨迹：滑出 → 峰值 → 回落进对侧探边位。
        // 后半程**不跟手反向**，是它自己走完剩下那半。
        var cx: CGFloat
        if p <= 0.5 {
            let q = CGFloat(p / 0.5)
            cx = CGFloat(d) * maxX * q
            if i == cur {
                l.x = cx
                l.rot = d * 8 * Double(q)
                l.scale = 1
                l.z = 110
            }
        } else {
            let q = (p - 0.5) / 0.5
            cx = CGFloat(d) * (maxX - (maxX - peek) * CGFloat(q))
            if i == cur {
                l.x = cx
                l.rot = d * (8 - (8 - rotStep) * q)
                l.scale = 1 - scaleStep * CGFloat(q)
                l.z = 102          // 越过峰值那一刻层级下沉，给新顶卡让位
            }
        }

        // 新顶卡：从对侧探边位插值升上来
        if i == cur - dir {
            l.x = CGFloat(-d) * peek * CGFloat(1 - p)
            l.rot = -d * rotStep * (1 - p)
            l.scale = 1 - scaleStep + scaleStep * CGFloat(p)
            l.opacity = 1
            l.z = 105
        }

        let qq = max(0, (p - 0.5) / 0.5)

        // 舞台转盘·进场：顶卡到峰值之前新探边不出场；后半程从升顶卡**背后**
        // 沿边滑出（露出来的是一条渐宽的窄边），透明度 0.55→1、由小变大。
        if i == cur - dir * 2, i >= 0, i < n {
            let (Lb, Rb) = quota(cur, n)
            let borrowed = dir < 0 ? (2 <= Rb) : (2 <= Lb)
            if borrowed {
                // 边界借位：这张本来就是可见的第二层探边，不参与进场编排，
                // 跟着升顶卡全程走位，保持实体（不然会凭空闪一下）。
                l.x = CGFloat(-d) * (peek + peekStep * CGFloat(1 - p))
                l.rot = -d * (rotStep * 2 - rotStep * p)
                l.scale = 1 - scaleStep * 2 + scaleStep * CGFloat(p)
                l.opacity = 1
            } else {
                let ntx = CGFloat(-d) * peek * CGFloat(1 - p)
                l.x = ntx * CGFloat(1 - qq) + (CGFloat(-d) * peek) * CGFloat(qq)
                l.rot = -d * (rotStep * 2 - rotStep * qq)
                l.scale = 1 - scaleStep * 2.5 + scaleStep * 1.5 * CGFloat(qq)
                l.opacity = min(1, qq / 0.18) * 0.55 + 0.45 * qq
            }
            l.z = dir < 0 ? 98 : 38
        }

        // 旧探边：进场的时间反演。但**结算之后还看得见的那张不退场**——
        // 它提前走位到降级后的外层探边位，顶卡落位时它已经就位。
        if i == cur + dir, i >= 0, i < n {
            let newCur = dir < 0 ? min(cur + 1, n - 1) : max(cur - 1, 0)
            let (L2, R2) = quota(newCur, n)
            let stays = i < newCur ? ((newCur - i) <= L2) : ((i - newCur) <= R2)
            if stays {
                l.x = CGFloat(d) * (peek + peekStep * CGFloat(p))
                l.rot = d * (rotStep + rotStep * p)
                l.scale = 1 - scaleStep - scaleStep * CGFloat(p)
            } else {
                let eq = 1 - (1 - qq) * (1 - qq)
                l.x = CGFloat(d) * peek * CGFloat(1 - eq) + cx * CGFloat(eq)
                l.rot = d * rotStep
                l.scale = 1 - scaleStep - scaleStep * 1.5 * CGFloat(qq)
                l.opacity = 1 - (min(1, qq / 0.18) * 0.55 + 0.45 * qq)
            }
        }

        return l
    }
}

// MARK: - 画面

/// 整叠卡。**自己是 Animatable 的**——动画插的是 `p` 这个进度，
/// 让它每一帧重算摆位，才走得出那条峰形轨迹；
/// 交给 SwiftUI 去插值各张卡的位移的话，插出来是一条直线，峰值就没了。
private struct StackBody: View, Animatable {

    let names: [String]
    var cur: Int
    var dir: Int
    var p: Double
    var width: CGFloat
    var height: CGFloat

    var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    /// 图先读进内存再画。**不能在 body 里直接 `ImageStore.load`**——
    /// 翻一次页 body 要重算几十帧，每帧都去磁盘读几张图会卡死。
    @State private var loaded: [String: UIImage] = [:]

    var body: some View {
        ZStack {
            ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                card(idx, name)
            }
        }
        .frame(width: width, height: height)
        .task(id: names) { await preload() }
    }

    @ViewBuilder
    private func card(_ i: Int, _ name: String) -> some View {
        let l = (dir == 0 || p <= 0)
            ? PhotoStackGeometry.settled(i, cur: cur, n: names.count)
            : PhotoStackGeometry.scrub(i, cur: cur, n: names.count,
                                       dir: dir, p: p, stageWidth: width)

        Group {
            if name.lowercased().hasSuffix(".gif") {
                // 会动的还是得逐帧播，缩略图只有第一帧
                AnimatedImageView(url: ImageStore.url(for: name))
                    .frame(width: width, height: height)
                    .clipped()
            } else if let img = loaded[name] {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Color.black.opacity(0.06)
                    .frame(width: width, height: height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
        .scaleEffect(l.scale)
        .rotationEffect(.degrees(l.rot))
        .offset(x: l.x)
        .opacity(l.opacity)
        .zIndex(l.z)
    }

    private func preload() async {
        let want = names.filter { !$0.lowercased().hasSuffix(".gif") }
        let side = max(width, height) * 3      // 留够放大的余量
        let got: [String: UIImage] = await Task.detached(priority: .userInitiated) {
            var out: [String: UIImage] = [:]
            for n in want {
                guard let img = UIImage(contentsOfFile: ImageStore.url(for: n).path) else { continue }
                let scale = min(1, side / max(img.size.width, img.size.height))
                if scale < 1,
                   let small = img.preparingThumbnail(
                    of: CGSize(width: img.size.width * scale, height: img.size.height * scale)) {
                    out[n] = small
                } else {
                    out[n] = img
                }
            }
            return out
        }.value
        loaded = got
    }
}

// MARK: - 手势

/// 横着划归卡片，竖着划归聊天列表。
///
/// 为什么不用 `DragGesture`：SwiftUI 的拖拽手势一旦落在滚动列表的子视图上，
/// 就把这一次触摸整个吃掉，**她想从照片上往下滚聊天记录会滚不动**。
/// 所以自己起一个 pan，方向一看出来是竖的就直接判失败，把触摸还回去。
private struct PhotoStackGesture: UIViewRepresentable {

    let onChange: (CGFloat, CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat, CGFloat) -> Void
    let onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear

        let pan = HorizontalPan(target: context.coordinator,
                                action: #selector(Coordinator.pan(_:)))
        v.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tap(_:)))
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onEnd: onEnd, onTap: onTap)
    }

    final class Coordinator: NSObject {
        var onChange: (CGFloat, CGFloat) -> Void
        var onEnd: (CGFloat, CGFloat, CGFloat) -> Void
        var onTap: () -> Void
        /// 起点在屏幕上的横坐标，当翻页进度的分母用
        private var startX: CGFloat = 0

        init(onChange: @escaping (CGFloat, CGFloat) -> Void,
             onEnd: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
             onTap: @escaping () -> Void) {
            self.onChange = onChange
            self.onEnd = onEnd
            self.onTap = onTap
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let dx = g.translation(in: g.view).x
            switch g.state {
            case .began:
                startX = max(1, g.location(in: nil).x - dx)
                onChange(dx, startX)
            case .changed:
                onChange(dx, startX)
            case .ended, .cancelled, .failed:
                // UIKit 给的是 px/s，原版那条 0.4 的阈值是 px/ms
                let v = g.velocity(in: g.view).x / 1000
                onEnd(dx, startX, v)
            default:
                break
            }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            onTap()
        }
    }
}

/// 只认横向的 pan：还没看出方向之前不喂给父类，免得它自己就 began 了
/// 把聊天列表的滚动挤掉；一看出是竖的就判失败。
private final class HorizontalPan: UIPanGestureRecognizer {

    private var origin: CGPoint = .zero
    private var decided = false

    override func reset() {
        super.reset()
        decided = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        origin = touches.first?.location(in: nil) ?? .zero
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !decided, let pt = touches.first?.location(in: nil) {
            let dx = pt.x - origin.x, dy = pt.y - origin.y
            if abs(dx) > 6 || abs(dy) > 6 {
                decided = true
                if abs(dy) > abs(dx) {
                    state = .failed
                    return
                }
            } else {
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }
}
