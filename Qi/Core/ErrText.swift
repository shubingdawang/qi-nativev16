import Foundation

/// 把报错翻成一句**说得出问题在哪**的话。
///
/// 起因：她报「The data couldn't be read because it isn't in the correct format.
/// 一直显示这个」。
///
/// 那句话是 Foundation 给 `DecodingError` 的默认文案，**它把所有有用的信息
/// 都丢掉了**——是哪个字段、期望什么类型、路径在哪一层，全都在 error 对象里
/// 装着，只是 `localizedDescription` 一个字都不往外说。
///
/// 于是这条报错对她、对我都等于没有：看到它只知道「有个 JSON 没解析成」，
/// 不知道是小屋的工具清单、是聊天的流、还是别的什么。
///
/// 这儿把那些信息拆出来。**报错的价值全在「下一步该去看哪儿」**。
enum ErrText {

    static func readable(_ error: Error) -> String {
        if let d = error as? DecodingError {
            switch d {
            case .keyNotFound(let key, let ctx):
                return "少了字段「\(key.stringValue)」" + where_(ctx)
            case .typeMismatch(let type, let ctx):
                return "字段类型对不上（要的是 \(type)）" + where_(ctx)
            case .valueNotFound(let type, let ctx):
                return "字段是空的（要的是 \(type)）" + where_(ctx)
            case .dataCorrupted(let ctx):
                let why = ctx.debugDescription
                return (why.isEmpty ? "内容不是预期的格式" : why) + where_(ctx)
            @unknown default:
                return error.localizedDescription
            }
        }
        let ns = error as NSError
        // 3840 = JSON 压根没解析成。最常见的是对面回了一页 HTML
        // （网关的错误页、被墙的提示页），或者干脆回了空。
        if ns.domain == NSCocoaErrorDomain, ns.code == 3840 {
            return "对面回的不是 JSON——多半是网关的错误页或者空回复"
        }
        return error.localizedDescription
    }

    /// 出错的字段在第几层。`codingPath` 是空的就不说废话。
    private static func where_(_ ctx: DecodingError.Context) -> String {
        let parts: [String] = ctx.codingPath.map { key in
            if let i = key.intValue { return "[\(i)]" }
            return key.stringValue
        }
        return parts.isEmpty ? "" : "（位置：" + parts.joined(separator: " → ") + "）"
    }
}
