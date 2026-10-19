import AppIntents
import UserNotifications

/// 快捷指令里的「记一笔」。
///
/// 用法一（Apple Pay）：快捷指令 → 自动化 → 「交易」，动作选「栖 · 记一笔」，
/// 金额填「交易 → 金额」、名字填「交易 → 商家」。
///
/// 用法二（银行卡扣款短信，微信 / 支付宝绑卡付款也会有）：自动化 → 「信息」，
/// 信息包含「支出」或「消费」（或者发件人选银行），动作选「记一笔」，把「原文」填成那条短信，
/// 金额和名字都空着——从短信里认出来。
///
/// 记下来的放在记账页「等你确认」里，并弹一条通知；她选个分类、点同意才算记上。
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔"
    static var description = IntentDescription("把一笔花销放进记账页的「等你确认」里。可以直接填金额，也可以把扣款短信整条放进「原文」")
    static var openAppWhenRun = false

    @Parameter(title: "金额")
    var amount: Double?

    @Parameter(title: "名字")
    var name: String?

    @Parameter(title: "原文", description: "扣款短信、通知的原文，金额和商户从里面认")
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = SpendParser.parse(raw)
        guard let value = amount ?? parsed.amount, value > 0 else {
            return .result(dialog: raw.isEmpty ? "金额要大于 0" : "这条里没认出金额")
        }
        // 短信里写的是收入、退款，不记
        if amount == nil, parsed.isIncome { return .result(dialog: "这条是进账，没记") }
        let title = ((name ?? "").isEmpty ? (parsed.merchant ?? "") : (name ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let e = Expense(category: "other", name: title, amount: value)
        let why = raw.isEmpty ? "刚刚刷卡记下的，选个分类再确认" : "从这条记下的：" + String(raw.prefix(80))
        AccountBook.shared.propose(BookProposal(kind: .add, expense: e, why: why))

        let content = UNMutableNotificationContent()
        content.title = "刚刚花了 " + BookFormat.money(value)
        content.body = title.isEmpty ? "打开记账确认一下" : "\(title) · 打开记账确认一下"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "book-" + e.id.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
        return .result(dialog: "放进记账了")
    }
}

/// 从扣款短信 / 通知里认金额和商户
enum SpendParser {
    struct Result {
        var amount: Double?
        var merchant: String?
        var isIncome = false
    }

    static func parse(_ s: String) -> Result {
        var r = Result()
        guard !s.isEmpty else { return r }
        let text = s.replacingOccurrences(of: ",", with: "")
        r.isIncome = ["收入", "存入", "退款", "退货", "转入", "到账"].contains { text.contains($0) }
            && !["支出", "消费", "扣款", "付款", "支付"].contains { text.contains($0) }

        // 先找紧跟在「支出 / 消费 / 扣款 / 付款 / 支付」后面的数，再找带 ¥ / 元 的
        let patterns = [
            #"(?:支出|消费|扣款|付款|支付|交易)(?:人民币|RMB|CNY)?\s*[¥￥]?\s*(\d+(?:\.\d{1,2})?)"#,
            #"[¥￥]\s*(\d+(?:\.\d{1,2})?)"#,
            #"(\d+(?:\.\d{1,2})?)\s*元"#
        ]
        for p in patterns {
            if let m = text.range(of: p, options: .regularExpression) {
                let hit = String(text[m])
                guard let num = hit.range(of: #"\d+(?:\.\d{1,2})?"#, options: .regularExpression),
                      let v = Double(String(hit[num])) else { continue }
                r.amount = v
                break
            }
        }

        // 商户：「在XX消费」「XX 支付」「商户：XX」
        let merchantPatterns = [
            #"商户[:：]\s*([^\s，。,；;()（）]{2,20})"#,
            #"在([^\s，。,；;()（）0-9]{2,20}?)(?:消费|支付|付款)"#,
            #"(?:财付通|支付宝|微信支付)[-－—]([^\s，。,；;()（）0-9]{2,20})"#
        ]
        for p in merchantPatterns {
            if let m = text.range(of: p, options: .regularExpression) {
                var hit = String(text[m])
                for cut in ["商户：", "商户:", "在", "消费", "支付", "付款", "财付通-", "支付宝-", "微信支付-",
                            "财付通－", "支付宝－", "微信支付－", "财付通—", "支付宝—", "微信支付—"] {
                    hit = hit.replacingOccurrences(of: cut, with: "")
                }
                hit = hit.trimmingCharacters(in: .whitespaces)
                if hit.count >= 2 { r.merchant = hit; break }
            }
        }
        return r
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
        AppShortcut(intent: CheckDueIntent(),
                    phrases: ["\(.applicationName)他要查岗吗"],
                    shortTitle: "他要查岗吗",
                    systemImageName: "eye")
        AppShortcut(intent: CheckReportIntent(),
                    phrases: ["用\(.applicationName)交查岗"],
                    shortTitle: "交查岗",
                    systemImageName: "checkmark.message")
        AppShortcut(intent: OpenHisChatIntent(),
                    phrases: ["打开\(.applicationName)和他的聊天", "\(.applicationName)找他"],
                    shortTitle: "打开和他的聊天",
                    systemImageName: "heart.text.square")
    }
}
