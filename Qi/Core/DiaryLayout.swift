import Foundation
import CoreGraphics

/// 日记本上那些便签摆在哪儿。
///
/// 以前的位置是 `entry.id.hashValue` 现算的，两个毛病：
///
/// 1. **全挤在一起**——偏移只有 ±30 点，一天写三条就叠成一坨
/// 2. **每次重开 App 位置都在跳**——Swift 的 `String.hashValue`
///    每个进程都换一次随机种子，同一条日记这次落在左边、
///    下次可能落在右边。它看着像"随机摆放"，其实是"每次重新随机"
///
/// 现在分两层：
///   · 默认位置用**自己写的稳定散列**算，同一条永远落在同一处
///   · 她拖过的那些记在这儿，拖到哪儿就一直在哪儿
@MainActor
final class DiaryLayout: ObservableObject {

    static let shared = DiaryLayout()

    /// 日记 id → 她把它拖到的偏移（相对那一叠的中心，单位是点）
    @Published private(set) var spots: [String: CGPoint] = [:]

    private init() {
        let raw = Storage.load([String: [Double]].self, from: "diary-notes.json") ?? [:]
        for (k, v) in raw where v.count == 2 {
            spots[k] = CGPoint(x: v[0], y: v[1])
        }
    }

    func spot(_ id: String) -> CGPoint? { spots[id] }

    func move(_ id: String, to p: CGPoint) {
        spots[id] = p
        save()
    }

    /// 这一条恢复成默认位置
    func reset(_ id: String) {
        spots.removeValue(forKey: id)
        save()
    }

    /// 全部摊回默认位置。她把桌面搞乱了想重来的时候用。
    func resetAll() {
        spots = [:]
        save()
    }

    private func save() {
        var raw: [String: [Double]] = [:]
        for (k, v) in spots { raw[k] = [v.x, v.y] }
        Storage.save(raw, to: "diary-notes.json")
    }

    // MARK: 默认怎么摆

    /// **自己写的稳定散列。**
    ///
    /// 不能用 `String.hashValue`——那玩意儿每个进程换一次种子，
    /// 拿它算位置等于每次重开都重新洗牌。
    /// 这个是纯函数，同一个字符串永远得到同一个数。
    static func steadyHash(_ s: String) -> Int {
        var h = 5381
        for b in s.utf8 { h = (h &* 33 &+ Int(b)) & 0x7FFF_FFFF }
        return h
    }

    /// 没拖过的那些默认落在哪儿。
    ///
    /// 摊成两列错开的样子，不再堆在正中间——她说的「全挤在一起」就是这个。
    /// 每张再按稳定散列抖动一点点，看着才像随手摆的，不像表格。
    static func defaultSpot(id: String, index: Int, width: CGFloat) -> CGPoint {
        let seed = steadyHash(id)
        // 一张便签 168 宽。窄屏放不下两列就退回一列。
        let twoColumns = width >= 344
        let col = twoColumns ? index % 2 : 0
        let row = twoColumns ? index / 2 : index
        let baseX: CGFloat = twoColumns ? (col == 0 ? -88 : 88) : 0
        let jitterX = CGFloat(seed % 17) - 8
        let jitterY = CGFloat((seed / 17) % 13) - 6
        return CGPoint(x: baseX + jitterX,
                       y: CGFloat(row) * 118 - 150 + jitterY)
    }

    /// 这张便签歪多少度。也走稳定散列，不然每次重开歪的方向都变。
    static func angle(id: String) -> Double {
        Double((steadyHash(id) % 9) - 4) * 0.9
    }
}
