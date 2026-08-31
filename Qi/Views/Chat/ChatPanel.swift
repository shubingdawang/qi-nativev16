import SwiftUI

/// 聊天页上那几张面板，合成一个。
///
/// ## 为什么要有这个
///
/// 以前它们是七个 `.sheet(isPresented:)` 一个接一个串在 `ChatView` 的
/// 同一个 view 上，加上别的一共十四个 presentation。
///
/// **这个结构已经害过两次：**
///
///   ① 我把「他刚才干了什么」那张挂在了 `MessageBubbleView` 上——
///      气泡是列表里几百条中的一条，等于同时装了几百个宿主。
///      表现是**整个 App 点哪儿都没反应**：侧边栏点了只弹回聊天页，
///      设置里供应商、语音全按不动。
///
///   ② 挪到 `ChatView` 之后串成了十四个。她报的是
///      **「只要是从其他页面进入絮语就会崩溃」**。
///
/// 合成一个 `.sheet(item:)` 之后，同一时刻只有一个 presentation 宿主，
/// 而且「现在开着哪一张」是一个值，不是七个各自为政的布尔——
/// 两张同时为真这种事从根上不可能发生了。
///
/// ⚠️ **以后加新面板往这儿加一个 case，不要再往 `ChatView` 上续 `.sheet`。**
enum ChatPanel: Identifiable {
    case model
    case prompt
    case tools
    case poke
    case memory
    case group
    /// 「他刚才干了什么」——带上是哪一条消息
    case process(ChatMessage)

    var id: String {
        switch self {
        case .model:   return "model"
        case .prompt:  return "prompt"
        case .tools:   return "tools"
        case .poke:    return "poke"
        case .memory:  return "memory"
        case .group:   return "group"
        // ⚠️ 带上消息的 id：换一条消息看过程，`id` 变了 SwiftUI 才会
        // 把里面的内容换掉。都返回 "process" 的话，
        // 关掉再点另一条，弹出来的还是上一条的内容。
        case .process(let m): return "process-" + m.id.uuidString
        }
    }
}
