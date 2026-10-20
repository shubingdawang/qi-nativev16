import Foundation

// MARK: - 手帐模板
//
// 排好的整页：纸、线、大日期、小标签、照片格、便签、胶带、墨印都摆好了，
// 文字和照片是空的占位（`hint`），选好以后点一下就去填。填完照样能拖、能换、能删。
//
// 坐标按 343 × 457 点的一页来写（手机上一页差不多这么大），存的时候换成比例。
// 文字给的是「左边从哪开始、多宽、多大」；照片、便签、胶带给的是中心点。

struct JournalTemplate: Identifiable {
    let id: String
    let name: String
    let note: String
    let paper: String
    var pattern = "plain"
    var weave = ""
    let build: (JournalTemplateDate) -> [JournalElement]

    func page(on day: Date) -> JournalPage {
        var p = JournalPage(day: day)
        p.paperHex = paper
        p.paperPattern = pattern
        p.paperWeave = weave
        p.elements = build(JournalTemplateDate(day))
        return p
    }
}

/// 模板里要用到的几种日期写法
struct JournalTemplateDate {
    let dd: String      // 10.20
    let md: String      // 10 / 20
    let dow: String     // TUE
    let year: String    // 2026
    let cn: String      // 十月二十日
    let week: String    // 星期二

    init(_ d: Date) {
        let cal = Calendar(identifier: .gregorian)
        let m = cal.component(.month, from: d), day = cal.component(.day, from: d)
        dd = String(format: "%02d.%02d", m, day)
        md = "\(m) / \(day)"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US_POSIX")
        en.dateFormat = "EEE"
        dow = en.string(from: d).uppercased()
        year = String(cal.component(.year, from: d))
        let zh = DateFormatter()
        zh.locale = Locale(identifier: "zh_CN")
        zh.dateFormat = "M月d日"
        cn = zh.string(from: d)
        zh.dateFormat = "EEEE"
        week = zh.string(from: d)
    }
}

/// 往一页上摆东西（坐标按 343 × 457）
struct JournalTemplateBuilder {
    static let W = 343.0, H = 457.0
    private(set) var els: [JournalElement] = []
    private var z = 0

    private mutating func put(_ e: JournalElement) {
        var e = e
        z += 1
        e.z = z
        els.append(e)
    }

    /// 文字。`left` 是左边，`y` 是这一行的中线，`w` 多宽，`size` 字号
    mutating func text(_ s: String = "", hint: String = "", left: Double, y: Double, w: Double,
                       size: Double, font: String = "", ink: String, align: String = "", angle: Double = 0) {
        var e = JournalElement(kind: .text)
        let k = size / 17
        e.text = s; e.hint = hint
        e.scale = k
        e.width = w / k
        e.x = (left + w / 2) / Self.W
        e.y = y / Self.H
        e.pattern = font
        e.colorHex = ink
        e.align = align
        e.angle = angle
        put(e)
    }

    /// 小标签：等宽、拉开字距
    mutating func label(_ s: String, left: Double, y: Double, w: Double, ink: String,
                        size: Double = 9.5, align: String = "") {
        text(s, left: left, y: y, w: w, size: size, font: "label", ink: ink, align: align)
    }

    mutating func line(left: Double, y: Double, w: Double, _ pattern: String = "rule", ink: String, angle: Double = 0) {
        var e = JournalElement(kind: .line)
        e.pattern = pattern
        e.width = w
        e.colorHex = ink
        e.x = (left + w / 2) / Self.W
        e.y = y / Self.H
        e.angle = angle
        put(e)
    }

    /// 竖着的一条线（中心点 + 长度）
    mutating func vline(cx: Double, cy: Double, len: Double, _ pattern: String = "rule", ink: String) {
        var e = JournalElement(kind: .line)
        e.pattern = pattern
        e.width = len
        e.colorHex = ink
        e.x = cx / Self.W
        e.y = cy / Self.H
        e.angle = 90
        put(e)
    }

    mutating func photo(cx: Double, cy: Double, side: Double, edge: String = "white",
                        hint: String = "放一张照片", angle: Double = 0, tone: String = "") {
        var e = JournalElement(kind: .photo)
        e.hint = hint
        e.pattern = edge
        e.colorHex = "FFFFFF"
        e.tone = tone
        e.scale = side / 120
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }

    /// 拍立得（宽 `w`）
    mutating func polaroid(cx: Double, cy: Double, w: Double, hint: String = "放一张照片",
                           style: String = "", angle: Double = 0) {
        var e = JournalElement(kind: .frame)
        e.hint = hint
        e.pattern = style
        e.colorHex = "FFFFFF"
        e.scale = w / 130
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }

    mutating func note(cx: Double, cy: Double, w: Double, hint: String, color: String,
                       style: String = "", angle: Double = 0) {
        var e = JournalElement(kind: .note)
        e.hint = hint
        e.width = w
        e.colorHex = color
        e.pattern = style
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }

    mutating func tape(cx: Double, cy: Double, len: Double, color: String, pattern: String = "plain",
                       angle: Double = 0, ink: String = "") {
        var e = JournalElement(kind: .tape)
        e.colorHex = color
        e.pattern = pattern
        e.inkHex = ink
        e.scale = len / 110
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }

    mutating func inkStamp(cx: Double, cy: Double, text: String, sub: String = "", color: String,
                           size: Double = 80, angle: Double = -12) {
        var e = JournalElement(kind: .stamp)
        e.pattern = "ink"
        e.text = text
        e.who = sub
        e.colorHex = color
        e.scale = size / 84
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }

    mutating func postStamp(cx: Double, cy: Double, asset: String, color: String, angle: Double = 3) {
        var e = JournalElement(kind: .stamp)
        e.assetName = asset
        e.colorHex = color
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }

    /// 实物贴纸（博物馆那批）
    mutating func sticker(cx: Double, cy: Double, asset: String, size: Double = 64, angle: Double = 0) {
        var e = JournalElement(kind: .sticker)
        e.assetName = asset
        e.scale = size / 72
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }

    /// 画出来的贴纸（太阳、云、心……）
    mutating func shape(cx: Double, cy: Double, _ shape: String, color: String, size: Double = 50, angle: Double = 0) {
        var e = JournalElement(kind: .sticker)
        e.pattern = shape
        e.colorHex = color
        e.scale = size / 50
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }

    mutating func clip(cx: Double, cy: Double, style: String = "paper", color: String = "B9B4AA", angle: Double = 0) {
        var e = JournalElement(kind: .clip)
        e.pattern = style
        e.colorHex = color
        e.x = cx / Self.W; e.y = cy / Self.H
        e.angle = angle
        put(e)
    }
}

enum JournalTemplates {

    // 常用的几个墨色
    private static let ink = "2B241D", soft = "5B4D3E", blue = "2E4A7A", rust = "9A3B30"
    private static let light = "ECE5D8", gold = "D9B867"

    private static func make(_ f: @escaping (inout JournalTemplateBuilder, JournalTemplateDate) -> Void)
        -> (JournalTemplateDate) -> [JournalElement] {
        { d in
            var b = JournalTemplateBuilder()
            f(&b, d)
            return b.els
        }
    }

    static let all: [JournalTemplate] = [
        JournalTemplate(id: "kraft", name: "牛皮纸日记", note: "大日期、标题、正文、一张便签和一张拍立得",
                        paper: "C9A57A", weave: "paper_kraft", build: make { b, d in
            b.label("HOME · " + d.md, left: 26, y: 28, w: 180, ink: ink)
            b.label("DIARY", left: 217, y: 28, w: 100, ink: ink, align: "trailing")
            b.line(left: 26, y: 40, w: 291, ink: ink)
            b.text(d.dd, left: 22, y: 86, w: 214, size: 60, font: "type", ink: "211A14")
            b.text(d.dow + "\n" + d.year, left: 240, y: 84, w: 70, size: 9, font: "label", ink: soft)
            b.text(hint: "写一个标题", left: 26, y: 140, w: 240, size: 21, ink: ink)
            b.line(left: 22, y: 160, w: 220, "hand", ink: blue)
            b.line(left: 26, y: 180, w: 291, "dash", ink: ink)
            b.text(hint: "今天发生了什么……", left: 26, y: 214, w: 291, size: 13.5, ink: ink)
            b.note(cx: 165, cy: 300, w: 200, hint: "记一句想留住的话", color: "F3EBDD", style: "torn", angle: -1.5)
            b.tape(cx: 150, cy: 254, len: 86, color: "E8E2D2", angle: -4)
            b.polaroid(cx: 262, cy: 392, w: 118, angle: 4)
            b.tape(cx: 262, cy: 330, len: 66, color: "C4786E", angle: -12)
            b.inkStamp(cx: 72, cy: 405, text: "好", sub: d.md, color: "8A3B32", size: 78)
        }),
        JournalTemplate(id: "polaroids", name: "拍立得墙", note: "四张拍立得歪歪地贴在墙上",
                        paper: "EFEAE0", weave: "paper_cotton", build: make { b, d in
            b.label("PHOTO WALL", left: 26, y: 30, w: 160, ink: ink)
            b.text(d.dd, left: 200, y: 32, w: 117, size: 26, font: "type", ink: ink, align: "trailing")
            b.line(left: 26, y: 52, w: 291, "double", ink: ink)
            b.polaroid(cx: 95, cy: 150, w: 126, angle: -5)
            b.tape(cx: 95, cy: 75, len: 60, color: "E8B4BC", pattern: "dot", angle: 4, ink: "FFFFFF")
            b.polaroid(cx: 248, cy: 140, w: 126, angle: 4)
            b.clip(cx: 248, cy: 64, style: "wood", color: "C9A57A")
            b.polaroid(cx: 100, cy: 318, w: 126, angle: 3)
            b.tape(cx: 100, cy: 244, len: 60, color: "9DB8D1", pattern: "stripe", angle: -6)
            b.polaroid(cx: 250, cy: 330, w: 126, angle: -4)
            b.tape(cx: 250, cy: 256, len: 60, color: "A8C4A2", angle: 8)
            b.text(hint: "这一天……", left: 26, y: 428, w: 291, size: 13, ink: soft, align: "center")
        }),
        JournalTemplate(id: "letter", name: "信纸", note: "横线信纸，写一封给他的信",
                        paper: "F5F0E6", pattern: "ruled", weave: "paper_cotton", build: make { b, d in
            b.text(hint: "亲爱的：", left: 34, y: 62, w: 200, size: 17, font: "kai", ink: ink)
            b.text(hint: "想对你说……", left: 34, y: 190, w: 275, size: 14.5, font: "kai", ink: ink)
            b.text(hint: "落款", left: 170, y: 378, w: 140, size: 15, font: "kai", ink: ink, align: "trailing")
            b.label(d.dd + " · " + d.year, left: 170, y: 402, w: 140, ink: soft, size: 8.5, align: "trailing")
            b.photo(cx: 272, cy: 74, side: 72, hint: "照片", angle: 6)
            b.clip(cx: 262, cy: 34, style: "paper", color: "A9A39A", angle: 8)
            b.sticker(cx: 58, cy: 418, asset: "leaf_03", size: 52, angle: -20)
        }),
        JournalTemplate(id: "cover", name: "杂志封面", note: "一张大图顶着，标题压在下面",
                        paper: "F2EFE9", weave: "paper_cotton", build: make { b, d in
            b.label("ISSUE " + d.md, left: 26, y: 22, w: 150, ink: ink)
            b.label(d.year, left: 217, y: 22, w: 100, ink: ink, align: "trailing")
            b.photo(cx: 171.5, cy: 180, side: 292, edge: "", hint: "放一张最好看的照片")
            b.text(hint: "大标题", left: 26, y: 358, w: 291, size: 30, ink: ink)
            b.line(left: 26, y: 384, w: 291, ink: ink)
            b.text(hint: "副标题，一句话", left: 26, y: 404, w: 240, size: 13, ink: soft)
            b.label(d.dow, left: 257, y: 404, w: 60, ink: soft, align: "trailing")
        }),
        JournalTemplate(id: "timeline", name: "时间线", note: "一条竖线，这一天按钟点往下走",
                        paper: "EEF0EA", weave: "paper_cotton", build: make { b, d in
            b.text(hint: "今天的时间线", left: 26, y: 40, w: 190, size: 20, ink: ink)
            b.text(d.dd, left: 220, y: 40, w: 97, size: 22, font: "type", ink: ink, align: "trailing")
            b.line(left: 26, y: 64, w: 291, ink: ink)
            b.vline(cx: 72, cy: 245, len: 320, "dash", ink: soft)
            for (i, t) in ["08:00", "11:00", "14:00", "18:00", "22:00"].enumerated() {
                let y = 105 + Double(i) * 64
                b.text(t, left: 18, y: y, w: 44, size: 9.5, font: "label", ink: soft, align: "trailing")
                b.text("●", left: 66, y: y, w: 12, size: 9, ink: rust, align: "center")
                b.text(hint: "做了什么", left: 86, y: y, w: 200, size: 13.5, ink: ink)
            }
            b.photo(cx: 286, cy: 410, side: 70, hint: "照片", angle: 6)
        }),
        JournalTemplate(id: "menu", name: "美食记录", note: "今天吃了什么、好不好吃",
                        paper: "F4EDE0", weave: "paper_news", build: make { b, d in
            b.label("TODAY'S MENU", left: 26, y: 32, w: 291, ink: ink, align: "center")
            b.text(d.dd, left: 26, y: 70, w: 291, size: 38, font: "type", ink: ink, align: "center")
            b.line(left: 70, y: 100, w: 203, "double", ink: ink)
            for i in 0..<3 {
                let y = 132 + Double(i) * 30
                b.text(hint: "菜名", left: 40, y: y, w: 110, size: 14, ink: ink)
                b.line(left: 150, y: y + 3, w: 105, "dots", ink: soft)
                b.text(hint: "好吃", left: 258, y: y, w: 50, size: 12, ink: rust, align: "trailing")
            }
            b.photo(cx: 112, cy: 312, side: 150, hint: "拍一张", angle: -3)
            b.tape(cx: 112, cy: 236, len: 70, color: "E8DCC0", angle: 3)
            b.note(cx: 258, cy: 312, w: 118, hint: "味道怎么样", color: "F7E9A0", angle: 3)
            b.inkStamp(cx: 262, cy: 418, text: "好吃", sub: d.md, color: rust, size: 70)
        }),
        JournalTemplate(id: "ticket", name: "旅行票根", note: "出发、到达、两张照片、一个到达章",
                        paper: "E9E4D8", weave: "paper_news", build: make { b, d in
            b.label("BOARDING PASS", left: 26, y: 28, w: 200, ink: ink)
            b.label(d.dd, left: 217, y: 28, w: 100, ink: ink, align: "trailing")
            b.line(left: 26, y: 42, w: 291, ink: ink)
            b.label("FROM", left: 30, y: 70, w: 100, ink: soft, size: 8)
            b.label("TO", left: 213, y: 70, w: 100, ink: soft, size: 8, align: "trailing")
            b.text(hint: "出发地", left: 30, y: 100, w: 120, size: 24, ink: ink)
            b.text("→", left: 150, y: 100, w: 43, size: 20, ink: soft, align: "center")
            b.text(hint: "目的地", left: 193, y: 100, w: 120, size: 24, ink: ink, align: "trailing")
            b.line(left: 26, y: 132, w: 291, "dash", ink: ink)
            b.label("DATE " + d.md + "    SEAT --", left: 26, y: 150, w: 291, ink: soft, size: 8.5)
            b.photo(cx: 104, cy: 262, side: 138, hint: "风景", angle: -4)
            b.photo(cx: 238, cy: 316, side: 138, hint: "风景", angle: 5)
            b.tape(cx: 238, cy: 246, len: 64, color: "9DB8D1", angle: -6)
            b.inkStamp(cx: 276, cy: 192, text: "到达", sub: d.dd, color: blue, size: 72, angle: 10)
            b.sticker(cx: 54, cy: 392, asset: "bird_03", size: 58)
            b.text(hint: "旅途里的一件小事", left: 26, y: 432, w: 220, size: 12.5, ink: ink)
        }),
        JournalTemplate(id: "reading", name: "读书摘抄", note: "书名、摘一句、写写自己的想法",
                        paper: "F1ECE0", weave: "paper_rice", build: make { b, d in
            b.label("READING NOTES", left: 26, y: 30, w: 200, ink: ink)
            b.label(d.dd, left: 217, y: 30, w: 100, ink: ink, align: "trailing")
            b.text(hint: "书名", left: 26, y: 70, w: 240, size: 22, ink: ink)
            b.text(hint: "作者", left: 26, y: 96, w: 200, size: 12, ink: soft)
            b.line(left: 22, y: 112, w: 150, "hand", ink: rust)
            b.note(cx: 171.5, cy: 200, w: 250, hint: "摘一句书里的话", color: "FBF7EE", style: "ruled", angle: -1)
            b.tape(cx: 171.5, cy: 146, len: 80, color: "E8DCC0", pattern: "stripe", angle: 2)
            b.text(hint: "我的想法", left: 26, y: 320, w: 291, size: 13.5, ink: ink)
            b.sticker(cx: 292, cy: 92, asset: "leaf_02", size: 62, angle: 15)
            b.sticker(cx: 68, cy: 414, asset: "moth_02", size: 56, angle: -10)
        }),
        JournalTemplate(id: "cinema", name: "观影记录", note: "深色纸、一张剧照、星级和感受",
                        paper: "26252B", weave: "paper_cotton", build: make { b, d in
            b.label("NOW SHOWING", left: 26, y: 30, w: 200, ink: light)
            b.label(d.dd, left: 217, y: 30, w: 100, ink: light, align: "trailing")
            b.photo(cx: 171.5, cy: 150, side: 220, edge: "film", hint: "剧照")
            b.text(hint: "片名", left: 26, y: 292, w: 291, size: 26, ink: light, align: "center")
            b.text("★★★★☆", left: 26, y: 322, w: 291, size: 15, ink: gold, align: "center")
            b.line(left: 90, y: 342, w: 163, ink: light)
            b.text(hint: "看完的感受", left: 40, y: 386, w: 263, size: 13, ink: light, align: "center")
            b.inkStamp(cx: 292, cy: 420, text: "观", sub: d.md, color: gold, size: 60)
        }),
        JournalTemplate(id: "weather", name: "天气心情", note: "天气、心情、想记下的事",
                        paper: "EEF2F4", weave: "paper_water", build: make { b, d in
            b.shape(cx: 64, cy: 66, "sun", color: "E8B04A", size: 54)
            b.shape(cx: 104, cy: 84, "cloud", color: "C9D6E2", size: 44)
            b.text(d.dd, left: 160, y: 66, w: 157, size: 42, font: "type", ink: ink, align: "trailing")
            b.label(d.dow + " · " + d.year, left: 160, y: 100, w: 157, ink: soft, align: "trailing")
            b.label("WEATHER", left: 26, y: 138, w: 140, ink: soft, size: 8.5)
            b.text(hint: "晴 · 22°C", left: 26, y: 160, w: 140, size: 15, ink: ink)
            b.label("MOOD", left: 180, y: 138, w: 137, ink: soft, size: 8.5)
            b.text(hint: "今天的心情", left: 180, y: 160, w: 137, size: 15, ink: ink)
            b.line(left: 26, y: 188, w: 291, "dash", ink: ink)
            b.text(hint: "想记下来的事", left: 26, y: 250, w: 291, size: 14, ink: ink)
            b.note(cx: 236, cy: 382, w: 140, hint: "给明天的自己", color: "E3EBF2", angle: 3)
            b.tape(cx: 236, cy: 334, len: 60, color: "9DB8D1", pattern: "dot", angle: -5, ink: "FFFFFF")
        }),
        JournalTemplate(id: "nine", name: "九宫格", note: "九张照片排成一方，底下一句话",
                        paper: "F5F2EA", weave: "paper_cotton", build: make { b, d in
            b.text(hint: "这一天的九张", left: 26, y: 30, w: 291, size: 20, ink: ink, align: "center")
            b.label(d.dd + " · " + d.dow, left: 26, y: 54, w: 291, ink: soft, align: "center")
            for r in 0..<3 {
                for c in 0..<3 {
                    b.photo(cx: 76 + Double(c) * 95.5, cy: 124 + Double(r) * 97, side: 90, edge: "", hint: "照片")
                }
            }
            b.text(hint: "一句话", left: 26, y: 418, w: 291, size: 13, ink: soft, align: "center")
        }),
        JournalTemplate(id: "oneline", name: "一句话", note: "大片留白，只写一句",
                        paper: "F6F4EF", weave: "paper_cotton", build: make { b, d in
            b.text(d.dd, left: 26, y: 120, w: 291, size: 18, font: "type", ink: ink, align: "center")
            b.line(left: 151.5, y: 146, w: 40, ink: ink)
            b.text(hint: "今天只写一句话", left: 40, y: 228, w: 263, size: 22, ink: ink, align: "center")
            b.label(d.week + " · " + d.year, left: 26, y: 410, w: 291, ink: soft, align: "center")
        }),
        JournalTemplate(id: "film", name: "胶片条", note: "三张胶片照片斜着排",
                        paper: "2B2A30", weave: "paper_cotton", build: make { b, d in
            b.label("FILM · " + d.dd, left: 26, y: 26, w: 200, ink: light)
            b.photo(cx: 112, cy: 116, side: 150, edge: "film", hint: "照片", angle: -4)
            b.photo(cx: 232, cy: 236, side: 150, edge: "film", hint: "照片", angle: 3)
            b.photo(cx: 112, cy: 352, side: 150, edge: "film", hint: "照片", angle: -2)
            b.text(hint: "这卷胶片拍了……", left: 195, y: 384, w: 125, size: 13, ink: light)
        }),
        JournalTemplate(id: "notes", name: "便签墙", note: "五张便签贴满一面墙",
                        paper: "B89A74", weave: "paper_kraft", build: make { b, d in
            b.text(d.dd, left: 26, y: 34, w: 160, size: 26, font: "type", ink: "3A2E22")
            b.note(cx: 92, cy: 128, w: 124, hint: "要做的事", color: "F7E9A0", angle: -4)
            b.clip(cx: 92, cy: 70, style: "pin", color: "C4786E")
            b.note(cx: 250, cy: 120, w: 124, hint: "想说的话", color: "F7D4D8", style: "fold", angle: 3)
            b.note(cx: 96, cy: 268, w: 124, hint: "今天的好事", color: "DDE8F5", style: "grid", angle: 2)
            b.tape(cx: 96, cy: 214, len: 56, color: "E8DCC0", angle: -8)
            b.note(cx: 252, cy: 262, w: 124, hint: "明天", color: "E4EBDE", style: "ruled", angle: -3)
            b.clip(cx: 252, cy: 206, style: "bull", color: "3A362E")
            b.note(cx: 172, cy: 392, w: 140, hint: "一个小愿望", color: "FFF3D6", style: "torn", angle: 1)
        }),
        JournalTemplate(id: "postcard", name: "明信片", note: "正面一张风景，背面写给谁",
                        paper: "F3EDE0", weave: "paper_cotton", build: make { b, d in
            b.photo(cx: 171.5, cy: 138, side: 250, hint: "风景")
            b.label("POST CARD", left: 26, y: 286, w: 160, ink: ink)
            b.line(left: 26, y: 300, w: 291, ink: ink)
            b.text(hint: "写给谁", left: 26, y: 330, w: 180, size: 14, font: "kai", ink: ink)
            b.line(left: 26, y: 362, w: 180, "dots", ink: soft)
            b.line(left: 26, y: 390, w: 180, "dots", ink: soft)
            b.line(left: 26, y: 418, w: 180, "dots", ink: soft)
            b.postStamp(cx: 284, cy: 346, asset: "stamp_house", color: "8A6A4E")
            b.inkStamp(cx: 238, cy: 392, text: "邮", sub: d.dd, color: soft, size: 66, angle: -14)
        }),
        JournalTemplate(id: "todo", name: "待办清单", note: "方格纸上一张清单",
                        paper: "F4F1EA", pattern: "grid", weave: "paper_cotton", build: make { b, d in
            b.text(hint: "今日清单", left: 26, y: 40, w: 180, size: 22, ink: ink)
            b.text(d.dd, left: 210, y: 40, w: 107, size: 20, font: "type", ink: ink, align: "trailing")
            b.line(left: 22, y: 62, w: 120, "hand", ink: "C4786E")
            for i in 0..<6 {
                let y = 102 + Double(i) * 38
                b.text("□", left: 30, y: y, w: 20, size: 15, ink: ink)
                b.text(hint: "一件事", left: 56, y: y, w: 240, size: 14, ink: ink)
            }
            b.note(cx: 250, cy: 404, w: 120, hint: "备忘", color: "F7E9A0", angle: 4)
        }),
        JournalTemplate(id: "walk", name: "散步日记", note: "走了多少步、去了哪儿、两张照片",
                        paper: "C9A57A", weave: "paper_kraft", build: make { b, d in
            b.label("WALK · " + d.md, left: 26, y: 28, w: 200, ink: ink)
            b.text(d.dd, left: 22, y: 70, w: 200, size: 44, font: "type", ink: "211A14")
            b.label("STEPS", left: 26, y: 118, w: 120, ink: soft, size: 8.5)
            b.text(hint: "8000 步", left: 26, y: 140, w: 130, size: 16, ink: ink)
            b.label("PLACE", left: 170, y: 118, w: 147, ink: soft, size: 8.5)
            b.text(hint: "去了哪儿", left: 170, y: 140, w: 147, size: 16, ink: ink)
            b.line(left: 26, y: 166, w: 291, "dash", ink: ink)
            b.polaroid(cx: 100, cy: 266, w: 120, angle: -4)
            b.polaroid(cx: 240, cy: 286, w: 120, angle: 5)
            b.tape(cx: 240, cy: 214, len: 60, color: "A8C4A2", angle: 6)
            b.sticker(cx: 296, cy: 70, asset: "leaf_05", size: 56, angle: 20)
            b.sticker(cx: 52, cy: 392, asset: "bug_03", size: 42, angle: -15)
            b.text(hint: "路上看到的", left: 80, y: 410, w: 237, size: 13, ink: ink)
        }),
        JournalTemplate(id: "anniversary", name: "纪念日", note: "大日期、一张拍立得、一个纪念章",
                        paper: "F5E6E1", weave: "paper_cotton", build: make { b, d in
            b.label("ANNIVERSARY", left: 26, y: 38, w: 291, ink: "8A4A55", align: "center")
            b.text(d.dd, left: 26, y: 86, w: 291, size: 50, font: "type", ink: "5A2E35", align: "center")
            b.text(hint: "今天是……", left: 26, y: 136, w: 291, size: 19, ink: "5A2E35", align: "center")
            b.line(left: 100, y: 156, w: 143, "hand", ink: "C9667F")
            b.polaroid(cx: 171.5, cy: 280, w: 148, angle: -3)
            b.shape(cx: 274, cy: 214, "heart", color: "D97B8E", size: 36, angle: 12)
            b.shape(cx: 66, cy: 340, "heart", color: "E8A9B6", size: 26, angle: -10)
            b.inkStamp(cx: 288, cy: 382, text: "纪念", sub: d.year, color: "B5485A", size: 66)
            b.text(hint: "想对你说的话", left: 26, y: 424, w: 230, size: 13, ink: "5A2E35")
        }),
        JournalTemplate(id: "night", name: "夜晚", note: "深蓝的纸、月亮、睡前的话",
                        paper: "1F2633", pattern: "stars", build: make { b, d in
            b.shape(cx: 284, cy: 66, "moon", color: "E9D9A8", size: 58, angle: -15)
            b.label("GOOD NIGHT", left: 26, y: 40, w: 200, ink: light)
            b.text(d.dd, left: 22, y: 84, w: 200, size: 34, font: "type", ink: light)
            b.line(left: 26, y: 132, w: 291, "dots", ink: light)
            b.text(hint: "睡前想说的话", left: 26, y: 200, w: 291, size: 15, ink: light)
            b.photo(cx: 236, cy: 336, side: 140, hint: "今天的一张", angle: 4)
            b.text(hint: "明天想做的事", left: 26, y: 424, w: 180, size: 13, ink: light)
        }),
        JournalTemplate(id: "mood", name: "心情手账", note: "开心的事、烦恼的事、想感谢的",
                        paper: "F1EFE8", weave: "paper_cotton", build: make { b, d in
            b.text(hint: "今天的心情", left: 26, y: 40, w: 190, size: 22, ink: ink)
            b.text(d.dd, left: 220, y: 40, w: 97, size: 20, font: "type", ink: ink, align: "trailing")
            b.line(left: 26, y: 62, w: 291, ink: ink)
            for (i, t) in ["开心的事", "烦恼的事", "想感谢的"].enumerated() {
                let y = 96 + Double(i) * 88
                b.label(t, left: 26, y: y, w: 150, ink: rust, size: 10)
                b.text(hint: "写一写", left: 26, y: y + 30, w: 291, size: 13.5, ink: ink)
            }
            b.shape(cx: 300, cy: 96, "flower", color: "E7A9B4", size: 30)
            b.note(cx: 240, cy: 400, w: 140, hint: "给自己一句话", color: "F7E3E6", angle: -3)
            b.tape(cx: 240, cy: 352, len: 56, color: "E8B4BC", angle: 5)
            b.sticker(cx: 66, cy: 404, asset: "moth_05", size: 54, angle: -12)
        })
    ]
}
