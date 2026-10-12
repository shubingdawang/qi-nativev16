import SwiftUI
import UIKit

/// 墙和地板：**跟小岛一个画法**的像素版。
///
/// 原来是 `WallFinishView` / `FloorFinishView` 用矢量线现画的——线是细的、边是软的，
/// 跟小岛那种一格一格的像素画放不到一起。这儿按屋子的几何**逐像素**画一张小图，
/// 一个像素就是 `RoomPixel.px` 那么大（跟窗户、踢脚线那层细节同一把尺子），放大不插值。
///
/// 每种墙纸、地板都照原来的样子画成像素版；主题配色照用（只取浅色那套——
/// 晚上变暗交给 `RoomNightShade`，跟小岛一样，不靠深色模式把墙涂成深棕）。
///
/// ⚠️ 画一张要逐像素算，**放后台算、算好缓存**；平面屋左右拖的时候不重画，
/// 拿不带偏移的那间屋画好，整张跟着挪（见 `IsoRoomView.walls`）。
struct RoomPixelShell: View {

    let room: IsoRoom
    let size: CGSize
    let wall: RoomFinish.Wall
    let floor: RoomFinish.Floor
    let theme: RoomTheme?
    let floorTheme: RoomTheme?
    var paintWalls = true
    var paintFloor = true

    @State private var image: UIImage?

    private var key: String {
        [room.projection.rawValue, "\(Int(size.width))x\(Int(size.height))",
         wall.rawValue, floor.rawValue, theme?.id ?? "-", floorTheme?.id ?? "-",
         paintWalls ? "w" : "", paintFloor ? "f" : ""].joined(separator: "|")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .task(id: key) {
            if let hit = RoomShellPainter.cache.object(forKey: key as NSString) {
                image = hit
                return
            }
            let job = RoomShellPainter(room: room, size: size, wall: wall, floor: floor,
                                       wallHexes: theme?.wallColors(.light) ?? [],
                                       floorHexes: floorTheme?.floorColors(.light) ?? [],
                                       paintWalls: paintWalls, paintFloor: paintFloor)
            let k = key
            let img = await Task.detached(priority: .userInitiated) { job.render() }.value
            if let img { RoomShellPainter.cache.setObject(img, forKey: k as NSString) }
            image = img
        }
    }
}

/// 真正一个像素一个像素画的那一段。不碰界面，后台跑。
struct RoomShellPainter {

    let room: IsoRoom
    let size: CGSize
    let wall: RoomFinish.Wall
    let floor: RoomFinish.Floor
    let wallHexes: [String]
    let floorHexes: [String]
    let paintWalls: Bool
    let paintFloor: Bool

    nonisolated(unsafe) static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 12
        return c
    }()

    typealias RGB = (r: Double, g: Double, b: Double)

    func render() -> UIImage? {
        let px = RoomPixel.px(room)
        let W = Int((size.width / px).rounded(.up)), H = Int((size.height / px).rounded(.up))
        guard W > 0, H > 0, W * H < 3_000_000 else { return nil }
        var buf = [UInt32](repeating: 0, count: W * H)
        let pal = palette()
        let g = room
        let n = Double(g.size), across = Double(g.across)
        let wallPx = Double(g.wallH / px)
        // 等距：墙角（地板最里那个顶点）和两面墙的另一头
        let c0 = g.point(0, 0), l0 = g.point(0, n - 1), r0 = g.point(n - 1, 0)
        let corner = CGPoint(x: c0.x, y: c0.y - g.tileH / 2)
        let leftEnd = CGPoint(x: l0.x - g.tileW / 2, y: l0.y)
        let rightEnd = CGPoint(x: r0.x + g.tileW / 2, y: r0.y)
        // 平面：后墙
        let backY = g.point(0, 0).y - g.rowPitch / 2
        let backHalf = g.tileW * g.flatWide(-0.5) * CGFloat(g.cols) / 2
        // 一格宽多少个像素点（量缝有多粗用）
        let tileArt = Double(g.tileW / px)
        let seam = 1.15 / max(4, tileArt * (g.projection == .flat ? 1.0 : 0.56))

        for j in 0..<H {
            for i in 0..<W {
                let p = CGPoint(x: (CGFloat(i) + 0.5) * px, y: (CGFloat(j) + 0.5) * px)
                var c: RGB?
                // 地板
                let t = g.tile(at: p)
                if t.gx >= -0.5 && t.gx < across - 0.5 && t.gy >= -0.5 && t.gy < n - 0.5 {
                    if paintFloor { c = floorColor(t.gx + 0.5, t.gy + 0.5, seam, pal, i, j) }
                } else if paintWalls {
                    if g.projection == .flat {
                        if p.x >= g.origin.x - backHalf && p.x < g.origin.x + backHalf
                            && p.y < backY && p.y >= backY - g.wallH {
                            let s = Int((p.x - (g.origin.x - backHalf)) / px)
                            let h = Int((backY - p.y) / px)
                            c = wallColor(s, h, wallPx, pal.wallL, pal)
                        }
                    } else if p.x < corner.x {
                        let f = (corner.x - p.x) / max(1, corner.x - leftEnd.x)
                        if f < 1 {
                            let baseY = corner.y + (leftEnd.y - corner.y) * f
                            let h = baseY - p.y
                            if h >= 0 && h < g.wallH {
                                c = wallColor(Int((corner.x - p.x) / px), Int(h / px), wallPx, pal.wallL, pal)
                            }
                        }
                    } else {
                        let f = (p.x - corner.x) / max(1, rightEnd.x - corner.x)
                        if f < 1 {
                            let baseY = corner.y + (rightEnd.y - corner.y) * f
                            let h = baseY - p.y
                            if h >= 0 && h < g.wallH {
                                c = wallColor(Int((p.x - corner.x) / px), Int(h / px), wallPx, pal.wallR, pal)
                            }
                        }
                    }
                }
                if let c {
                    let r = UInt32(max(0, min(255, c.r))), gg = UInt32(max(0, min(255, c.g)))
                    let b = UInt32(max(0, min(255, c.b)))
                    // RGBA，小端存成 ABGR
                    buf[j * W + i] = 0xFF00_0000 | (b << 16) | (gg << 8) | r
                }
            }
        }
        let data = buf.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: W * 4, space: space,
                               // 内存里一个像素是 R G B A 四个字节（上面那个 UInt32 小端存的正是这个顺序）
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: 颜色

    struct Palette {
        var wallL: RGB
        var wallR: RGB
        var accent: RGB
        var floor: [RGB]
        var floorSeam: RGB
        var floorInk: RGB
    }

    static func rgb(_ hex: String) -> RGB {
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return (200, 200, 200) }
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    static func mul(_ c: RGB, _ k: Double) -> RGB { (c.r * k, c.g * k, c.b * k) }

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    /// 暗一档：只带一丝暖粉（跟小岛的阴影一个方向），不往灰里、也不往紫里压
    static func shade(_ c: RGB, _ k: Double) -> RGB {
        (c.r * k, c.g * k * 0.985, c.b * k * 0.99)
    }

    private func palette() -> Palette {
        let wl = wallHexes.first.map(Self.rgb) ?? Self.rgb("F6EDE3")
        let wr: RGB = wallHexes.count > 1 ? Self.rgb(wallHexes[1]) : Self.shade(wl, 0.95)
        let accentDefault: String
        switch wall {
        case .bows: accentDefault = "F2A7B8"
        case .lace: accentDefault = "F2C3CD"
        case .stripe: accentDefault = "F3D9D0"
        default: accentDefault = "E9D3C2"
        }
        let accent = wallHexes.count > 2 ? Self.rgb(wallHexes[2]) : Self.rgb(accentDefault)
        let defaults: [String]
        switch floor {
        case .checker: defaults = ["E9D9C0", "DCC8AA"]
        case .wood: defaults = ["E3BA88", "DBAF7C", "E9C493"]
        case .tatami: defaults = ["DCD8A6", "D1CD98"]
        case .tile: defaults = ["F1F0EB"]
        case .terrazzo: defaults = ["EEE8DF"]
        case .bows: defaults = ["F8ECD8", "F2E3CB", "C9A7DE"]
        }
        let hexes = floorHexes.isEmpty ? defaults : floorHexes
        var tones = hexes.map(Self.rgb)
        while tones.count < 3 { tones.append(Self.shade(tones.last ?? (220, 200, 180), 0.96)) }
        let seam: RGB
        switch floor {
        case .tatami: seam = Self.mix(Self.rgb("9AA66A"), tones[0], 0.35)
        case .tile, .terrazzo: seam = Self.mix(tones[0], (255, 255, 255), 0.55)
        default: seam = Self.shade(tones[0], 0.8)
        }
        let ink = floor == .bows ? tones[2] : Self.shade(tones[0], 0.72)
        return Palette(wallL: wl, wallR: wr, accent: accent, floor: tones, floorSeam: seam, floorInk: ink)
    }

    static func hash(_ a: Int, _ b: Int, _ salt: Int) -> Double { RoomPixel.hash(a, b, salt) }

    // MARK: 墙

    /// 墙上一点：`s` 沿墙第几个像素、`h` 离地第几个像素、`H` 墙多高（像素）
    private func wallColor(_ s: Int, _ h: Int, _ H: Double, _ base: RGB, _ pal: Palette) -> RGB {
        let dk = Self.shade(base, 0.93)
        let lt = Self.mix(base, (255, 255, 255), 0.4)
        switch wall {
        case .plain:
            return (s % 9 == 0 && h % 9 == 4) ? dk : base
        case .stripe:
            let band = (s / 5) % 2
            if s % 5 == 0 { return Self.shade(base, 0.95) }
            return band == 0 ? base : Self.mix(base, pal.accent, 0.45)
        case .brick:
            let row = h / 5
            let off = row % 2 == 0 ? 0 : 6
            let bx = (s + off) % 12
            if h % 5 == 0 || bx == 0 { return lt }
            let k = 0.95 + 0.06 * Self.hash((s + off) / 12, row, 9)
            let brick = Self.mul(Self.mix(base, (226, 170, 150), 0.35), k)
            return h % 5 == 4 ? Self.mix(brick, (255, 255, 255), 0.18) : brick
        case .wainscot:
            let cut = Int(H * 0.36)
            if h < cut - 2 {
                let wood = Self.mix(base, (232, 200, 160), 0.6)
                if s % 6 == 0 { return Self.shade(wood, 0.84) }
                return (s / 6) % 2 == 0 ? wood : Self.shade(wood, 0.97)
            }
            if h < cut {
                return h == cut - 1 ? Self.mix(base, (255, 250, 240), 0.6) : Self.shade(Self.mix(base, (232, 200, 160), 0.6), 0.86)
            }
            return (s % 9 == 0 && h % 9 == 4) ? dk : base
        case .tile:
            if s % 7 == 0 || h % 6 == 0 { return lt }
            if s % 7 == 6 || h % 6 == 1 { return Self.shade(base, 0.95) }
            return base
        case .lace:
            let cut = Int(H * 0.34)
            if h < cut {
                // 下半截素板，花边垂在腰线下面
                let scallop = [1, 2, 3, 3, 2, 1][s % 6]
                if h >= cut - scallop {
                    return (s % 6 == 2 && h == cut - 2) ? Self.mix(pal.accent, base, 0.3) : (255, 253, 250)
                }
                return Self.shade(Self.mix(base, pal.accent, 0.25), 0.95)
            }
            if h < cut + 2 { return (255, 252, 248) }
            return s % 6 < 2 ? Self.mix(base, pal.accent, 0.5) : base
        case .bows:
            let row = h / 15
            let off = row % 2 == 0 ? 0 : 8
            let bx = (s + off) % 16 - 5, by = h % 15 - 6
            // 5×4 的小蝴蝶结：两片翅膀 + 中间一颗结 + 两根飘带
            let shape: [Int: Int] = [0: 1, 1: 1, 3: 1, 4: 1, 10: 1, 11: 2, 12: 2, 13: 2, 14: 1,
                                     20: 1, 21: 1, 23: 1, 24: 1]
            if bx >= 0 && bx < 5 && by >= 0 && by < 3, let k = shape[by * 10 + bx] {
                return k == 2 ? Self.shade(pal.accent, 0.86) : pal.accent
            }
            if by == -1 && (bx == 1 || bx == 3) { return Self.shade(pal.accent, 0.92) }
            return (s % 8 == 0 && h % 8 == 4) ? Self.shade(base, 0.97) : base
        }
    }

    // MARK: 地

    /// 地上一点：`u` 沿 gx、`v` 沿 gy（格，从墙角量）
    private func floorColor(_ u: Double, _ v: Double, _ seam: Double, _ pal: Palette,
                            _ i: Int, _ j: Int) -> RGB {
        let iu = Int(u.rounded(.down)), iv = Int(v.rounded(.down))
        let fu = u - Double(iu), fv = v - Double(iv)
        let t = pal.floor
        switch floor {
        case .checker:
            let c = (iu + iv) % 2 == 0 ? t[0] : t[1]
            if fu < seam || fv < seam { return Self.mix(c, (255, 255, 255), 0.18) }
            return c
        case .wood:
            // 板子顺着 gy 铺，一格两条
            let b = Int((u * 2).rounded(.down))
            let fb = u * 2 - Double(b)
            if fb < seam * 2 { return pal.floorSeam }
            let joint = ((v + Double(b % 4) * 1.3) / 3).truncatingRemainder(dividingBy: 1)
            if joint < seam / 3 { return pal.floorSeam }
            var c = t[b % 3]
            if Self.hash(i, j, 41) < 0.035 { c = Self.shade(c, 0.9) }
            if fb > 1 - seam * 2 { c = Self.mix(c, (255, 250, 240), 0.15) }
            return c
        case .tatami:
            // 一张席 1×2 格，隔一张换个方向
            let flip = (iu + iv / 2) % 2 == 0
            let mu = flip ? fu : (v / 2 - Double(iv / 2))
            let mv = flip ? (v / 2 - Double(iv / 2)) : fu
            if mu < seam * 1.4 || mv < seam * 0.8 { return pal.floorSeam }
            let weave = Int((mv * 14).rounded(.down)) % 2 == 0
            return weave ? t[0] : t[1]
        case .tile:
            if fu < seam || fv < seam { return pal.floorSeam }
            if fu > 1 - seam || fv > 1 - seam { return Self.shade(t[0], 0.94) }
            return t[0]
        case .terrazzo:
            let r = Self.hash(i, j, 63)
            if r < 0.008 { return Self.rgb("D8A49A") }
            if r < 0.016 { return Self.rgb("A9C1B4") }
            if r < 0.03 { return Self.shade(t[0], 0.86) }
            if fu < seam || fv < seam { return pal.floorSeam }
            return t[0]
        case .bows:
            let light = (iu + iv) % 2 == 0
            let c = light ? t[0] : t[1]
            if fu < seam || fv < seam { return Self.mix(c, pal.floorInk, 0.25) }
            if light {
                // 躺在地上的小蝴蝶结：在屏幕上是横着的
                let du = fu - 0.5, dv = fv - 0.5
                let sx = du - dv, sy = (du + dv) / 2
                if abs(sx) < 0.05 && abs(sy) < 0.05 { return Self.shade(pal.floorInk, 0.85) }
                if abs(sx) < 0.24 && abs(sy) < 0.03 + abs(sx) * 0.4 { return pal.floorInk }
            }
            return c
        }
    }
}
