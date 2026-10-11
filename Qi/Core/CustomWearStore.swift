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
}

extension CustomWear {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? "cw_head_" + UUID().uuidString.prefix(8)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        imageName = (try? c.decodeIfPresent(String.self, forKey: .imageName)) ?? ""
        slot = (try? c.decodeIfPresent(String.self, forKey: .slot)) ?? "head"
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
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
        guard let file = ImageStore.save(image) else { return nil }
        let id = "cw_\(slot.rawValue)_" + String(UUID().uuidString.prefix(8)).lowercased()
        let item = CustomWear(id: id, name: name.isEmpty ? "自制" : name, imageName: file, slot: slot.rawValue)
        items.insert(item, at: 0)
        return item
    }

    func delete(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if ClawdStore.shared.isWearing(id) { ClawdStore.shared.wear(id) }
        ImageStore.delete(items[i].imageName)
        items.remove(at: i)
    }

    func image(_ id: String) -> UIImage? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return ImageStore.cached(item.imageName)
    }

    func name(_ id: String) -> String? { items.first { $0.id == id }?.name }
}
