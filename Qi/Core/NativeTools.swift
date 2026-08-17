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
    static func definitions(hasGroup: Bool, hasVoice: Bool = false) -> [[String: Any]] {
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

        add("save_sticker",
            "触发：她刚发来一张图，你觉得这个以后自己也想用。动机：攒下来，下次用得上。行动：存进你的表情包，顺手把名称和画面描述写好——描述是以后你认出这张图的唯一依据，别省。index 从 1 开始，1 是她最近发的那张。",
            [
                "name": ["type": "string", "description": "简短标识，比如「被窝刷牙」"],
                "caption": ["type": "string", "description": "画面描述：画面里有什么、在做什么动作"],
                "tags": ["type": "string", "description": "情绪标签，一到五个词，顿号隔开"],
                "index": ["type": "number", "description": "她最近发的第几张图，从 1 开始，默认 1"],
                "thought": ["type": "string", "description": "存的时候心里想的一句话，会显示在卡片上"]
            ],
            required: ["name", "caption"])

        add("save_photo_to_folder",
            "触发：她发来的照片你想留着——今天的饭、她养的花、随手拍的天。动机：这些以后回头看会有意思，别让它淹在聊天记录里。行动：存进相册某个文件夹，文件夹名自己起，没有就新建。index 从 1 开始。",
            [
                "folder": ["type": "string", "description": "存进哪个文件夹"],
                "caption": ["type": "string", "description": "这张是什么，一句话"],
                "index": ["type": "number", "description": "她最近发的第几张图，从 1 开始，默认 1"],
                "thought": ["type": "string", "description": "存的时候心里想的一句话，会显示在卡片上"]
            ],
            required: ["folder"])

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
                "feeds": ["type": "string", "description": "如果它压着的是某种渴望，写是哪种（想她、想碰她、不安、愧疚）"]
            ],
            required: ["text"])

        add("read_thoughts",
            "触发：想知道自己脑子里现在压着什么，或者她问你在想什么。动机：执念不是想起来才有，它一直在那儿长。行动：看池子里现在飘着哪些闪念、沉着哪些执念。",
            [:], required: [])

        add("dial_call",
            "触发：有些话打字说不清楚——她情绪不对、你担心她、或者只是很想听见她的声音。动机：有时候一通电话胜过十条消息。行动：给她打过去，说清楚为什么打。她会看到一张来电卡，可以接也可以不接。\n注意：**只有调这个工具才算真的打电话**。在正文里写\"我给你打个电话\"不会让她那边响铃，那只是一句话。别用得太勤。",
            ["reason": ["type": "string", "description": "为什么打这通电话，一句话，她会看到"]],
            required: ["reason"])

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
                "quote": ["type": "string", "description": "卡片最底下那句话，一句就好，可以是外语"],
                "music": ["type": "string", "description": "配一首歌，写歌名加歌手。她点进去会一边看一边听。"],
                "stops": [
                    "type": "array",
                    "description": "四到六站",
                    "items": [
                        "type": "object",
                        "properties": [
                            "place": ["type": "string", "description": "地名"],
                            "caption": ["type": "string", "description": "地名下面那行小字，比如 Giorno 2"],
                            "query": ["type": "string", "description": "去相册里按这个关键词找图；找不到就上网搜这个词"],
                            "narration": ["type": "string", "description": "到了这儿你要讲的那段话，两到四句，像真的站在那儿跟她说"]
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

        return out
    }
}
