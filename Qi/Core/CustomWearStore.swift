import Foundation
import UIKit

/// 她自己做的衣服（拼豆板导出、导入的图）。
///
/// 跟自带的那批一样，图是**按身体那张 36 格图纸摆好的整张图**，戴上去整张对齐就行。
/// 编号写成 `cw_<位置>_<短号>`：`ClawdRig.wearSlot` 看编号就知道它穿在哪儿，
/// 不用另外查表（那个函数不在主线程上，查不了这里）。
struct CustomWear: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var imageName: String
    var slot: String
    var createdAt = Date()
    /// 袖子（跟着手转的那两块，见 `OutfitCutter`）。没有就是 nil
    var armL: String?
    var armR: String?
    /// 眼睛画在这件衣服上面（她画的整套衣服默认开）
    var eyesOnTop: Bool?
    /// 眼睛挪几格（挪到她画眼睛的地方）
    var eyeDX: Double?
    var eyeDY: Double?
    var eyeScale: Double?
    /// 做这件时的原图和调好的那些数：长按回到做衣服那一页接着改
    var design: OutfitDesign?
}

/// 一件衣服的原图 + 调好的参数（存下来好回去改）
struct OutfitDesign: Codable, Hashable {
    var w: Int
    var h: Int
    var cells: [String]
    var slot: String
    var clawdColors: [String]
    var scale: Double
    var offX: Double
    var offY: Double
    var eyesOnTop: Bool
    var eyeNudgeX: Double
    var eyeNudgeY: Double
    var eyeScale: Double
}

extension CustomWear {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? "cw_head_" + UUID().uuidString.prefix(8)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        imageName = (try? c.decodeIfPresent(String.self, forKey: .imageName)) ?? ""
        slot = (try? c.decodeIfPresent(String.self, forKey: .slot)) ?? "head"
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        armL = (try? c.decodeIfPresent(String.self, forKey: .armL)) ?? nil
        armR = (try? c.decodeIfPresent(String.self, forKey: .armR)) ?? nil
        eyesOnTop = (try? c.decodeIfPresent(Bool.self, forKey: .eyesOnTop)) ?? nil
        eyeDX = (try? c.decodeIfPresent(Double.self, forKey: .eyeDX)) ?? nil
        eyeDY = (try? c.decodeIfPresent(Double.self, forKey: .eyeDY)) ?? nil
        eyeScale = (try? c.decodeIfPresent(Double.self, forKey: .eyeScale)) ?? nil
        design = (try? c.decodeIfPresent(OutfitDesign.self, forKey: .design)) ?? nil
    }
}

@MainActor
final class CustomWearStore: ObservableObject {

    static let shared = CustomWearStore()

    @Published private(set) var items: [CustomWear] = [] {
        didSet { if loaded { Storage.save(items, to: "custom-wear.json") } }
    }
    private var loaded = false

    private init() {
        items = Storage.load([CustomWear].self, from: "custom-wear.json") ?? []
        loaded = true
    }

    /// 挑位置时给她看的名字
    static let slots: [(ClawdRig.WearSlot, String)] = [
        (.head, "头上"), (.face, "脸上"), (.neck, "脖子"), (.body, "贴身"),
        (.outer, "外套"), (.back, "背上"), (.feet, "脚上")
    ]

    @discardableResult
    func add(_ image: UIImage, slot: ClawdRig.WearSlot, name: String) -> CustomWear? {
        // ⚠️ 存 PNG：存成 jpg 的话透明的地方全变白——抠掉的脸、衣服外面那一圈都成了白块
        guard let file = ImageStore.savePNG(image) else { return nil }
        let id = "cw_\(slot.rawValue)_" + String(UUID().uuidString.prefix(8)).lowercased()
        let item = CustomWear(id: id, name: name.isEmpty ? "自制" : name, imageName: file, slot: slot.rawValue)
        items.insert(item, at: 0)
        return item
    }

    /// 她画的一整套（`OutfitCutter` 抠出来的）：身子那层 + 两只袖子
    @discardableResult
    func addOutfit(_ layers: OutfitCutter.Layers, name: String, eyesOnTop: Bool = true,
                   slot: ClawdRig.WearSlot = .outer, design: OutfitDesign? = nil,
                   replacing old: String? = nil) -> CustomWear? {
        // 改的是原来那件：先脱下、删掉，新的一件替上
        var wasWearing = false
        if let old, items.contains(where: { $0.id == old }) {
            wasWearing = ClawdStore.shared.isWearing(old)
            delete(old)
        }
        guard var item = add(layers.body, slot: slot, name: name) else { return nil }
        item.design = design
        defer { if wasWearing, !ClawdStore.shared.isWearing(item.id) { ClawdStore.shared.wear(item.id) } }
        item.eyesOnTop = eyesOnTop
        item.eyeDX = layers.eyeDX
        item.eyeDY = layers.eyeDY
        item.eyeScale = layers.eyeScale
        item.armL = layers.left.flatMap { ImageStore.savePNG($0) }
        item.armR = layers.right.flatMap { ImageStore.savePNG($0) }
        items[0] = item
        return item
    }

    /// 身上穿着的有没有要露眼睛的
    func eyesOnTop(_ wornIDs: [String]) -> Bool {
        wornIDs.contains { id in id.hasPrefix("cw_") && items.first(where: { $0.id == id })?.eyesOnTop == true }
    }

    /// 眼睛要挪几格（穿着的那件里第一件要露眼睛的）
    func eyeShift(_ wornIDs: [String]) -> (dx: Double, dy: Double, scale: Double) {
        for id in wornIDs where id.hasPrefix("cw_") {
            if let item = items.first(where: { $0.id == id }), item.eyesOnTop == true {
                return (item.eyeDX ?? 0, item.eyeDY ?? 0, item.eyeScale ?? 1)
            }
        }
        return (0, 0, 1)
    }

    /// 身上穿着的那几件里，左手 / 右手的袖子
    func sleeve(_ wornIDs: [String], left: Bool) -> UIImage? {
        for id in wornIDs where id.hasPrefix("cw_") {
            guard let item = items.first(where: { $0.id == id }),
                  let name = left ? item.armL : item.armR else { continue }
            return ImageStore.cached(name)
        }
        return nil
    }

    /// 只改它穿在哪儿（老的那几件没存原图，图不变，换个位置）
    func changeSlot(_ id: String, to slot: ClawdRig.WearSlot) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let wearing = ClawdStore.shared.isWearing(id)
        if wearing { ClawdStore.shared.wear(id) }
        var item = items[i]
        item.id = "cw_\(slot.rawValue)_" + String(UUID().uuidString.prefix(8)).lowercased()
        item.slot = slot.rawValue
        items[i] = item
        if wearing { ClawdStore.shared.wear(item.id) }
    }

    func delete(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if ClawdStore.shared.isWearing(id) { ClawdStore.shared.wear(id) }
        if let a = items[i].armL { ImageStore.delete(a) }
        if let a = items[i].armR { ImageStore.delete(a) }
        ImageStore.delete(items[i].imageName)
        items.remove(at: i)
    }

    func image(_ id: String) -> UIImage? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return ImageStore.cached(item.imageName)
    }

    func name(_ id: String) -> String? { items.first { $0.id == id }?.name }
}
