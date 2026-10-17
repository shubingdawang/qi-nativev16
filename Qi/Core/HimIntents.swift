import AppIntents

/// 快捷指令里跟他有关的几件。
///
/// 「查岗」的用法：快捷指令 → 自动化 → 特定时间（比如每晚 23:30）→
/// 动作先「获取电池电量」「获取当前位置」，再拼成一句文本（「23:30，电量 18%，在家」），
/// 最后一步选「栖 · 告诉他」，内容填这句。到点他就看到这句，接着来问你在干嘛。
///
/// 也可以挂在「打开 App」自动化上：她一打开抖音 / 小红书，就把「她刚打开了抖音」送过去。

/// 等 App 起来（冷启动时 `WakeEngine.app` 要等第一屏画出来才有）
@MainActor
private func waitForApp() async -> AppState? {
    for _ in 0..<40 {
        if let app = WakeEngine.shared.app { return app }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return WakeEngine.shared.app
}

/// 送一句给他，并打开和他的聊天
struct TellHimIntent: AppIntent {
    static var title: LocalizedStringResource = "告诉他"
    static var description = IntentDescription("把一句话送进和他的聊天里，打开聊天看他怎么回")
    static var openAppWhenRun = true

    @Parameter(title: "内容")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let app = await waitForApp() else { return .result() }
        app.shortcutToHim(t, open: true)
        return .result()
    }
}

/// 送一句给他，不打开 App（他回的话照常发通知）
struct TellHimQuietlyIntent: AppIntent {
    static var title: LocalizedStringResource = "悄悄告诉他"
    static var description = IntentDescription("把一句话送进和他的聊天里，不打开 App，他回了会发通知")
    static var openAppWhenRun = false

    @Parameter(title: "内容")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let app = await waitForApp() else { return .result() }
        // 等他说完再发通知（系统给快捷指令的时间有限，说不完的回到 App 会接着说）
        await app.shortcutToHimAndNotify(t)
        return .result()
    }
}

/// 直接打开和他的聊天
struct OpenHisChatIntent: AppIntent {
    static var title: LocalizedStringResource = "打开和他的聊天"
    static var description = IntentDescription("打开栖并翻到和他的聊天")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await waitForApp()?.openHisChat()
        return .result()
    }
}
