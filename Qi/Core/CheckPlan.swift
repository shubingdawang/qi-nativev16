import AppIntents
import UniformTypeIdentifiers
import UIKit

// MARK: - 他定的查岗
//
// 他自己决定什么时候查、查哪几样（在做什么 / 屏幕使用 / 健康），记在这儿。
// 她手机上的快捷指令隔一阵问一次「他要查岗吗」：到点了就按他要的那几样收集，
// 再用「交查岗」一次交过去（几样合成一条，不会一样问一次、互相打架）。
// 思路来自 Aru 的 iOS 查岗快捷指令，这里是本机重写的一份。

struct CheckPlan: Codable, Hashable {
    var at: Date
    /// 要看哪几样：在做什么、屏幕使用、健康
    var items: [String]
    /// 他自己记一句为什么（她看不到，给他自己回头看）
    var why = ""

    static let all = ["在做什么", "屏幕使用", "健康"]

    private static let key = "himCheckPlan"

    static var current: CheckPlan? {
        get {
            guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(CheckPlan.self, from: d)
        }
        set {
            if let v = newValue, let d = try? JSONEncoder().encode(v) {
                UserDefaults.standard.set(d, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

/// 快捷指令里问一句：他现在要查岗吗？到点了返回他要的那几样（用「、」隔开），没到就返回空
struct CheckDueIntent: AppIntent {
    static var title: LocalizedStringResource = "他要查岗吗"
    static var description = IntentDescription("到了他定的查岗时间就返回他要看的几样（在做什么、屏幕使用、健康），没到返回空。返回一次就算查过了")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let p = CheckPlan.current, p.at <= Date() else { return .result(value: "") }
        CheckPlan.current = nil
        return .result(value: p.items.joined(separator: "、"))
    }
}

/// 把这次查岗收到的几样一次交给他：在做什么、屏幕使用的截图、健康数据。不打开 App，他回了发通知
struct CheckReportIntent: AppIntent {
    static var title: LocalizedStringResource = "交查岗"
    static var description = IntentDescription("把在做什么、屏幕使用截图、健康数据合成一条交给他。不打开 App，他回了会发通知")
    static var openAppWhenRun = false

    @Parameter(title: "在做什么")
    var doing: String?

    @Parameter(title: "截图", supportedTypeIdentifiers: ["public.image"])
    var shot: IntentFile?

    @Parameter(title: "健康数据")
    var health: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        var lines = ["（查岗回执"]
        let d = (doing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let h = (health ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { lines.append("在做什么：" + d) }
        if !h.isEmpty { lines.append("健康：" + h) }
        var images: [UIImage] = []
        if let shot, let img = UIImage(data: shot.data) {
            images.append(ImageStore.downscale(img, maxSide: 1400))
            lines.append("附了一张截图（屏幕使用时间或此刻的屏幕）")
        }
        guard lines.count > 1 else { return .result() }
        lines[lines.count - 1] += "）"
        var app: AppState?
        for _ in 0..<40 {
            if let a = WakeEngine.shared.app { app = a; break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let app else { return .result() }
        await app.shortcutToHimAndNotify(lines.joined(separator: "\n"), images: images)
        return .result()
    }
}
