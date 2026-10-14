import Foundation

/// 各座岛自己的玩法。
///
/// 花岛采花扎花束、养温室里那盆；月湾退潮捡贝壳、堆沙堡、点灯塔；松林采蘑菇捡松果、喂松鼠、泡温泉；
/// 星丘认星座、对着流星许愿；果园摘果子、熬果酱；小镇赶集把篮子里的东西卖掉换币。
///
/// 拿到的东西都进小岛的篮子（`WorldStore.save.basket`），岛和岛之间就是靠篮子串起来的：
/// 花岛的花扎成花束拿去小镇卖，果园的果子拿回小屋熬果酱。
/// 冷却、图鉴、松鼠认不认得她这些另存一份，不往小岛的存档里塞。
@MainActor
final class IslandPlay: ObservableObject {

    static let shared = IslandPlay()

    struct Save: Codable {
        /// 哪一处什么时候弄过（「岛:x,y:做什么」→ 时间）
        var done: [String: Date] = [:]
        /// 图鉴：贝壳、星座、稀有花……
        var book: [String: [String]] = [:]
        /// 喂过松鼠几回
        var squirrel = 0
        /// 温室里那盆什么时候种下的
        var greenhouse: Date?
        /// 许过的愿
        var wishes: [String] = []
    }

    @Published private(set) var s = Save() {
        didSet { if loaded { Storage.save(s, to: "island-play.json") } }
    }
    private var loaded = false

    private init() {
        s = Storage.load(Save.self, from: "island-play.json") ?? Save()
        loaded = true
    }

    private var world: WorldStore { WorldStore.shared }
    private var region: String { world.save.region }

    // MARK: 冷却

    private func key(_ what: String, _ x: Int, _ y: Int) -> String { "\(region):\(x),\(y):\(what)" }

    /// 这一处还要等多久（0 = 可以了）
    func wait(_ what: String, _ x: Int, _ y: Int, hours: Double) -> TimeInterval {
        guard let t = s.done[key(what, x, y)] else { return 0 }
        return max(0, hours * 3600 - Date().timeIntervalSince(t))
    }

    private func mark(_ what: String, _ x: Int, _ y: Int) {
        s.done[key(what, x, y)] = Date()
        // 太久以前的清掉，别越攒越多
        if s.done.count > 600 {
            let old = Date().addingTimeInterval(-3 * 86400)
            s.done = s.done.filter { $0.value > old }
        }
    }

    static func later(_ t: TimeInterval) -> String {
        let m = Int((t / 60).rounded(.up))
        return m >= 60 ? "\(m / 60) 小时\(m % 60 > 0 ? "\(m % 60) 分" : "")后" : "\(max(1, m)) 分钟后"
    }

    private func give(_ name: String, _ n: Int = 1) {
        world.addBasket(name, n)
    }

    private func take(_ name: String, _ n: Int = 1) -> Bool {
        guard count(name) >= n else { return false }
        world.addBasket(name, -n)
        return true
    }

    func count(_ name: String) -> Int { world.save.basket[name] ?? 0 }

    private func collect(_ book: String, _ item: String) -> Bool {
        var list = s.book[book] ?? []
        guard !list.contains(item) else { return false }
        list.append(item)
        s.book[book] = list
        return true
    }

    func book(_ name: String) -> [String] { s.book[name] ?? [] }

    // MARK: 花岛

    /// 景 → 采下来的花叫什么
    static let flowerOf: [WorldDecorKind: String] = [
        .daisy: "雏菊", .clover: "粉花", .flowerY: "小黄花", .flowerR: "郁金香",
        .tulipPeach: "杏色郁金香", .lavender: "薰衣草", .sunflower: "向日葵", .roseArch: "玫瑰"
    ]
    static var flowerNames: [String] { Array(Set(flowerOf.values)).sorted() }

    func pickFlower(_ d: WorldDecor, _ k: WorldDecorKind) -> String {
        guard let name = Self.flowerOf[k] else { return "" }
        let w = wait("flower", d.x, d.y, hours: 6)
        guard w == 0 else { return "这一丛刚采过，\(Self.later(w))再来" }
        mark("flower", d.x, d.y)
        give(name)
        world.flash("leaf")
        world.log("她采了一朵\(name)。")
        world.gain(2)
        return "采到一朵\(name)，放进篮子了"
    }

    /// 篮子里有哪些花、各几朵
    var flowersInBasket: [(String, Int)] {
        Self.flowerNames.compactMap { n in count(n) > 0 ? (n, count(n)) : nil }
    }

    /// 挑几朵扎成一束（2～5 朵）。返回这一束是什么样的
    func makeBouquet(_ picks: [String]) -> String? {
        guard picks.count >= 2 else { return nil }
        var need: [String: Int] = [:]
        for p in picks { need[p, default: 0] += 1 }
        guard need.allSatisfy({ count($0.key) >= $0.value }) else { return nil }
        for (n, c) in need { _ = take(n, c) }
        give("花束")
        let desc = need.sorted { $0.value > $1.value }.map { "\($0.value) 朵\($0.key)" }.joined(separator: "、")
        world.flash("gift")
        world.log("她扎了一束花：\(desc)。")
        world.gain(6)
        return desc
    }

    /// 温室里那盆：种下，一天以后开花
    func greenhouse() -> String {
        guard let t = s.greenhouse else {
            s.greenhouse = Date()
            world.log("她在温室里种下一颗稀有的花种。")
            return "种下了一颗稀有的花种，大概一天以后开花"
        }
        let left = 20 * 3600 - Date().timeIntervalSince(t)
        guard left <= 0 else { return "还没开，\(Self.later(left))再来看" }
        s.greenhouse = nil
        give("星光花")
        let first = collect("稀有花", "星光花")
        world.flash("sparkles")
        world.log("温室里那盆开了，是一朵会发光的星光花。")
        world.gain(15)
        return first ? "开了！是一朵会发光的星光花（第一次见）" : "又开了一朵星光花"
    }

    var greenhouseState: String {
        guard let t = s.greenhouse else { return "空着" }
        let left = 20 * 3600 - Date().timeIntervalSince(t)
        return left <= 0 ? "开花了" : "还要 " + Self.later(left).replacingOccurrences(of: "后", with: "")
    }

    // MARK: 月湾

    /// 退潮：早上 6～9 点、傍晚 17～20 点
    static var lowTide: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return (6..<9).contains(h) || (17..<20).contains(h)
    }

    static let shells: [(String, Int)] = [
        ("扇贝", 30), ("海螺", 24), ("粉色贝壳", 18), ("星星砂", 12), ("寄居蟹", 8), ("珍珠贝", 4), ("宝箱", 2), ("漂流瓶", 2)
    ]
    static var shellNames: [String] { shells.map(\.0).filter { $0 != "宝箱" && $0 != "漂流瓶" } }

    func beachcomb(_ x: Int, _ y: Int) -> String {
        guard Self.lowTide else { return "潮水还没退。早上 6～9 点、傍晚 5～8 点退潮，沙滩上才捡得到东西" }
        let w = wait("comb", x, y, hours: 3)
        guard w == 0 else { return "这一片刚翻过，换个地方，或者\(Self.later(w))再来" }
        mark("comb", x, y)
        let total = Self.shells.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<total)
        var got = "扇贝"
        for (n, w) in Self.shells { if r < w { got = n; break }; r -= w }
        world.gain(got == "珍珠贝" || got == "宝箱" ? 10 : 3)
        switch got {
        case "寄居蟹":
            _ = collect("贝壳", got)
            world.log("她在沙滩上翻到一只寄居蟹，看了一会儿又放回去了。")
            return "翻到一只寄居蟹，看了一会儿又放回去了"
        case "宝箱":
            ClawdStore.shared.coins += 20
            world.flash("star")
            world.log("她在退潮的沙滩上挖出一个小宝箱。")
            return "挖出一个小宝箱，里面有 20 币"
        default:
            give(got)
            let first = Self.shellNames.contains(got) && collect("贝壳", got)
            world.flash("sparkles")
            world.log("她在沙滩上捡到一个\(got)。")
            return "捡到一个\(got)" + (first ? "（第一次捡到，记进图鉴了）" : "")
        }
    }

    func sandcastle() -> String {
        let w = wait("castle", 0, 0, hours: 1)
        guard w == 0 else { return "刚堆的那个还在呢，\(Self.later(w))再堆一个" }
        mark("castle", 0, 0)
        world.flash("sparkles")
        world.log("她拉着你在沙滩上堆了一座沙堡。")
        world.gain(3)
        return "她拉着你在月湾的沙滩上堆了一座沙堡，插了一根羽毛当旗子。"
    }

    func lightTheLighthouse() -> String? {
        guard WorldStore.isNight else { return nil }
        let w = wait("light", 0, 0, hours: 6)
        guard w == 0 else { return nil }
        mark("light", 0, 0)
        world.flash("sparkles")
        world.log("你们一起点亮了月湾的灯塔。")
        world.gain(5)
        return "她拉着你爬上月湾的灯塔，把灯点亮了，光一圈一圈扫过湾里的水。"
    }

    // MARK: 松林

    func pickMushroom(_ d: WorldDecor) -> String {
        let w = wait("mush", d.x, d.y, hours: 6)
        guard w == 0 else { return "这一丛刚采过，\(Self.later(w))再来" }
        mark("mush", d.x, d.y)
        let kind = ["香菇", "鸡枞", "小红伞", "松茸"].randomElement() ?? "香菇"
        if kind == "小红伞" {
            _ = collect("蘑菇", kind)
            world.log("她发现一丛小红伞，没敢采。")
            return "是一丛小红伞，好看但不能吃，没采"
        }
        give("蘑菇")
        let first = collect("蘑菇", kind)
        world.gain(kind == "松茸" ? 8 : 3)
        world.log("她采了一把\(kind)。")
        return "采到一把\(kind)" + (first ? "（第一次见，记进图鉴了）" : "")
    }

    func pickPinecone(_ d: WorldDecor) -> String {
        let w = wait("cone", d.x, d.y, hours: 4)
        guard w == 0 else { return "树底下的都捡完了，\(Self.later(w))再来" }
        mark("cone", d.x, d.y)
        let n = Int.random(in: 1...3)
        give("松果", n)
        world.gain(2)
        world.log("她在松树底下捡了 \(n) 个松果。")
        return "捡到 \(n) 个松果"
    }

    var squirrelLevel: String {
        switch s.squirrel {
        case 0: return "还没见过"
        case 1..<3: return "远远看着你"
        case 3..<6: return "敢过来拿了"
        case 6..<10: return "认得你了"
        default: return "一看见你就跑过来"
        }
    }

    func feedSquirrel() -> String {
        guard take("松果") else { return "篮子里没有松果。先在松树底下捡几个" }
        let w = wait("squirrel", 0, 0, hours: 0.5)
        guard w == 0 else { give("松果"); return "它刚吃饱，抱着松果跑回树上了，\(Self.later(w))再来" }
        mark("squirrel", 0, 0)
        s.squirrel += 1
        world.flash("heart")
        world.gain(3)
        world.log("她喂了松林里的小松鼠一个松果。")
        switch s.squirrel {
        case 1: return "一只小松鼠从树上探出头，等你走开才下来把松果叼走了"
        case 3: return "小松鼠这回敢从你手边拿了"
        case 6: return "小松鼠认得你了，一看见你就从树上跑下来"
        case 10: return "小松鼠爬到你肩膀上，吃完还在你手心蹭了蹭"
        default: return "小松鼠抱着松果啃得很香（\(squirrelLevel)）"
        }
    }

    func hotSpring() -> String? {
        let w = wait("spring", 0, 0, hours: 2)
        guard w == 0 else { return nil }
        mark("spring", 0, 0)
        world.flash("bubbles.and.sparkles")
        world.log("你们一起在松林的温泉里泡了一会儿。")
        world.gain(6)
        return "她拉着你一起泡进松林的温泉，水汽把两个人的脸都蒸红了。"
    }

    // MARK: 星丘

    static let constellations = ["北斗七星", "猎户座", "仙后座", "天蝎座", "天鹅座", "天琴座", "狮子座",
                                 "双子座", "金牛座", "大熊座", "小熊座", "南十字"]

    func stargaze() -> String {
        guard WorldStore.isNight else { return "天还亮着，晚上再来看" }
        let w = wait("star", 0, 0, hours: 1)
        guard w == 0 else { return "眼睛还花着呢，\(Self.later(w))再看" }
        mark("star", 0, 0)
        let seen = book("星座")
        let left = Self.constellations.filter { !seen.contains($0) }
        world.gain(4)
        guard let got = left.randomElement() else {
            world.log("她又用望远镜看了一会儿星星。")
            return "星座都认全了，你们就躺着看了一会儿"
        }
        _ = collect("星座", got)
        world.flash("star")
        world.log("她用望远镜认出了\(got)。")
        return "认出了\(got)（星座图鉴 \(seen.count + 1)/\(Self.constellations.count)）"
    }

    func wish(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        s.wishes.append(t)
        world.flash("sparkles")
        world.log("她对着流星许了个愿。")
        world.gain(5)
    }

    // MARK: 果园

    static let fruitOf: [WorldDecorKind: String] = [.treeBig: "苹果", .olive: "桃子", .berry: "蓝莓"]
    static let fruits = ["苹果", "桃子", "蓝莓"]

    func pickFruit(_ d: WorldDecor, _ k: WorldDecorKind) -> String {
        guard let name = Self.fruitOf[k] else { return "" }
        let w = wait("fruit", d.x, d.y, hours: 5)
        guard w == 0 else { return "这棵刚摘过，\(Self.later(w))再来" }
        mark("fruit", d.x, d.y)
        let n = k == .berry ? Int.random(in: 2...4) : Int.random(in: 1...2)
        give(name, n)
        world.flash("leaf")
        world.gain(2)
        world.log("她摘了 \(n) 个\(name)。")
        return "摘到 \(n) 个\(name)"
    }

    var fruitCount: Int { Self.fruits.reduce(0) { $0 + count($1) } }

    /// 三个果子熬一罐果酱（果园的小屋、小屋的灶台都能熬）
    func makeJam() -> String {
        guard fruitCount >= 3 else { return "果子不够，要 3 个（现在 \(fruitCount) 个）。去果园摘" }
        var left = 3
        var used: [String: Int] = [:]
        for f in Self.fruits.sorted(by: { count($0) > count($1) }) where left > 0 {
            let n = min(left, count(f))
            if n > 0 { _ = take(f, n); used[f] = n; left -= n }
        }
        let main = used.max { $0.value < $1.value }?.key ?? "果"
        let name = main + "果酱"
        give("果酱")
        _ = collect("果酱", name)
        world.gain(6)
        world.log("熬了一罐\(name)。")
        return "熬好了一罐\(name)，放进小岛的篮子里了"
    }

    // MARK: 小镇

    /// 收东西的价钱（币）。漂流瓶留着走剧情，不收
    static func price(_ item: String) -> Int? {
        switch item {
        case "漂流瓶": return nil
        case "花束": return 25
        case "星光花": return 60
        case "果酱": return 30
        case "珍珠贝": return 30
        case "珍珠": return 50
        case "锦鲤": return 40
        case "一朵睡莲": return 12
        case "鲫鱼": return 5
        case "小鱼": return 3
        case "旧靴子": return 1
        case "蘑菇": return 5
        case "松果": return 2
        case "苹果", "桃子", "蓝莓": return 4
        case "扇贝", "海螺": return 4
        case "粉色贝壳", "星星砂": return 6
        case "南瓜": return 12
        case "西瓜": return 40
        case "玫瑰": return 30
        case "樱桃番茄": return 10
        case "面包": return nil
        case "番茄", "草莓": return 6
        default: return Self.flowerNames.contains(item) ? 3 : 5
        }
    }

    /// 面包店：8 币一个
    func buyBread() -> String {
        guard ClawdStore.shared.coins >= 8 else { return "币不够，一个面包 8 币" }
        ClawdStore.shared.coins -= 8
        give("面包")
        world.log("她在小镇的面包店买了一个刚出炉的面包。")
        return "买了一个刚出炉的面包，放进篮子了"
    }

    func eatBread() -> String? {
        guard take("面包") else { return nil }
        world.flash("heart")
        world.gain(3)
        world.log("你们分着吃了一个面包。")
        return "她把面包掰成两半，大的那半塞给你，两个人坐在喷泉边上吃。"
    }

    /// 种子在篮子里叫「西瓜种子」这样
    func seedPackets(_ s: WorldSeed) -> Int { count(s.name + "种子") }

    func useSeedPacket(_ s: WorldSeed) -> Bool { take(s.name + "种子") }

    /// 篮子里能卖的
    var sellable: [(name: String, n: Int, price: Int)] {
        world.save.basket.compactMap { k, v in
            guard v > 0, !k.hasSuffix("种子"), let p = Self.price(k) else { return nil }
            return (k, v, p)
        }
        .sorted { $0.price * $0.n > $1.price * $1.n }
    }

    func sell(_ item: String, _ n: Int = 1) -> String? {
        guard let p = Self.price(item), take(item, n) else { return nil }
        ClawdStore.shared.coins += p * n
        world.log("她在小镇的集市上卖了 \(n) 个\(item)。")
        return "卖了 \(n) 个\(item)，+\(p * n) 币"
    }
}
