import SwiftUI
import Translation

// MARK: - 系统自带的翻译
//
// 她要的：
//
// > 思考链翻译就是直接不用到 ai，直接翻译就行了，类似于机翻？
// > 就像苹果自带的翻译一样，不用调用模型 ai 工具等等。
//
// 苹果这套（Translation 框架）正好：**离线跑在手机上**，不花钱、不联网、
// 没有额度，第一次用会让她下一个语言包，下完以后飞机上都能翻。
//
// ⚠️ 它只能在**界面里**跑：翻译会话是 `.translationTask` 这个修饰符给的，
// 没有「随便在哪儿叫一个函数」的用法。所以这儿是这么接的：
//
//   ① 谁要翻，就把字丢进 `AppleTranslate.shared`，然后等着
//   ② `RootView` 上常挂着一个 `AppleTranslateHost`（看不见的一层）
//   ③ 它看见有人排队，就开一次会话，翻完把结果还回去
//
// ⚠️ iOS 18 以下没有这套，那时候 `translate` 直接返回 nil，
// 外面会退回网上那两个免费接口（见 `Translator`）。

/// 排队等翻译的那些。
@MainActor
final class AppleTranslate: ObservableObject {

    static let shared = AppleTranslate()

    struct Job: Identifiable {
        let id = UUID()
        let text: String
        let done: (String?) -> Void
    }

    /// 还没翻的。`AppleTranslateHost` 盯着它
    @Published private(set) var queue: [Job] = []

    /// 这台机器上能不能用（iOS 18 起才有）
    var available: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    /// 翻一段。翻不了（系统不支持、语言包没下、出错）就返回 nil
    func translate(_ text: String) async -> String? {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard available, !source.isEmpty else { return nil }
        return await withCheckedContinuation { cont in
            var resumed = false
            queue.append(Job(text: source) { out in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: out)
            })
        }
    }

    /// 宿主翻完了一批（或者失败了），把结果还回去
    fileprivate func finish(_ id: UUID, _ text: String?) {
        guard let at = queue.firstIndex(where: { $0.id == id }) else { return }
        let job = queue.remove(at: at)
        job.done(text)
    }

    fileprivate func failAll() {
        let all = queue
        queue.removeAll()
        for job in all { job.done(nil) }
    }
}

/// 看不见的一层，挂在 `RootView` 上。它才是真正跑翻译的地方。
struct AppleTranslateHost: View {

    @ObservedObject private var store = AppleTranslate.shared
    /// 这一批要翻什么。`translationTask` 认的是「配置变了就重跑」，
    /// 所以每来一批就换一个新配置
    @State private var config: Any?

    var body: some View {
        if #available(iOS 18.0, *) {
            Color.clear
                .frame(width: 0, height: 0)
                .translationTask(config as? TranslationSession.Configuration) { session in
                    await run(session)
                }
                .onChange(of: store.queue.count) { _, n in
                    guard n > 0 else { return }
                    // 换一份新配置 = 让 translationTask 再跑一次
                    config = TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(identifier: "zh-Hans"))
                }
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    @available(iOS 18.0, *)
    private func run(_ session: TranslationSession) async {
        let batch = store.queue
        guard !batch.isEmpty else { return }
        do {
            // ⚠️ 语言包没下过的话这一句会弹系统那张下载卡片，
            // 她点了「下载」之后才真的翻得动——这跟系统翻译 App 是同一套。
            try await session.prepareTranslation()
            for job in batch {
                if let r = try? await session.translate(job.text) {
                    store.finish(job.id, r.targetText)
                } else {
                    store.finish(job.id, nil)
                }
            }
        } catch {
            store.failAll()
        }
    }
}
