import SwiftUI

// MARK: - clawd 跟家具的互动
//
// 她要的：「每一个家具或者物品跟 clawd 都有三到四个互动动作。」
//
// ## 还是不画帧
//
// 跟「拿东西」那套（`ClawdRig`）一个道理：
// 二十件家具 × 四个动作 = 八十套帧，画不完，而且加一件新家具就得再画四套。
//
// 所以这儿也只描述**规则**，动作从已有的那几帧里长出来：
// 一个动作 = 「他该在这件东西的哪儿」+「摆哪一帧」+「多久」+「嘀咕一句」。
//
// **加一件新家具，只在 `IsoShape.actions` 里写几个动作名就行。**
// 动作名怎么演，这儿有一张全局的表——「坐下」不管是坐凳子还是坐床沿，
// 演法是一样的。
//
// ## ⚠️ 这一整套不花一分钱
//
// 挑哪件家具、做哪个动作、嘀咕哪一句，全是本机随机——
// **一次模型都不调**。他自己在屋里过日子这件事，
// 不该跟她的账单挂钩。
//
// （接上阿晏之后，他在那句已经会发生的话里可以顺手指定做什么，
//  见 `RoomMarker`——那也还是同一次请求，不多花。）

/// 一个互动动作。
struct RoomAct {
    let name: String
    /// 他该待在这件东西的哪儿
    let spot: Spot
    /// 用哪一帧
    let mood: ClawdMood
    /// 持续多久
    let seconds: Double
    /// 会嘀咕的几句，随机挑一句。**本地台词，不花钱**
    let lines: [String]

    enum Spot {
        /// 站在旁边（浇水、看电视）
        case beside
        /// 待在它**上面**（坐、躺、踩）
        case onTop
    }
}

enum RoomActs {

    /// 动作名 → 怎么演。**一张全局的表**——
    /// 「坐下」不管是坐凳子还是坐床沿，演法都一样。
    ///
    /// 表里没有的名字会退回一个通用的「凑过去看看」，
    /// **不会因为写了个新名字就崩**。
    static func act(_ name: String) -> RoomAct {
        switch name {

        case "躺下", "钻被窝":
            return RoomAct(name: name, spot: .onTop, mood: .sleeping, seconds: 9,
                           lines: ["躺一会儿", "唔……软的", "就眯一小会儿"])
        case "打滚":
            return RoomAct(name: name, spot: .onTop, mood: .flail, seconds: 3.5,
                           lines: ["滚一圈", "嘿嘿", "咕噜噜"])
        case "坐下", "坐边上", "瘫着":
            return RoomAct(name: name, spot: .onTop, mood: .idle, seconds: 7,
                           lines: ["坐会儿", "歇一下", "这儿舒服"])
        case "踩上去":
            return RoomAct(name: name, spot: .onTop, mood: .happy, seconds: 3,
                           lines: ["登高了", "看得远一点"])
        case "趴桌上", "趴扶手":
            return RoomAct(name: name, spot: .onTop, mood: .drowsy, seconds: 6,
                           lines: ["趴一下", "有点困"])

        case "浇水":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 4,
                           lines: ["喝点水吧", "又长高了一点", "别蔫啊"])
        case "闻一闻":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 3,
                           lines: ["香的", "唔——"])
        case "打开看", "凑近看", "按两下":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 6,
                           lines: ["看会儿", "咦", "这个好玩"])
        case "开灯", "凑到灯下":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 4,
                           lines: ["亮了", "暖和"])
        case "抽一本", "踮脚够":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 5,
                           lines: ["找找看", "够不着……", "拿到了"])
        case "抱一下":
            return RoomAct(name: name, spot: .beside, mood: .loving, seconds: 4,
                           lines: ["抱抱", "毛茸茸的"])
        case "说悄悄话":
            return RoomAct(name: name, spot: .beside, mood: .talking, seconds: 4,
                           lines: ["嘘——", "跟你说个事"])
        case "摆正":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 3,
                           lines: ["歪了", "这样才对"])
        case "拿起来", "摸一下":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 3,
                           lines: ["摸摸", "这个是什么来着"])

        // MARK: 三个一直漏着的
        //
        // 这三个名字在 `IsoShape.actions` 里用了很久，
        // **但这张表里从来没有过**——所以他跑过去，站着说一句「……」。
        // 是加新家具的时候写脚本对了一遍「用到的动作名 vs 表里有的」才发现的。
        //
        // ⚠️ 记一句：这种漏**不会报错**，只会让动作变哑。
        // 加完新家具要对一遍这两张表。

        case "把东西放上去":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 4,
                           lines: ["放这儿吧", "摆正一点", "好了"])
        case "在桌边站着":
            return RoomAct(name: name, spot: .beside, mood: .thinking, seconds: 5,
                           lines: ["站会儿", "在想事情", "……"])
        case "戳一下":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 3,
                           lines: ["戳戳", "硬的", "会动吗"])

        // MARK: 厨房和浴室那几件
        //
        // ⚠️ **新家具的动作名一定要在这儿有一条。**
        // 漏了不会报错，会掉进最底下那个 default——
        // 于是他跑过去站着说一句「……」。看着像坏了，其实是没写。

        case "开冰箱":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 5,
                           lines: ["有什么好吃的", "凉气跑出来了", "……又忘了要拿什么"])
        case "贴着凉快":
            return RoomAct(name: name, spot: .beside, mood: .drowsy, seconds: 6,
                           lines: ["凉的", "贴一会儿", "舒服"])
        case "盯着转":
            return RoomAct(name: name, spot: .beside, mood: .thinking, seconds: 6,
                           lines: ["转啊转", "还没好", "快了快了"])
        case "坐上面":
            return RoomAct(name: name, spot: .onTop, mood: .happy, seconds: 6,
                           lines: ["震得屁股麻", "这儿暖", "坐会儿"])

        case "掀盖子":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 3,
                           lines: ["啪嗒", "又合上了"])
        case "冲一下":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 3,
                           lines: ["哗——", "好听"])

        case "泡进去":
            return RoomAct(name: name, spot: .onTop, mood: .drowsy, seconds: 10,
                           lines: ["泡一会儿", "唔……热的", "快化了"])
        case "拍水花":
            return RoomAct(name: name, spot: .onTop, mood: .flail, seconds: 4,
                           lines: ["啪啪啪", "溅出来了", "嘿嘿"])
        case "洗把脸":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 4,
                           lines: ["醒醒神", "水好凉"])
        case "照镜子":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 4,
                           lines: ["还是这么好看", "头顶翘起来了", "整理一下"])

        case "挑一瓶":
            return RoomAct(name: name, spot: .beside, mood: .thinking, seconds: 6,
                           lines: ["选哪个呢", "都想要", "……还是这个吧"])
        case "拍一下":
            return RoomAct(name: name, spot: .beside, mood: .flail, seconds: 3,
                           lines: ["卡住了", "出来啊", "咚"])
        case "隔着玻璃看":
            return RoomAct(name: name, spot: .beside, mood: .peeking, seconds: 5,
                           lines: ["贴着看", "亮晶晶的"])

        default:
            return RoomAct(name: name, spot: .beside, mood: .idle, seconds: 3,
                           lines: ["……", "看看"])
        }
    }

    /// 这件家具能做的那几个动作
    static func acts(for kindID: String) -> [RoomAct] {
        FurnitureCatalog.shape(of: kindID).actions.map { act($0) }
    }

    /// 他做这个动作的时候该站/坐在**屏幕上的哪个点**。
    ///
    /// ⚠️ 「坐在上面」不是站在同一格就完事——**得抬到台面那么高**，
    /// 不然他是站在凳子里，不是坐在凳子上。
    /// 抬多高按这件东西的高度算（`IsoShape.tall` 是以格为单位的）。
    static func spot(of item: Furniture, kindID: String,
                     in geo: IsoRoom, act: RoomAct) -> CGPoint {
        let s = FurnitureCatalog.shape(of: kindID)
        let cx = Double(item.gx) + Double(s.w - 1) / 2
        let cy = Double(item.gy) + Double(s.d - 1) / 2

        switch act.spot {
        case .onTop:
            var p = geo.point(cx, cy)
            p.y -= geo.tileH * CGFloat(s.tall)
            return p
        case .beside:
            // 站在它**靠镜头那一侧**的旁边一格——
            // 站在背面的话他被家具挡住，动作做了她也看不见
            let p = geo.point(cx + Double(s.w) * 0.5 + 0.6,
                              cy + Double(s.d) * 0.5 + 0.6)
            return p
        }
    }
}
