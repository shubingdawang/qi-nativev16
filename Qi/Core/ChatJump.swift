import Foundation
import SwiftUI

/// 「跳到某一条消息」。点引用、从搜索里点进来，都走这一个。
///
/// 她要的：
/// · 「我点击引用的句子可以直接跳转到这个句子所在地。」
/// · 「搜索聊天记录点击句子跳转有点不太准确，跳转的地方偏下大概 12 条左右；
///   跳过来的时候点击的那个句子应该像微信这样稍微亮一下，大概 2 秒消失。」
///
/// ⚠️ 用一个共享的小对象传话，而不是给气泡再加一个回调参数：
/// 气泡那个初始化器已经二十几个参数，再加一个，消息列表那段的类型检查
/// 就会超时（CI 报过好几次 unable to type-check in reasonable time）。
@MainActor
final class ChatJump: ObservableObject {

    static let shared = ChatJump()

    /// 要跳到的那一条。消息列表看见它就滚过去，然后清空
    @Published var target: UUID?

    private init() {}

    func go(_ id: UUID) { target = id }

    /// 点引用：有原句的 id 就用 id；老消息没存 id 的，按原句的字去找
    func goToQuote(of message: ChatMessage, in conversation: Conversation?) {
        if let id = message.quotedMessageID {
            go(id)
            return
        }
        let text = message.quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let conv = conversation else { return }
        // 引用是截了头的，拿前二十个字去比
        let head = String(text.prefix(20))
        if let hit = conv.messages.last(where: {
            $0.id != message.id && $0.content.contains(head)
        }) {
            go(hit.id)
        }
    }
}
