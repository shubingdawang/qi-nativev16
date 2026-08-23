import Foundation

/// 终端：这个 App 刚才到底做了什么。
///
/// 她在参考图里看到别人有「终端」，问那是干嘛的。那些桌面工具里的终端
/// 是把模型的原始请求和响应打出来——**在手机上照搬没意义**（一屏 JSON 谁看）。
/// 她要的其实是同一件事的另一面：**看得见里面在动**。
///
/// 所以这一份记的是「发生了什么」，不是「原始报文」：
/// 什么时候发了请求、发给哪个模型、多大、回来花了多久、
/// 哪个工具跑了、成没成、花了多少 token、什么时候自己醒的、哪儿出错了。
///
/// 她现在正在测，这一页首先是**给她自己看的**：
/// App 有点不对劲的时候，能翻出那一刻发生了什么，
/// 而不是只能截个图说「它卡住了」。
///
/// ⚠️ 三条自律：
/// 1. **只记不发。** 一条都不上传，也不进提示词——他看不到这一页。
/// 2. **不花钱。** 纯本机字符串，不会因为记日志多调一次模型。
/// 3. **不落盘。** 只在内存里留最近 400 条，App 一关就没了。
///    这里头会经过她说的话的片段，写进文件等于多一份留底，没必要。
@MainActor
final class Console: ObservableObject {

    static let shared = Console()

    enum Kind: String, CaseIterable, Sendable {
        case net  = "请求"
        case tool = "工具"
        case cost = "用量"
        case wake = "唤醒"
        case warn = "出错"
        case app  = "其他"

        var icon: String {
            switch self {
            case .net:  return "arrow.up.arrow.down"
            case .tool: return "wrench.and.screwdriver"
            case .cost: return "circle.grid.cross"
            case .wake: return "bell"
            case .warn: return "exclamationmark.triangle"
            case .app:  return "circle"
            }
        }
    }

    struct Line: Identifiable {
        let id = UUID()
        let at = Date()
        let kind: Kind
        let title: String
        let detail: String
    }

    @Published private(set) var lines: [Line] = []

    /// 留多少条。太多的话滚起来卡，太少又翻不到刚才那一下。
    private let cap = 400

    private init() {}

    func add(_ kind: Kind, _ title: String, _ detail: String = "") {
        lines.append(Line(kind: kind, title: title, detail: detail))
        if lines.count > cap { lines.removeFirst(lines.count - cap) }
    }

    /// 从任何线程都能叫的那个口子。
    ///
    /// 记日志**永远不能挡住正事**——所以这儿是排一个任务到主线程，
    /// 不是 `await`。网络那边正在收流，不该为了写一行字停下来等。
    nonisolated static func log(_ kind: Kind, _ title: String, _ detail: String = "") {
        Task { @MainActor in shared.add(kind, title, detail) }
    }

    func clear() { lines.removeAll() }

    /// 复制出去的样子。给她贴给我看的时候用。
    func plainText(_ kinds: Set<Kind>? = nil) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return lines
            .filter { kinds == nil || kinds!.contains($0.kind) }
            .map { line in
                var s = "[\(f.string(from: line.at))] \(line.kind.rawValue) \(line.title)"
                if !line.detail.isEmpty { s += "\n    " + line.detail }
                return s
            }
            .joined(separator: "\n")
    }
}
