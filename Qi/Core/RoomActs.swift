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
    /// 身子怎么用这件家具：坐、躺、泡、骑、伸手够……（见 `RoomUse`）
    var use: RoomUse = .stand

    enum Spot {
        /// 站在旁边（浇水、看电视）
        case beside
        /// 待在它**上面**（坐、躺、踩）
        case onTop
    }
}

/// 他**怎么用**这件家具——不是换个表情，是身子真的在做。
///
/// 她说的：「很多家具实际上根本没有 clawd 使用的动画。」
/// 以前「坐下」是站在沙发上面、「泡进去」是整只站在浴缸上、
/// 「开冰箱」是在旁边发呆。这里每一档对应一种身体姿势，
/// 画法在 `ClawdHomeView.usingBody`，家具那边跟着动的在 `IsoRoomView`。
enum RoomUse: Equatable, Sendable {
    /// 站着（旁边做个动作）
    case stand
    /// 坐在上面：腿弯下去、落在坐面上
    case sit
    /// 躺着（床、地毯）
    case lie
    /// 泡在里面：只露出上半身，轻轻浮着
    case soak
    /// 骑着摇：他和那件家具一起前后摇
    case ride
    /// 坐在上面跟着震（洗衣机）
    case jiggle
    /// 伸手去开、去按、去够前面那件
    case reach
    /// 踮脚往高处够：两手举起、一颠一颠
    case tiptoe
    /// 照镜子：左右转身看自己
    case mirror
    /// 拿起来抱着（轻的小东西），放回原处
    case hug
}

enum RoomActs {

    /// 这个动作身子怎么用家具
    static func use(for name: String) -> RoomUse {
        switch name {
        case "坐下", "坐边上", "瘫着", "趴扶手", "坐着换鞋": return .sit
        case "坐上面":                                   return .jiggle
        case "躺下", "钻被窝", "躺一会儿", "打滚":         return .lie
        case "泡进去", "拍水花", "洗澡":                  return .soak
        case "骑上去", "摇一摇":                          return .ride
        case "开冰箱", "拉开柜门", "掀盖子", "挑一瓶", "按两下", "开灯",
             "冲一下", "洗把脸", "把东西放上去", "拍一下", "喂鱼", "转一下",
             "抽一张", "做饭", "洗碗", "摆正":              return .reach
        case "踮脚够", "抽一本":                           return .tiptoe
        case "照镜子", "照一照":                           return .mirror
        case "抱一下", "拿起来":                           return .hug
        default:                                          return .stand
        }
    }

    /// 坐面 / 床面 / 缸里水面离地多高（世界里几格高，跟 `scripts/px_furniture.py` 的模型对得上）。
    /// 没登记的按 `tall` 的八成。
    static func seatHeight(_ id: String) -> Double? {
        if id.hasSuffix("_bed") || id == "bed" || id == "bed_berry" || id == "bed_xmas" { return 0.9 }
        if id.hasSuffix("_sofa") || id == "sofa" || id == "vic_loveseat" || id == "star_seat" { return 0.78 }
        if id.hasSuffix("_rug") || id == "rug" { return 0.03 }
        switch id {
        case "armchair", "gothic_chair", "lolita_chair", "xmas_chair", "ny_chair", "vic_chair",
             "xred_armchair", "rose_armchair", "star_armchair": return 0.58
        case "vic_ottoman", "xred_ottoman", "rose_ottoman", "star_ottoman": return 0.5
        case "stool":    return 0.9
        case "bench":    return 0.64
        case "toilet":   return 0.76
        case "washer":   return 1.5
        case "horse":    return 0.92
        case "bathtub":  return 0.35
        case "pillow":   return 0.3
        default:         return nil
        }
    }

    /// 动作名 → 怎么演。**一张全局的表**——
    /// 「坐下」不管是坐凳子还是坐床沿，演法都一样。
    ///
    /// 表里没有的名字会退回一个通用的「凑过去看看」，
    /// **不会因为写了个新名字就崩**。
    static func act(_ name: String) -> RoomAct {
        var a = baseAct(name)
        a.use = use(for: name)
        return a
    }

    private static func baseAct(_ name: String) -> RoomAct {
        switch name {

        // ⚠️「躺一会儿」是地毯那件用的名字，以前**不在这张表里**——
        // 于是在地毯上「躺一会儿」他只会站着说一句「……」。
        // 是 `scripts/artcheck.py` 对出来的，不是看出来的。
        case "躺下", "钻被窝", "躺一会儿":
            // ⚠️ 演的是 `.lying` 不是 `.sleeping`。
            // `.sleeping` 那个 gif **自带一张床和一床被子**——
            // 躺在她自己摆的床上就成了两张床叠在一起。
            // ⚠️ 9 → 30 秒。她报的：「clawd 睡觉会一会有动画一会回到待机。」
            //
            // 不是动画坏了——是**这一档只有九秒**。躺下、九秒、站起来、
            // 走开、过一会儿再躺下，看着就是一直在抖。
            // 睡这件事本来就该占一段时间，别的动作三五秒是对的，这个不是。
            return RoomAct(name: name, spot: .onTop, mood: .lying, seconds: 30,
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
            // 有专门浇花的 gif（`.watering`），以前演的是笼统的「动手做事」
            return RoomAct(name: name, spot: .beside, mood: .watering, seconds: 6,
                           lines: ["喝点水吧", "又长高了一点", "别蔫啊"])
        case "照料":
            return RoomAct(name: name, spot: .beside, mood: .gardening, seconds: 6,
                           lines: ["修一修", "开得真好", "这片叶子黄了"])

        // MARK: 跟物品配对的动作（有专门 gif 的都用上）
        //
        // 她要的：「动作要和物品匹配。」以前书架、钢琴、吉他、唱片机……
        // 全是「凑近看 / 摸一下 / 动手做事」那几个笼统动作，
        // 资源包里明明有看书、弹琴、弹吉他、听歌、打游戏、拍照、洗澡、烤东西的 gif。
        case "看书":
            return RoomAct(name: name, spot: .beside, mood: .reading, seconds: 10,
                           lines: ["看到哪儿了", "这段好看", "……再看一页"])
        case "弹琴":
            return RoomAct(name: name, spot: .beside, mood: .piano, seconds: 9,
                           lines: ["叮叮咚咚", "这首你听过吗", "弹错了一个音"])
        case "弹吉他":
            return RoomAct(name: name, spot: .beside, mood: .guitar, seconds: 9,
                           lines: ["来一段", "调一下弦", "唱给你听"])
        case "听歌":
            return RoomAct(name: name, spot: .beside, mood: .listening, seconds: 9,
                           lines: ["这首好听", "跟着晃一晃", "再放一遍"])
        case "打游戏", "看电视":
            return RoomAct(name: name, spot: .beside, mood: .gaming, seconds: 9,
                           lines: ["就一局", "这关好难", "赢了！"])
        case "拍照":
            return RoomAct(name: name, spot: .beside, mood: .photo, seconds: 5,
                           lines: ["咔嚓", "笑一个", "拍糊了"])
        case "洗澡":
            return RoomAct(name: name, spot: .onTop, mood: .shower, seconds: 10,
                           lines: ["哗啦啦", "洗香香", "水温正好"])
        case "做饭":
            return RoomAct(name: name, spot: .beside, mood: .baking, seconds: 9,
                           lines: ["做点好吃的", "香出来了", "别碰，烫"])
        case "洗碗":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 6,
                           lines: ["洗干净", "泡泡好多", "摞好了"])
        case "写写画画":
            return RoomAct(name: name, spot: .beside, mood: .painting, seconds: 9,
                           lines: ["画点什么呢", "你看像不像", "再添一笔"])
        case "烤火":
            return RoomAct(name: name, spot: .beside, mood: .drowsy, seconds: 8,
                           lines: ["暖和", "噼啪噼啪", "不想挪窝"])
        case "喂鱼", "看鱼":
            return RoomAct(name: name, spot: .beside, mood: .peeking, seconds: 6,
                           lines: ["吃饭啦", "游过来了", "它在看我"])
        case "转一下":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 4,
                           lines: ["转转转", "停在哪儿就去哪儿", "这是哪儿"])
        case "抽一张":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 3,
                           lines: ["抽一张", "擦擦", "又抽出来两张"])
        case "闻一闻":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 3,
                           lines: ["香的", "唔——"])
        case "打开看", "凑近看", "按两下":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 6,
                           lines: ["看会儿", "咦", "这个好玩"])
        case "开灯", "凑到灯下":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 4,
                           lines: ["亮了", "暖和"])
        case "抽一本":
            // 抽出来就翻开看：接看书的 gif
            return RoomAct(name: name, spot: .beside, mood: .reading, seconds: 8,
                           lines: ["找找看", "拿到了", "这本还没看完"])
        case "踮脚够":
            return RoomAct(name: name, spot: .beside, mood: .working, seconds: 5,
                           lines: ["够不着……", "再高一点", "拿到了"])
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

        // v9 那四件的动作
        case "靠上去":
            return RoomAct(name: name, spot: .onTop, mood: .drowsy, seconds: 7,
                           lines: ["软的", "靠一会儿", "不想起来了"])
        case "撑开":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 4,
                           lines: ["唰——", "这下淋不到了"])
        case "撞一下":
            return RoomAct(name: name, spot: .beside, mood: .flail, seconds: 3,
                           lines: ["咚", "晃了两下"])

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

        // MARK: 这一批是新家具带进来的
        //
        // 衣柜、落地镜、鞋架、摇摇马自己报占地那次（见 `FurnitureCatalog`
        // 那张尺寸表）顺手写了动作名，而**这张表里没有**——
        // 没补的话他跑过去站着说一句「……」，看着像坏了。
        case "拉开柜门":
            return RoomAct(name: name, spot: .beside, mood: .peeking, seconds: 4,
                           lines: ["看看有什么", "关上关上"])
        case "照一照":
            return RoomAct(name: name, spot: .beside, mood: .happy, seconds: 4,
                           lines: ["还是这么好看", "转一圈"])
        case "坐着换鞋":
            return RoomAct(name: name, spot: .beside, mood: .idle, seconds: 4,
                           lines: ["穿好了", "这只在哪儿"])
        case "骑上去":
            return RoomAct(name: name, spot: .onTop, mood: .happy, seconds: 5,
                           lines: ["驾", "跑起来了"])
        case "摇一摇":
            return RoomAct(name: name, spot: .onTop, mood: .flail, seconds: 4,
                           lines: ["晃啊晃", "再快一点"])

        default:
            return RoomAct(name: name, spot: .beside, mood: .idle, seconds: 3,
                           lines: ["……", "看看"])
        }
    }

    /// 这件家具能做的那几个动作
    static func acts(for kindID: String) -> [RoomAct] {
        (actionOverride(kindID) ?? FurnitureCatalog.shape(of: kindID).actions).map { act($0) }
    }

    /// 按**这一件具体是什么**改动作。
    ///
    /// 形状表（`IsoShape.actions`）是按「一类」给的：衣柜借的是书架那一类，
    /// 于是衣柜的动作是「抽一本」；灶台、厨房水槽也借了书架；三角钢琴借的是桌子，
    /// 动作是「趴桌上」。她说「动作要和物品匹配」，这里按 id 一件件纠正。
    static func actionOverride(_ id: String) -> [String]? {
        switch id {
        case "stove":                           return ["做饭", "闻一闻"]
        case "kitchensink":                     return ["洗碗", "洗把脸"]
        case "microwave":                       return ["做饭", "盯着转", "把东西放上去"]
        case "wardrobe", "lolita_wardrobe", "vic_wardrobe", "xred_wardrobe", "rose_wardrobe":
            return ["拉开柜门", "照一照", "踮脚够"]
        case "vic_sideboard", "xred_sideboard", "rose_sideboard", "star_sideboard", "ny_cabinet":
            return ["拉开柜门", "把东西放上去"]
        case "nightstand", "vic_night":         return ["开灯", "把东西放上去"]
        case "shelf", "gothic_shelf", "xmas_shelf", "vic_shelf", "xred_shelf", "rose_shelf",
             "star_shelf", "nordic_shelf":
            return ["看书", "抽一本", "踮脚够"]
        case "star_books":                      return ["看书", "摆正"]
        case "vic_piano":                       return ["弹琴", "在桌边站着"]
        case "guitar_item":                     return ["弹吉他", "摸一下"]
        case "record", "speaker", "star_gramophone":
            return ["听歌", "凑近看"]
        case "console":                         return ["打游戏", "凑近看"]
        case "tv":                              return ["看电视", "按两下"]
        case "polaroid":                        return ["拍照", "摸一下"]
        case "bathtub":                         return ["洗澡", "泡进去", "拍水花"]
        case "desk", "vic_desk":                return ["写写画画", "趴桌上", "在桌边站着"]
        case "vanity", "lolita_vanity", "vic_vanity", "xred_vanity", "rose_vanity", "star_vanity":
            return ["照镜子", "趴桌上"]
        case "gothic_fire", "xmas_fire", "star_fireplace":
            return ["烤火", "凑近看"]
        case "tank":                            return ["看鱼", "喂鱼"]
        case "globe":                           return ["转一下", "凑近看"]
        case "tissue":                          return ["抽一张"]
        case "candle", "humid":                 return ["凑近看", "闻一闻"]
        case "sunflower", "sakura", "flowervase", "vic_vase", "jp_vase", "ny_plum",
             "rose_flower", "star_flower", "xred_flower", "sakura_bonsai", "bonsai":
            return ["浇水", "照料", "闻一闻"]
        default:
            return nil
        }
    }

    /// 吃喝有专门 gif 的那几样：他坐在桌边**直接吃/喝这一样**，不拿在手上抿
    ///（gif 里自带碗和杯子，再拿一份在手上就是两份）
    static func eatingGif(_ id: String) -> ClawdMood? {
        switch id {
        case "sushi":              return .sushi
        case "ramen":              return .ramen
        case "hotpot":             return .hotpot
        // ⚠️ 咖啡、茶、奶茶**不走 gif**：她要「端着咖啡喝」——
        // 拿起桌上那一杯、端在手上、送到脸边喝（`CarryPose.sip`），喝完放回去。
        // gif 里自带一只别的杯子，桌上那杯还得先藏起来，看着是换了一杯。
        default:                   return nil
        }
    }

    /// 他做这个动作的时候该站/坐在**屏幕上的哪个点**。
    ///
    /// ⚠️ 「坐在上面」不是站在同一格就完事——**得抬到台面那么高**，
    /// 不然他是站在凳子里，不是坐在凳子上。
    /// 抬多高按这件东西的高度算（`IsoShape.tall` 是以格为单位的）。
    static func spot(of item: Furniture, kindID: String,
                     in geo: IsoRoom, act: RoomAct) -> CGPoint {
        let s = FurnitureCatalog.shape(of: item, projection: geo.projection)
        // ⚠️⚠️ **两种视角各存各的格子，不能直接读 `item.gx / gy`。**
        //
        // `gx/gy` 是**立体屋专用**的那一对；平面屋那一对叫 `fx/fy`
        //（见 `Furniture.flatCell`）。读错的话他会走到屋子另一头去
        // 站着做动作——东西在这边，他在那边。
        let cell = geo.projection == .flat
            ? item.flatCell(cols: ClawdStore.flatCols)
            : (gx: item.gx, gy: item.gy)
        let cx = Double(cell.gx) + Double(s.w - 1) / 2
        let cy = Double(cell.gy) + Double(s.d - 1) / 2

        switch act.spot {
        case .onTop:
            // 落在**坐面 / 床面**上，不是家具最高那一截（沙发靠背、床头）
            var p = geo.point(cx, cy)
            let h = seatHeight(kindID) ?? s.tall * 0.8
            p.y -= geo.unitH * 0.72 * CGFloat(h)
            return p
        case .beside:
            return besidePoint(cell: cell, w: s.w, d: s.d, in: geo)
        }
    }

    /// 床面正中那一点（躺下的时候摆到这儿）
    static func bedTop(of item: Furniture, in geo: IsoRoom) -> CGPoint {
        let s = FurnitureCatalog.shape(of: item, projection: geo.projection)
        let cell = geo.projection == .flat
            ? item.flatCell(cols: ClawdStore.flatCols)
            : (gx: item.gx, gy: item.gy)
        var p = geo.point(Double(cell.gx) + Double(s.w - 1) / 2,
                          Double(cell.gy) + Double(s.d - 1) / 2)
        let h = seatHeight(item.kind) ?? s.tall * 0.8
        p.y -= geo.unitH * 0.72 * CGFloat(h)
        return p
    }

    /// 站在一块占地**靠镜头那一侧**的旁边一格——
    /// 站在背面的话他被家具挡住，动作做了她也看不见
    static func besidePoint(cell: (gx: Int, gy: Int), w: Int, d: Int, in geo: IsoRoom) -> CGPoint {
        let cx = Double(cell.gx) + Double(w - 1) / 2
        let cy = Double(cell.gy) + Double(d - 1) / 2
        return geo.point(cx + Double(w) * 0.5 + 0.6, cy + Double(d) * 0.5 + 0.6)
    }
}
