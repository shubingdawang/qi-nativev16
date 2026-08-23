import Foundation
import CoreLocation

// MARK: - 查岗：她此刻在哪儿、那儿什么天气
//
// 她给的那份参考（p1）是「不用 VPS 的 iPhone 查岗小指令」：
// AI 自己决定要不要看一眼手机当前的画面；决定看就**发一封邮件**触发
// iPhone 快捷指令，手机截屏 + 取定位 + 取天气，再把结果**邮件回传**给 AI。
//
// ⚠️ **那一圈邮件我们不要。**
//
// 那份教程绕邮件，是因为 ChatGPT 那种官方客户端**没法让手机做事**——
// 它只能靠「发一封邮件」当信号线，让快捷指令那头收到、动手、再寄回来。
// 光是为了这条信号线，她就得配两个邮箱、开 IMAP/SMTP、生成授权码、
// 配 Caddy、还要跟 VPN 节点较劲（那份教程第六节整节都在讲这个有多难搞）。
//
// **我们就在这台手机上。** 截图读本地文件夹（跟「让他看屏幕」同一条路），
// 定位和天气直接问系统和一个免密钥的接口。
// 不发邮件、不过服务器、不用 VPS——**一个字节都不出这台手机**，
// 除了问天气那一下（只发经纬度，见下面 `coarse`）。
//
// ## 那份教程里真正值钱的一句
//
// 不是链路，是第五节那段行为规矩：
//
//   > 把本轮运行视为一次自然醒来的机会，不是必须发送消息。
//   > 先综合本聊天最近的内容、当前时间和我们之间尚未说完的事，
//   > 判断此刻是否真的有一句具体而自然的话主动对我说。
//   > 若没有，不通知，也不要为了完成任务机械查岗。
//
// 这跟我们 `AttentionSet` 那套是同一句话（「什么都不说也是一个完整的结果」），
// 所以 `check_in` 的返回里也带着这句——**给了他一堆事实之后，
// 最后一句必须是「不值得说就别说」**，不然他会为了用上刚拿到的东西硬找话说。

/// 她此刻的处境。拿不到的那几样就是 nil，**不编**。
struct Whereabouts: Sendable {
    /// 城市 / 行政区（比如「日本 东京都 涩谷区」）
    var place: String?
    /// 精确到街道的那一档。**只有她把精度调到「精确」才会有**。
    var street: String?
    var tempC: Double?
    var feelsC: Double?
    var weather: String?
    var humidity: Int?
    /// 天气是哪个时刻的
    var at: Date?
    /// 出了什么问题（权限没给、定位超时…），要跟她和他都说实话
    var trouble: String?
}

@MainActor
final class WhereaboutsService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = WhereaboutsService()

    /// 定位给到什么程度。**默认只到城市**——
    /// 那份教程第八节自己写着：「不想暴露精确地址时，只回传城市或行政区。」
    enum Precision: String, Codable, CaseIterable, Identifiable {
        case off      // 完全不给
        case coarse   // 只到城市/行政区
        case exact    // 精确到街道

        var id: String { rawValue }
        var label: String {
            switch self {
            case .off:    return "不给位置"
            case .coarse: return "只到城市"
            case .exact:  return "精确到街道"
            }
        }
    }

    private let manager = CLLocationManager()
    private var pending: [CheckedContinuation<CLLocation?, Never>] = []
    @Published var lastTrouble: String?

    private override init() {
        super.init()
        manager.delegate = self
        // 只到城市那一档就用低精度——**省电，而且系统本来就给得更粗**。
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    func ask() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: 拿一次位置

    /// 要一次当前位置。**一次性**，不开持续定位——
    /// 持续定位又费电又是一直在跟着她，查岗不需要那样。
    func locate() async -> CLLocation? {
        guard authorized else {
            ask()
            lastTrouble = "还没给定位权限"
            return nil
        }
        manager.desiredAccuracy = precision == .exact
            ? kCLLocationAccuracyHundredMeters
            : kCLLocationAccuracyKilometer

        return await withCheckedContinuation { cont in
            pending.append(cont)
            manager.requestLocation()
            // 定位有时候会一直不回。**不能让他就这么挂着**——
            // 8 秒还没结果就当拿不到，别的信息照样给。
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self.finish(nil, trouble: "定位一直没回来（8 秒）")
            }
        }
    }

    private func finish(_ loc: CLLocation?, trouble: String?) {
        guard !pending.isEmpty else { return }
        if let trouble { lastTrouble = trouble }
        let waiting = pending
        pending.removeAll()
        for c in waiting { c.resume(returning: loc) }
    }

    nonisolated func locationManager(_ m: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last, trouble: nil) }
    }

    nonisolated func locationManager(_ m: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(nil, trouble: "定位失败：\(error.localizedDescription)")
        }
    }

    /// 现在这一档给到多细。存在设置里，这儿只是取个方便。
    var precision: Precision {
        Precision(rawValue: UserDefaults.standard.string(forKey: "checkInPrecision") ?? "")
            ?? .coarse
    }

    // MARK: 把经纬度翻成地名

    /// 把经纬度翻成地名。
    ///
    /// 默认走系统自带的反地理编码，**不用密钥、不用第三方**。
    /// 她要是在设置里填了高德的 key，就先问高德——它在国内更细，
    /// 能给到街道和**周边有什么**（`CLGeocoder` 只到省市区）。
    ///
    /// **精度那条线不变**：她设的是「只到城市」的话，
    /// 高德查回来的街道照样不给他。那条线是她的，不是接口的。
    func placeName(of loc: CLLocation) async -> (place: String?, street: String?) {
        let key = UserDefaults.standard.string(forKey: "amapKey") ?? ""
        if !key.isEmpty, let amap = await amapPlace(of: loc, key: key) {
            return amap
        }
        guard let marks = try? await CLGeocoder().reverseGeocodeLocation(loc),
              let m = marks.first else { return (nil, nil) }
        let coarse = [m.country, m.administrativeArea, m.locality, m.subLocality]
            .compactMap { $0 }
            .reduce(into: [String]()) { acc, x in if !acc.contains(x) { acc.append(x) } }
            .joined(separator: " ")
        let fine = [m.thoroughfare, m.subThoroughfare, m.name]
            .compactMap { $0 }
            .reduce(into: [String]()) { acc, x in if !acc.contains(x) { acc.append(x) } }
            .joined(separator: " ")
        return (coarse.isEmpty ? nil : coarse,
                precision == .exact && !fine.isEmpty ? fine : nil)
    }

    /// 问一次高德的逆地理编码。
    ///
    /// 走的是 **Web 服务**那套（纯 HTTPS，不是 iOS SDK——SDK 要绑 Bundle ID，
    /// 还得往包里塞一个几兆的库）。只发经纬度，不发她是谁。
    ///
    /// 出错就返回 nil，调用方自己退回系统那条路——
    /// **她的位置不该因为一个第三方接口抽风就查不出来**。
    private func amapPlace(of loc: CLLocation, key: String)
        async -> (place: String?, street: String?)? {
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        guard let url = URL(string:
            "https://restapi.amap.com/v3/geocode/regeo?key=\(key)"
            + "&location=\(String(format: "%.6f,%.6f", lon, lat))"
            + "&extensions=\(precision == .exact ? "all" : "base")&radius=200")
        else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? String) == "1",
              let re = json["regeocode"] as? [String: Any],
              let comp = re["addressComponent"] as? [String: Any]
        else { return nil }

        // 省市区那一档：直辖市的 city 是空的，退回省
        let province = comp["province"] as? String
        let cityRaw = comp["city"]
        let city = (cityRaw as? String) ?? ""
        let district = comp["district"] as? String
        let coarse = [province, city.isEmpty ? nil : city, district]
            .compactMap { $0 }
            .reduce(into: [String]()) { acc, x in if !acc.contains(x) { acc.append(x) } }
            .joined(separator: " ")

        guard precision == .exact else {
            return (coarse.isEmpty ? nil : coarse, nil)
        }

        // 精确那一档才给街道和周边。**这是她自己开的**
        var fine: [String] = []
        if let sn = comp["township"] as? String, !sn.isEmpty { fine.append(sn) }
        if let street = comp["streetNumber"] as? [String: Any] {
            let s = (street["street"] as? String) ?? ""
            let n = (street["number"] as? String) ?? ""
            if !s.isEmpty { fine.append(s + n) }
        }
        // 周边最近的那个点。「你家楼下那家便利店」就是它
        if let pois = re["pois"] as? [[String: Any]],
           let near = pois.first, let name = near["name"] as? String, !name.isEmpty {
            fine.append("靠近" + name)
        }
        let street = fine.joined(separator: " ")
        return (coarse.isEmpty ? nil : coarse, street.isEmpty ? nil : street)
    }

    // MARK: 天气

    /// Open-Meteo。**不用注册、不用密钥、大陆也通。**
    ///
    /// 只发经纬度出去，不发她是谁——这是整套查岗里**唯一**离开这台手机的东西，
    /// 所以专门挑了一个不需要账号的接口：没有账号就没有「谁在什么时候查过哪儿」。
    func weather(at loc: CLLocation) async -> Whereabouts {
        var out = Whereabouts()
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        guard let url = URL(string:
            "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code"
            + "&timezone=auto")
        else { return out }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any]
        else {
            out.trouble = "天气没拿到"
            return out
        }
        out.tempC = cur["temperature_2m"] as? Double
        out.feelsC = cur["apparent_temperature"] as? Double
        out.humidity = (cur["relative_humidity_2m"] as? NSNumber)?.intValue
        if let code = (cur["weather_code"] as? NSNumber)?.intValue {
            out.weather = Self.weatherWord(code)
        }
        out.at = Date()
        return out
    }

    /// WMO 天气代码翻成人话。照 Open-Meteo 文档那张表。
    static func weatherWord(_ code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻雨"
        case 61, 63: return "下雨"
        case 65: return "大雨"
        case 66, 67: return "冻雨"
        case 71, 73: return "下雪"
        case 75: return "大雪"
        case 77: return "米雪"
        case 80, 81: return "阵雨"
        case 82: return "暴雨"
        case 85, 86: return "阵雪"
        case 95: return "雷阵雨"
        case 96, 99: return "雷暴带冰雹"
        default: return "说不好"
        }
    }

    // MARK: 一次拿全

    /// 位置 + 地名 + 天气，一次拿全。拿不到的就空着，**绝不编**。
    func snapshot() async -> Whereabouts {
        var out = Whereabouts()
        guard precision != .off else {
            out.trouble = "她把位置关掉了"
            return out
        }
        guard let loc = await locate() else {
            out.trouble = lastTrouble ?? "拿不到位置"
            return out
        }
        // ⚠️ 这两步都**必须有闹钟**（她报的第 3 条：查岗卡顿甚至卡死，只能大退）。
        //
        // 定位那步本来就有 8 秒的兜底，但后面两步没有：
        // · `CLGeocoder` **不带超时**，挂在墙外的时候能吊很久；
        // · 天气那条虽然 `timeoutInterval = 10`，赶上重试也不止十秒。
        // 三步串起来最坏能拖到半分钟以上——她那边看到的就是「点了没反应」。
        //
        // 现在每一步都跟一个闹钟赛跑，谁先到算谁：
        // 地名 6 秒、天气 8 秒。超时就当这一项没有，**别的照给**。
        // 查岗少一行地名不要紧，卡死才要命。
        let names = await raced(6) { await self.placeName(of: loc) } ?? (nil, nil)
        out.place = names.place
        out.street = names.street

        var w = await raced(8) { await self.weather(at: loc) } ?? Whereabouts()
        if w.tempC == nil && out.place != nil { w.trouble = "天气没查到（超时）" }
        w.place = out.place
        w.street = out.street
        return w
    }

    /// 给一件可能永远不回来的事套一个闹钟。谁先到算谁。
    ///
    /// 超时那一路返回 nil，调用方自己决定拿什么顶上——
    /// **不抛错**：查岗是「顺手看一眼」，不该因为一项没查到就整件事失败。
    private func raced<T: Sendable>(_ seconds: Double,
                          _ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
