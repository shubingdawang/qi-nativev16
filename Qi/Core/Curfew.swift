import Foundation

/// 宵禁：说过晚安之后，拦住那几个会让她刷到天亮的 App。
///
/// ## 为什么是「写一个文件」而不是真的锁
///
/// iOS 上真的去锁别的 App 只有一条路：`FamilyControls` / `ManagedSettings` /
/// `DeviceActivity`。**那三个框架要苹果单独批一个 entitlement**
/// （Family Controls Distribution），个人账号申请得到但要审，
/// 而且要单独的 target 和描述文件——那是另一批活。
///
/// 不用授权的那条路是**快捷指令**：她的「打开 App 自动化」在被拦的那几个 App
/// 打开时跑一下，读这个文件，写着 1 就把她弹回桌面。
/// 所以这一层要做的事只有一件：**把「现在是不是宵禁」老老实实写进一个文件**。
///
/// ⚠️ 这条路拦不住铁了心的人（她可以关掉自动化）。
/// 它拦的是「顺手一点就滑进去了」那种，不是防人。
///
/// ## 文件在哪儿、长什么样
///
/// 「文件」App →「我的 iPhone」→「栖」→ `宵禁.txt`，一行：
///
///     1|2026-09-17 07:00|说了晚安
///     0||
///
/// 第一格是 0/1，快捷指令只要认这一个字就够；后面两格是给人看的。
///
/// ⚠️ **每次变都要写**，包括自己到点解除那一次——
/// 文件停在 1 上没人改的话，她第二天早上会被自己的自动化关在外面。
@MainActor
final class Curfew: ObservableObject {

    static let shared = Curfew()

    /// 功能开着没有（她在「手机」那一页里的总开关）
    @Published var on: Bool {
        didSet {
            UserDefaults.standard.set(on, forKey: "curfewOn")
            if !on { until = nil }
            write()
        }
    }

    /// 宵禁到几点。`nil` = 现在没在宵禁
    @Published var until: Date? {
        didSet {
            UserDefaults.standard.set(until?.timeIntervalSince1970 ?? 0, forKey: "curfewUntil")
            write()
        }
    }

    /// 为什么开的（说了晚安 / 她自己按的 / 他按的）
    @Published var why: String {
        didSet { UserDefaults.standard.set(why, forKey: "curfewWhy") }
    }

    /// 早上几点解除
    @Published var wakeHour: Int {
        didSet {
            UserDefaults.standard.set(wakeHour, forKey: "curfewWakeHour")
            write()
        }
    }

    private init() {
        let d = UserDefaults.standard
        on = d.bool(forKey: "curfewOn")
        let t = d.double(forKey: "curfewUntil")
        until = t > 0 ? Date(timeIntervalSince1970: t) : nil
        why = d.string(forKey: "curfewWhy") ?? ""
        wakeHour = d.object(forKey: "curfewWakeHour") as? Int ?? 7
        settle()
    }

    /// 此刻拦不拦
    var active: Bool {
        guard on, let until else { return false }
        return until > Date()
    }

    /// 到点了就自己解除。**App 每次活过来都叫一次**——不开定时器，
    /// 后台定时器在 iOS 上本来就不保证跑，而这件事晚几分钟没有影响。
    func settle() {
        if let until, until <= Date() {
            self.until = nil
            why = ""
        } else {
            write()
        }
    }

    /// 开始宵禁，到明天早上 `wakeHour` 点。
    ///
    /// 已经在宵禁里就不动——**不要每说一句晚安就把时间往后推**。
    @discardableResult
    func start(why reason: String) -> Date? {
        guard on else { return nil }
        if active { return until }
        why = reason
        until = nextWake()
        return until
    }

    /// 现在就放她走
    func stop() {
        until = nil
        why = ""
    }

    /// 下一个「早上几点」
    private func nextWake() -> Date {
        let cal = Calendar.current
        let now = Date()
        var c = cal.dateComponents([.year, .month, .day], from: now)
        c.hour = wakeHour
        c.minute = 0
        let today = cal.date(from: c) ?? now.addingTimeInterval(8 * 3600)
        return today > now ? today : cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// 她说的话里有没有「睡了」的意思。
    ///
    /// ⚠️ 只认**她自己说**的那几句，不认他说的——
    /// 他道个晚安就把她锁了是最快让她关掉这个功能的方式。
    static func soundsLikeBed(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
        guard t.count <= 24 else { return false }      // 长句里顺口提一嘴的不算
        for w in ["晚安", "睡了", "去睡", "睡觉了", "我睡", "洗洗睡"] where t.contains(w) {
            return true
        }
        return false
    }

    // MARK: - 写给快捷指令看的那个文件

    /// `宵禁.txt` 在哪儿
    static var file: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("宵禁.txt")
    }

    private func write() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let line = active
            ? "1|\(f.string(from: until ?? Date()))|\(why.isEmpty ? "宵禁中" : why)\n"
            : "0||\n"
        try? line.data(using: .utf8)?.write(to: Self.file, options: .atomic)
    }

    /// 给她看的一句话
    var brief: String {
        guard on else { return "没开" }
        guard let until, active else { return "开着，今晚还没开始拦" }
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return "拦到 \(f.string(from: until))" + (why.isEmpty ? "" : "（\(why)）")
    }
}
