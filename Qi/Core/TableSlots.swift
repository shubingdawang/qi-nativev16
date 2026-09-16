import Foundation
import CoreGraphics

/// 台面上有哪几个位置。
///
/// 她说的：
/// > 放在桌子上的位置要规划一下，微波炉都跑到桌子外面去了。
/// > 一个桌子根据形状来分有几个位置：长方形的书桌就六个，前面三个后面三个；
/// > 圆形的就七个，前面两个中间三个后面两个。床头柜一般可以有两个位置。
/// > 小的在前面。
///
/// 以前是「吸到最近那一格」：一格一件，床头柜只有一格所以只能摆一件，
/// 而两格宽的微波炉吸到边上那格就有一半悬在桌子外面。
///
/// 现在每张台面按形状给一串**位置**（格坐标里的小数点，
/// 相对这件家具占地的左上角那一格的外沿），摆东西就是挑一个空位置坐下。
enum TableSlots {

    /// 这张台面上的位置。返回的是「离占地左上角多少格」，0…w / 0…d 之间
    static func offsets(for kindID: String, w: Int, d: Int) -> [CGPoint] {
        // 圆桌：七个位置——后面两个、中间三个、前面两个（四个角空着，圆桌那儿没有桌面）
        if isRound(kindID), w >= 3, d >= 3 {
            let cx = Double(w) / 2, cy = Double(d) / 2
            return [CGPoint(x: cx - 0.5, y: cy - 1.0), CGPoint(x: cx + 0.5, y: cy - 1.0),
                    CGPoint(x: cx - 1.0, y: cy), CGPoint(x: cx, y: cy), CGPoint(x: cx + 1.0, y: cy),
                    CGPoint(x: cx - 0.5, y: cy + 1.0), CGPoint(x: cx + 0.5, y: cy + 1.0)]
        }
        // 一格见方的小柜子（床头柜、凳子）：左右两个位置
        if w == 1 && d == 1 {
            return [CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.7, y: 0.5)]
        }
        // 长方形：一格一个位置（3×2 的书桌就是前三后三）
        var out: [CGPoint] = []
        for j in 0..<max(1, d) {
            for i in 0..<max(1, w) {
                out.append(CGPoint(x: Double(i) + 0.5, y: Double(j) + 0.5))
            }
        }
        return out
    }

    /// 圆的台面
    static func isRound(_ id: String) -> Bool {
        switch id {
        case "table", "lolita_table", "vic_tea", "xred_table", "rose_table", "star_table",
             "ny_table", "nordic_table", "jp_table":
            return true
        default:
            return false
        }
    }

    /// 摆在台面上的小东西。**小的往前排**（她说的），大的留在后排
    static func small(_ id: String) -> Bool {
        switch id {
        case "microwave", "record", "star_gramophone", "tank", "globe", "minitree",
             "humid", "speaker", "bonsai", "hotpot", "pizza":
            return false
        default:
            return true
        }
    }

    /// 位置在屋里的格坐标（`geo.point` 直接能用的那种小数格）
    static func point(originGX: Int, originGY: Int, offset: CGPoint) -> (gx: Double, gy: Double) {
        (Double(originGX) - 0.5 + offset.x, Double(originGY) - 0.5 + offset.y)
    }
}
