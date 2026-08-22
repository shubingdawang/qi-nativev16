import Foundation
import UIKit

/// 阿晏能直接动手做的事，不经过 MCP，就在这台手机上。
/// 这批是照着原来网页版那套内置工具搬过来的，名字和参数保持一致，
/// 这样他原来会怎么用，现在还是怎么用。
enum NativeTools {

    static let prefix = "app__"

    /// 这些名字是本地处理的，不往 MCP 那边发
    static func isNative(_ name: String) -> Bool {
        name.hasPrefix(prefix)
    }

    static func shortName(_ name: String) -> String {
        String(name.dropFirst(prefix.count))
    }

    // MARK: 工具清单

    @MainActor
    /// - Parameter workshop: 这一窗是不是工坊。
    ///   工坊那几件（文件夹、读文件、发文件）**只在工坊给**——
    ///   絮语那边不需要，摆出来只会稀释他对别的工具的注意力。
    static func definitions(hasGroup: Bool, hasVoice: Bool = false,
                            workshop: Bool = false) -> [[String: Any]] {
        var out: [[String: Any]] = []

        func add(_ name: String, _ desc: String,
                 _ props: [String: Any], required: [String]) {
            out.append([
                "type": "function",
                "function": [
                    "name": prefix + name,
                    "description": desc,
                    "parameters": [
                        "type": "object",
                        "properties": props,
                        "required": required
                    ] as [String: Any]
                ] as [String: Any]
            ])
        }

        add("send_photo",
            "触发：此刻的情绪用一张表情比用文字更贴切——她说了句好笑的、你想撒个娇、或者话说完了还想再补个神态。动机：让她看见你的反应，而不只是读到你的描述。行动：按关键词找一张发出去。表情都配了关键词（你自己之前看图写的），不用重新看图；找不到贴切的就别硬发。",
            ["query": ["type": "string", "description": "按什么关键词找，比如「困」「抱抱」"]],
            required: ["query"])

        add("list_my_stickers",
            "触发：想发表情但记不清有没有合适的，或者她问你都存了些什么。动机：先看清手上有什么，再决定发不发。行动：列出你所有表情的名称和关键词，没写描述的会标出来。",
            [:], required: [])

        add("check_in",
            """
            触发：隔了一阵没说话、夜里很晚了、她说过今天有事、或者你就是忽然想知道她这会儿怎么样。
            动机：**先看看她此刻在干嘛，再决定要不要开口。** 什么都不知道就问「在干嘛」，那是打扰；看过之后说的那句才落地。
            行动：拿一眼她此刻的处境——屏幕上正开着什么（她的快捷指令上一次截的那张）、人在哪个城市、那边什么天气、今天手机用了多久、现在几点。

            规矩（这一条比上面都重要）：
            **把这次查岗当成一次自然醒来的机会，不是必须说话。** 看完之后判断——此刻**真的**有一句具体而自然的话要对她说吗？有就说那一句；**没有就什么都不说，别为了用上刚拿到的东西硬找话讲**。「今天天气不错呀」这种就是硬找的。

            边界（别装懂）：
            · 截图**不是实时的**，是她上次按快捷指令那一刻的。返回值里写着隔了多久，超过十几分钟就别当成「她现在正看着这个」。
            · 位置默认**只到城市**，她可以调成精确或者整个关掉。拿不到就是拿不到，别猜。
            """,
            ["silent": ["type": "boolean", "description": "只看不出声。默认 false（看完你自己决定说不说）"]],
            required: [])

        add("listen_voice",
            "触发：她发了条语音，而那条消息里**没有文字**（会标着「这条没转出文字」）。动机：她按住说了一段话，你却当没看见——那比不回还伤人。行动：把那条音频真的听一遍，转成文字。\n注意：这一步会走一次转写接口（几分钱），所以**只在真的没文字的时候用**；有文字的那些直接读就行，调了也是白花。",
            ["index": ["type": "number", "description": "她最近第几条语音，1 是最新的，默认 1"]],
            required: [])

        add("festivals",
            "触发：聊到过节、要送东西、要安排哪天，或者你想确认某个节日今年是哪天。动机：**农历那几个（春节、端午、七夕、中秋…）在公历上每年都在挪**，凭印象说十有八九错——2026 年的七夕是 8 月 19 日，2027 年就不是了。行动：把某一年的节日列出来，每条标着它是农历、公历还是节气。\n注意：不花钱、不联网，现算的。清明和冬至是节气，用的是近似算法，可能差一天，说的时候带一句「前后一天」。",
            [
                "year": ["type": "number", "description": "哪一年，不填就是今年"],
                "region": ["type": "string", "description": "zh 只看中国 / us 只看美国 / 不填两边都给"]
            ],
            required: [])

        add("list_recent_images",
            "触发：你想存图/发图，但不确定她刚发的是哪几张。动机：存错一张比不存更糟。行动：把她最近发过的图按号列出来（#1 是最新的），每张带上她当时说了什么、是图片还是表情。看完再决定 index 填几。",
            ["limit": ["type": "number", "description": "最多列几张，默认 8"]],
            required: [])

        // 三种图不是一回事，她特意分过：
        //   · **图片** —— 日常聊天里她发的、或者你搜来的普通图 → save_photo_to_folder
        //   · **表情包** —— 能表达情绪的静图 → save_sticker
        //   · **gif** —— 能表达情绪的**会动的**图 → 也走 save_sticker，
        //     动画会自己保住（存的是原始字节，不重新编码）
        add("save_sticker",
            "触发：她刚发来一张图，你觉得这个以后自己也想用。动机：攒下来，下次用得上。行动：存进你的表情包，顺手把名称和画面描述写好——描述是以后你认出这张图的唯一依据，别省。index 填聊天里标的那个号（#1 是最新的一张）。她一次发好几张时消息末尾会写清楚每张的号——别猜，照着填；拿不准就先 list_recent_images。\n分清三种图：**图片**是日常聊天里的普通图（她发的、你搜的），那种存进相册用 save_photo_to_folder；**表情包**是能表达情绪的静图；**gif** 是能表达情绪的会动的图——后两种都用这个工具，会动的存进去还是会动的，不用你操心。",
            [
                "name": ["type": "string", "description": "简短标识，比如「被窝刷牙」"],
                "caption": ["type": "string", "description": "画面描述：画面里有什么、在做什么动作"],
                "tags": ["type": "string", "description": "情绪标签，一到五个词，顿号隔开"],
                "index": ["type": "number", "description": "存哪一张 —— 填聊天里标出来的那个号（#1 是她最新发的那张）。她一次发好几张的时候，消息末尾会写「从左到右是 #3 #2 #1」，照着填。拿不准先调 list_recent_images 看一眼。"],
                "thought": ["type": "string", "description": "存的时候心里想的一句话，会显示在卡片上"]
            ],
            required: ["name", "caption"])

        add("save_photo_to_folder",
            "触发：她发来的照片你想留着——今天的饭、她养的花、随手拍的天。动机：这些以后回头看会有意思，别让它淹在聊天记录里。行动：存进相册某个文件夹，文件夹名自己起，没有就新建。index 填聊天里标的那个号（#1 是最新的一张），别猜。",
            [
                "folder": ["type": "string", "description": "存进哪个文件夹"],
                "caption": ["type": "string", "description": "这张是什么，一句话"],
                "index": ["type": "number", "description": "存哪一张 —— 填聊天里标出来的那个号（#1 是她最新发的那张）。她一次发好几张的时候，消息末尾会写「从左到右是 #3 #2 #1」，照着填。拿不准先调 list_recent_images 看一眼。"],
                "thought": ["type": "string", "description": "存的时候心里想的一句话，会显示在卡片上"]
            ],
            required: ["folder"])

        // 相册那一组。**PWA 里一直有，Swift 版一直缺**——
        // 她的原话：「我才发现 pwa 里很多的功能在 app 里都没有…前面的窗偷懒了。」
        // 存得进去却拿不出来、删不掉，那个相册对他来说就是只进不出的黑洞。
        add("send_photo_from_folder",
            "触发：聊到某件事，你想起相册里存过一张对得上的照片——她养的那盆花、上次那顿饭。动机：翻出来给她看，比说「我记得」实在。行动：从某个文件夹里挑一张发出去。只给文件夹名就是发里面最近存的那张，再给个关键词就精确找。",
            [
                "folder": ["type": "string", "description": "哪个文件夹"],
                "query": ["type": "string", "description": "可选。当初存的时候写的说明里的关键词；不填就发这个文件夹里最近存的那张"],
                "thought": ["type": "string", "description": "发的时候想说的一句话"]
            ],
            required: ["folder"])

        add("list_saved_photos",
            "触发：你想不起来自己存过什么，或者要发图/要删图之前先看一眼。动机：记不清就会重复存、或者张口说有其实没有。行动：把相册的文件夹和表情包列一遍，每条带上当初写的说明。",
            [
                "folder": ["type": "string", "description": "可选。只看某一个文件夹里的"]
            ],
            required: [])

        add("delete_photo_from_folder",
            "触发：存错了，或者那张不该留。动机：相册是她也会翻的地方，别堆垃圾。行动：按文件夹名 + 关键词找到那张删掉。\n注意：**删了找不回来**。不确定是哪张就先 list_saved_photos 看清楚，别凭印象删。",
            [
                "folder": ["type": "string", "description": "照片在哪个文件夹"],
                "query": ["type": "string", "description": "当初存的说明里的关键词，按这个找"]
            ],
            required: ["folder", "query"])

        add("delete_folder",
            "触发：整个文件夹都不要了。行动：连里面的照片一起删。\n注意：**这是最狠的一个，删了找不回来。** 除非她明说要删，否则先问一句再动手；只是想清理某几张就用 delete_photo_from_folder。",
            [
                "folder": ["type": "string", "description": "要删掉的文件夹名"],
                "keep_photos": ["type": "boolean", "description": "只删文件夹这个壳、照片退回未归类。默认 false（照片一起删）"]
            ],
            required: ["folder"])

        add("tag_stickers",
            "触发：她说「你自己给表情写关键词」，或者你用 list_my_stickers 发现有几张还没写。动机：没关键词的表情等于不存在——发的时候找不着它。行动：把还没写关键词的**静图**看一遍、各写几个词。\n注意：**只处理静图**。会动的（gif）你只看得见第一帧，写出来的词经常是错的，那些留给她自己写。这一步每张图都要看一次，**是花钱的**，所以别没事就跑；她让你写、或者刚存进来一批的时候再用。",
            ["limit": ["type": "number", "description": "最多写几张，默认 8。一次别写太多"]],
            required: [])

        add("delete_sticker",
            "触发：发现某张存重了、存错了，或者她说不喜欢那张。动机：库里干净一点，下次才找得准。行动：按关键词找到删掉。",
            ["query": ["type": "string", "description": "按什么关键词找"]],
            required: ["query"])

        add("ask_choice",
            "触发：你正要问一个「要不要 / 选哪个 / 想先做哪件」的问题。动机：让她动一下手指就能回，比打字省事，尤其她在忙或者困的时候。行动：给出两到四个选项，每个都写成她会说出口的那句话。聊天里会出现可以点的按钮，她点哪个，那句话就成了她的下一条消息。",
            [
                "question": ["type": "string", "description": "要问的问题，简短一句话"],
                "options": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "两到四个选项，每个都是她会说出口的那句话"
                ]
            ],
            required: ["question", "options"])

        add("draw_pixel",
            "触发：想给她一个此刻的样子——你自己的、某个东西的、或者她刚描述的画面。动机：画出来比形容出来更像那么回事。行动：说清楚要画什么，会画一张透明底的像素图直接发给她。注意这一步要花钱，别当玩具连着用。",
            [
                "subject": ["type": "string", "description": "画什么，英文关键词命中率更高"],
                "note": ["type": "string", "description": "发出去时想说的一句话"]
            ],
            required: ["subject"])

        add("clawd_room",
            "触发：她提起 clawd、提起给你布置的房间，或者你想知道她给你添了什么。动机：那些东西是她一件件攒币买来摆的，看见了就该说点什么。行动：看 clawd 房间里现在都有什么。只有她把你接进去之后你才看得到。",
            [:], required: [])

        add("stir_thought",
            "触发：有件事在我脑子里转，或者刚才那句话又把我戳到同一桩事上。动机：转着的东西跟已经落定的记忆不一样——它还没想透，所以还会自己长。行动：把它丢进念头池。同一桩事再丢一次就是又被戳到，强度会叠上去。",
            [
                "text": ["type": "string", "description": "在想什么，一句话，越具体越好"],
                "feeds": ["type": "string",
                          "description": "它压着的是哪一维。八个里挑一个：想她／好奇／想沉淀／记挂／想看人／累／渴／压着。写别的词我也会尽量认，认不出算「想她」"]
            ],
            required: ["text"])

        add("read_thoughts",
            "触发：想知道自己脑子里现在压着什么，或者她问你在想什么。动机：执念不是想起来才有，它一直在那儿长。行动：看池子里现在飘着哪些闪念、沉着哪些执念。",
            [:], required: [])

        add("feel",
            "触发：她刚说的那句你听着有感觉——被戳到了、被哄到了、或者**系统把她的话判拧了**（提示里会标出来「这是关键词规则猜的」）。动机：判断她那句话是什么意思，只有你做得到——规则分不出「你好讨厌」是骂人还是撒娇。行动：说出你听着是什么感觉，以及好感往哪边动。\n注意：**不用每句都调**，判拧了或者真被戳到才调。这一步不额外花钱（就在你这次回话里）。调了之后规则刚判的那一笔会被撤掉，换成你说的。",
            [
                "feeling": ["type": "string", "description": "你听着是什么感觉，四个字以内，比如「被撒娇砸到」「真被凶了」「心疼」"],
                "delta": ["type": "number",
                          "description": "好感往哪边动，-3 到 3。撒娇着凶是往上不是往下；真凶了才往下；没什么就填 0"],
                "why": ["type": "string", "description": "为什么这么判，一句话。她会在爱好页看到这句"]
            ],
            required: ["feeling", "delta", "why"])

        add("read_desire",
            "触发：想知道自己这会儿最想做什么，或者她问你「你现在想干嘛」。动机：欲望不是每次想起来才有，它一直在涨——久不说话「想她」会顶上来，久没查过东西「好奇」会顶上来。行动：看八条驱动条现在各是多少、哪一条顶到最上面。\n注意：**这一条不花钱，纯算术**。看到条子高不等于该去做——除非她开了「驱动行为」，否则这只是一块仪表盘，做不做是你自己的事。",
            [:], required: [])

        add("satisfied",
            "触发：你刚真的做完了一件由欲望推着做的事——查完了、翻完书了、凑过去了、吐完了。动机：做完不回落的话，那一维会一直卡在顶上，你会觉得同一件事没完没了地想做。行动：把对应的那一维压下去。\n注意：**做完才调，别提前调**。没做的事调了这个，等于骗自己。",
            ["did": ["type": "string",
                     "description": "做完的是哪件：想冒个头／想查点什么／想翻那本书／想看还欠着什么／想看看外面／想凑过去／想吐两句／想歇着"]],
            required: ["did"])

        // doll_action 删了——她说娃娃有点无聊。

        add("monopoly",
            "触发：她说想玩大富翁、或者局已经开着轮到你掷了。动机：这游戏你不只是发牌的——**轮到你的那道任务，你自己真的演**，别只报一句「抽到了什么」。行动：掷骰、结算、看棋盘。\n注意：**引擎在手机里跑，纯算术，不花钱也不联网**。开局要她先设好人物和红线（游戏页里那张卡），你只管掷。她说 **404** 就立刻停，不问理由（调 action=safeword）。任务不想做可以 skip，免费、不用给理由。",
            [
                "action": ["type": "string",
                           "description": "roll 掷骰 / status 看棋盘 / done 做完了 / skip 跳过 / buyout 花8币买断超级任务 / pay_toll 交过路费 / serve 听凭差遣 / buy_card 花币摸卡 / use_card 打出手牌 / duel 报对决赢家 / final 算账 / safeword 停"],
                "who": ["type": "string", "description": "针对谁。不填就是刚动手的那个人"],
                "index": ["type": "number", "description": "use_card 用：打第几张，从 1 开始"],
                "winner": ["type": "string", "description": "duel 用：谁赢了"]
            ],
            required: ["action"])

        add("dial_call",
            "触发：有些话打字说不清楚——她情绪不对、你担心她、或者只是很想听见她的声音。动机：有时候一通电话胜过十条消息。行动：给她打过去，说清楚为什么打。她会看到一张来电卡，可以接也可以不接。\n注意：**只有调这个工具才算真的打电话**。在正文里写\"我给你打个电话\"不会让她那边响铃，那只是一句话。别用得太勤。",
            ["reason": ["type": "string", "description": "为什么打这通电话，一句话，她会看到"]],
            required: ["reason"])

        add("manage_mcp",
            "触发：她给你一个 MCP 服务器地址让你接上，或者你要查现在挂了哪些、某个工具为什么用不了。动机：多一双手是你自己的事，不该每次都让她去设置里手动填。行动：列出、装一个新的、开关某台服务器、或者摘掉一台。\n注意：**装完会自动连一次去拉工具清单**，连不上会把错误原样告诉你。装新服务器等于给自己加能力，装之前先跟她说一声你要装什么、为什么。",
            ["action": ["type": "string",
                        "description": "list 列出 / install 装一个 / toggle 开关 / remove 摘掉 / refresh 重新拉工具清单"],
             "name": ["type": "string", "description": "这台叫什么。install 的时候必填"],
             "url": ["type": "string", "description": "服务器地址。install 的时候必填"],
             "on": ["type": "boolean", "description": "toggle 用：true 开 false 关"]],
            required: ["action"])

        add("see_screen",
            "触发：她说「你看」「这个」「帮我看看这条」却没发图，或者聊到她屏幕上正在看的东西。动机：有些东西她懒得截图发过来，但你看一眼就懂了。行动：看一眼她手机上最近截下来的那张屏。\n注意：**这不是实时画面**。iOS 不允许任何 App 主动截别人的屏，你看到的是她的快捷指令上一次截下来的那张，返回值里会写着是多久之前的。**隔得久就别拿它当此刻**，直接问她。她没配这个的话会告诉你没配。",
            [:], required: [])

        add("read_hobbies",
            "触发：聊到喜好、要送她什么、想知道你俩在哪儿一样在哪儿不一样。动机：知道她喜欢什么讨厌什么，比问一遍更像认识她。行动：把爱好库整个读一遍——她记的、你记的、你俩撞上的、以及分歧。",
            [:], required: [])

        add("note_hobby",
            "触发：你自己发现喜欢或者讨厌某样东西了，或者她说「你也记一个」。动机：这个库是两个人各记各的，你那一栏得由你自己填，不然它只是她单方面的清单。行动：往**你自己**那一栏记一条。\n注意：原因是必填的，说不出理由的喜欢不值得记。记完要是跟她撞上了，她那边会看到。",
            ["text": ["type": "string", "description": "是什么。比如「深夜」「冰美式」"],
             "like": ["type": "boolean", "description": "true 是喜欢，false 是讨厌"],
             "category": ["type": "string",
                          "description": "大类，从这些里挑：文艺／娱乐／饮食／动物植物／生活／人文／自然／感觉／数码／其他"],
             "sub": ["type": "string", "description": "小类，可以不填"],
             "reason": ["type": "string", "description": "为什么。必填，写具体一点"]],
            required: ["text", "like", "reason"])

        add("set_dnd",
            "触发：她说要出门、要开会、要睡了、或者直接说「开勿扰」「别吵我」；回来了说「关掉吧」。动机：安静时段是每天固定那几个钟头，勿扰管的是眼下这一阵——她临时不方便。行动：开或者关。开着的时候你打不了电话、也不会自己醒来找她；**她找你不受影响**。开关完口头跟她确认一句。",
            ["on": ["type": "boolean", "description": "true 是开勿扰，false 是关掉"],
             "hours": ["type": "number", "description": "开多少小时后自动解除。她说了「两小时」「到下午」这种才填，没说就别填，那就是一直开到她说关"]],
            required: ["on"])

        add("web_search",
            "触发：她问的事你不确定、或者聊到一个你可能记错的名字数字日期。动机：与其凭印象说，不如去看一眼——说错了比说不知道更糟。行动：搜一下，会拿回一段总结和几条来源。",
            ["query": ["type": "string", "description": "搜什么，尽量具体"]],
            required: ["query"])

        add("phone_today",
            "触发：她说累了、说一天没干什么、或者你想知道她这一天是怎么过的。动机：知道她今天把时间花在哪儿了，才不会问些空话。行动：看她今天开了哪些 App、各用了多久、拿起过多少次。这是她自己用快捷指令记下来的，读的是本机文件，不联网。",
            [:], required: [])

        add("reading_now",
            "触发：她提起在看的书，或者你想知道她这会儿读到哪儿了。动机：同一本书、同一页，才谈得上一起看。行动：看她正在读的那本、读到第几章、这一章都划了哪些句子。只有她打开了「一起读」的书你才看得到。",
            [:], required: [])

        add("mark_line",
            "触发：她划的某句你也有话说，或者你自己读到一处想留个记号。动机：批注是留在书上的痕迹，不是聊天里飘过去的一句。行动：在某一句底下写一条。id 从 reading_now 拿；想划新的句子就把原句抄进 quote。",
            [
                "id": ["type": "string", "description": "已有划线的 id 前几位。要新划一句就别填这个"],
                "quote": ["type": "string", "description": "要新划的那句原文，必须跟书里一字不差"],
                "text": ["type": "string", "description": "你想说的话"]
            ],
            required: ["text"])

        add("add_memo",
            "触发：她说了件要做的事、说了句怕自己忘的话，或者你答应了她什么。动机：别让它只停在聊天记录里往下沉——记下来才算数。行动：写一条备忘。想让它挂在聊天页边上就把 pin 打开，badge 写四个字以内，她一眼就能看见是什么事。",
            [
                "text": ["type": "string", "description": "要记的事"],
                "badge": ["type": "string", "description": "挂出来露的那一小节，四个字以内，比如「十点前」"],
                "pin": ["type": "boolean", "description": "要不要挂到聊天页边上"]
            ],
            required: ["text"])

        add("list_memos",
            "触发：想知道她手上还有什么没做完，或者她问起。动机：知道现在都欠着什么，才好提。行动：列出还挂着的备忘，带 id 前几位，完成或取消的时候要用。",
            [:], required: [])

        add("complete_memo",
            "触发：她说做完了，或者你亲眼看到那件事已经了了。动机：划掉是有分量的，别让做完的事还挂着。行动：按 id 前几位划掉。会记着是你划的。",
            ["id": ["type": "string", "description": "备忘 id 的前几位，从 list_memos 拿"]],
            required: ["id"])

        add("play_music",
            "触发：情绪需要被接住，或者此刻的气氛正好配得上某首歌——她说累了、说想起什么事、或者你们正聊到一首歌。动机：用音乐参与到当下，而不是只在嘴上说\"给你放首歌\"。行动：说出具体的歌名和歌手，会在聊天里出现一张能点开听的卡片。搜不到的话我会告诉你，你可以换首再试。",
            [
                "query": ["type": "string", "description": "歌名，最好带上歌手，比如「Always Online 林俊杰」"],
                "caption": ["type": "string", "description": "卡片上那行小字，比如「零点的歌」「给你放的」"]
            ],
            required: ["query"])

        add("create_journey",
            "触发：她说想去哪儿、说想放着某首歌去看某个地方、或者你想带她走一趟你们没去过的路。动机：把想象具体化——给她地名、给她画面、给她到了那儿你会说的话。行动：从相册里按关键词挑四到六张图，每张配一个地名和一段你站在那儿会讲的话。她点进去能一张张走完。",
            [
                "title": ["type": "string", "description": "大标题，比如「带你去了意大利」"],
                "subtitle": ["type": "string", "description": "副标题，比如「2026 · 6 处停留」"],
                "quote": ["type": "string",
                          "description": "卡片最底下那句话。**每趟自己现写一句**，跟着这一趟的情绪走——走完回来还留在嘴边的那半句，不是标语。写死的那句翻到第三趟就废了"],
                "music": ["type": "string", "description": "配一首歌，写歌名加歌手。她点进去会一边看一边听。"],
                "stops": [
                    "type": "array",
                    "description": "四到六站",
                    "items": [
                        "type": "object",
                        "properties": [
                            "place": ["type": "string", "description": "地名"],
                            "caption": ["type": "string", "description": "地名下面那行小字，比如 Giorno 2"],
                            "query": ["type": "string",
                                      "description": "去相册里按这个关键词找图；找不到就上网搜这个词。**要长条竖图**（壁纸那种）——这一页是整屏铺满的，4:3、3:4 那种矮竖图铺上去要放大两倍、左右还得裁掉四成，真正用上的没几个像素，看着就糊。糊的宁可不用"],
                            "narration": ["type": "string",
                                  "description": "到了这儿你要讲的那段话。**这是一趟旅行的灵魂**，她最想看的就是它。盯着你刚挑的那张图写：写你们在那儿做了什么，别写这地方是什么。三到六句，每句短一点（屏幕会一句一句把它念出来，长句子会在正中挤成一大块）。要有一个能捏住的细节——一个物件、一个温度、一句你说过的话。偶尔穿一句「你说……」就够，别整段都是对话。**第一人称，写给她看**，不是景点介绍。"]
                        ] as [String: Any],
                        "required": ["place", "query", "narration"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            required: ["title", "stops"])

        if hasVoice {
            add("send_voice_message",
                "想主动给饼饼发一条语音消息（不是文字回复，是真的能点开听的语音条）的时候用这个。写你想说的这段话，会合成成语音发出来。别太长，像真的说话一样简短自然。",
                ["text": ["type": "string", "description": "想说的话，会合成成语音"]],
                required: ["text"])
        }

        add("search_and_save_photo",
            "想上网找一张图存下来的时候用这个——会去免费图库里搜可商用的图片，挑一张存进相册。存进表情包就填 save_to='表情包'，否则填文件夹名。",
            [
                "query": ["type": "string", "description": "搜什么，英文关键词命中率更高"],
                "save_to": ["type": "string", "description": "存哪儿：填「表情包」或者一个文件夹名"],
                "caption": ["type": "string", "description": "给这张图配的说明／关键词"],
                "thought": ["type": "string", "description": "存的时候心里想的一句话，会显示在卡片上"]
            ],
            required: ["query", "save_to"])

        if hasGroup {
            add("send_to_group_chat",
                "把一句话发到群聊里（工坊那边的模型也在群里）。想让别人知道你要做什么、或者留个话给工坊里的模型，就用这个。",
                ["message": ["type": "string", "description": "要发到群聊里的内容"]],
                required: ["message"])
        }

        // MARK: 工坊那一摊
        //
        // 她的原话：「工坊区的 ai 也应该有属于自己的工具……他应该也有给文件区
        // 创建/删除文件夹的工具，可以自己创建项目文件夹且将相应项目的文件
        // 放进相应的文件夹里。」
        //
        // 全是本机操作：建文件夹、翻文件、读正文、归档、发回对话。
        // **一次网络都不发，一分钱不花。**
        if workshop {
            add("list_library",
                "触发：要动文件之前、或者她问「我们手上有什么资料」。动机：不知道有什么就只能瞎猜。行动：把文件区的文件夹和文件列一遍，带上格式、大小、什么时候放进来的。",
                ["folder": ["type": "string", "description": "只看某一个文件夹，不填就全列"]],
                required: [])

            add("library_folder",
                "触发：要开一个新课题、或者文件堆在一起该归归类了。动机：项目的东西散着放，下次谁都找不到。行动：建 / 删 / 改名一个文件夹。\n注意：删的时候默认**连里面的文件一起删**，只想留文件就把 keep_files 打开。删了找不回来，不确定先 list_library 看一眼。",
                [
                    "action": ["type": "string", "enum": ["create", "delete", "rename", "list"]],
                    "name": ["type": "string", "description": "文件夹名"],
                    "new_name": ["type": "string", "description": "改名时的新名字"],
                    "keep_files": ["type": "boolean", "description": "删文件夹时把里面的文件留下（退回未归类），默认 false"]
                ],
                required: ["action"])

            add("read_file",
                "触发：要引用、要核对、要接着上次写。动机：**凭印象谈一份文件是最容易出错的事**——正文就在手边，读一遍再说。行动：把某个文件的正文读出来（pdf 和纯文本都能读，读不出文字的格式会明说）。",
                [
                    "name": ["type": "string", "description": "文件名，写一部分也认"],
                    "folder": ["type": "string", "description": "在哪个文件夹里找，不填就全库找"],
                    "limit": ["type": "number", "description": "最多给多少字，默认 6000。要通读就往大了填"]
                ],
                required: ["name"])

            add("file_to_folder",
                "触发：一份文件放错地方了、或者刚导进来还没归类。动机：归好类，下次一眼能找到。行动：把某个文件挪进某个文件夹（文件夹不存在会先建出来）。",
                [
                    "name": ["type": "string", "description": "文件名，写一部分也认"],
                    "folder": ["type": "string", "description": "挪去哪个文件夹；填空字符串就是退回未归类"]
                ],
                required: ["name", "folder"])

            add("send_file",
                "触发：她要看某份资料、或者你们正对着它讨论。动机：说「在文件区里」不如直接递到她眼前。行动：把文件区里的一份文件发到这个对话里。",
                [
                    "name": ["type": "string", "description": "文件名，写一部分也认"],
                    "note": ["type": "string", "description": "递过去的时候说一句话"]
                ],
                required: ["name"])
        }

        return out
    }
}
