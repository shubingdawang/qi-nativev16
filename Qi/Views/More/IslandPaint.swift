import UIKit

// MARK: - 栖岛的地面：按像素画
//
// 每种地块不是拼图块，而是按格子算出一个平滑的形状（格子之间双线性插值 + 一点起伏），
// 再按离边几像素分出描边、背光边、受光边。草地有很淡的大块明暗、一丛丛小草、零星野花；
// 路有小石子，田是一垄一垄的，池塘有深浅、岸边一圈亮和波光，海岸有湿沙、沙滩、白浪、浅水。
// 一格 16 像素，放大三倍不插值。跟 scripts/island/terrain.py 是同一套算法（那边出预览）。

enum IslandPaint {

    static let px = 16

    struct RGB { let r: UInt8, g: UInt8, b: UInt8 }

    private static func c(_ hex: UInt32) -> RGB {
        RGB(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }
    private static func mix(_ a: RGB, _ b: RGB, _ t: Float) -> RGB {
        RGB(r: UInt8(Float(a.r) * (1 - t) + Float(b.r) * t), g: UInt8(Float(a.g) * (1 - t) + Float(b.g) * t),
            b: UInt8(Float(a.b) * (1 - t) + Float(b.b) * t))
    }

    // 调色：淡、干净；暗部往玫瑰紫 / 蓝绿走，描边是深梅色
    private static let grass = [c(0x86B97F), c(0xA2CD8D), c(0xB2D89B), c(0xC6E3AB)]
    private static let blade = [c(0x6FA373), c(0xD2EBB2)]
    private static let path = [c(0xC9A993), c(0xE3CBB2), c(0xEED9C1), c(0xF6E8D4)]
    private static let pathRim = c(0xA4847D)
    private static let sand = [c(0xE8CFAE), c(0xF3E2C4), c(0xF8EDD8)]
    private static let sandRim = c(0xD6B699)
    private static let soil = [c(0x9A6E64), c(0xB68877), c(0xCDA08C)]
    private static let soilRim = c(0x765056)
    private static let water = [c(0x74B6C6), c(0x8ECCD3), c(0xA9DCDC), c(0xD3F0EA)]
    private static let waterRim = c(0x5F8E9E)
    private static let wood = [c(0xA9776A), c(0xD2A285), c(0xE3BC9B)]
    private static let woodRim = c(0x7C5560)
    private static let board = [c(0x8A5E5A), c(0xA97970), c(0xC4968A), c(0xDDB5A6)]
    private static let plum = c(0x4E3A4F)
    private static let stone = [c(0xA79BA5), c(0xCFC6CE), c(0xDDD6DC), c(0xEEE9ED)]
    private static let stoneRim = c(0x8E8396)
    static let sea = [c(0x86CDD8), c(0xA2DCE1), c(0xC2EBEA)]
    private static let foam = c(0xF6FCF9)
    private static let wet = c(0xDDBFA0)
    private static let petals = [c(0xF7C6D4), c(0xFBEFF3), c(0xD9C6EE), c(0xFBE3A6), c(0xF5A9B8)]
    private static let wild = [c(0xFBEFF3), c(0xFBE3A6), c(0xF7C6D4)]
    private static let bloom = c(0xF2C46B)

    private static let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { Float($0) / 16 }

    @inline(__always) static func nz(_ x: Double, _ y: Double, _ k: Double = 0) -> Double {
        let v = sin(x * 12.9898 + y * 78.233 + k * 37.719) * 43758.5453
        return v - floor(v)
    }

    static func vnoise(_ x: Double, _ y: Double, _ k: Double) -> Double {
        let i = floor(x), j = floor(y)
        var fx = x - i, fy = y - j
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        let a = nz(i, j, k), b = nz(i + 1, j, k), c = nz(i, j + 1, k), d = nz(i + 1, j + 1, k)
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    }

    /// 格子上的 0/1 → 每个像素在不在里面（双线性 + 起伏 > 0.5）
    private static func field(_ ind: (Int, Int) -> Bool, _ tw: Int, _ th: Int, wobble: Double, k: Double) -> [Bool] {
        let W = tw * px, H = th * px
        var pad = [Double](repeating: 0, count: (tw + 2) * (th + 2))
        for y in 0..<th { for x in 0..<tw where ind(x, y) { pad[(y + 1) * (tw + 2) + x + 1] = 1 } }
        var out = [Bool](repeating: false, count: W * H)
        for y in 0..<H {
            let v = (Double(y) + 0.5) / Double(px) - 0.5 + 1
            let j = min(th, max(0, Int(floor(v)))), fv = v - floor(v)
            for x in 0..<W {
                let u = (Double(x) + 0.5) / Double(px) - 0.5 + 1
                let i = min(tw, max(0, Int(floor(u)))), fu = u - floor(u)
                let r0 = j * (tw + 2), r1 = (j + 1) * (tw + 2)
                var f = (pad[r0 + i] * (1 - fu) + pad[r0 + i + 1] * fu) * (1 - fv) + (pad[r1 + i] * (1 - fu) + pad[r1 + i + 1] * fu) * fv
                f += (vnoise(Double(x) / 7, Double(y) / 7, k) - 0.5) * wobble
                out[y * W + x] = f > 0.5
            }
        }
        return out
    }

    /// 每个 true 像素离最近的 false 有几步（八邻域，切比雪夫距离），最多 n+1。outside：画面外面算不算 true
    private static func dist(_ m: [Bool], _ W: Int, _ H: Int, _ n: Int, outside: Bool = false) -> [UInt8] {
        let big = Int32(n + 1)
        var d = m.map { $0 ? big : 0 }
        func at(_ x: Int, _ y: Int) -> Int32 {
            guard x >= 0, y >= 0, x < W, y < H else { return outside ? big : 0 }
            return d[y * W + x]
        }
        for y in 0..<H {
            for x in 0..<W where d[y * W + x] != 0 {
                let v = min(d[y * W + x], at(x - 1, y) + 1, at(x - 1, y - 1) + 1, at(x, y - 1) + 1, at(x + 1, y - 1) + 1)
                d[y * W + x] = v
            }
        }
        for y in stride(from: H - 1, through: 0, by: -1) {
            for x in stride(from: W - 1, through: 0, by: -1) where d[y * W + x] != 0 {
                let v = min(d[y * W + x], at(x + 1, y) + 1, at(x + 1, y + 1) + 1, at(x, y + 1) + 1, at(x - 1, y + 1) + 1)
                d[y * W + x] = v
            }
        }
        return d.map { UInt8(min(Int32(255), $0)) }
    }

    /// 整片地面，一格 16 像素，带透明（海那里是空的，底下铺海的图）
    // 各季节的草、草叶、野花、花丛、池塘
    private static func palette(_ s: WorldSeason) -> (grass: [RGB], blade: [RGB], wild: [RGB], petals: [RGB], water: [RGB]) {
        switch s {
        case .spring:
            return (grass, blade, wild, petals, water)
        case .summer:
            return ([c(0x7DB57A), c(0x98CA86), c(0xA9D492), c(0xBEE0A4)], [c(0x649D6A), c(0xCDEAAA)],
                    [c(0xFFFFFF), c(0xFBE3A6), c(0xF5A9B8)], [c(0xF5A9B8), c(0xFFFFFF), c(0xC9B6E8), c(0xFBE3A6), c(0xA9DCDC)], water)
        case .autumn:
            return ([c(0xAFAA74), c(0xC6C087), c(0xD3CC93), c(0xE1D9A6)], [c(0x9E8A5A), c(0xEBD9A2)],
                    [c(0xF5B38A), c(0xF2C46B), c(0xE9A28F)],
                    [c(0xF2B07E), c(0xE98F78), c(0xF4CE7A), c(0xD9A56F), c(0xFBE3C2)], water)
        case .winter:
            return ([c(0xDCE4EE), c(0xEBF0F6), c(0xF4F7FB), c(0xFFFFFF)], [c(0xB7C4D4), c(0xFFFFFF)],
                    [c(0xD6DFEB), c(0xFFFFFF), c(0xE3E9F2)],
                    [c(0xFFFFFF), c(0xE6ECF4), c(0xD9E2EE), c(0xF4F7FB), c(0xC8D4E2)],
                    [c(0x9CC6D4), c(0xBADCE6), c(0xCFE7EE), c(0xEEF8FB)])
        }
    }

    static func render(_ g: [WorldGround], width tw: Int, height th: Int, season: WorldSeason = .spring) -> CGImage? {
        let W = tw * px, H = th * px, N = W * H
        let pal = palette(season)
        let grass = pal.grass, blade = pal.blade, wild = pal.wild, petals = pal.petals, water = pal.water
        func kind(_ x: Int, _ y: Int) -> WorldGround {
            guard x >= 0, y >= 0, x < tw, y < th else { return .sea }
            return g[y * tw + x]
        }
        var rgb = [RGB](repeating: grass[1], count: N)
        var alpha = [Float](repeating: 1, count: N)

        // ── 草地：一整片底色，很淡的大块明暗，一丛丛小草，零星野花
        for y in 0..<H {
            for x in 0..<W {
                let i = y * W + x
                let fx = Double(x), fy = Double(y)
                let t = vnoise(fx / 30, fy / 30, 1) * 0.7 + vnoise(fx / 12, fy / 12, 2) * 0.3 + Double(bayer[(y % 4) * 4 + x % 4] - 0.5) * 0.12
                if t > 0.6 { rgb[i] = grass[2] } else if t < 0.36 { rgb[i] = mix(grass[1], grass[0], 0.35) }
                // 小草丛：每 6×6 一格里最多一丛
                let cx = floor(fx / 6), cy = floor(fy / 6)
                if nz(cx, cy, 5) < 0.30 {
                    let lx = x % 6 - (Int(nz(cx, cy, 6) * 3) + 1), ly = y % 6 - (Int(nz(cx, cy, 7) * 2) + 2)
                    switch Int(nz(cx, cy, 8) * 3) {
                    case 0:
                        if (lx == 0 && ly == 0) || (lx == 2 && ly == 0) || (lx == 1 && ly == 1) { rgb[i] = blade[0] }
                        if (lx == 0 || lx == 2) && ly == -1 { rgb[i] = blade[1] }
                    case 1:
                        if lx == 1 && (ly == 0 || ly == 1) { rgb[i] = blade[0] }
                        if lx == 1 && ly == -1 { rgb[i] = blade[1] }
                    default:
                        if (lx == 0 && ly == 1) || (lx == 1 && (ly == 0 || ly == 1)) || (lx == 2 && ly == 1) { rgb[i] = blade[0] }
                        if (lx == 1 && ly == -1) || (lx == 0 && ly == 0) || (lx == 2 && ly == 0) { rgb[i] = blade[1] }
                    }
                }
                let wx = floor(fx / 9), wy = floor(fy / 9)
                if nz(wx, wy, 16) < 0.16, x % 9 == Int(nz(wx, wy, 17) * 7) + 1, y % 9 == Int(nz(wx, wy, 18) * 7) + 1 {
                    rgb[i] = wild[Int(nz(wx, wy, 19) * 3) % 3]
                }
            }
        }

        // ── 花丛：草上撒小花，黄心 + 四瓣
        let fl = field({ kind($0, $1) == .flowers }, tw, th, wobble: 0.35, k: 11)
        for y in 0..<H {
            for x in 0..<W where fl[y * W + x] {
                let cx = floor(Double(x) / 5), cy = floor(Double(y) / 5)
                guard nz(cx, cy, 12) < 0.62 else { continue }
                let lx = x % 5 - (Int(nz(cx, cy, 13) * 2) + 1), ly = y % 5 - (Int(nz(cx, cy, 14) * 2) + 1)
                let col = petals[Int(nz(cx, cy, 15) * 5) % 5]
                let i = y * W + x
                if (lx == 1 && (ly == 0 || ly == 2)) || (ly == 1 && (lx == 0 || lx == 2)) { rgb[i] = col }
                if lx == 1 && ly == 1 { rgb[i] = bloom }
                if lx == 1 && ly == 3 { rgb[i] = blade[0] }
            }
        }

        // ── 一般地块：填色 → 纹理 → 上沿左沿背光、下沿受光、外圈描边
        func terrain(_ k: WorldGround, _ cols: [RGB], _ rim: RGB, wobble: Double, seed: Double,
                     _ texture: (Int, Int, Int) -> Void) -> [Bool] {
            // 岛上没有这种地就不用算
            guard g.contains(k) else { return [Bool](repeating: false, count: N) }
            let m = field({ kind($0, $1) == k }, tw, th, wobble: wobble, k: seed)
            let d = dist(m, W, H, 4)
            func on(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < W && y < H && m[y * W + x] }
            for y in 0..<H {
                for x in 0..<W where m[y * W + x] {
                    let i = y * W + x
                    rgb[i] = cols[1]
                    texture(x, y, i)
                    let up = !on(x, y - 1) || !on(x, y - 2), lt = !on(x - 1, y), dn = !on(x, y + 1)
                    if (up || lt) && d[i] <= 2 { rgb[i] = cols[0] }
                    if dn { rgb[i] = cols[cols.count - 1] } else if d[i] == 1 { rgb[i] = rim }
                }
            }
            return m
        }

        _ = terrain(.sand, sand, sandRim, wobble: 0.3, seed: 21) { x, y, i in
            let s = nz(Double(x), Double(y), 41)
            if s < 0.05 { rgb[i] = sand[0] } else if s > 0.96 { rgb[i] = sand[2] }
        }
        let pathM = terrain(.path, path, pathRim, wobble: 0.22, seed: 22) { x, y, i in
            // 稀疏的小石子：两像素，上亮下暗
            let cx = floor(Double(x) / 7), cy = floor(Double(y) / 6)
            if nz(cx, cy, 31) < 0.45 {
                let lx = x % 7 - Int(nz(cx, cy, 32) * 5), ly = y % 6 - Int(nz(cx, cy, 33) * 4)
                if lx == 0 || lx == 1 {
                    if ly == 0 { rgb[i] = path[3] } else if ly == 1 { rgb[i] = path[0] }
                }
            }
            if nz(Double(x), Double(y), 34) < 0.025 { rgb[i] = path[0] }
        }
        _ = terrain(.soil, soil, soilRim, wobble: 0.12, seed: 23) { x, y, i in
            // 一垄一垄，垄背微微起伏
            let wave = Int(((vnoise(Double(x) / 5, floor(Double(y) / 5), 52) - 0.5) * 1.6).rounded())
            let row = ((y + wave) % 5 + 5) % 5
            if row == 0 { rgb[i] = soil[2] }
            if row == 4 { rgb[i] = soil[0] }
            if row == 2, nz(Double(x), Double(y), 53) < 0.07 { rgb[i] = soil[0] }
            if row == 1, nz(Double(x), Double(y), 54) < 0.05 { rgb[i] = soil[2] }
        }
        // 石板：一块块错开的方石，缝暗，左上一点亮，有的深一点
        _ = terrain(.stone, stone, stoneRim, wobble: 0.1, seed: 25) { x, y, i in
            let row = y / 5
            let sx = x + (row % 2) * 4
            let lx = sx % 8, ly = y % 5
            if nz(floor(Double(sx) / 8), Double(row), 81) > 0.6 { rgb[i] = stone[2] }
            if lx == 1 && ly == 1 { rgb[i] = stone[3] }
            if lx == 0 || ly == 0 { rgb[i] = stone[0] }
        }
        var pond = [UInt8]()
        let pondM = field({ kind($0, $1) == .water }, tw, th, wobble: 0.3, k: 24)
        pond = dist(pondM, W, H, 12)
        _ = terrain(.water, water, waterRim, wobble: 0.3, seed: 24) { x, y, i in
            let dd = pond[i]
            if dd > 5 { rgb[i] = water[0] }
            else if dd > 2, bayer[(y % 4) * 4 + x % 4] < 0.5 { rgb[i] = water[0] }
            if dd == 2 { rgb[i] = water[3] }
            if dd > 3, nz(floor(Double(x) / 4), Double(y), 61) < 0.05 { rgb[i] = water[3] }
        }
        // 池塘外面一圈草压暗一点（岸边的影子）
        let ring = dist(pondM.map { !$0 }, W, H, 2, outside: true)
        for i in 0..<N where !pondM[i] && ring[i] == 1 && !pathM[i] { rgb[i] = grass[0] }

        // ── 海岸：木桥不算陆地
        func bridge(_ x: Int, _ y: Int) -> Bool {
            kind(x, y) == .wood && [(0, 1), (0, -1), (1, 0), (-1, 0)].contains { kind(x + $0.0, y + $0.1) == .sea }
        }
        let landF = field({ kind($0, $1) != .sea && !bridge($0, $1) }, tw, th, wobble: 0.24, k: 3)
        let din = dist(landF, W, H, 12)
        let dout = dist(landF.map { !$0 }, W, H, 10, outside: true)
        for y in 0..<H {
            for x in 0..<W {
                let i = y * W + x
                let k = kind(x / px, y / px)
                if landF[i] {
                    let soft = k == .grass || k == .flowers || k == .sand || k == .sea
                    guard soft else { continue }
                    let d = Int(din[i])
                    let sw = 6 + Int(vnoise(Double(x) / 11, Double(y) / 11, 7) * 4)
                    if d <= 1 { rgb[i] = wet }
                    else if d == 2 { rgb[i] = sand[0] }
                    else if d <= sw {
                        rgb[i] = sand[1]
                        if nz(Double(x), Double(y), 71) < 0.05 { rgb[i] = sand[0] }
                        if nz(Double(x), Double(y), 72) > 0.95 { rgb[i] = sand[2] }
                    } else if d == sw + 1 && k != .sand { rgb[i] = sandRim }
                    else if k == .sea { rgb[i] = sand[1] }
                } else {
                    let d = Int(dout[i])
                    alpha[i] = 0
                    if d <= 1 { rgb[i] = foam; alpha[i] = 1 }
                    else if d == 2 { rgb[i] = sea[2]; alpha[i] = 1 }
                    else if d == 5 && vnoise(Double(x) / 5, Double(y) / 5, 9) > 0.42 { rgb[i] = foam; alpha[i] = 0.7 }
                    else if d >= 3 && d < 9 { rgb[i] = sea[2]; alpha[i] = 0.5 * (1 - Float(d - 3) / 6) }
                }
            }
        }

        // ── 木地板（岛上的）：横木板，整格
        var woodM = [Bool](repeating: false, count: N)
        for ty in 0..<th {
            for tx in 0..<tw where kind(tx, ty) == .wood && !bridge(tx, ty) {
                for y in (ty * px)..<((ty + 1) * px) { for x in (tx * px)..<((tx + 1) * px) { woodM[y * W + x] = true } }
            }
        }
        let wd = dist(woodM, W, H, 2)
        for y in 0..<H {
            for x in 0..<W where woodM[y * W + x] {
                let i = y * W + x
                rgb[i] = wood[1]
                if y % 6 == 0 { rgb[i] = wood[0] } else if y % 6 == 1 { rgb[i] = wood[2] }
                if (x + (y / 6) * 7) % 16 == 0 { rgb[i] = wood[0] }
                if wd[i] == 1 { rgb[i] = woodRim }
                alpha[i] = 1
            }
        }

        // ── 桥：木板竖着铺，后面一道栏杆、前面一道栏杆，桥下影子，桩子插进水里
        func put(_ x: Int, _ y: Int, _ c: RGB, _ a: Float = 1) {
            guard x >= 0, y >= 0, x < W, y < H else { return }
            rgb[y * W + x] = c; alpha[y * W + x] = a
        }
        for ty in 0..<th {
            for tx in 0..<tw where bridge(tx, ty) {
                let x0 = tx * px, y0 = ty * px
                for y in (y0 + 3)..<(y0 + 13) {
                    for x in x0..<(x0 + px) { put(x, y, x % 4 == 0 ? board[0] : (x % 4 == 1 ? board[3] : board[2])) }
                }
                for x in x0..<(x0 + px) {
                    put(x, y0 + 2, plum); put(x, y0 + 13, board[0]); put(x, y0 + 14, plum)
                    put(x, y0 - 3, plum); put(x, y0 - 2, board[2]); put(x, y0 - 1, plum)
                    for yy in (y0 + 15)...(y0 + 17) where yy < H && alpha[yy * W + x] < 1 {
                        put(x, yy, RGB(r: 60, g: 100, b: 120), 0.35)
                    }
                }
                for p in [x0 + 2, x0 + 10] {
                    for y in (y0 - 3)...(y0 + 2) { put(p, y, plum); put(p + 2, y, plum) }
                    for y in (y0 - 2)...(y0 + 1) { put(p + 1, y, board[1]) }
                }
                for p in [x0 + 3, x0 + 11] {
                    for y in (y0 + 15)...(y0 + 18) { put(p, y, board[0]); put(p + 1, y, board[1]) }
                    put(p - 1, y0 + 19, foam); put(p + 2, y0 + 19, foam)
                }
                for x in x0..<(x0 + px) { put(x, y0 + 9, plum); put(x, y0 + 10, board[3]); put(x, y0 + 11, plum) }
                for p in [x0 + 2, x0 + 10] {
                    for y in (y0 + 9)...(y0 + 14) { put(p, y, plum); put(p + 2, y, plum) }
                    for y in (y0 + 10)...(y0 + 13) { put(p + 1, y, board[2]) }
                }
            }
        }

        // ── 出图（预乘透明）
        var bytes = [UInt8](repeating: 0, count: N * 4)
        for i in 0..<N {
            let a = alpha[i]
            guard a > 0 else { continue }
            let c = rgb[i]
            bytes[i * 4] = UInt8(Float(c.r) * a); bytes[i * 4 + 1] = UInt8(Float(c.g) * a)
            bytes[i * 4 + 2] = UInt8(Float(c.b) * a); bytes[i * 4 + 3] = UInt8(a * 255)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 背景的海：一块 16×16，两道短波纹
    static func seaTile() -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: px * px * 4)
        for y in 0..<px {
            for x in 0..<px {
                var c = sea[0]
                if (y == 4 && (2...5).contains(x)) || (y == 12 && (9...12).contains(x)) { c = sea[2] }
                if (y == 5 && (3...4).contains(x)) || (y == 13 && (10...11).contains(x)) { c = sea[1] }
                let i = (y * px + x) * 4
                bytes[i] = c.r; bytes[i + 1] = c.g; bytes[i + 2] = c.b
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: px, height: px, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: px * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
