import Foundation
import UIKit

/// 切好的家具素材。
///
/// ## 她要的是什么
///
/// 她的原话：「我想切割之后增加一个**选择切割图片后保存**的功能，
/// 这样我就不用一直切割同一张图片了。」
///
/// 以前切图这条路是**一次性**的：导一整版进来 → 切开 → 挑一块贴给某件家具 →
/// 这一版就用完了。下次想给别的家具换图，得**把同一张图再切一遍**。
/// 切一次要读图、缩放、跑连通域，还得再一块块认一遍——重复劳动全在她这边。
///
/// 现在切完能存进这儿，以后直接挑。
///
/// ## 顺带把「换一版就没了」那件事变结实
///
/// 她说「我在一版买的东西在下一版会全部消失，我切割的图片也会」。
///
/// 买的东西（`clawd-room.json`）和切好的图（`Images/` 里那些 png）
/// **一直都在备份里**——丢的那次是 v113 之前那个路径 bug：
/// 图被放回了 Documents 根目录，家具找不着就退回画的那一版，
/// 看着就像「我买的东西没了」。
///
/// 但这条路走完之后还剩一个真的窟窿：**切好的图只被某一件家具引用着**。
/// 那件家具一删，图就成了没人认领的孤儿；她也没法把同一张图再用到别处。
/// 存进素材库之后它是**一条独立的记录**，删家具不影响它。
///
/// ⚠️ 存的是**文件名**不是图（图走 `ImageStore`）：
/// 备份自动带上、画的时候走 `cached` 不重复解码。跟墙纸那套一个道理。
struct FurniturePiece: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 她给这块起的名字。空的也行，就按导入日期排
    var name: String = ""
    /// 存在 `Images/` 里的文件名
    var imageName: String = ""
    var createdAt: Date = Date()
}

/// 容错解码。
/// ⚠️ 新加字段的时候不补这个，整个素材库会在升级那一下变空
/// （见 `Storage.load` 那段注释）。
extension FurniturePiece {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        imageName = (try? c.decodeIfPresent(String.self, forKey: .imageName)) ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
    }
}

@MainActor
final class PieceStore: ObservableObject {

    static let shared = PieceStore()

    @Published var pieces: [FurniturePiece] = [] {
        didSet { if loaded { Storage.save(pieces, to: "furniture-pieces.json") } }
    }
    private var loaded = false

    init() {
        pieces = Storage.load([FurniturePiece].self, from: "furniture-pieces.json") ?? []
        loaded = true
    }

    /// 还原完重读一遍。⚠️ `loaded` 先关掉——读的时候不许写盘。
    func reload() {
        loaded = false
        pieces = Storage.load([FurniturePiece].self, from: "furniture-pieces.json") ?? []
        loaded = true
    }

    /// 存一块进来。返回存好的那条；存不下就返回 nil。
    @discardableResult
    func add(_ image: UIImage, name: String = "") -> FurniturePiece? {
        // ⚠️ 走 `FurnitureImage.save`，不是 `ImageStore.save`——
        // 前者会抠掉白底、裁紧边框。存原图的话，贴到屋里是一块白方板。
        guard let file = FurnitureImage.save(image) else { return nil }
        let piece = FurniturePiece(name: name, imageName: file)
        pieces.insert(piece, at: 0)
        return piece
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = pieces.firstIndex(where: { $0.id == id }) else { return }
        pieces[i].name = name
    }

    /// 删一块。**图也一起删掉**——素材库是这张图唯一的主人，
    /// 记录没了还留着文件，那就是在磁盘上攒垃圾。
    ///
    /// ⚠️ 但**贴出去的那些不受影响**：`dressUp` 走的是
    /// `FurnitureImage.save`，每贴一次另存一份，两边不共用同一个文件。
    func remove(_ id: UUID) {
        guard let i = pieces.firstIndex(where: { $0.id == id }) else { return }
        let file = pieces[i].imageName
        pieces.remove(at: i)
        if !file.isEmpty { ImageStore.delete(file) }
    }

    func image(_ piece: FurniturePiece) -> UIImage? {
        ImageStore.cached(piece.imageName)
    }
}
