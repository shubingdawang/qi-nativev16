import Foundation

/// 「同页」：他用那一天聊过的话、她发的照片、那天的小票，替她拼一页手帐。
/// 拼出来的是一页普通的手帐，她照样能挪、能改、能贴；右上角摇骰子换一种排法。
///
/// 思路来自 Toska 的「同页」（跟机一起做手帐），这里是本机重写的一份。
struct JournalAutoParts: Codable, Hashable {
    var title = ""
    var texts: [String] = []
    /// `ImageStore` 里的图（已经复制过，跟聊天里那张分开）
    var photos: [String] = []
    var stickers: [String] = []
    /// 小票上的每一行
    var receipt: [String] = []
    var stamp = ""
    var mood = ""
    var layout = 0
}

enum JournalAuto {
    /// 拼出来的那几样都打这个记号，摇骰子时只换它们，她自己加的不动
    static let tag = "同页"
    static let layoutCount = 4

    private struct Slot { var x: Double; var y: Double; var angle: Double = 0; var scale: Double = 1 }

    private struct Layout {
        var title: Slot
        var stamp: Slot
        var photos: [Slot]
        var texts: [Slot]
        var receipt: Slot
        var mood: Slot
        var stickers: [Slot]
    }

    private static func layout(_ i: Int) -> Layout {
        switch i % layoutCount {
        case 1: // 大图在上
            return Layout(
                title: Slot(x: 0.5, y: 0.46, scale: 1.25),
                stamp: Slot(x: 0.87, y: 0.43, angle: 7),
                photos: [Slot(x: 0.5, y: 0.21, angle: -1.5, scale: 1.55),
                         Slot(x: 0.25, y: 0.70, angle: -6, scale: 0.85),
                         Slot(x: 0.76, y: 0.72, angle: 4, scale: 0.85)],
                texts: [Slot(x: 0.5, y: 0.55, scale: 0.85), Slot(x: 0.72, y: 0.90, scale: 0.8),
                        Slot(x: 0.5, y: 0.62, scale: 0.8)],
                receipt: Slot(x: 0.27, y: 0.89, angle: -3),
                mood: Slot(x: 0.5, y: 0.97, scale: 0.7),
                stickers: [Slot(x: 0.1, y: 0.45), Slot(x: 0.9, y: 0.58), Slot(x: 0.5, y: 0.79)])
        case 2: // 字多的那种
            return Layout(
                title: Slot(x: 0.42, y: 0.07, angle: -1, scale: 1.3),
                stamp: Slot(x: 0.88, y: 0.07, angle: 6),
                photos: [Slot(x: 0.22, y: 0.73, angle: -5, scale: 0.78),
                         Slot(x: 0.5, y: 0.71, angle: 3, scale: 0.78),
                         Slot(x: 0.78, y: 0.74, angle: -2, scale: 0.78)],
                texts: [Slot(x: 0.5, y: 0.2, scale: 0.88), Slot(x: 0.5, y: 0.36, scale: 0.88),
                        Slot(x: 0.5, y: 0.52, scale: 0.88)],
                receipt: Slot(x: 0.74, y: 0.91, angle: 3),
                mood: Slot(x: 0.3, y: 0.93, scale: 0.72),
                stickers: [Slot(x: 0.1, y: 0.15), Slot(x: 0.9, y: 0.45), Slot(x: 0.08, y: 0.6)])
        case 3: // 拼贴
            return Layout(
                title: Slot(x: 0.72, y: 0.1, angle: 2, scale: 1.2),
                stamp: Slot(x: 0.13, y: 0.07, angle: -8),
                photos: [Slot(x: 0.3, y: 0.22, angle: -7),
                         Slot(x: 0.73, y: 0.32, angle: 6),
                         Slot(x: 0.38, y: 0.55, angle: -2, scale: 1.05)],
                texts: [Slot(x: 0.76, y: 0.56, scale: 0.8), Slot(x: 0.3, y: 0.82, scale: 0.82),
                        Slot(x: 0.68, y: 0.94, scale: 0.78)],
                receipt: Slot(x: 0.76, y: 0.78, angle: 4),
                mood: Slot(x: 0.3, y: 0.95, scale: 0.7),
                stickers: [Slot(x: 0.9, y: 0.16), Slot(x: 0.12, y: 0.4), Slot(x: 0.88, y: 0.66)])
        default: // 交错
            return Layout(
                title: Slot(x: 0.34, y: 0.07, angle: -2, scale: 1.22),
                stamp: Slot(x: 0.86, y: 0.08, angle: 6),
                photos: [Slot(x: 0.28, y: 0.28, angle: -4, scale: 1.05),
                         Slot(x: 0.72, y: 0.53, angle: 5),
                         Slot(x: 0.3, y: 0.77, angle: -3, scale: 0.9)],
                texts: [Slot(x: 0.7, y: 0.27, scale: 0.82), Slot(x: 0.3, y: 0.52, scale: 0.82),
                        Slot(x: 0.7, y: 0.79, scale: 0.8)],
                receipt: Slot(x: 0.72, y: 0.81, angle: 3),
                mood: Slot(x: 0.5, y: 0.96, scale: 0.7),
                stickers: [Slot(x: 0.12, y: 0.41), Slot(x: 0.88, y: 0.66), Slot(x: 0.55, y: 0.41)])
        }
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

    static func compose(_ p: JournalAutoParts, layout index: Int, seed: UInt64) -> [JournalElement] {
        let L = layout(index)
        var dice = Dice(s: seed | 1)
        var out: [JournalElement] = []
        var z = 1

        func place(_ e: inout JournalElement, _ s: Slot, jitter: Double = 0.015) {
            e.x = min(0.95, max(0.05, s.x + dice.jitter(jitter)))
            e.y = min(0.97, max(0.03, s.y + dice.jitter(jitter)))
            e.angle = s.angle + dice.jitter(1.5)
            e.scale = s.scale
            e.z = z
            e.who = tag
            z += 1
        }

        let ink = "3A342E"
        // 照片 + 压在上沿的胶带
        for (i, name) in p.photos.prefix(L.photos.count).enumerated() {
            var e = JournalElement()
            e.kind = .photo
            e.imageName = name
            place(&e, L.photos[i])
            out.append(e)
            var t = JournalElement()
            t.kind = .tape
            let tape = JournalKit.tapes[Int(dice.next() * Double(JournalKit.tapes.count)) % JournalKit.tapes.count]
            t.colorHex = tape.1
            let pats = JournalKit.tapePatterns
            t.pattern = pats[Int(dice.next() * Double(pats.count)) % pats.count].1
            place(&t, Slot(x: e.x + dice.jitter(0.04), y: e.y - 0.095 * L.photos[i].scale,
                           angle: dice.jitter(14), scale: 0.9), jitter: 0)
            out.append(t)
        }
        // 标题
        if !p.title.isEmpty {
            var e = JournalElement()
            e.kind = .text
            e.text = p.title
            e.colorHex = ink
            place(&e, L.title)
            out.append(e)
        }
        // 正文：有小票的话最后一格让给小票
        let textSlots = p.receipt.isEmpty ? L.texts : Array(L.texts.prefix(2))
        for (i, t) in p.texts.prefix(textSlots.count).enumerated() {
            var e = JournalElement()
            e.kind = .text
            e.text = t
            e.colorHex = ink
            place(&e, textSlots[i])
            out.append(e)
        }
        if !p.receipt.isEmpty {
            var e = JournalElement()
            e.kind = .note
            e.text = p.receipt.joined(separator: "\n")
            e.colorHex = "FBF8F1"
            place(&e, L.receipt)
            out.append(e)
        }
        if !p.mood.isEmpty {
            var e = JournalElement()
            e.kind = .text
            e.text = p.mood
            e.colorHex = "8A8178"
            place(&e, L.mood)
            out.append(e)
        }
        if !p.stamp.isEmpty {
            var e = JournalElement()
            e.kind = .stamp
            e.emoji = p.stamp
            e.colorHex = "B07A5A"
            place(&e, L.stamp)
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

    /// 换一种排法：只换他拼的那几样
    static func reroll(_ page: inout JournalPage) {
        guard var parts = page.auto else { return }
        parts.layout = (parts.layout + 1 + Int.random(in: 0..<(layoutCount - 1))) % layoutCount
        page.auto = parts
        let mine = page.elements.filter { $0.who != tag }
        // 拼的那几样压在底下，她后来贴的照样在上面
        var made = compose(parts, layout: parts.layout, seed: UInt64.random(in: 1...UInt64.max))
        for i in made.indices { made[i].z -= 1000 }
        page.elements = made + mine
        let soft = JournalKit.papers.filter { $0.0 != "深棕" }
        page.paperHex = soft.randomElement()?.1 ?? page.paperHex
    }
}
