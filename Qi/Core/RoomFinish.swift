import SwiftUI

/// 内置的墙面和地面。
///
/// ## 她问的是什么
///
/// 她说「墙和地板这个内置我没看懂是什么意思」。是这么回事：
/// v153 通了「贴自己的图」那条路，但**不贴图的时候**屋子长这样——
/// 两面纯色的墙 + 一地棋盘格。能看，但素。
/// 「内置默认」的意思就是：**准备几套现成的，她不想找图也不难看。**
///
/// ## 为什么是画出来的，不是图
///
/// ⚠️ **仓库是公开的，第三方素材一张都不能进。**
/// 所以这几套全是用 `Path` 和 `Rectangle` 现画的——
/// 屋里所有家具本来就是一格一格画出来的，这条路早就走通了。
/// 好处顺带还有两个：一个字节都不占，而且跟着主题色走。
///
/// ## 怎么存的
///
/// 跟她自己贴的图**共用同一个字符串**（`ClawdStore.wallpaper(of:)`）：
/// 内置的存成 `#wood` 这种带井号的记号，她自己的图存的是文件名（UUID）。
/// UUID 里不会出现井号，所以两者天然分得开，不用加第二个字段、
/// 不用改存储、备份也自动跟着走。
///
/// ⚠️ 加一套新的要动两处：`Wall`／`Floor` 里加一档，
/// 加完 `all` 里会自动有（它是从 `CaseIterable` 来的），
/// **但 `IsoRoomView` 那边什么都不用改**——它只认「井号开头就问这儿要」。
enum RoomFinish {

    /// 内置的记号都以它开头。她自己那些图是 UUID，不会撞上。
    static let mark: Character = "#"

    static func isBuiltIn(_ token: String) -> Bool { token.first == mark }

    // MARK: 墙

    enum Wall: String, CaseIterable, Identifiable {
        /// 纯色。**这是原来那版**，留着当「什么都不选」
        case plain
        /// 竖条纹墙纸
        case stripe
        /// 砖墙
        case brick
        /// 下半截木墙裙，上半截素的
        case wainscot
        /// 方瓷砖（厨房浴室那种）
        case tile

        var id: String { rawValue }
        var token: String { String(RoomFinish.mark) + rawValue }
        var label: String {
            switch self {
            case .plain: return "纯色"
            case .stripe: return "条纹"
            case .brick: return "砖墙"
            case .wainscot: return "木墙裙"
            case .tile: return "瓷砖"
            }
        }
    }

    // MARK: 地

    enum Floor: String, CaseIterable, Identifiable {
        /// 棋盘格。**原来那版**
        case checker
        /// 木地板，长条
        case wood
        /// 榻榻米
        case tatami
        /// 方地砖，带缝
        case tile
        /// 水磨石，撒点子
        case terrazzo

        var id: String { rawValue }
        var token: String { String(RoomFinish.mark) + rawValue }
        var label: String {
            switch self {
            case .checker: return "棋盘格"
            case .wood: return "木地板"
            case .tatami: return "榻榻米"
            case .tile: return "地砖"
            case .terrazzo: return "水磨石"
            }
        }
    }

    // MARK: 配套
    //
    // ⚠️ **原来的 `Suite` / `suites` 删掉了，别加回来。**
    // 那五套现在是 `RoomTheme.all` 里价钱为 0 的前五个，一字不差，
    // 只是旁边多了带配色的那些。两份并存的话，改了一份另一份就开始撒谎——
    // 这个项目里这种事已经栽过太多次。

    // MARK: 记号怎么拆
    //
    // 一个记号有三种长相，**共用同一个字符串字段**：
    //
    //     UUID              她自己贴的那张图（文件名）
    //     #wood             内置花纹，用花纹自带的配色
    //     #wood@xmas        内置花纹 + 主题配色（`RoomTheme.id`）
    //
    // UUID 里既没有井号也没有 @，所以三者天然分得开——
    // 不用加第二个字段、不用改存储、备份自动跟着走。

    /// 记号里**花纹**那一段：`#wood@xmas` → `wood`
    ///
    /// ⚠️ 调用前先过 `isBuiltIn`。不是内置记号（她自己那张图）的话，
    /// 这儿会把 UUID 的第一个字符当井号砍掉。
    static func body(_ token: String) -> String {
        let noHash = String(token.dropFirst())
        guard let at = noHash.firstIndex(of: RoomTheme.mark) else { return noHash }
        return String(noHash[noHash.startIndex..<at])
    }

    /// 记号里**主题**那一段：`#wood@xmas` → 圣诞那套。没带主题就是 nil。
    ///
    /// nil 的意思是「用花纹自带的配色」，也就是原来那五套的样子。
    static func theme(_ token: String) -> RoomTheme? {
        guard isBuiltIn(token) else { return nil }
        let noHash = String(token.dropFirst())
        guard let at = noHash.firstIndex(of: RoomTheme.mark) else { return nil }
        let id = String(noHash[noHash.index(after: at)...])
        return RoomTheme.find(id)
    }

    /// 一个记号是哪一档墙。认不出来就算纯色。
    static func wall(_ token: String) -> Wall {
        guard isBuiltIn(token) else { return .plain }
        return Wall(rawValue: body(token)) ?? .plain
    }

    /// 一个记号是哪一档地。认不出来就算棋盘格。
    static func floor(_ token: String) -> Floor {
        guard isBuiltIn(token) else { return .checker }
        return Floor(rawValue: body(token)) ?? .checker
    }
}
