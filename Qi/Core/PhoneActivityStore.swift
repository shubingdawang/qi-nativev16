import Foundation

/// 手机上今天开了什么 App、开了多久。
///
/// 为什么不走网络：
/// 快捷指令在后台跑的时候，Tailscale 常常还没连上、或者请求超时，
/// 于是就报"网络错误"。改成**写文件**之后这条路彻底不依赖网络——
/// 快捷指令只往一个 txt 里追加一行，栖自己去读。
///
/// 快捷指令那边这么配（一次配好，以后不用管）：
///   1. 新建自动化 → 打开 App → 选你想记的那些 App
///   2. 动作选「文本」，内容填：`2026-08-10 14:30|微信|open`
///      （日期和时间用变量「当前日期」，格式随意，能认出来就行）
///   3. 再加一个「追加到文件」，存到 iCloud 云盘或本机的
///      「快捷指令」文件夹，文件名 `phone-activity.txt`
///   4. 关掉「运行前询问」
///
/// 然后在栖里把那个文件导进来一次，之后每次读都是最新的。
struct PhoneEvent: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var time: Date
    var app: String
    /// open 或 close，只有 open 也能用
    var action: String = "open"
}

@MainActor
final class PhoneActivityStore: ObservableObject {

    static let shared = PhoneActivityStore()

    @Published var events: [PhoneEvent] = []
    /// 那个 txt 在哪儿。用书签存，这样下次打开还能读到。
    @Published var bookmark: Data? {
        didSet { UserDefaults.standard.set(bookmark, forKey: "phoneActivityBookmark") }
    }
    @Published var lastError: String?

    init() {
        bookmark = UserDefaults.standard.data(forKey: "phoneActivityBookmark")
    }

    /// 选好文件之后记下来，以后自动读。
    ///
    /// 这里之前有个坑：**书签必须在权限范围之内创建**，
    /// 不然 bookmarkData() 会失败，而失败时又什么都没做，
    /// 界面就一动不动，看着像"选了没反应"。
    func remember(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        // 先把内容读出来。哪怕书签存不下，这一次也得有结果。
        let raw = try? String(contentsOf: url, encoding: .utf8)

        if let data = try? url.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmark = data
        }

        if let raw {
            events = parse(raw)
            lastError = events.isEmpty
                ? "文件读到了，但一条也没解析出来。看看每行是不是「日期|App名字|open」这样。"
                : nil
            if bookmark == nil {
                lastError = "这次读到 \(events.count) 条，但记不住这个文件，下次还得重选。把 txt 放进「文件」App 里再选会好些。"
            }
        } else {
            lastError = "打不开这个文件，换个位置试试（放进「文件」App 里最稳）"
        }
    }

    /// 重新读一遍
    func reload() {
        guard let bookmark else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            lastError = "找不到那个文件了，重新选一次"
            return
        }
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            lastError = "读不出来，检查一下是不是纯文本"
            return
        }
        events = parse(raw)
        lastError = events.isEmpty
            ? "文件是空的，或者每行的格式对不上（要「日期|App名字|open」这样）"
            : nil
    }

    /// 一行一条。用竖线、逗号、制表符隔开都行——
    /// 快捷指令里手打分隔符太容易打错，多认几种省事。
    private func parse(_ text: String) -> [PhoneEvent] {
        var out: [PhoneEvent] = []

        // 中文那几种要用中文 locale，不然 DateFormatter 认不出「年月日」
        let cnFormats = ["yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm",
                         "yyyy年M月d日HH:mm:ss", "yyyy年M月d日HH:mm"]
        let enFormats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
                         "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
                         "yyyy.MM.dd HH:mm:ss", "yyyy.MM.dd HH:mm",
                         "MM-dd HH:mm"]
        var formatters: [DateFormatter] = []
        for f in cnFormats {
            let d = DateFormatter()
            d.locale = Locale(identifier: "zh_CN")
            d.dateFormat = f
            formatters.append(d)
        }
        for f in enFormats {
            let d = DateFormatter()
            d.locale = Locale(identifier: "en_US_POSIX")
            d.dateFormat = f
            formatters.append(d)
        }

        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }

            // 分隔符：半角竖线、**全角竖线**（快捷指令里打出来的就是这个）、
            // 逗号、制表符。空字段要留着占位，不能过滤掉——
            // 「日期｜｜close」这种行如果把空的挤掉，就会把 close 当成 App 名。
            let parts = t.components(separatedBy: CharacterSet(charactersIn: "|｜,，\t"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }

            var when: Date?
            for f in formatters {
                if let d = f.date(from: parts[0]) { when = d; break }
            }
            guard let when else { continue }

            let app = parts[1]
            // App 名是空的（快捷指令偶尔会漏），这条没用
            guard !app.isEmpty else { continue }

            var event = PhoneEvent(time: when, app: app)
            if parts.count >= 3 {
                // 「closeen」「openn」这种脏尾巴也认，前缀对上就行
                let raw = parts[2].lowercased()
                if raw.hasPrefix("close") { event.action = "close" }
                else if raw.hasPrefix("open") { event.action = "open" }
                else if raw.isEmpty { continue }
                else { event.action = raw }
            }
            out.append(event)
        }
        return out.sorted { $0.time > $1.time }
    }

    // MARK: 算一算

    // 下面这几样原来只会算「今天」。
    //
    // 她要能往回翻，所以全部改成**按指定那天算**，
    // 原来那几个 today 开头的留着当薄壳子——
    // 工具那边、给他看的那段话都还在用它们，签名一动就得跟着改一圈。

    /// 有记录的那些天，新的在前。翻页就是在这个数组里走。
    var days: [Date] {
        let cal = Calendar.current
        var seen: Set<Date> = []
        for e in events { seen.insert(cal.startOfDay(for: e.time)) }
        return seen.sorted(by: >)
    }

    func events(on day: Date) -> [PhoneEvent] {
        let cal = Calendar.current
        return events.filter { cal.isDate($0.time, inSameDayAs: day) }
    }

    func pickups(on day: Date) -> Int {
        events(on: day).filter { $0.action == "open" }.count
    }

    var todayEvents: [PhoneEvent] { events(on: Date()) }

    /// 今天拿起手机多少次——把每次打开都算一次
    var pickups: Int { pickups(on: Date()) }

    func todayByApp() -> [(app: String, seconds: TimeInterval, times: Int)] {
        byApp(on: Date())
    }

    /// 那天每个 App 用了多久。
    /// 只有 open 事件的话，用相邻两次打开的间隔估；
    /// 有 close 就用真实时长，准得多。
    func byApp(on day: Date) -> [(app: String, seconds: TimeInterval, times: Int)] {
        let list = events(on: day).sorted { $0.time < $1.time }
        var seconds: [String: TimeInterval] = [:]
        var times: [String: Int] = [:]

        for (i, e) in list.enumerated() {
            guard e.action == "open" else { continue }
            times[e.app, default: 0] += 1

            // 优先找同一个 App 的 close
            if let close = list[(i + 1)...].first(where: {
                $0.app == e.app && $0.action == "close"
            }) {
                seconds[e.app, default: 0] += close.time.timeIntervalSince(e.time)
                continue
            }
            // 没有的话就用"下一次打开别的 App"当结束
            if let next = list[(i + 1)...].first(where: { $0.action == "open" }) {
                let gap = next.time.timeIntervalSince(e.time)
                // 隔太久多半是放下手机了，不算
                if gap < 3600 { seconds[e.app, default: 0] += gap }
            }
        }

        return seconds.keys.map {
            (app: $0, seconds: seconds[$0] ?? 0, times: times[$0] ?? 0)
        }
        .sorted { $0.seconds > $1.seconds }
    }

    func total(on day: Date) -> TimeInterval {
        byApp(on: day).reduce(0) { $0 + $1.seconds }
    }

    var todayTotal: TimeInterval { total(on: Date()) }

    /// 正在用哪个——最后一条 open
    var currentApp: String? {
        todayEvents.first { $0.action == "open" }?.app
    }

    /// 给他看的那段话
    func brief() -> String {
        let list = todayByApp()
        guard !list.isEmpty else {
            return "今天还没有手机使用记录。（快捷指令可能没跑起来，或者文件还没导进来）"
        }
        var s = "她今天用了 \(clock(todayTotal))，拿起 \(pickups) 次。"
        if let now = currentApp { s += "刚才在用：\(now)。" }
        s += "\n用得最多的："
        for item in list.prefix(5) {
            s += "\n· \(item.app)　\(clock(item.seconds))　\(item.times) 次"
        }
        return s
    }

    func clock(_ s: TimeInterval) -> String {
        let m = Int(s) / 60
        if m < 60 { return "\(m) 分钟" }
        return "\(m / 60) 小时 \(m % 60) 分"
    }
}
