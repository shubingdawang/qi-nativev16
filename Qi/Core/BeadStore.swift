import Foundation
import SwiftUI
import UIKit

// MARK: - 拼豆板
//
// 一块电子拼豆板：底下垫一张参考图，上面一格一格放豆子。
// 做好的东西导出成图片，放进家具素材、表情包这些地方（见 `ImportPlacementView`）。
// 纯本机，存档是 `beads.json`，参考图走 `ImageStore`。

struct BeadProject: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    /// 边长几格（正方形板）
    var size = 32
    /// 每一格的颜色（十六进制，"" = 空）。按行排，长度 = size * size
    var cells: [String] = []
    /// 参考图（`ImageStore` 里的文件名），"" = 没有
    var refImage = ""
    var refOpacity: Double = 0.5
    var refShown = true
    /// 参考图的摆法：放大倍数、旋转（度）、平移（占板边长的比例）
    var refScale: Double = 1
    var refRotation: Double = 0
    var refX: Double = 0
    var refY: Double = 0
    var updatedAt = Date()

    init(size: Int, name: String = "") {
        self.size = size
        self.name = name
        self.cells = Array(repeating: "", count: size * size)
    }

    var filled: Int { cells.filter { !$0.isEmpty }.count }
}

// 以后加字段，老存档缺哪个用默认，不许整份读不出来
extension BeadProject {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        size = max(4, (try? c.decodeIfPresent(Int.self, forKey: .size)) ?? 32)
        cells = (try? c.decodeIfPresent([String].self, forKey: .cells)) ?? []
        if cells.count != size * size { cells = Array(repeating: "", count: size * size) }
        refImage = (try? c.decodeIfPresent(String.self, forKey: .refImage)) ?? ""
        refOpacity = (try? c.decodeIfPresent(Double.self, forKey: .refOpacity)) ?? 0.5
        refShown = (try? c.decodeIfPresent(Bool.self, forKey: .refShown)) ?? true
        refScale = (try? c.decodeIfPresent(Double.self, forKey: .refScale)) ?? 1
        refRotation = (try? c.decodeIfPresent(Double.self, forKey: .refRotation)) ?? 0
        refX = (try? c.decodeIfPresent(Double.self, forKey: .refX)) ?? 0
        refY = (try? c.decodeIfPresent(Double.self, forKey: .refY)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
    }
}

@MainActor
final class BeadStore: ObservableObject {

    static let shared = BeadStore()

    @Published private(set) var projects: [BeadProject] = [] {
        didSet { if loaded { Storage.save(projects, to: "beads.json") } }
    }
    private var loaded = false

    private init() {
        projects = Storage.load([BeadProject].self, from: "beads.json") ?? []
        loaded = true
    }

    func project(_ id: UUID) -> BeadProject? { projects.first { $0.id == id } }

    @discardableResult
    func create(size: Int, refImage: String = "") -> BeadProject {
        var p = BeadProject(size: size, name: "拼豆 \(projects.count + 1)")
        p.refImage = refImage
        projects.insert(p, at: 0)
        return p
    }

    func save(_ p: BeadProject) {
        var p = p
        p.updatedAt = Date()
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            projects[i] = p
        } else {
            projects.insert(p, at: 0)
        }
    }

    func delete(_ id: UUID) {
        if let p = project(id), !p.refImage.isEmpty { ImageStore.delete(p.refImage) }
        projects.removeAll { $0.id == id }
    }

    // MARK: 色板

    /// 拼豆常用色，偏淡一点
    static let palette: [String] = [
        "FFFFFF", "F4F1EC", "E3DED8", "B9B2AB", "7D766F", "3B3634", "1A1717",
        "FAD4DC", "F4A7B9", "E8758F", "C9415E", "8E2440",
        "FBE3CF", "F8C39B", "F09A62", "D96B3A", "A3492A",
        "FFF3B8", "FBE27A", "F2C230", "C99A1B",
        "E2F2D3", "B8DE9C", "7FBF6A", "4C8F45", "2E5E33",
        "D6EEF2", "A9D8E6", "6FB4D2", "3F80B5", "264F82",
        "E7DCF4", "C9B6E8", "A08AD3", "6E58A8", "45346F",
        "F1D9C7", "D9B396", "B48464", "8A5A3C", "5E3A26"
    ]

    // MARK: 出图

    enum Look: String, CaseIterable, Identifiable {
        case bead, pixel
        var id: String { rawValue }
        var label: String { self == .bead ? "豆子" : "像素" }
    }

    /// 把一块板画成图。透明底；cellPx 是一格多少像素
    static func render(_ p: BeadProject, look: Look, cellPx: CGFloat = 16) -> UIImage {
        let side = CGFloat(p.size) * cellPx
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let g = ctx.cgContext
            for row in 0..<p.size {
                for col in 0..<p.size {
                    let hex = p.cells[row * p.size + col]
                    guard !hex.isEmpty, let c = UIColor(beadHex: hex) else { continue }
                    let r = CGRect(x: CGFloat(col) * cellPx, y: CGFloat(row) * cellPx, width: cellPx, height: cellPx)
                    switch look {
                    case .pixel:
                        g.setFillColor(c.cgColor)
                        g.fill(r)
                    case .bead:
                        let inset = r.insetBy(dx: cellPx * 0.06, dy: cellPx * 0.06)
                        g.setFillColor(c.cgColor)
                        g.fillEllipse(in: inset)
                        // 中间那个孔
                        let hole = r.insetBy(dx: cellPx * 0.34, dy: cellPx * 0.34)
                        g.setFillColor(c.darker(0.18).cgColor)
                        g.fillEllipse(in: hole)
                        // 一点高光
                        let shine = CGRect(x: r.minX + cellPx * 0.22, y: r.minY + cellPx * 0.18,
                                           width: cellPx * 0.2, height: cellPx * 0.14)
                        g.setFillColor(UIColor.white.withAlphaComponent(0.45).cgColor)
                        g.fillEllipse(in: shine)
                    }
                }
            }
        }
    }

    /// 一键铺豆：把参考图按现在的摆法缩到 size×size，每格取色，就近换成色板里的颜色。
    /// exact = true 时不换色板，直接用原色
    static func trace(_ p: BeadProject, image: UIImage, exact: Bool) -> [String] {
        let n = p.size
        // 自己开一块 RGBA 的小画布，字节顺序是定的，读起来不用猜
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return p.cells }
        // UIKit 画图是左上角为原点，CGContext 是左下角：翻过来再画
        ctx.translateBy(x: 0, y: CGFloat(n))
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        drawReference(image, in: CGSize(width: n, height: n), project: p)
        UIGraphicsPopContext()
        guard let raw = ctx.data else { return p.cells }
        let ptr = raw.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var out = Array(repeating: "", count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let o = (y * n + x) * 4
                let a = Double(ptr[o + 3])
                guard a > 128 else { continue }
                // 预乘过的还原一下
                let k = 255 / max(a, 1)
                let r = min(255, Double(ptr[o]) * k)
                let g = min(255, Double(ptr[o + 1]) * k)
                let b = min(255, Double(ptr[o + 2]) * k)
                out[y * n + x] = exact ? String(format: "%02X%02X%02X", Int(r), Int(g), Int(b))
                                       : nearest(r, g, b)
            }
        }
        return out
    }

    private static let paletteRGB: [(String, Double, Double, Double)] = palette.compactMap { hex in
        guard let v = Int(hex, radix: 16) else { return nil }
        return (hex, Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    static func nearest(_ r: Double, _ g: Double, _ b: Double) -> String {
        var best = palette[0]
        var bestD = Double.greatestFiniteMagnitude
        for (hex, pr, pg, pb) in paletteRGB {
            // 人眼对绿最敏感，权重照常见的那组给
            let d = 0.3 * (r - pr) * (r - pr) + 0.59 * (g - pg) * (g - pg) + 0.11 * (b - pb) * (b - pb)
            if d < bestD { bestD = d; best = hex }
        }
        return best
    }

    /// 参考图在一块边长 side 的板上怎么摆：等比放进正方形里居中，再按项目里的放大、旋转、平移
    static func drawReference(_ image: UIImage, in side: CGSize, project p: BeadProject) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        let s = side.width
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return }
        let fit = min(s / iw, s / ih)
        let w = iw * fit, h = ih * fit
        g.saveGState()
        g.translateBy(x: s / 2 + CGFloat(p.refX) * s, y: s / 2 + CGFloat(p.refY) * s)
        g.rotate(by: CGFloat(p.refRotation) * .pi / 180)
        g.scaleBy(x: CGFloat(p.refScale), y: CGFloat(p.refScale))
        image.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        g.restoreGState()
    }
}

extension UIColor {
    convenience init?(beadHex hex: String) {
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    func darker(_ k: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * (1 - k), green: g * (1 - k), blue: b * (1 - k), alpha: a)
    }

    var beadHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(max(0, min(1, r)) * 255),
                      Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
