import Foundation

/// 小屋里能玩的那几样（她挑的四条）：
///   1. 要照顾的：绿植要浇水，会长大开花；鱼缸要喂，不喂鱼会蔫
///   2. 一起做的：拉他一起看电视、一起做饭（做好的菜进柜子）、一起听歌
///   3. 每天他在某件家具里藏一样小东西，她一件件翻，找到有金币
///   4. 跟作息连起来：早上醒了伸懒腰，快睡了自己回卧室
///
/// 全是本机的事，一分钱不花。这儿只记状态，演出来在 `ClawdHomeView`。
@MainActor
final class HomePlay: ObservableObject {

    static let shared = HomePlay()

    struct Plant: Codable {
        var watered: Date?
        /// 0 刚种 … 3 开花
        var growth: Double = 0
        var bloomed = false
        /// 哪天浇水给过金币（一天一次）
        var coinDay = ""
    }

    struct Treasure: Codable {
        var day: String
        var furniture: UUID?
        var found = false
        var prize = 8
        var what = ""
        /// 已经翻过的
        var tried: [UUID] = []
    }

    struct State: Codable {
        var plants: [String: Plant] = [:]
        /// 鱼缸上次喂的时候
        var fed: [String: Date] = [:]
        var fedCoinDay: [String: String] = [:]
        var treasure: Treasure?
        /// 哪天早上伸过懒腰了
        var morningDay = ""
        /// 哪天晚上自己回过卧室了
        var eveningDay = ""
        /// 一起做过几次饭
        var cooked = 0
    }

    @Published private(set) var state = State() {
        didSet { if loaded { Storage.save(state, to: "home-play.json") } }
    }
    private var loaded = false

    private init() {
        state = Storage.load(State.self, from: "home-play.json") ?? State()
        loaded = true
    }

    static func day(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    // MARK: 绿植

    func isPlant(_ kindID: String) -> Bool {
        if FurnitureCatalog.kind(kindID)?.category == .plant { return true }
        if ["hanging", "succulent", "bonsai", "plant", "cactus"].contains(kindID) { return true }
        return RoomActs.acts(for: kindID).contains { $0.name == "浇水" }
    }

    func plant(_ id: UUID) -> Plant { state.plants[id.uuidString] ?? Plant() }

    /// 渴了：一天半没浇（刚买来的也算渴）
    func thirsty(_ id: UUID, now: Date = Date()) -> Bool {
        guard let w = plant(id).watered else { return true }
        return now.timeIntervalSince(w) > 36 * 3600
    }

    func stage(_ id: UUID) -> Int { min(3, Int(plant(id).growth)) }

    static let stageNames = ["刚种下", "冒新叶", "长高了", "开花了"]

    /// 浇一次水。一天之内多浇不会长得更快；每天第一次浇给 2 个币，开花那一下给 10 个
    func water(_ id: UUID, now: Date = Date()) -> (text: String, coins: Int) {
        var p = plant(id)
        let today = Self.day(now)
        var coins = 0
        let wateredToday = p.watered.map { Self.day($0) == today } ?? false
        if !wateredToday {
            p.growth = min(3, p.growth + 1)
            if p.coinDay != today { coins += 2; p.coinDay = today }
        }
        p.watered = now
        var text: String
        if p.growth >= 3 && !p.bloomed {
            p.bloomed = true
            coins += 10
            text = "开花了！"
        } else if wateredToday {
            text = "今天浇过了，喝饱了"
        } else {
            text = "浇好了，" + Self.stageNames[min(3, Int(p.growth))]
        }
        if coins > 0 { text += "（+\(coins) 币）" }
        state.plants[id.uuidString] = p
        return (text, coins)
    }

    // MARK: 鱼缸

    func isTank(_ kindID: String) -> Bool {
        RoomActs.acts(for: kindID).contains { $0.name == "喂鱼" }
    }

    /// 饿了：一天没喂
    func hungry(_ id: UUID, now: Date = Date()) -> Bool {
        guard let f = state.fed[id.uuidString] else { return true }
        return now.timeIntervalSince(f) > 24 * 3600
    }

    func feed(_ id: UUID, now: Date = Date()) -> (text: String, coins: Int) {
        let today = Self.day(now)
        let was = hungry(id, now: now)
        state.fed[id.uuidString] = now
        var coins = 0
        if state.fedCoinDay[id.uuidString] != today {
            coins = 1
            state.fedCoinDay[id.uuidString] = today
        }
        var text = was ? "鱼游过来抢着吃" : "鱼吃饱了，在吐泡泡"
        if coins > 0 { text += "（+\(coins) 币）" }
        return (text, coins)
    }

    // MARK: 每天藏一样东西

    private static let hidden = ["一颗星星糖", "一张小纸条", "一枚亮晶晶的扣子", "半块饼干",
                                 "一片四叶草", "一只纸鹤", "一颗玻璃珠", "一枚贝壳"]

    /// 今天的那一样（没有就现藏一个）。屋里一件家具都没有就是 nil
    func todayTreasure(among items: [Furniture], now: Date = Date()) -> Treasure? {
        let today = Self.day(now)
        if let t = state.treasure, t.day == today { return t }
        guard let spot = items.filter({ $0.gx >= 0 && !$0.hidden }).randomElement() else { return nil }
        let t = Treasure(day: today, furniture: spot.id, prize: Int.random(in: 6...15),
                         what: Self.hidden.randomElement() ?? "一颗糖")
        state.treasure = t
        return t
    }

    /// 翻一件。返回：找到了 / 不在这儿
    func search(_ id: UUID) -> (found: Bool, text: String, coins: Int) {
        guard var t = state.treasure, t.day == Self.day(), !t.found else {
            return (false, "今天的已经找到了", 0)
        }
        if t.furniture == id {
            t.found = true
            state.treasure = t
            return (true, "找到了！是" + t.what + "（+\(t.prize) 币）", t.prize)
        }
        if !t.tried.contains(id) { t.tried.append(id) }
        state.treasure = t
        return (false, "这里没有……", 0)
    }

    // MARK: 作息

    func markMorning() { state.morningDay = Self.day() }
    func markEvening() { state.eveningDay = Self.day() }
    func noteCooked() { state.cooked += 1 }
}
