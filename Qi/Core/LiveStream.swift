import Foundation
import Combine

/// 他正在往外蹦的那几个字，**先放这儿，不放 `conversations` 里**。
///
/// 她报的：「他在回复时 app 很卡，巨卡无比，划侧边栏还是打字都很卡。」
///
/// `conversations` 挂在 `AppState` 上，而 `AppState` 被几十个页面订阅着：
/// 侧栏、输入栏、每一个气泡……流式每刷一次字就改一次它，
/// 于是**全 App 一秒重画好几次**，她这时候干什么都得排在后面。
///
/// 现在蹦字的时候只改这个小对象，订阅它的只有消息区；
/// 要跑工具、说完、出错、按停止的时候（`flushStream(force: true)`）
/// 才一次性写回 `conversations`。
@MainActor
final class LiveStream: ObservableObject {
    static let shared = LiveStream()

    /// 消息 id → 还没写回去的正文 / 思考
    @Published private(set) var text: [UUID: String] = [:]
    @Published private(set) var reason: [UUID: String] = [:]

    func add(_ id: UUID, text t: String, reason r: String) {
        if !t.isEmpty { text[id, default: ""] += t }
        if !r.isEmpty { reason[id, default: ""] += r }
    }

    /// 拿走这一条攒着的（写回 `conversations` 用）
    func take(_ id: UUID) -> (text: String, reason: String) {
        let out = (text[id] ?? "", reason[id] ?? "")
        if text[id] != nil { text[id] = nil }
        if reason[id] != nil { reason[id] = nil }
        return out
    }

    func drop(_ id: UUID) { _ = take(id) }

    /// 这条消息加上还没写回去的那几个字，就是屏幕上该显示的样子
    func merged(_ m: ChatMessage) -> ChatMessage {
        guard m.isStreaming else { return m }
        let t = text[m.id], r = reason[m.id]
        guard t != nil || r != nil else { return m }
        var out = m
        if let t { out.content += t }
        if let r { out.reasoning = (out.reasoning ?? "") + r }
        return out
    }

    /// 字一长就变，消息区盯着它滚到底
    var tick: Int {
        text.values.reduce(0) { $0 + $1.count } + reason.values.reduce(0) { $0 + $1.count }
    }
}
