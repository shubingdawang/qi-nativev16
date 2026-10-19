import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - 动图工坊
//
// 一张图 → 会动的表情包：图自己怎么动、身边飘什么、写一句什么字、字怎么动。
// 预览和导出走**同一个画法**（`GifFrame.draw`），看到什么存下来就是什么。
// 一圈 24 帧，存成 GIF 进表情库。

struct GifSpec {
    var motion: GifMotion = .bounce
    var effect: GifEffect = .none
    var text = ""
    /// 字的中心在画面上的位置（0…1）
    var textX: Double = 0.5
    var textY: Double = 0.86
    var textSize: Double = 0.15
    var textColor = "FFFFFF"
    var strokeColor = "4A3442"
    /// 描边多粗（占字号的比例）。0 = 不描
    var strokeWidth: Double = 0.09
    var font: GifFont = .rounded
    var textAnim: GifTextAnim = .none
    /// 一圈多快（1 = 两秒一圈）
    var speed: Double = 1
    /// 像素图：放大不糊
    var pixel = false
    var whiteBG = false
    /// 图占画面多大
    var imageScale: Double = 0.74
    /// 特效什么颜色（空 = 那种特效自己的颜色）、多少（1 = 正常）
    var effectColor = ""
    var effectAmount: Double = 1
    /// 每一颗挪了多少（以画面边长为 1），没挪的不在里面
    var effectOffsets: [Int: CGPoint] = [:]
    /// 特效的快慢：1 = 原来的快慢；2、3、4 = 一圈里多走几遍；½、¼ = 慢下来
    /// （慢下来的时候整张动图拉长成两圈、四圈，图自己的动作照常重复，首尾才接得上）
    var effectSpeed: Double = 1
    /// 特效每一颗多大（1 = 原来那么大）
    var effectSize: Double = 1

    /// 特效慢下来的时候，整张动图是几圈
    var loops: Int { effectSpeed < 0.99 ? max(1, Int((1 / effectSpeed).rounded())) : 1 }
    /// 自己做的逐帧动画。有它就按它画，不走上面那套动作
    var anim: GifAnim?
    /// 正在编辑第几帧（预览停在这一帧，不播）；淡影显示哪一帧
    var editFrame: Int?
    var onionFrame: Int?

    static let frames = 24

    /// 导出几帧：逐帧动画不补间时就是她摆的那几帧
    var exportFrames: Int {
        if let a = anim, !a.tween { return a.count * loops }
        return Self.frames * loops
    }
}

enum GifMotion: String, CaseIterable, Identifiable {
    case none, bounce, shake, heartbeat, jelly, float, jitter, walk, spin, pop, zoom,
         nod, faint, flyaway, blink, peek, turn, shy,
         breathe, bow, tilt, drop, sink, slidein,
         rock, shiver, dizzy, rocket, squash, stretch,
         hopside, excited, sneak, wiggle, knockout, pulse
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "不动"
        case .bounce: return "蹦跳"
        case .shake: return "摇头"
        case .heartbeat: return "心跳"
        case .jelly: return "果冻"
        case .float: return "飘着"
        case .jitter: return "气得发抖"
        case .walk: return "走路"
        case .spin: return "转圈"
        case .pop: return "冒出来"
        case .zoom: return "怼脸"
        case .nod: return "点头"
        case .faint: return "倒下"
        case .flyaway: return "飞走"
        case .blink: return "一闪一闪"
        case .peek: return "探头"
        case .turn: return "转身"
        case .shy: return "缩一下"
        case .breathe: return "呼吸"
        case .bow: return "鞠躬"
        case .tilt: return "歪头"
        case .drop: return "从天而降"
        case .sink: return "沉下去"
        case .slidein: return "滑进滑出"
        case .rock: return "前后摇"
        case .shiver: return "打哆嗦"
        case .dizzy: return "晕乎乎"
        case .rocket: return "冲上天"
        case .squash: return "被压扁"
        case .stretch: return "伸懒腰"
        case .hopside: return "左右跳"
        case .excited: return "激动"
        case .sneak: return "蹑手蹑脚"
        case .wiggle: return "扭来扭去"
        case .knockout: return "被弹飞"
        case .pulse: return "忽大忽小"
        }
    }
}

enum GifEffect: String, CaseIterable, Identifiable {
    case none, hearts, sparkles, stars, rain, sweat, anger, notes, petals, sleepy, question, exclaim,
         fire, tears, confetti, bubbles, blush, lightning, flowers, shine, speed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "无"
        case .hearts: return "冒爱心"
        case .sparkles: return "闪闪"
        case .stars: return "转星星"
        case .rain: return "下雨"
        case .sweat: return "流汗"
        case .anger: return "生气"
        case .notes: return "哼歌"
        case .petals: return "飘花瓣"
        case .sleepy: return "犯困"
        case .question: return "问号"
        case .exclaim: return "感叹号"
        case .fire: return "燃起来"
        case .tears: return "掉眼泪"
        case .confetti: return "撒彩纸"
        case .bubbles: return "吐泡泡"
        case .blush: return "脸红"
        case .lightning: return "被雷劈"
        case .flowers: return "开小花"
        case .shine: return "集中线"
        case .speed: return "飞快"
        }
    }
    /// 这种特效自己的颜色
    var tint: String {
        switch self {
        case .hearts: return "F2708F"
        case .sparkles, .stars: return "FFD45E"
        case .rain, .sweat, .tears, .bubbles: return "8FD0F0"
        case .anger: return "EF5350"
        case .notes: return "9D8BE0"
        case .petals, .flowers: return "F6A9C0"
        case .sleepy: return "A9B8E8"
        case .question, .exclaim: return "FFB547"
        case .fire: return "FF8A3D"
        case .confetti: return "F2708F"
        case .blush: return "F48FA5"
        case .lightning: return "FFE14D"
        case .shine, .speed: return "FFFFFF"
        case .none: return "FFFFFF"
        }
    }
    /// 画在图后面的（不挡住脸）
    var behind: Bool { [.rain, .petals, .confetti, .shine, .speed].contains(self) }
}

/// 特效用的小像素图：`f` 填色、`w` 高光、`o` 描边、`.` 空。都是一笔一笔画的，不用 emoji
enum GifSprites {
    static let heart = [".oo.oo.", "offoffo", "ofwfffo", "offfffo", ".offfo.", "..ofo..", "...o..."]
    static let spark = ["..o..", ".ofo.", "ofwfo", ".ofo.", "..o.."]
    static let star = ["......o......", ".....ofo.....", ".....ofo.....", "....offfo....", ".oooofffoooo.", "offffwwfffffo", ".ooffwffffoo.", "...offfffo...", "...offfffo...", "...offfffo...", "..offoooffo..", "...oo...oo..."]
    static let drop = ["..o..", ".ofo.", ".ofo.", "offfo", "owffo", "offfo", ".ooo."]
    static let note = ["...ooo", "...ofo", "...o.o", "...o..", ".ooo..", "offo..", "offo..", ".oo..."]
    static let anger = ["....o...o....", "...ofo.ofo...", "...ofo.ofo...", ".ooffo.offoo.", "offfo...offfo", ".ooo.....ooo.", ".............", ".ooo.....ooo.", "offfo...offfo", ".ooffo.offoo.", "...ofo.ofo...", "...ofo.ofo...", "....o...o...."]
    static let petal = ["..oooffo", ".offfffo", "offwfffo", "ofwfffo.", "offfffo.", "offfffo.", ".ooffo..", "...oo..."]
    static let zee = [".oooooo.", "offffffo", ".ooooffo", "...offo.", "..offo..", ".offooo.", "offffffo", ".oooooo."]
    static let question = ["..ooo..", ".offfo.", "offoffo", ".oooffo", "..offo.", "..offo.", "...oo..", "..offo.", "...oo.."]
    static let exclaim = [".oo.", "offo", "offo", "offo", "offo", ".oo.", "offo", ".oo."]
    static let fireA = ["..o..", ".ofo.", ".ofo.", "offfo", "ofwfo", "ofwfo", ".ooo."]
    static let fireB = [".o...", ".ofo.", "offo.", "offfo", "ofwfo", "ofwfo", ".ooo."]
    static let bubble = [".ooo.", "ow..o", "o...o", "o...o", ".ooo."]
    static let bolt = [".......o.", "......ofo", ".....offo", "....ofwfo", "...ofwfo.", "..ofwfoo.", ".offffffo", "offfffffo", ".oooofffo", "...offfo.", "..offfo..", "..offo...", ".offo....", ".ofo.....", "..o......"]
    static let flower = [".o.o.", "ofofo", ".owo.", "ofofo", ".o.o."]
}

enum GifFont: String, CaseIterable, Identifiable {
    case rounded, heavy, serif, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rounded: return "圆润"
        case .heavy: return "粗黑"
        case .serif: return "宋体"
        case .mono: return "像素感"
        }
    }
    func ui(_ size: CGFloat) -> UIFont {
        switch self {
        case .rounded:
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        case .heavy:
            return UIFont.systemFont(ofSize: size, weight: .black)
        case .serif:
            return UIFont(name: "STSongti-SC-Black", size: size)
                ?? UIFont(name: "STSongti-SC-Bold", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .bold)
        case .mono:
            return UIFont.monospacedSystemFont(ofSize: size, weight: .heavy)
        }
    }
}

enum GifTextAnim: String, CaseIterable, Identifiable {
    case none, type, hop, blink, shake, grow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "不动"
        case .type: return "一个个打出来"
        case .hop: return "一跳一跳"
        case .blink: return "闪"
        case .shake: return "抖"
        case .grow: return "一下变大"
        }
    }
}

// MARK: - 一帧怎么画

enum GifFrame {

    /// 在当前 UIKit 画布上画第 t（0…1）那一刻。画布左上是原点、y 向下
    static func draw(_ image: UIImage?, spec: GifSpec, side: CGFloat, t: Double) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        if spec.whiteBG {
            g.setFillColor(UIColor.white.cgColor)
            g.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        // 图摆在哪：特效围着它冒
        let box = imageBox(image, spec: spec, side: side)
        // 特效慢下来时整张拉长成几圈：图和字的动作每圈照常走一遍，特效整段才走一遍
        let tm = (t * Double(spec.loops)).truncatingRemainder(dividingBy: 1)
        if spec.effect.behind { drawEffect(spec, box: box, side: side, t: t) }
        if let image { drawImage(image, spec: spec, side: side, t: tm, in: g) }
        if spec.effect != .none, !spec.effect.behind { drawEffect(spec, box: box, side: side, t: t) }
        drawText(spec, side: side, t: tm)
    }

    private static func drawImage(_ image: UIImage, spec: GifSpec, side: CGFloat, t: Double, in g: CGContext) {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return }
        let box = side * CGFloat(spec.imageScale)
        let fit = min(box / iw, box / ih)
        let w = iw * fit, h = ih * fit
        // 正在编辑某一帧时不套整体动作，停在原位好摆
        let m = spec.editFrame == nil ? motion(spec.motion, t: t) : Pose()
        g.saveGState()
        g.interpolationQuality = spec.pixel ? .none : .high
        // 绕脚底变形（蹦跳、果冻落地时是脚底不动）
        let cx = side / 2 + CGFloat(m.dx) * side
        let footY = side / 2 + h / 2 + CGFloat(m.dy) * side
        g.translateBy(x: cx, y: footY)
        g.rotate(by: CGFloat(m.rot) * .pi / 180)
        g.scaleBy(x: CGFloat(m.sx), y: CGFloat(m.sy))
        g.setAlpha(CGFloat(m.alpha))
        let local = CGRect(x: -w / 2, y: -h, width: w, height: h)
        if let anim = spec.anim {
            if let o = spec.onionFrame, o >= 0 {
                drawParts(anim, in: local, t: t, frame: o, alpha: 0.3, pixel: spec.pixel, in: g)
            }
            drawParts(anim, in: local, t: t, frame: spec.editFrame, alpha: CGFloat(m.alpha), pixel: spec.pixel, in: g)
        } else {
            // ⚠️ UIImage.draw 总是不透明地画，外面的 setAlpha 管不住：画进透明层，合上去时才按透明度算
            g.beginTransparencyLayer(auxiliaryInfo: nil)
            image.draw(in: local)
            g.endTransparencyLayer()
        }
        g.restoreGState()
    }

    /// 图在画面上占的那一块（不算动作）
    static func imageBox(_ image: UIImage?, spec: GifSpec, side: CGFloat) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGRect(x: side * 0.2, y: side * 0.2, width: side * 0.6, height: side * 0.6)
        }
        let box = side * CGFloat(spec.imageScale)
        let fit = min(box / image.size.width, box / image.size.height)
        let w = image.size.width * fit, h = image.size.height * fit
        return CGRect(x: side / 2 - w / 2, y: side / 2 - h / 2, width: w, height: h)
    }

    struct Pose { var dx = 0.0, dy = 0.0, rot = 0.0, sx = 1.0, sy = 1.0, alpha = 1.0 }

    static func motion(_ m: GifMotion, t: Double) -> Pose {
        var p = Pose()
        let tau = 2 * Double.pi
        switch m {
        case .none: break
        case .bounce:
            let ph = (t * 2).truncatingRemainder(dividingBy: 1)
            p.dy = -abs(sin(ph * .pi)) * 0.10
            // 落地那一下扁一点
            if ph < 0.12 || ph > 0.88 { p.sx = 1.08; p.sy = 0.9 }
        case .shake:
            // 摇头：左右甩，带一点点歪
            p.dx = sin(t * tau * 3) * 0.035
            p.rot = sin(t * tau * 3) * 4
        case .heartbeat:
            let ph = t.truncatingRemainder(dividingBy: 1)
            // 咚、咚：一大一小两下
            var beat = 0.0
            if ph < 0.15 {
                beat = sin(ph / 0.15 * .pi)
            } else if ph > 0.25 && ph < 0.4 {
                beat = sin((ph - 0.25) / 0.15 * .pi) * 0.7
            }
            p.sx = 1 + beat * 0.12; p.sy = p.sx
            p.dy = beat * 0.04 * 0.5
        case .jelly:
            let s = sin(t * tau * 2)
            p.sx = 1 + s * 0.09; p.sy = 1 - s * 0.09
        case .float:
            p.dy = sin(t * tau) * 0.05 - 0.02
            p.rot = sin(t * tau + 1) * 3
        case .jitter:
            // 气得发抖：鼓起来一圈，乱着抖
            let k = Int(t * 24)
            p.dx = Double((k * 37) % 7 - 3) * 0.008
            p.dy = Double((k * 53) % 5 - 2) * 0.008
            p.sx = 1.05; p.sy = 1.05
        case .walk:
            p.rot = sin(t * tau * 2) * 6
            p.dy = -abs(sin(t * tau * 2)) * 0.03
            p.dx = sin(t * tau) * 0.06
        case .spin:
            p.rot = t * 360
            p.dy = -0.12          // 绕中心转：抬到中间
        case .pop:
            let e = min(1, t / 0.35)
            let over = e < 1 ? (sin(e * .pi * 0.5) * 1.15) : 1
            p.sx = max(0.01, over); p.sy = p.sx
        case .zoom:
            let e = min(1, t / 0.4)
            p.sx = 1 + 0.28 * (1 - pow(1 - e, 3)); p.sy = p.sx
            p.dy = 0.06 * e
        case .nod:
            // 往前点两下：绕脚底往前倾，头低下去
            let s = max(0, sin(t * tau * 2))
            p.rot = s * 8
            p.sy = 1 - s * 0.05
        case .faint:
            // 晃两下，倒下去，躺一会儿
            if t < 0.3 { p.rot = sin(t / 0.3 * tau * 2) * 6 }
            else if t < 0.5 { p.rot = (t - 0.3) / 0.2 * 90 }
            else { p.rot = 90 }
        case .flyaway:
            let e = t < 0.8 ? t / 0.8 : 1
            p.dy = -e * e * 0.9
            p.dx = sin(e * tau) * 0.05
            p.alpha = t < 0.8 ? 1 - e * 0.3 : 0
            if t >= 0.9 { p.dy = 0; p.alpha = (t - 0.9) / 0.1 }
        case .blink:
            p.alpha = Int(t * 6) % 2 == 0 ? 1 : 0.15
        case .peek:
            // 从底下冒上来，左右看一眼，再缩回去
            let up: Double
            if t < 0.25 { up = t / 0.25 } else if t < 0.75 { up = 1 } else { up = 1 - (t - 0.75) / 0.25 }
            p.dy = (1 - up) * 0.75
            if t >= 0.3 && t < 0.7 { p.rot = sin((t - 0.3) / 0.4 * tau) * 8 }
        case .turn:
            // 左右翻过来再翻回去
            p.sx = cos(t * tau)
            if abs(p.sx) < 0.08 { p.sx = p.sx < 0 ? -0.08 : 0.08 }
        case .shy:
            let s = t < 0.5 ? sin(t / 0.5 * .pi) : 0
            p.sx = 1 - s * 0.18; p.sy = 1 - s * 0.24
            p.dx = -s * 0.03
        case .breathe:
            let s = sin(t * tau)
            p.sy = 1 + s * 0.04; p.sx = 1 - s * 0.02
        case .bow:
            // 弯下去停一下，再直起来
            let e: Double = t < 0.3 ? t / 0.3 : (t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4)
            p.rot = 28 * e * e * (3 - 2 * e)
        case .tilt:
            p.rot = t < 0.5 ? -10 * sin(t / 0.5 * .pi) : 10 * sin((t - 0.5) / 0.5 * .pi)
        case .drop:
            // 从上面掉下来，落地扁一下，再弹一小下
            if t < 0.35 {
                let e = t / 0.35
                p.dy = -0.9 * (1 - e * e)
            } else if t < 0.45 {
                p.sy = 0.75; p.sx = 1.2
            } else if t < 0.6 {
                p.dy = -sin((t - 0.45) / 0.15 * .pi) * 0.05
            }
        case .sink:
            if t < 0.4 {
                p.dy = t / 0.4 * 0.6; p.alpha = 1 - t / 0.4 * 0.9
            } else if t < 0.6 {
                p.dy = 0.6; p.alpha = 0.1
            } else {
                let e = (t - 0.6) / 0.4
                p.dy = (1 - e) * 0.6; p.alpha = 0.1 + e * 0.9
            }
        case .slidein:
            func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
            if t < 0.3 { p.dx = -0.8 * (1 - ease(t / 0.3)) }
            else if t < 0.7 { p.rot = sin((t - 0.3) / 0.4 * tau) * 3 }
            else { p.dx = 0.8 * ease((t - 0.7) / 0.3) }
        case .rock:
            // 前后摇：慢慢往前倾、往后仰，一圈一个来回
            p.rot = sin(t * tau) * 16
            p.sy = 1 - 0.04 * abs(sin(t * tau))
        case .shiver:
            // 打哆嗦：缩着身子，一帧往左一帧往右
            let k = Int((t * 24).rounded(.down))
            let side: Double = k % 2 == 0 ? 1 : -1
            p.dx = side * 0.012
            p.rot = side * 1.5
            p.sy = 0.95; p.sx = 0.98
        case .dizzy:
            p.dx = cos(t * tau * 2) * 0.04
            p.rot = sin(t * tau * 2) * 10
            p.dy = sin(t * tau * 4) * 0.01
        case .rocket:
            // 蹲一下，冲上去，从上面落回来
            if t < 0.25 {
                let s = sin(t / 0.25 * .pi / 2)
                p.sy = 1 - 0.2 * s; p.sx = 1 + 0.1 * s
            } else if t < 0.6 {
                let e = (t - 0.25) / 0.35
                p.dy = -e * e * 1.3; p.sy = 1.15; p.sx = 0.9
            } else if t < 0.75 {
                p.alpha = 0
            } else {
                p.dy = -(1 - (t - 0.75) / 0.25) * 1.0
            }
        case .squash:
            if t < 0.15 {
                let e = t / 0.15
                p.sy = 1 - 0.55 * e; p.sx = 1 + 0.4 * e
            } else if t < 0.6 {
                p.sy = 0.45; p.sx = 1.4
            } else if t < 0.75 {
                let e = (t - 0.6) / 0.15
                p.sy = 0.45 + 0.7 * e; p.sx = 1.4 - 0.5 * e
            } else {
                let e = (t - 0.75) / 0.25
                p.sy = 1 + 0.15 * cos(e * .pi * 3) * (1 - e); p.sx = 1 - 0.08 * cos(e * .pi * 3) * (1 - e)
            }
        case .stretch:
            let e = sin(t * .pi)
            p.sy = 1 + 0.22 * e; p.sx = 1 - 0.08 * e
            p.rot = sin(t * tau) * 3
        case .hopside:
            let ph = (t * 2).truncatingRemainder(dividingBy: 1)
            p.dy = -sin(ph * .pi) * 0.12
            p.dx = t < 0.5 ? -0.08 + 0.16 * ph : 0.08 - 0.16 * ph
        case .excited:
            // 激动：原地小碎跳，一跳一缩
            let ph = (t * 4).truncatingRemainder(dividingBy: 1)
            p.dy = -abs(sin(ph * .pi)) * 0.07
            p.sx = 1 + 0.06 * sin(ph * tau)
            p.sy = 1 - 0.06 * sin(ph * tau)
        case .sneak:
            // 弓着身子挪过去，转身挪回来
            p.dx = sin(t * tau) * 0.2
            p.dy = -abs(sin(t * tau * 4)) * 0.015
            p.sy = 0.9
            p.sx = cos(t * tau) >= 0 ? 1.05 : -1.05
        case .wiggle:
            p.rot = sin(t * tau * 4) * 7
            p.sx = 1 + sin(t * tau * 4) * 0.04
        case .knockout:
            // 被打飞出去转着圈，再从上面掉回来
            if t < 0.5 {
                let e = t / 0.5
                p.dx = 1.2 * e; p.dy = -sin(e * .pi) * 0.5; p.rot = e * 540
            } else if t < 0.7 {
                p.alpha = 0
            } else {
                let e = (t - 0.7) / 0.3
                p.dy = -0.9 * (1 - e) * (1 - e)
            }
        case .pulse:
            // 忽大忽小：慢慢变大再慢慢缩回去（心跳是咚咚两下，这个是一整口气）
            p.sx = 1 + 0.22 * sin(t * tau); p.sy = p.sx
        }
        return p
    }

    /// 身边冒的那些。每一颗的位置只由 t 和它自己的序号算出来，一圈首尾接得上。
    /// 画的是小像素图（`GifSprites`），颜色、多少她能调
    /// 摆位置的时候用：不画，只把每一颗在开头那一刻的位置报出来
    nonisolated(unsafe) static var effectCollector: ((Int, CGPoint) -> Void)?

    /// 每一颗特效在开头那一刻在哪（画面坐标）
    static func effectAnchors(_ image: UIImage?, spec: GifSpec, side: CGFloat) -> [(Int, CGPoint)] {
        var out: [(Int, CGPoint)] = []
        var seen = Set<Int>()
        effectCollector = { i, p in if seen.insert(i).inserted { out.append((i, p)) } }
        defer { effectCollector = nil }
        let box = imageBox(image, spec: spec, side: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        _ = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { _ in
            drawEffect(spec, box: box, side: side, t: 0)
        }
        return out
    }

    private static func drawEffect(_ spec: GifSpec, box: CGRect, side: CGFloat, t t0: Double) {
        // 快慢：一圈里多走几遍（整数遍，首尾接得上）
        let t = (t0 * max(1, spec.effectSpeed.rounded())).truncatingRemainder(dividingBy: 1)
        // 本来只有一颗的那几种，多少调大了也能多冒几颗：换个位置、错开一点节奏
        let spots: [(CGFloat, CGFloat)] = [(0, 0), (-0.78, 0.04), (-0.4, -0.12), (-0.2, 0.3)]
        let e = spec.effect
        guard e != .none, let g = UIGraphicsGetCurrentContext() else { return }
        let col = UIColor(beadHex: spec.effectColor.isEmpty ? e.tint : spec.effectColor) ?? .white
        let ink = UIColor(beadHex: "4A3442") ?? .black
        let hi = UIColor.white
        let ps = max(1, (side / 72).rounded() * CGFloat(max(0.4, spec.effectSize)))   // 一个像素多大
        let amount = max(0.4, spec.effectAmount)
        let tau = 2 * Double.pi
        func n(_ base: Int) -> Int { max(1, Int((Double(base) * amount).rounded())) }
        func put(_ idx: Int, _ rows: [String], _ cx0: CGFloat, _ cy0: CGFloat, alpha: CGFloat = 1, k: CGFloat = 1,
                 fill: UIColor? = nil) {
            // 她拖过这一颗：整条路线跟着挪
            let o = spec.effectOffsets[idx] ?? .zero
            let cx = cx0 + o.x * side, cy = cy0 + o.y * side
            if let collect = effectCollector {
                collect(idx, CGPoint(x: cx, y: cy))
                return
            }
            guard alpha > 0.02 else { return }
            let p = ps * k
            let hgt = CGFloat(rows.count), wid = CGFloat(rows.first?.count ?? 0)
            let x0 = (cx - wid * p / 2).rounded(), y0 = (cy - hgt * p / 2).rounded()
            g.saveGState()
            g.setAlpha(alpha)
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    let c: UIColor
                    switch ch {
                    case "f": c = fill ?? col
                    case "w": c = hi
                    case "o": c = ink
                    default: continue
                    }
                    g.setFillColor(c.cgColor)
                    g.fill(CGRect(x: x0 + CGFloat(x) * p, y: y0 + CGFloat(y) * p, width: p + 0.5, height: p + 0.5))
                }
            }
            g.restoreGState()
        }
        let top = box.minY, midX = box.midX
        switch e {
        case .hearts, .notes:
            // 从身边往上冒，越高越淡
            let rows = e == .hearts ? GifSprites.heart : GifSprites.note
            let k = n(4)
            for i in 0..<k {
                let ph = (t + Double(i) / Double(k)).truncatingRemainder(dividingBy: 1)
                let left = i % 2 == 0
                let x = (left ? box.minX : box.maxX) + CGFloat(sin(ph * tau + Double(i)) * 6) + (left ? -6 : 6)
                let y = box.midY - CGFloat(ph) * box.height * 0.8
                let a = ph < 0.15 ? ph / 0.15 : 1 - (ph - 0.15) / 0.85
                put(i, rows, x, y, alpha: CGFloat(a), k: 0.9 + CGFloat(ph) * 0.4)
            }
        case .sparkles:
            let spots: [(CGFloat, CGFloat)] = [(-0.1, 0.05), (1.08, 0.12), (-0.05, 0.6), (1.05, 0.7), (0.5, -0.12), (0.2, -0.05)]
            for (i, sp) in spots.prefix(n(5)).enumerated() {
                let ph = (t * 2 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let a = sin(ph * .pi)
                put(i, GifSprites.spark, box.minX + box.width * sp.0, box.minY + box.height * sp.1,
                    alpha: CGFloat(a), k: 0.8 + CGFloat(a) * 0.6)
            }
        case .stars:
            // 一圈星星绕着头顶转
            let k = n(4)
            for i in 0..<k {
                let a = (t + Double(i) / Double(k)) * tau
                put(i, GifSprites.star, midX + CGFloat(cos(a)) * box.width * 0.42,
                    top + CGFloat(sin(a)) * box.height * 0.08 - ps * 3)
            }
        case .rain, .petals, .confetti:
            let k = n(e == .rain ? 10 : 8)
            let palette = ["F2708F", "FFD45E", "8FD0F0", "B8DE9C", "C9A7DE"]
            for i in 0..<k {
                let x0 = (Double(i) + 0.5) / Double(k) + sin(Double(i) * 2.3) * 0.04
                let speed = e == .rain ? 2.0 : 1.0
                let ph = (t * speed + Double(i) * 0.29).truncatingRemainder(dividingBy: 1)
                let x = CGFloat(x0 + (e == .rain ? 0 : sin(ph * tau + Double(i)) * 0.05)) * side
                let y = CGFloat(-0.05 + ph * 1.1) * side
                switch e {
                case .rain: put(i, GifSprites.drop, x, y, alpha: 0.85, k: 0.7)
                case .petals: put(i, GifSprites.petal, x, y, alpha: 0.95)
                default:
                    let c = UIColor(beadHex: palette[i % palette.count]) ?? col
                    put(i, ["ff", "ff"], x, y, fill: spec.effectColor.isEmpty ? c : col)
                }
            }
        case .sweat:
            for i in 0..<min(spots.count, n(1)) {
                let ph = (t + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                put(i, GifSprites.drop, box.maxX - box.width * 0.12 + box.width * spots[i].0,
                    top + box.height * (0.08 + spots[i].1 + CGFloat(ph) * 0.25),
                    alpha: ph < 0.8 ? 1 : CGFloat((1 - ph) / 0.2), k: 1.2)
            }
        case .anger:
            for i in 0..<min(spots.count, n(1)) {
                let a = 0.8 + 0.35 * abs(sin(t * tau * 2 + Double(i)))
                put(i, GifSprites.anger, box.maxX - box.width * 0.1 + box.width * spots[i].0,
                    top + box.height * (0.08 + spots[i].1), k: CGFloat(a) * 1.4)
            }
        case .sleepy:
            let k = n(3)
            for i in 0..<k {
                let ph = (t + Double(i) / Double(k)).truncatingRemainder(dividingBy: 1)
                put(i, GifSprites.zee, box.maxX + CGFloat(ph) * box.width * 0.2, top + box.height * 0.2 - CGFloat(ph) * box.height * 0.4,
                    alpha: CGFloat(1 - ph), k: 0.8 + CGFloat(ph) * 0.8, fill: col)
            }
        case .question, .exclaim:
            let rows = e == .question ? GifSprites.question : GifSprites.exclaim
            for i in 0..<min(spots.count, n(1)) {
                let a = sin(t * tau + Double(i) * 1.7) * 0.15
                put(i, rows, box.maxX - box.width * 0.05 + box.width * spots[i].0,
                    top - ps * 2 + box.height * spots[i].1 + CGFloat(a) * ps * 10, k: 1.5, fill: col)
            }
        case .fire:
            let k = n(5)
            for i in 0..<k {
                let flick = Int(t * 12 + Double(i)) % 2 == 0
                let x = box.minX + box.width * (CGFloat(i) + 0.5) / CGFloat(k)
                put(i, flick ? GifSprites.fireA : GifSprites.fireB, x, box.maxY - ps * 3, k: 1.3)
            }
        case .tears:
            for i in 0..<n(2) {
                let ph = (t * 2 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let x = box.minX + box.width * (i % 2 == 0 ? 0.32 : 0.68)
                put(i, GifSprites.drop, x, box.midY + CGFloat(ph) * box.height * 0.35, alpha: CGFloat(1 - ph), k: 0.8)
            }
        case .bubbles:
            for i in 0..<n(5) {
                let ph = (t + Double(i) * 0.21).truncatingRemainder(dividingBy: 1)
                let x = box.maxX + CGFloat(sin(ph * tau * 2 + Double(i))) * 8
                put(i, GifSprites.bubble, x, box.midY - CGFloat(ph) * box.height * 0.9, alpha: CGFloat(1 - ph * 0.8),
                    k: 0.7 + CGFloat(ph) * 0.8)
            }
        case .blush:
            // 两团腮红 + 三道斜线，一闪一闪
            let a = 0.6 + 0.4 * abs(sin(t * tau))
            for sx in [0.3, 0.7] {
                put((sx < 0.5 ? 0 : 1), [".fff.", "fffff", ".fff."], box.minX + box.width * CGFloat(sx), box.minY + box.height * 0.55,
                    alpha: CGFloat(a), k: 1.3)
            }
        case .lightning:
            let on = Int(t * 8) % 2 == 0
            if on {
                g.saveGState()
                g.setFillColor(UIColor.white.withAlphaComponent(0.25).cgColor)
                g.fill(CGRect(x: 0, y: 0, width: side, height: side))
                g.restoreGState()
            }
            for i in 0..<min(spots.count, n(1)) {
                let lit = Int(t * 8 + Double(i)) % 2 == 0
                put(i, GifSprites.bolt, box.midX + box.width * (0.25 + spots[i].0 * 0.6),
                    top - ps * 2 + box.height * spots[i].1, alpha: lit ? 1 : 0.6, k: 2)
            }
        case .flowers:
            for i in 0..<n(6) {
                let a = Double(i) / Double(n(6)) * tau + t * tau * 0.25
                let ph = (t * 2 + Double(i) * 0.3).truncatingRemainder(dividingBy: 1)
                put(i, GifSprites.flower, midX + CGFloat(cos(a)) * box.width * 0.62,
                    box.midY + CGFloat(sin(a)) * box.height * 0.55, alpha: CGFloat(0.5 + 0.5 * sin(ph * .pi)))
            }
        case .shine:
            // 集中线：从中心往外一圈长短不一的线，慢慢转
            g.saveGState()
            g.setStrokeColor(col.withAlphaComponent(0.85).cgColor)
            g.setLineWidth(ps)
            let c = CGPoint(x: box.midX, y: box.midY)
            let k = n(28)
            for i in 0..<k {
                let a = Double(i) / Double(k) * tau + t * 0.6
                let r0 = side * (i % 2 == 0 ? 0.36 : 0.42), r1 = side * 0.75
                g.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * r0, y: c.y + CGFloat(sin(a)) * r0))
                g.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r1, y: c.y + CGFloat(sin(a)) * r1))
            }
            g.strokePath()
            g.restoreGState()
        case .speed:
            g.saveGState()
            g.setFillColor(col.withAlphaComponent(0.8).cgColor)
            for i in 0..<n(8) {
                let ph = (t * 3 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let y = box.minY + box.height * CGFloat(Double(i) / Double(n(8)))
                let len = side * 0.18
                let x = box.minX - CGFloat(ph) * side * 0.5
                g.fill(CGRect(x: x.rounded() - len, y: y.rounded(), width: len, height: ps))
            }
            g.restoreGState()
        case .none:
            break
        }
    }

    private static func drawText(_ spec: GifSpec, side: CGFloat, t: Double) {
        let raw = spec.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let g = UIGraphicsGetCurrentContext() else { return }
        let chars = Array(raw)
        var shown = chars.count
        if spec.textAnim == .type { shown = min(chars.count, Int(Double(chars.count + 1) * min(1, t / 0.6))) }
        if spec.textAnim == .blink, Int(t * 6) % 2 == 1 { return }
        guard shown > 0 else { return }
        var scale = 1.0
        if spec.textAnim == .grow {
            let e = min(1, t / 0.25)
            scale = e < 1 ? 0.3 + 0.95 * sin(e * .pi / 2) : 1
        }
        let size = CGFloat(spec.textSize * scale) * side
        let font = spec.font.ui(size)
        let fill = UIColor(beadHex: spec.textColor) ?? .white
        let stroke = UIColor(beadHex: spec.strokeColor) ?? .black
        // 每个字单独摆，一跳一跳 / 抖的时候各动各的
        let pieces = chars.map { String($0) }
        let widths = pieces.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }
        let total = widths.reduce(0, +)
        var x = CGFloat(spec.textX) * side - total / 2
        let cy = CGFloat(spec.textY) * side
        for (i, p) in pieces.enumerated() {
            defer { x += widths[i] }
            guard i < shown else { continue }
            var dy: CGFloat = 0, dx: CGFloat = 0
            if spec.textAnim == .hop {
                let phase: Double = (t * 2 - Double(i) * 0.12) * 2 * .pi
                let up: Double = max(0, sin(phase))
                dy = -CGFloat(up) * size * 0.25
            }
            if spec.textAnim == .shake {
                let k = Int(t * 24) + i * 7
                dx = CGFloat((k * 37) % 5 - 2) * size * 0.03
                dy = CGFloat((k * 53) % 5 - 2) * size * 0.03
            }
            let at = CGPoint(x: x + dx, y: cy - font.lineHeight / 2 + dy)
            g.saveGState()
            // 描边：同一个字用描边色绕一圈画 16 次，叠出一圈**圆的**边——
            // 以前用字体自带的描边，转角是尖的，看着有毛刺
            let r = CGFloat(spec.strokeWidth) * size
            if r > 0.3 {
                let outline = NSAttributedString(string: p, attributes: [.font: font, .foregroundColor: stroke])
                for k in 0..<16 {
                    let a = Double(k) / 16 * 2 * .pi
                    outline.draw(at: CGPoint(x: at.x + CGFloat(cos(a)) * r, y: at.y + CGFloat(sin(a)) * r))
                }
                // 里面再补一圈，粗描边时中间不漏
                for k in 0..<8 {
                    let a = Double(k) / 8 * 2 * .pi
                    outline.draw(at: CGPoint(x: at.x + CGFloat(cos(a)) * r * 0.5, y: at.y + CGFloat(sin(a)) * r * 0.5))
                }
            }
            NSAttributedString(string: p, attributes: [
                .font: font, .foregroundColor: fill
            ]).draw(at: at)
            g.restoreGState()
        }
    }

    /// 存成 GIF
    static func gif(_ image: UIImage?, spec: GifSpec, side: CGFloat = 240) -> Data? {
        let data = NSMutableData()
        var spec = spec
        spec.editFrame = nil
        spec.onionFrame = nil
        let n = spec.exportFrames
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, n, nil)
        else { return nil }
        let delay = 2.0 * Double(spec.loops) / Double(n) / max(0.25, spec.speed)
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        for i in 0..<n {
            let frame = renderer.image { _ in
                draw(image, spec: spec, side: side, t: Double(i) / Double(n))
            }
            guard let cg = frame.cgImage else { continue }
            CGImageDestinationAddImage(dest, cg, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

// MARK: - 页面

/// 从哪张图开始做动图
struct GifStart: Identifiable {
    let id = UUID()
    let image: UIImage?
    let name: String
    /// 进来先停在哪一档（4 = 逐帧）
    var section = 0
}

struct GifMakerView: View {

    var image: UIImage?
    var name: String = ""
    /// 进来先停在哪一档（4 = 逐帧）
    var startSection = 0

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var stickers = StickerStore.shared

    @State private var base: UIImage?
    @State private var spec = GifSpec()
    @State private var section = 0
    @State private var photo: PhotosPickerItem?
    @State private var choosing = false
    @State private var saving = false
    @State private var title = ""
    @State private var notice: String?
    @State private var dragFrom: (x: Double, y: Double)?
    // 逐帧那一档
    @State private var animFrame = 0
    @State private var animPart: UUID?
    @State private var animTool: GifAnimEditor.Tool = .pose
    @State private var animPlaying = false
    @State private var onion = true
    @State private var poseFrom: PartPose?
    @State private var sel: PaintSel?
    // 逐帧那一档的画面放大
    @State private var viewZoom: CGFloat = 1
    @State private var viewPan: CGSize = .zero
    @State private var panning = false
    @State private var panFrom: CGSize?
    @State private var zoomFrom: CGFloat = 1
    @State private var zoomPanFrom: CGSize = .zero
    @State private var pinching = false
    @State private var dragging = false
    @State private var selBefore: PaintSel?
    @State private var selErase = false
    @State private var brush = 1
    @State private var pivotAt: CGPoint?
    @State private var pickingPart = false
    // 特效一颗颗摆
    @State private var effectEditing = false
    @State private var effIdx: Int?
    @State private var effFrom: CGPoint?
    // 存
    @State private var savedSticker: Sticker?
    @FocusState private var titleFocused: Bool
    @State private var rotFrom: Double?
    @State private var scaleFrom: Double?

    private let textColors = ["FFFFFF", "4A3442", "F4A9BB", "FFD86B", "A8D8F0", "B8DE9C", "E8758F", "1A1717"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                stage
                sectionPicker
                ScrollView { controls.padding(.horizontal, 16).padding(.bottom, 24) }
            }
            .padding(.top, 8)
            .background(WallpaperBackground())
            .navigationTitle("动图工坊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("存成表情") {
                        title = name.isEmpty ? spec.text : name
                        saving = true
                    }
                        .disabled(base == nil && spec.text.isEmpty)
                }
            }
            .onAppear {
                if base == nil, let image {
                    base = image
                    spec.pixel = Self.looksPixel(image)
                }
                if startSection != 0, section == 0, base != nil { section = startSection }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        use(img)
                    }
                    photo = nil
                }
            }
            .sheet(isPresented: $choosing) { stickerPicker }
            // 起名用一张小页（不用系统弹框）：输入法开着，点「存」也是一下就存
            .sheet(isPresented: $saving) { saveSheet }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                if let s = savedSticker {
                    Button("存到手机相册") {
                        let url = StickerStore.shared.url(of: s)
                        savedSticker = nil
                        Task { @MainActor in notice = await StickerExport.saveToPhotos(url) }
                    }
                }
                Button("好") { notice = nil; savedSticker = nil }
            }
            .onChange(of: spec.anim?.parts.count) { _, _ in sel = nil }
        }
    }

    private func use(_ img: UIImage) {
        base = img
        spec.pixel = Self.looksPixel(img)
    }

    /// 像素图（小图，或者拼豆导出那种一格好几个像素的）：放大不插值
    static func looksPixel(_ img: UIImage) -> Bool {
        if max(img.size.width, img.size.height) <= 160 { return true }
        guard let px = GifAnim.pixels(GifAnim.normalized(img)) else { return false }
        return GifAnim.detectedCell(px) != nil
    }

    // MARK: 预览

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            stageCanvas
            animOverlay
            effectOverlay
        }
        .frame(width: stageSide, height: stageSide, alignment: .topLeading)
        .scaleEffect(viewZoom, anchor: .topLeading)
        .offset(viewPan)
        .frame(width: stageSide, height: stageSide, alignment: .topLeading)
        .background(TransparencyGrid())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .center) {
            if base == nil {
                VStack(spacing: 10) {
                    Text("先挑一张图").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                    pickButtons
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if viewZoom > 1.01 {
                Button { viewZoom = 1; viewPan = .zero; panning = false } label: {
                    Label("还原", systemImage: "arrow.down.right.and.arrow.up.left").font(.app(11))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .contentShape(Rectangle())
        // 在预览上拖：逐帧那一档按工具来，别的时候挪字
        .gesture(stageDrag)
        .simultaneousGesture(stageTurn)
        .simultaneousGesture(stageZoom)
        .animation(.easeInOut(duration: 0.2), value: stageSide)
        .onChange(of: section) { _, v in if v != 4 { viewZoom = 1; viewPan = .zero; panning = false } }
    }

    /// 预览上的一点 → 放大以前那张图上的位置
    private func cpt(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - viewPan.width) / viewZoom, y: (p.y - viewPan.height) / viewZoom)
    }

    /// 放大以后画面别挪出框
    private func clampPan(_ p: CGSize) -> CGSize {
        let lim = (viewZoom - 1) * stageSide
        return CGSize(width: min(0, max(-lim, p.width)), height: min(0, max(-lim, p.height)))
    }

    private var stageCanvas: some View {
        TimelineView(.animation) { ctx in
            let period = 2.0 * Double(spec.loops) / max(0.25, spec.speed)
            let raw = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            // 跟导出一样按帧一跳，预览看到的就是存下来的节奏
            let nf = Double(spec.exportFrames)
            let t = (raw * nf).rounded(.down) / nf
            let shown = previewSpec
            Canvas { gc, size in
                let side = min(size.width, size.height)
                gc.withCGContext { cg in
                    UIGraphicsPushContext(cg)
                    GifFrame.draw(base, spec: shown, side: side, t: t)
                    UIGraphicsPopContext()
                }
            }
        }
        .frame(width: stageSide, height: stageSide)
    }

    /// 预览用的参数：编辑逐帧、没在播的时候停在那一帧，带淡影
    private var previewSpec: GifSpec {
        var s = spec
        if section == 4, spec.anim != nil, !animPlaying {
            s.editFrame = animFrame
            s.onionFrame = onion && animFrame > 0 ? animFrame - 1 : nil
        }
        return s
    }

    private var editingAnim: Bool { section == 4 && spec.anim != nil && !animPlaying }

    /// 正在一颗颗摆特效的位置
    private var placingEffect: Bool { section == 1 && effectEditing && spec.effect != .none }

    /// 预览多大：逐帧那一档要一格格点，放大一些
    private var stageSide: CGFloat { section == 4 ? 330 : 260 }

    /// 图在预览上占的那一块
    private var stageBox: CGRect { GifFrame.imageBox(base, spec: spec, side: stageSide) }

    private var selectedPart: UUID? { animPart ?? spec.anim?.parts.first?.id }

    /// 选中部位的转轴、选中的像素
    @ViewBuilder
    private var animOverlay: some View {
        if editingAnim, let a = spec.anim, let id = selectedPart, let part = a.parts.first(where: { $0.id == id }) {
            let side = stageSide
            let b = stageBox
            let pose = a.pose(id, frame: animFrame)
            let pv = pivotAt ?? CGPoint(x: b.minX + part.pivot.x * b.width + CGFloat(pose.dx) * b.width,
                                        y: b.minY + part.pivot.y * b.height + CGFloat(pose.dy) * b.width)
            ZStack(alignment: .topLeading) {
                if let s = sel, s.part == id, let img = s.overlay {
                    // 选中的像素：跟这个部位一样挪、转、放大，盖在它上面
                    Canvas { gc, _ in
                        var shade = part
                        shade.image = img
                        var one = GifAnim()
                        one.parts = [shade]
                        one.frames = [[id: pose]]
                        gc.withCGContext { cg in
                            UIGraphicsPushContext(cg)
                            GifFrame.drawParts(one, in: b, t: 0, frame: 0, alpha: 1, pixel: true, in: cg)
                            UIGraphicsPopContext()
                        }
                    }
                    .frame(width: side, height: side)
                }
                if animTool == .pivot {
                    // 十字线：手指盖住那个点的时候也看得出它在哪
                    Path { p in
                        p.move(to: CGPoint(x: pv.x, y: 0)); p.addLine(to: CGPoint(x: pv.x, y: side))
                        p.move(to: CGPoint(x: 0, y: pv.y)); p.addLine(to: CGPoint(x: side, y: pv.y))
                    }
                    .stroke(app.settings.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                Circle().stroke(app.settings.accentColor, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .position(pv)
                Circle().fill(app.settings.accentColor).frame(width: 4, height: 4).position(pv)
            }
            .frame(width: side, height: side)
            .allowsHitTesting(false)
        }
    }

    struct EffectHandle: Identifiable {
        let id: Int
        let at: CGPoint
    }

    /// 摆特效位置：每一颗一个圆点，拖哪颗挪哪颗
    @ViewBuilder
    private var effectOverlay: some View {
        if placingEffect, base != nil {
            let side = stageSide
            let handles = GifFrame.effectAnchors(base, spec: spec, side: side).map { EffectHandle(id: $0.0, at: $0.1) }
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: side, height: side)
                ForEach(handles) { h in
                    Text("\(h.id + 1)")
                        .font(.app(10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(app.settings.accentColor.opacity(effIdx == h.id ? 1 : 0.8)))
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .contentShape(Circle().inset(by: -8))
                        .position(h.at)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("gifStage"))
                                .onChanged { v in
                                    if effIdx != h.id {
                                        effIdx = h.id
                                        effFrom = spec.effectOffsets[h.id] ?? .zero
                                    }
                                    let f = effFrom ?? .zero
                                    spec.effectOffsets[h.id] = CGPoint(x: f.x + v.translation.width / side,
                                                                       y: f.y + v.translation.height / side)
                                }
                                .onEnded { _ in effIdx = nil; effFrom = nil }
                        )
                }
            }
            .frame(width: side, height: side)
            .coordinateSpace(name: "gifStage")
        }
    }

    /// 预览上一点 → 这个部位没摆动作时在哪（把这一帧的挪、转、放大倒回去）
    private func unposed(_ s: CGPoint, part: GifPart, pose: PartPose) -> CGPoint {
        let b = stageBox
        let pv = CGPoint(x: b.minX + part.pivot.x * b.width, y: b.minY + part.pivot.y * b.height)
        let vx = s.x - pv.x - CGFloat(pose.dx) * b.width
        let vy = s.y - pv.y - CGFloat(pose.dy) * b.width
        let a = -CGFloat(pose.rot) * .pi / 180
        let k = 1 / CGFloat(max(0.05, pose.scale))
        return CGPoint(x: pv.x + (vx * cos(a) - vy * sin(a)) * k,
                       y: pv.y + (vx * sin(a) + vy * cos(a)) * k)
    }

    /// 预览上一点 → 部位那张图上的像素
    private func partPixel(_ s: CGPoint, _ part: GifPart, _ pose: PartPose, _ px: GifAnim.Pixels) -> (Double, Double) {
        let b = stageBox
        let u = unposed(s, part: part, pose: pose)
        let fx = (u.x - b.minX) / b.width, fy = (u.y - b.minY) / b.height
        let r = part.rect
        return (Double((fx - r.minX) / r.width) * Double(px.w), Double((fy - r.minY) / r.height) * Double(px.h))
    }

    /// 选区跟着选中的部位：换了部位就从头选
    private func ensureSel(_ part: GifPart) -> Bool {
        if sel?.part == part.id { return true }
        guard let px = GifAnim.pixels(part.image) else { return false }
        sel = PaintSel(part: part.id, px: px, cell: GifAnim.cellSize(px),
                       mask: Array(repeating: false, count: px.w * px.h))
        return true
    }

    private var selTint: (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(app.settings.accentColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private var stageDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if editingAnim {
                    if !dragging { dragging = true; selBefore = sel }
                    if pinching { return }
                    if panning {
                        if panFrom == nil { panFrom = viewPan }
                        let f = panFrom ?? .zero
                        viewPan = clampPan(CGSize(width: f.width + v.translation.width, height: f.height + v.translation.height))
                        return
                    }
                    animDrag(loc: cpt(v.location),
                             tr: CGSize(width: v.translation.width / viewZoom, height: v.translation.height / viewZoom))
                    return
                }
                guard !placingEffect, !spec.text.isEmpty, v.translation != .zero else { return }
                if dragFrom == nil { dragFrom = (spec.textX, spec.textY) }
                guard let f = dragFrom else { return }
                spec.textX = min(0.95, max(0.05, f.x + Double(v.translation.width / stageSide)))
                spec.textY = min(0.95, max(0.05, f.y + Double(v.translation.height / stageSide)))
            }
            .onEnded { v in
                dragFrom = nil
                dragging = false
                panFrom = nil
                if editingAnim, !pinching, !panning { animDragEnded(loc: cpt(v.location)) }
                if pinching { pivotAt = nil; poseFrom = nil }
            }
    }

    private func animDrag(loc: CGPoint, tr: CGSize) {
        guard let id = selectedPart else { return }
        switch animTool {
        case .pose:
            guard tr != .zero else { return }
            if poseFrom == nil { poseFrom = spec.anim?.pose(id, frame: animFrame) }
            guard var p = poseFrom else { return }
            let w = max(1, stageBox.width)
            p.dx += Double(tr.width / w)
            p.dy += Double(tr.height / w)
            spec.anim?.frames[animFrame][id] = p
        case .paint:
            // 点一下选一格，拖着就一路涂过去
            guard let a = spec.anim, let part = a.parts.first(where: { $0.id == id }),
                  ensureSel(part), var s = sel else { return }
            let (x, y) = partPixel(loc, part, a.pose(id, frame: animFrame), s.px)
            if s.paint(at: x, y, radius: brush - 1, erase: selErase) {
                s.overlay = s.overlayImage(selTint)
                sel = s
            }
        case .pivot:
            pivotAt = loc
        case .wand:
            break
        }
    }

    private func animDragEnded(loc: CGPoint) {
        poseFrom = nil
        guard let a = spec.anim, let id = selectedPart,
              let part = a.parts.first(where: { $0.id == id }) else { return }
        switch animTool {
        case .wand:
            guard ensureSel(part), var s = sel else { return }
            let (x, y) = partPixel(loc, part, a.pose(id, frame: animFrame), s.px)
            guard x >= 0, y >= 0 else { notice = "点在选中部位有颜色的地方"; return }
            let m = GifAnim.wandMask(s.px, Int(x), Int(y))
            if s.add(m, erase: selErase) {
                s.overlay = s.overlayImage(selTint)
                sel = s
            } else if !selErase { notice = "点在选中部位有颜色的地方" }
        case .pivot:
            pivotAt = nil
            setPivot(loc, id)
        case .pose, .paint:
            break
        }
    }

    /// 转轴设在手指那儿。换了转轴，转过、放大过的那些帧补一下挪的量，部位不会跳开
    private func setPivot(_ s: CGPoint, _ id: UUID) {
        guard var a = spec.anim, let k = a.parts.firstIndex(where: { $0.id == id }) else { return }
        let b = stageBox
        let part = a.parts[k]
        let q = unposed(s, part: part, pose: a.pose(id, frame: animFrame))
        let pv = CGPoint(x: b.minX + part.pivot.x * b.width, y: b.minY + part.pivot.y * b.height)
        let d = CGPoint(x: pv.x - q.x, y: pv.y - q.y)
        for f in a.frames.indices {
            guard var p = a.frames[f][id] else { continue }
            let th = CGFloat(p.rot) * .pi / 180, sc = CGFloat(p.scale)
            let rx = (d.x * cos(th) - d.y * sin(th)) * sc
            let ry = (d.x * sin(th) + d.y * cos(th)) * sc
            p.dx += Double((d.x - rx) / b.width)
            p.dy += Double((d.y - ry) / b.width)
            a.frames[f][id] = p
        }
        a.parts[k].pivot = CGPoint(x: (q.x - b.minX) / b.width, y: (q.y - b.minY) / b.height)
        spec.anim = a
    }

    /// 选好的像素切成一个新部位
    private func cutSelection() {
        guard var a = spec.anim, let s = sel, s.count > 0 else { return }
        if let new = a.cut(from: s.part, mask: s.mask, name: "部位\(a.parts.count)") {
            spec.anim = a
            animPart = new
            sel = nil
            // 切好接着设转轴
            animTool = .pivot
        } else { notice = "选中的地方没有颜色" }
    }

    /// 点选像素 / 点同色 那两个工具底下的一排
    private var selectionBar: some View {
        let has = (sel?.part == selectedPart) && (sel?.count ?? 0) > 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $selErase) {
                    Text("选").tag(false)
                    Text("擦").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                Toggle(isOn: $panning) { Image(systemName: "hand.draw") }
                    .toggleStyle(.button)
                    .tint(app.settings.accentColor)
                if animTool == .paint {
                    Picker("", selection: $brush) {
                        Text("1 格").tag(1)
                        Text("3 格").tag(2)
                        Text("5 格").tag(3)
                    }
                    .pickerStyle(.segmented)
                }
            }
            HStack(spacing: 8) {
                Button { cutSelection() } label: {
                    Label("切成部位", systemImage: "scissors").font(.app(12.5, weight: .medium))
                        .foregroundStyle(has ? .white : Theme.textMuted(scheme))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(has ? app.settings.accentColor : Theme.softFillDeep))
                }
                .buttonStyle(.plain)
                .disabled(!has)
                Button { sel = nil } label: {
                    Label("清空选择", systemImage: "xmark").font(.app(12.5))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.softFillDeep))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textMain(scheme))
                .disabled(!has)
            }
            Text("两指捏开放大画面；点手的图标后单指拖动是挪画面，再点一下回来继续选。")
                .font(.app(10.5)).foregroundStyle(Theme.textMuted(scheme))
        }
    }

    private var stageTurn: some Gesture {
        RotateGesture()
            .onChanged { v in
                guard editingAnim, animTool == .pose, let id = selectedPart else { return }
                let now = spec.anim?.pose(id, frame: animFrame) ?? PartPose()
                if rotFrom == nil { rotFrom = now.rot }
                var p = now
                p.rot = (rotFrom ?? 0) + v.rotation.degrees
                spec.anim?.frames[animFrame][id] = p
            }
            .onEnded { _ in rotFrom = nil }
    }

    private var stageZoom: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                guard editingAnim else { return }
                if animTool != .pose {
                    // 放大画面：捏的那一点不动
                    if !pinching {
                        pinching = true
                        zoomFrom = viewZoom
                        zoomPanFrom = viewPan
                        // 两根手指落下时第一根已经涂了几格：退回去
                        if animTool == .paint { sel = selBefore }
                        pivotAt = nil
                    }
                    let z0 = zoomFrom, p0 = zoomPanFrom
                    let c = CGPoint(x: (v.startLocation.x - p0.width) / z0, y: (v.startLocation.y - p0.height) / z0)
                    viewZoom = min(6, max(1, z0 * v.magnification))
                    viewPan = clampPan(CGSize(width: v.startLocation.x - c.x * viewZoom,
                                              height: v.startLocation.y - c.y * viewZoom))
                    return
                }
                guard let id = selectedPart else { return }
                let now = spec.anim?.pose(id, frame: animFrame) ?? PartPose()
                if scaleFrom == nil { scaleFrom = now.scale }
                var p = now
                p.scale = min(3, max(0.2, (scaleFrom ?? 1) * Double(v.magnification)))
                spec.anim?.frames[animFrame][id] = p
            }
            .onEnded { _ in
                scaleFrom = nil
                // 手指全抬起来以后再让拖动生效
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    pinching = false
                }
            }
    }

    private var pickButtons: some View {
        HStack(spacing: 10) {
            Button { choosing = true } label: {
                Label("从表情包挑", systemImage: "face.smiling").font(.app(12.5))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.softFillDeep))
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("从相册", systemImage: "photo").font(.app(12.5))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.softFillDeep))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMain(scheme))
    }

    private var sectionPicker: some View {
        Picker("", selection: $section) {
            Text("动作").tag(0)
            Text("特效").tag(1)
            Text("文字").tag(2)
            Text("逐帧").tag(4)
            Text("其他").tag(3)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .onChange(of: section) { _, v in
            // 第一次进逐帧：整张图当第一个部位，整体动作先关掉（不然跟她摆的动作叠在一起）
            if v == 4, spec.anim == nil, let base {
                spec.anim = GifAnim.start(base)
                spec.motion = .none
                animFrame = 0
                animPart = nil
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch section {
        case 0: chips(GifMotion.allCases, selected: spec.motion, label: { $0.label }) { spec.motion = $0 }
        case 1: effectControls
        case 4: animControls
        case 2: textControls
        default: otherControls
        }
    }

    private func chips<T: Hashable>(_ all: [T], selected: T, label: @escaping (T) -> String,
                                    pick: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(all, id: \.self) { v in
                Button { pick(v) } label: {
                    Text(label(v))
                        .font(.app(13))
                        .foregroundStyle(v == selected ? app.settings.accentColor : Theme.textMain(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(v == selected ? app.settings.accentColor.opacity(0.16) : Theme.softFillDeep))
                }
                .buttonStyle(.plain)
            }
        }
    }

    static let effectSpeeds: [Double] = [0.25, 0.5, 1, 2, 3, 4]

    static func speedLabel(_ v: Double) -> String {
        switch v {
        case 0.25: return "×¼"
        case 0.5:  return "×½"
        default:   return "×\(Int(v))"
        }
    }

    private var effectControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            chips(GifEffect.allCases, selected: spec.effect, label: { $0.label }) {
                spec.effect = $0
                spec.effectOffsets = [:]
            }
            if spec.effect != .none {
                Toggle("一颗一颗摆位置", isOn: $effectEditing).font(.app(14))
                if effectEditing {
                    let none = GifFrame.effectAnchors(base, spec: spec, side: stageSide).isEmpty
                    Text(none ? "这个特效是一整片的，没有一颗一颗的位置。"
                              : "圆点是每一颗开始的地方；拖圆点，那一颗就从那儿开始飘，预览照样在动。")
                        .font(.app(10.5)).foregroundStyle(Theme.textMuted(scheme))
                    if !spec.effectOffsets.isEmpty {
                        Button("全部回到原来的位置") { spec.effectOffsets = [:] }
                            .font(.app(12.5))
                    }
                }
                row("多少") { Slider(value: $spec.effectAmount, in: 0.5...4) }
                row("大小") {
                    HStack(spacing: 8) {
                        Slider(value: $spec.effectSize, in: 0.5...2.5)
                        Text(String(format: "×%.1f", spec.effectSize)).font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(width: 36)
                    }
                }
                row("快慢") {
                    // 往左慢、往右快：¼ ½ 1 2 3 4
                    HStack(spacing: 8) {
                        Slider(value: Binding(get: { Double(Self.effectSpeeds.firstIndex(of: spec.effectSpeed) ?? 2) },
                                              set: { spec.effectSpeed = Self.effectSpeeds[Int($0.rounded())] }),
                               in: 0...Double(Self.effectSpeeds.count - 1), step: 1)
                        Text(Self.speedLabel(spec.effectSpeed)).font(.app(12)).foregroundStyle(Theme.textSoft(scheme))
                            .frame(width: 36)
                    }
                }
                row("颜色") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button { spec.effectColor = "" } label: {
                                Text("原色").font(.app(11))
                                    .padding(.horizontal, 8).frame(height: 26)
                                    .background(Capsule().fill(spec.effectColor.isEmpty
                                                               ? app.settings.accentColor.opacity(0.2) : Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)
                            swatchRow($spec.effectColor)
                        }
                    }
                }
            }
        }
        .tint(app.settings.accentColor)
    }

    @ViewBuilder
    private var animControls: some View {
        if base == nil {
            Text("先挑一张图").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
        } else if spec.anim != nil {
            GifAnimEditor(anim: Binding(get: { spec.anim ?? GifAnim() }, set: { spec.anim = $0 }),
                          frame: $animFrame, selected: $animPart, tool: $animTool,
                          playing: $animPlaying, onion: $onion,
                          extras: animTool == .paint || animTool == .wand ? AnyView(selectionBar) : nil)
            Button { pickingPart = true } label: {
                Label("加零件（拼豆里存的零件）", systemImage: "puzzlepiece").font(.app(12.5))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textMain(scheme))
            .sheet(isPresented: $pickingPart) { partPicker }
            Button("不用逐帧了（回到上面那些动作）") {
                spec.anim = nil
                section = 0
            }
            .font(.app(12))
            .foregroundStyle(Theme.textMuted(scheme))
            .padding(.top, 6)
        }
    }

    private func swatchRow(_ value: Binding<String>) -> some View {
        HStack(spacing: 8) {
            ForEach(textColors, id: \.self) { hex in
                Button { value.wrappedValue = hex } label: {
                    Circle().fill(Color(hexString: hex) ?? .white)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.6))
                        .overlay(Circle().stroke(app.settings.accentColor, lineWidth: value.wrappedValue == hex ? 2.2 : 0)
                            .padding(-3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
    }

    private var textControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("写一句，比如：在吗", text: $spec.text)
                .font(.app(15))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            Text("在预览上拖动可以挪字的位置").font(.app(10.5)).foregroundStyle(Theme.textMuted(scheme))
            row("字号") {
                Slider(value: $spec.textSize, in: 0.07...0.3)
            }
            row("颜色") { swatches($spec.textColor) }
            row("描边") { swatches($spec.strokeColor) }
            row("描边粗细") {
                Slider(value: $spec.strokeWidth, in: 0...0.22)
            }
            row("字体") {
                Picker("", selection: $spec.font) {
                    ForEach(GifFont.allCases) { f in Text(f.label).tag(f) }
                }
                .pickerStyle(.segmented)
            }
            Text("字怎么动").font(.app(12, weight: .medium)).foregroundStyle(Theme.textSoft(scheme))
            chips(GifTextAnim.allCases, selected: spec.textAnim, label: { $0.label }) { spec.textAnim = $0 }
        }
    }

    private var otherControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("速度") {
                Slider(value: $spec.speed, in: 0.4...2.5)
            }
            row("图的大小") {
                Slider(value: $spec.imageScale, in: 0.4...0.95)
            }
            Toggle("像素图（放大不糊）", isOn: $spec.pixel).font(.app(14))
            Toggle("白底（边缘更干净）", isOn: $spec.whiteBG).font(.app(14))
            Text("换一张图").font(.app(12, weight: .medium)).foregroundStyle(Theme.textSoft(scheme))
            pickButtons
        }
        .tint(app.settings.accentColor)
    }

    private func row<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.app(13)).foregroundStyle(Theme.textSoft(scheme)).frame(width: 64, alignment: .leading)
            content()
        }
    }

    private func swatches(_ value: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(textColors, id: \.self) { hex in
                    Button { value.wrappedValue = hex } label: {
                        Circle().fill(Color(hexString: hex) ?? .white)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.6))
                            .overlay(Circle().stroke(app.settings.accentColor, lineWidth: value.wrappedValue == hex ? 2.2 : 0)
                                .padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)
        }
    }

    // MARK: 从表情包挑

    private var stickerPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                    ForEach(stickers.stickers.filter { $0.isUser }) { s in
                        Button {
                            if let img = Self.firstFrame(s) { use(img) }
                            choosing = false
                        } label: {
                            // 图本身不接手势（allowsHitTesting(false)），按钮得自己有一块能点的地方
                            StickerImage(sticker: s, size: 62)
                                .frame(maxWidth: .infinity, minHeight: 68)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .navigationTitle("挑一张表情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { choosing = false } } }
        }
    }

    /// 一张表情的图（动图取第一帧）
    static func firstFrame(_ s: Sticker) -> UIImage? {
        let store = StickerStore.shared
        if s.animated, !s.thumbName.isEmpty, let img = UIImage(contentsOfFile: store.url(s.thumbName).path) {
            return img
        }
        return UIImage(contentsOfFile: store.url(of: s).path)
    }

    // MARK: 加零件

    private var partPicker: some View {
        let parts = BeadStore.shared.projects.filter { $0.asPart == true }
        return NavigationStack {
            ScrollView {
                if parts.isEmpty {
                    Text("还没有零件。拼豆导出页点「存成零件」，就会出现在这里。")
                        .font(.app(12.5)).foregroundStyle(Theme.textMuted(scheme))
                        .multilineTextAlignment(.center)
                        .padding(.top, 40).padding(.horizontal, 24)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    ForEach(parts) { p in
                        Button {
                            let img = BeadStore.render(p, look: .pixel, cellPx: 8)
                            let aspect = base.map { Double($0.size.width / max(1, $0.size.height)) } ?? 1
                            spec.anim?.addPart(img, name: p.name.isEmpty ? "零件" : p.name, baseAspect: aspect)
                            animPart = spec.anim?.parts.last?.id
                            animTool = .pose
                            pickingPart = false
                        } label: {
                            VStack(spacing: 6) {
                                Image(uiImage: BeadStore.render(p, look: .pixel, cellPx: 4))
                                    .resizable().interpolation(.none).scaledToFit()
                                    .frame(height: 60)
                                Text(p.name.isEmpty ? "零件" : p.name).font(.app(11)).lineLimit(1)
                                    .foregroundStyle(Theme.textMain(scheme))
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .navigationTitle("加零件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { pickingPart = false } } }
        }
    }

    // MARK: 存

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("存成表情").font(.app(16, weight: .semibold)).foregroundStyle(Theme.textMain(scheme))
            TextField("名字", text: $title)
                .font(.app(15))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { saving = false; save() }
            Text("存进表情库「我的」里，一圈 \(spec.exportFrames) 帧。存好可以再存一份到手机相册。")
                .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
            HStack(spacing: 10) {
                Button { saving = false } label: {
                    Text("取消").font(.app(14))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.softFillDeep))
                }
                .foregroundStyle(Theme.textMain(scheme))
                Button { saving = false; save() } label: {
                    Text("存").font(.app(14, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(app.settings.accentColor))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WallpaperBackground())
        .presentationDetents([.height(250)])
        .onAppear { titleFocused = true }
    }

    private func save() {
        let spec = spec, base = base
        Task { @MainActor in
            guard let data = await Task.detached(priority: .userInitiated, operation: {
                GifFrame.gif(base, spec: spec)
            }).value, var s = StickerStore.shared.add(data: data, ext: "gif", owner: "user") else {
                notice = "没存上，再试一次。"
                return
            }
            let n = title.trimmingCharacters(in: .whitespacesAndNewlines)
            s.name = n.isEmpty ? (spec.text.isEmpty ? "动图" : spec.text) : n
            // 描述替她写好一句（他靠描述知道这张什么时候用），想改去表情库里改
            var about = (name.isEmpty ? "一张会动的表情" : name) + "，" + (spec.anim != nil ? "自己摆的动作" : spec.motion.label)
            if spec.effect != .none { about += "，" + spec.effect.label }
            if !spec.text.isEmpty { about += "，写着「" + spec.text + "」" }
            s.description = about
            s.animated = true
            StickerStore.shared.update(s)
            savedSticker = s
            notice = "存好了，在表情库「我的」里。"
        }
    }
}
