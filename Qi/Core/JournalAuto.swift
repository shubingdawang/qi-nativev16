import Foundation

/// 「同页」：他用那一天聊过的话、她发的照片、那天的小票，替她拼一页手帐。
/// 拼出来的是一页普通的手帐，她照样能挪、能改、能贴；右上角摇骰子换一种排法和风格。
///
/// 思路来自 Toska 的「同页」（跟机一起做手帐），这里是本机重写的一份。
struct JournalAutoParts: Codable, Hashable {
    var title = ""
    var texts: [String] = []
    /// `ImageStore` 里的图（已经复制过，跟聊天里那张分开）
    var photos: [String] = []
    /// 每张照片几点拍的（HH:mm，读不到就空）。时间线那种排法用
    var times: [String] = []
    var stickers: [String] = []
    /// 小票上的每一行
    var receipt: [String] = []
    var stamp = ""
    var mood = ""
    /// 快门条：「14:32 · 青岛 · f/1.8 1/250s ISO 64」
    var strip = ""
    /// 那天在哪（照片读出来的地名）
    var place = ""
    var layout = 0
}

extension JournalAutoParts {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        texts = (try? c.decodeIfPresent([String].self, forKey: .texts)) ?? []
        photos = (try? c.decodeIfPresent([String].self, forKey: .photos)) ?? []
        times = (try? c.decodeIfPresent([String].self, forKey: .times)) ?? []
        stickers = (try? c.decodeIfPresent([String].self, forKey: .stickers)) ?? []
        receipt = (try? c.decodeIfPresent([String].self, forKey: .receipt)) ?? []
        stamp = (try? c.decodeIfPresent(String.self, forKey: .stamp)) ?? ""
        mood = (try? c.decodeIfPresent(String.self, forKey: .mood)) ?? ""
        strip = (try? c.decodeIfPresent(String.self, forKey: .strip)) ?? ""
        place = (try? c.decodeIfPresent(String.self, forKey: .place)) ?? ""
        layout = (try? c.decodeIfPresent(Int.self, forKey: .layout)) ?? 0
    }
}

enum JournalAuto {
    /// 拼出来的那几样都打这个记号，摇骰子时只换它们，她自己加的不动
    static let tag = "同页"

    private struct Slot { var x: Double; var y: Double; var angle: Double = 0; var scale: Double = 1 }

    /// 垫在底下的一张纸（明信片背面、信纸、撕页日历那一页）
    private struct Back { var slot: Slot; var color: String; var pattern: String; var lines: Int }

    private struct Layout {
        var name: String
        var title: Slot?
        var stamp: Slot?
        var photos: [Slot]
        var texts: [Slot]
        var receipt: Slot?
        var mood: Slot?
        var stickers: [Slot]
        var strip: Slot? = Slot(x: 0.3, y: 0.935)
        /// 照片换成拍立得
        var polaroid = false
        /// 照片套什么边（胶片条那种）
        var edge: String? = nil
        /// 照片上不贴胶带
        var noTape = false
        /// 正文写成便签
        var notes = false
        var backs: [Back] = []
        /// 大大的日子
        var bigDate: Slot? = nil
        /// 日子底下那行小字
        var dateSub: Slot? = nil
        /// 每张照片旁边写几点拍的
        var times: [Slot] = []
        /// 横一根晾衣绳，照片挂上去
        var rope: Slot? = nil
    }

    private static let layouts: [Layout] = [
        Layout(name: "交错",
               title: Slot(x: 0.34, y: 0.07, angle: -2, scale: 1.22),
               stamp: Slot(x: 0.86, y: 0.08, angle: 6),
               photos: [Slot(x: 0.28, y: 0.28, angle: -4, scale: 1.05),
                        Slot(x: 0.72, y: 0.53, angle: 5),
                        Slot(x: 0.3, y: 0.77, angle: -3, scale: 0.9)],
               texts: [Slot(x: 0.7, y: 0.27, scale: 0.82), Slot(x: 0.3, y: 0.52, scale: 0.82),
                       Slot(x: 0.7, y: 0.79, scale: 0.8)],
               receipt: Slot(x: 0.72, y: 0.81, angle: 3),
               mood: Slot(x: 0.62, y: 0.965, scale: 0.7),
               stickers: [Slot(x: 0.12, y: 0.41), Slot(x: 0.88, y: 0.66), Slot(x: 0.55, y: 0.41)]),
        Layout(name: "大图在上",
               title: Slot(x: 0.5, y: 0.46, scale: 1.25),
               stamp: Slot(x: 0.87, y: 0.43, angle: 7),
               photos: [Slot(x: 0.5, y: 0.21, angle: -1.5, scale: 1.55),
                        Slot(x: 0.25, y: 0.70, angle: -6, scale: 0.85),
                        Slot(x: 0.76, y: 0.72, angle: 4, scale: 0.85)],
               texts: [Slot(x: 0.5, y: 0.55, scale: 0.85), Slot(x: 0.72, y: 0.90, scale: 0.8),
                       Slot(x: 0.5, y: 0.62, scale: 0.8)],
               receipt: Slot(x: 0.27, y: 0.89, angle: -3),
               mood: Slot(x: 0.62, y: 0.97, scale: 0.7),
               stickers: [Slot(x: 0.1, y: 0.45), Slot(x: 0.9, y: 0.58), Slot(x: 0.5, y: 0.79)]),
        Layout(name: "字多",
               title: Slot(x: 0.42, y: 0.07, angle: -1, scale: 1.3),
               stamp: Slot(x: 0.88, y: 0.07, angle: 6),
               photos: [Slot(x: 0.22, y: 0.73, angle: -5, scale: 0.78),
                        Slot(x: 0.5, y: 0.71, angle: 3, scale: 0.78),
                        Slot(x: 0.78, y: 0.74, angle: -2, scale: 0.78)],
               texts: [Slot(x: 0.5, y: 0.2, scale: 0.88), Slot(x: 0.5, y: 0.36, scale: 0.88),
                       Slot(x: 0.5, y: 0.52, scale: 0.88)],
               receipt: Slot(x: 0.74, y: 0.91, angle: 3),
               mood: Slot(x: 0.62, y: 0.97, scale: 0.72),
               stickers: [Slot(x: 0.1, y: 0.15), Slot(x: 0.9, y: 0.45), Slot(x: 0.08, y: 0.6)]),
        Layout(name: "拼贴",
               title: Slot(x: 0.72, y: 0.1, angle: 2, scale: 1.2),
               stamp: Slot(x: 0.13, y: 0.07, angle: -8),
               photos: [Slot(x: 0.3, y: 0.22, angle: -7),
                        Slot(x: 0.73, y: 0.32, angle: 6),
                        Slot(x: 0.38, y: 0.55, angle: -2, scale: 1.05)],
               texts: [Slot(x: 0.76, y: 0.56, scale: 0.8), Slot(x: 0.3, y: 0.82, scale: 0.82),
                       Slot(x: 0.68, y: 0.94, scale: 0.78)],
               receipt: Slot(x: 0.76, y: 0.78, angle: 4),
               mood: Slot(x: 0.62, y: 0.975, scale: 0.7),
               stickers: [Slot(x: 0.9, y: 0.16), Slot(x: 0.12, y: 0.4), Slot(x: 0.88, y: 0.66)]),
        Layout(name: "拍立得墙",
               title: Slot(x: 0.5, y: 0.05, scale: 1.15),
               stamp: Slot(x: 0.88, y: 0.06, angle: 7),
               photos: [Slot(x: 0.27, y: 0.22, angle: -6, scale: 0.9),
                        Slot(x: 0.73, y: 0.24, angle: 5, scale: 0.9),
                        Slot(x: 0.28, y: 0.52, angle: 4, scale: 0.9),
                        Slot(x: 0.72, y: 0.54, angle: -4, scale: 0.9)],
               texts: [Slot(x: 0.5, y: 0.74, scale: 0.85), Slot(x: 0.5, y: 0.84, scale: 0.8)],
               receipt: Slot(x: 0.8, y: 0.88, angle: 4),
               mood: Slot(x: 0.62, y: 0.97, scale: 0.7),
               stickers: [Slot(x: 0.07, y: 0.38), Slot(x: 0.93, y: 0.4), Slot(x: 0.5, y: 0.66)],
               polaroid: true),
        Layout(name: "明信片",
               title: Slot(x: 0.32, y: 0.47, angle: -1, scale: 1.1),
               stamp: Slot(x: 0.8, y: 0.6, angle: 5, scale: 1.1),
               photos: [Slot(x: 0.5, y: 0.22, angle: -1, scale: 2.0)],
               texts: [Slot(x: 0.33, y: 0.66, scale: 0.72), Slot(x: 0.33, y: 0.78, scale: 0.7)],
               receipt: nil,
               mood: Slot(x: 0.72, y: 0.78, scale: 0.7),
               stickers: [Slot(x: 0.9, y: 0.4), Slot(x: 0.1, y: 0.9)],
               strip: Slot(x: 0.33, y: 0.87),
               backs: [Back(slot: Slot(x: 0.5, y: 0.72, scale: 2.6), color: "FBF8F1", pattern: "", lines: 9)]),
        Layout(name: "时间线",
               title: Slot(x: 0.5, y: 0.05, scale: 1.15),
               stamp: Slot(x: 0.9, y: 0.06, angle: 6),
               photos: [Slot(x: 0.4, y: 0.22, angle: -2, scale: 0.78),
                        Slot(x: 0.4, y: 0.5, angle: 2, scale: 0.78),
                        Slot(x: 0.4, y: 0.78, angle: -1, scale: 0.78)],
               texts: [Slot(x: 0.8, y: 0.22, scale: 0.68), Slot(x: 0.8, y: 0.5, scale: 0.68),
                       Slot(x: 0.8, y: 0.78, scale: 0.68)],
               receipt: nil,
               mood: Slot(x: 0.62, y: 0.97, scale: 0.7),
               stickers: [Slot(x: 0.08, y: 0.94)],
               noTape: true,
               times: [Slot(x: 0.1, y: 0.22, scale: 0.6), Slot(x: 0.1, y: 0.5, scale: 0.6),
                       Slot(x: 0.1, y: 0.78, scale: 0.6)]),
        Layout(name: "信纸",
               title: Slot(x: 0.32, y: 0.13, angle: -1, scale: 1.05),
               stamp: Slot(x: 0.84, y: 0.1, angle: 6),
               photos: [Slot(x: 0.7, y: 0.76, angle: 4, scale: 0.62)],
               texts: [Slot(x: 0.5, y: 0.3, scale: 0.82), Slot(x: 0.5, y: 0.45, scale: 0.82),
                       Slot(x: 0.42, y: 0.6, scale: 0.82)],
               receipt: nil,
               mood: Slot(x: 0.36, y: 0.86, scale: 0.72),
               stickers: [Slot(x: 0.12, y: 0.92)],
               strip: Slot(x: 0.34, y: 0.92),
               backs: [Back(slot: Slot(x: 0.5, y: 0.5, scale: 2.5), color: "FFFDF8", pattern: "ruled", lines: 17)]),
        Layout(name: "便签墙",
               title: Slot(x: 0.3, y: 0.05, angle: -2, scale: 1.1),
               stamp: Slot(x: 0.88, y: 0.05, angle: 6),
               photos: [Slot(x: 0.5, y: 0.25, angle: -1, scale: 1.55)],
               texts: [Slot(x: 0.28, y: 0.55, angle: -4), Slot(x: 0.72, y: 0.57, angle: 3),
                       Slot(x: 0.28, y: 0.77, angle: 2), Slot(x: 0.72, y: 0.79, angle: -3)],
               receipt: nil,
               mood: Slot(x: 0.62, y: 0.97, scale: 0.7),
               stickers: [Slot(x: 0.9, y: 0.42), Slot(x: 0.08, y: 0.66)],
               notes: true),
        Layout(name: "撕页日历",
               title: Slot(x: 0.7, y: 0.08, scale: 1.1),
               stamp: Slot(x: 0.9, y: 0.92, angle: 6),
               photos: [Slot(x: 0.5, y: 0.56, angle: -1.5, scale: 1.6)],
               texts: [Slot(x: 0.7, y: 0.2, scale: 0.72), Slot(x: 0.5, y: 0.85, scale: 0.82)],
               receipt: nil,
               mood: Slot(x: 0.25, y: 0.3, scale: 0.62),
               stickers: [Slot(x: 0.9, y: 0.36)],
               strip: Slot(x: 0.32, y: 0.95),
               backs: [Back(slot: Slot(x: 0.25, y: 0.17, scale: 1.25), color: "FFFDF8", pattern: "", lines: 6)],
               bigDate: Slot(x: 0.25, y: 0.18, scale: 2.8),
               dateSub: Slot(x: 0.25, y: 0.08, scale: 0.62)),
        Layout(name: "胶片条",
               title: Slot(x: 0.7, y: 0.08, scale: 1.1),
               stamp: Slot(x: 0.88, y: 0.9, angle: 6),
               photos: [Slot(x: 0.27, y: 0.18, scale: 0.72),
                        Slot(x: 0.27, y: 0.45, scale: 0.72),
                        Slot(x: 0.27, y: 0.72, scale: 0.72)],
               texts: [Slot(x: 0.7, y: 0.24, scale: 0.75), Slot(x: 0.7, y: 0.42, scale: 0.75),
                       Slot(x: 0.7, y: 0.6, scale: 0.75)],
               receipt: nil,
               mood: Slot(x: 0.62, y: 0.97, scale: 0.7),
               stickers: [],
               strip: Slot(x: 0.68, y: 0.76),
               edge: "film", noTape: true),
        Layout(name: "只留重点",
               title: nil, stamp: nil,
               photos: [Slot(x: 0.5, y: 0.5, scale: 2.3)],
               texts: [Slot(x: 0.5, y: 0.84, scale: 1.0)],
               receipt: nil, mood: nil, stickers: [],
               strip: Slot(x: 0.32, y: 0.93),
               noTape: true,
               bigDate: Slot(x: 0.2, y: 0.1, scale: 3.4),
               dateSub: Slot(x: 0.55, y: 0.12, scale: 0.75)),
        Layout(name: "晾起来",
               title: Slot(x: 0.5, y: 0.05, scale: 1.15),
               stamp: Slot(x: 0.88, y: 0.9, angle: 6),
               photos: [Slot(x: 0.22, y: 0.25, angle: -4, scale: 0.8),
                        Slot(x: 0.5, y: 0.27, angle: 2, scale: 0.8),
                        Slot(x: 0.78, y: 0.25, angle: 5, scale: 0.8)],
               texts: [Slot(x: 0.5, y: 0.56, scale: 0.85), Slot(x: 0.5, y: 0.7, scale: 0.82)],
               receipt: Slot(x: 0.26, y: 0.85, angle: -3),
               mood: Slot(x: 0.62, y: 0.97, scale: 0.7),
               stickers: [Slot(x: 0.9, y: 0.45), Slot(x: 0.1, y: 0.48)],
               polaroid: true, noTape: true,
               rope: Slot(x: 0.5, y: 0.13, scale: 1.05)),
    ]

    static var layoutCount: Int { layouts.count }
    static var layoutNames: [String] { layouts.map(\.name) }

    static func layoutIndex(named n: String) -> Int? {
        let t = n.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return layouts.firstIndex { $0.name == t || t.contains($0.name) || $0.name.contains(t) }
    }

    /// 简单的伪随机：同一个种子排出来一样
    private struct Dice {
        var s: UInt64
        mutating func next() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double(s >> 11) / Double(1 << 53)
        }
        mutating func jitter(_ r: Double) -> Double { (next() * 2 - 1) * r }
    }

    private static let monthNames = ["一月", "二月", "三月", "四月", "五月", "六月",
                                     "七月", "八月", "九月", "十月", "十一月", "十二月"]

    static func compose(_ p: JournalAutoParts, layout index: Int, seed: UInt64,
                        day: Date = Date()) -> [JournalElement] {
        let L = layouts[((index % layouts.count) + layouts.count) % layouts.count]
        var dice = Dice(s: seed | 1)
        var out: [JournalElement] = []
        var z = 1
        let cal = Calendar.current

        func place(_ e: inout JournalElement, _ s: Slot, jitter: Double = 0.012) {
            e.x = min(0.95, max(0.05, s.x + dice.jitter(jitter)))
            e.y = min(0.97, max(0.03, s.y + dice.jitter(jitter)))
            e.angle = s.angle + dice.jitter(1.2)
            e.scale = s.scale
            e.z = z
            e.who = tag
            z += 1
        }

        let ink = "3A362E"
        // 垫底的纸
        for b in L.backs {
            var e = JournalElement()
            e.kind = .note
            e.text = String(repeating: "\n", count: b.lines)
            e.colorHex = b.color
            e.pattern = b.pattern
            place(&e, b.slot, jitter: 0.004)
            e.angle = b.slot.angle + dice.jitter(0.8)
            out.append(e)
        }
        // 晾衣绳
        var ropeID = ""
        if let r = L.rope {
            var e = JournalElement()
            e.kind = .rope
            e.colorHex = "8A7356"
            place(&e, r, jitter: 0)
            e.angle = 0
            ropeID = e.id.uuidString
            out.append(e)
        }
        // 照片 + 压在上沿的胶带
        for (i, name) in p.photos.prefix(L.photos.count).enumerated() {
            var e = JournalElement()
            e.kind = L.polaroid ? .frame : .photo
            e.imageName = name
            if let edge = L.edge { e.pattern = edge }
            place(&e, L.photos[i])
            if !ropeID.isEmpty { e.hangOn = ropeID }
            out.append(e)
            if !L.noTape {
                var t = JournalElement()
                t.kind = .tape
                let tape = JournalKit.tapes[Int(dice.next() * Double(JournalKit.tapes.count)) % JournalKit.tapes.count]
                t.colorHex = tape.1
                let pats = JournalKit.tapePatterns
                t.pattern = pats[Int(dice.next() * Double(pats.count)) % pats.count].1
                let lift = (L.polaroid ? 0.12 : 0.095) * L.photos[i].scale
                place(&t, Slot(x: e.x + dice.jitter(0.04), y: e.y - lift,
                               angle: dice.jitter(14), scale: 0.9), jitter: 0)
                out.append(t)
            }
            // 时间线：照片旁边写几点
            if i < L.times.count, i < p.times.count, !p.times[i].isEmpty {
                var t = JournalElement()
                t.kind = .text
                t.text = p.times[i]
                t.colorHex = "8A8378"
                t.pattern = "mono"
                place(&t, L.times[i], jitter: 0)
                out.append(t)
            }
        }
        // 大日子
        if let s = L.bigDate {
            var e = JournalElement()
            e.kind = .text
            e.text = String(cal.component(.day, from: day))
            e.colorHex = ink
            e.emoji = "date"
            place(&e, s, jitter: 0)
            e.angle = 0
            out.append(e)
        }
        if let s = L.dateSub {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "EEE"
            var sub = monthNames[cal.component(.month, from: day) - 1] + " · " + f.string(from: day)
            if !p.place.isEmpty { sub += " · " + p.place }
            var e = JournalElement()
            e.kind = .text
            e.text = sub
            e.colorHex = "8A8378"
            place(&e, s, jitter: 0)
            e.angle = 0
            out.append(e)
        }
        // 标题
        if !p.title.isEmpty, let s = L.title {
            var e = JournalElement()
            e.kind = .text
            e.text = p.title
            e.colorHex = ink
            e.emoji = "title"
            place(&e, s)
            out.append(e)
        }
        // 正文：有小票的话最后一格让给小票
        let textSlots = (p.receipt.isEmpty || L.receipt == nil) ? L.texts : Array(L.texts.prefix(max(1, L.texts.count - 1)))
        for (i, t) in p.texts.prefix(textSlots.count).enumerated() {
            var e = JournalElement()
            if L.notes {
                e.kind = .note
                e.text = t
                e.colorHex = JournalKit.notes[i % JournalKit.notes.count].1
            } else {
                e.kind = .text
                e.text = t
                e.colorHex = ink
            }
            place(&e, textSlots[i])
            out.append(e)
        }
        if !p.receipt.isEmpty, let s = L.receipt {
            var e = JournalElement()
            e.kind = .note
            e.text = p.receipt.joined(separator: "\n")
            e.colorHex = "FBF8F1"
            place(&e, s)
            out.append(e)
        }
        if !p.mood.isEmpty, let s = L.mood {
            var e = JournalElement()
            e.kind = .text
            e.text = p.mood
            e.colorHex = "8A8178"
            place(&e, s)
            out.append(e)
        }
        if !p.strip.isEmpty, let s = L.strip {
            var e = JournalElement()
            e.kind = .strip
            e.text = p.strip
            e.colorHex = ink
            place(&e, s, jitter: 0)
            e.angle = 0
            out.append(e)
        }
        if !p.stamp.isEmpty, let s = L.stamp {
            var e = JournalElement()
            e.kind = .stamp
            e.emoji = p.stamp
            e.colorHex = "B07A5A"
            place(&e, s)
            out.append(e)
        }
        for (i, s) in p.stickers.prefix(L.stickers.count).enumerated() {
            var e = JournalElement()
            e.kind = .sticker
            e.emoji = s
            place(&e, L.stickers[i], jitter: 0.03)
            e.angle = dice.jitter(15)
            out.append(e)
        }
        return out
    }

    /// 拼一页：排法 + 风格一起上
    static func build(_ parts: JournalAutoParts, theme: JournalTheme?, into page: inout JournalPage) {
        page.auto = parts
        page.length = 1
        page.elements = compose(parts, layout: parts.layout, seed: UInt64.random(in: 1...UInt64.max), day: page.day)
        if let theme {
            JournalTheme.apply(theme, to: &page, seed: Int.random(in: 0..<10))
        } else {
            let soft = JournalKit.papers.filter { $0.0 != "深棕" }
            page.paperHex = soft.randomElement()?.1 ?? page.paperHex
        }
    }

    /// 换一种排法和风格：只换他拼的那几样，她后来贴的不动
    static func reroll(_ page: inout JournalPage) {
        guard var parts = page.auto else { return }
        parts.layout = (parts.layout + 1 + Int.random(in: 0..<(layoutCount - 1))) % layoutCount
        page.auto = parts
        let mine = page.elements.filter { $0.who != tag }
        // 拼的那几样压在底下，她后来贴的照样在上面
        var made = compose(parts, layout: parts.layout, seed: UInt64.random(in: 1...UInt64.max), day: page.day)
        for i in made.indices { made[i].z -= 1000 }
        let others = JournalTheme.all.filter { $0.id != page.themeID }
        var themed = page
        themed.elements = made
        if let t = others.randomElement() { JournalTheme.apply(t, to: &themed, seed: Int.random(in: 0..<10)) }
        page.paperHex = themed.paperHex
        page.paperPattern = themed.paperPattern
        page.paperWeave = themed.paperWeave
        page.themeID = themed.themeID
        page.elements = themed.elements + mine
    }

    /// 她说的感觉 → 挑哪几种排法、哪几种风格
    static func pick(moods: [String]) -> (layouts: [Int], themes: [String]) {
        var ls: [Int] = [], ts: [String] = []
        func L(_ names: [String]) { ls += names.compactMap { layoutIndex(named: $0) } }
        for m in moods {
            if m.contains("安静") { L(["信纸", "只留重点", "交错"]); ts += ["qingmo", "mono", "xuan", "water"] }
            if m.contains("复古") { L(["拍立得墙", "明信片", "胶片条"]); ts += ["film", "kraft", "academia"] }
            if m.contains("热闹") { L(["便签墙", "拼贴", "拍立得墙"]); ts += ["washi", "nature", "sketch"] }
            if m.contains("放大") { L(["大图在上", "明信片", "只留重点"]) }
        }
        return (ls, ts)
    }
}
