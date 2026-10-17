import AppIntents
import UserNotifications

/// 快捷指令里的「记一笔」。
///
/// 用法：快捷指令 → 自动化 → 「交易」（钱包里刷卡后触发），动作选「栖 · 记一笔」，
/// 金额填「交易 → 金额」、名字填「交易 → 商家」。刷完卡这一笔就进了记账页的「等你确认」，
/// 顺手弹一条通知；她点开选个分类、点同意就记上了。
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔"
    static var description = IntentDescription("把一笔花销放进记账页的「等你确认」里")
    static var openAppWhenRun = false

    @Parameter(title: "金额")
    var amount: Double

    @Parameter(title: "名字")
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else { return .result(dialog: "金额要大于 0") }
        let title = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let e = Expense(category: "other", name: title, amount: amount)
        AccountBook.shared.propose(BookProposal(kind: .add, expense: e, why: "刚刚刷卡记下的，选个分类再确认"))

        let content = UNMutableNotificationContent()
        content.title = "刚刚花了 " + BookFormat.money(amount)
        content.body = title.isEmpty ? "打开记账确认一下" : "\(title) · 打开记账确认一下"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "book-" + e.id.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
        return .result(dialog: "放进记账了")
    }
}

struct QiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogExpenseIntent(),
                    phrases: ["用\(.applicationName)记一笔", "\(.applicationName)记账"],
                    shortTitle: "记一笔",
                    systemImageName: "yensign.circle")
        AppShortcut(intent: TellHimIntent(),
                    phrases: ["用\(.applicationName)告诉他", "\(.applicationName)告诉他"],
                    shortTitle: "告诉他",
                    systemImageName: "bubble.left")
        AppShortcut(intent: TellHimQuietlyIntent(),
                    phrases: ["用\(.applicationName)悄悄告诉他"],
                    shortTitle: "悄悄告诉他",
                    systemImageName: "bubble.left.and.text.bubble.right")
        AppShortcut(intent: OpenHisChatIntent(),
                    phrases: ["打开\(.applicationName)和他的聊天", "\(.applicationName)找他"],
                    shortTitle: "打开和他的聊天",
                    systemImageName: "heart.text.square")
    }
}
