import Foundation
import ImageIO
import CoreLocation
import UIKit

// MARK: - 整页风格
//
// 一键换：纸、格线、字色和字体、胶带、照片边框和色调、便签、邮票一起换。
// 东西摆在哪不动，只换样子。思路来自 Toska 的「同页」，这里是本机重写的一份。

struct JournalTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String
    let paper: String
    let pattern: String
    var weave = ""
    let ink: String
    /// 日期、标题这种要跳一下的字
    let dateInk: String
    let tapes: [String]
    let tapePattern: String
    /// 照片边：JournalKit.photoEdges 里的那几种
    let edge: String
    /// 相框：JournalKit.frameStyles 里的那几种
    let frame: String
    let notes: [String]
    let stamp: String
    /// 字体：serif / sans / mono / round
    let font: String
    /// 照片色调：warm / mono / cyan / 空
    let tone: String
    let rope: String

    /// 深色纸（夜航、蓝晒、黑板）
    var dark: Bool { JournalTheme.luma(paper) < 0.45 }

    /// 六位色号的亮度 0~1
    static func luma(_ hex: String) -> Double {
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return 1 }
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255
    }

    static let all: [JournalTheme] = [
        .init(id: "qingmo", name: "青墨素纸", note: "灰白纸、横线、青墨字，留白多",
              paper: "F2F0EA", pattern: "ruled", ink: "2F4A4F", dateInk: "2F4A4F",
              tapes: ["B9C6C8", "D3D8D4"], tapePattern: "plain", edge: "hair", frame: "thin",
              notes: ["EEF0EC", "E3E9E7"], stamp: "5B7579", font: "serif", tone: "", rope: "6E7F80"),
        .init(id: "film", name: "复古胶片", note: "暖褪色、拍立得白边、打字机字",
              paper: "EDE3D1", pattern: "plain", ink: "5A4636", dateInk: "A0715A",
              tapes: ["E3D3B5", "D9C3A0"], tapePattern: "stripe", edge: "white", frame: "",
              notes: ["F4ECDC", "EFE2CB"], stamp: "A0715A", font: "mono", tone: "warm", rope: "8A7356"),
        .init(id: "kraft", name: "牛皮纸", note: "牛皮纸底、白胶带、蓝印泥",
              paper: "D6C29E", pattern: "plain", ink: "3A362E", dateInk: "4A6785",
              tapes: ["F4F0E6", "E8E2D2"], tapePattern: "dash", edge: "white", frame: "wood",
              notes: ["F6F2E8", "EFE7D6"], stamp: "4A6785", font: "serif", tone: "", rope: "6B5844"),
        .init(id: "xuan", name: "宣纸", note: "纤维纸、朱砂日期，安安静静",
              paper: "F3EEE2", pattern: "fiber", ink: "2E2B28", dateInk: "B5483A",
              tapes: ["D9CDB8", "CFC3AE"], tapePattern: "plain", edge: "hair", frame: "thin",
              notes: ["F6F2E8"], stamp: "B5483A", font: "serif", tone: "", rope: "8A7E6A"),
        .init(id: "washi", name: "和纸", note: "樱粉小点、圆角、软胶带",
              paper: "F6E9E8", pattern: "dot", ink: "6B4F55", dateInk: "C98B96",
              tapes: ["E8BCC2", "F0D2D6", "D9C4DE"], tapePattern: "dot", edge: "round", frame: "round",
              notes: ["F7D4D8", "FBE7EA"], stamp: "C98B96", font: "round", tone: "", rope: "C98B96"),
        .init(id: "water", name: "水彩", note: "四角晕开淡水彩",
              paper: "FAF7F0", pattern: "water", ink: "4D5A66", dateInk: "8FAAC6",
              tapes: ["C7D6CF", "D6CFE0"], tapePattern: "wave", edge: "white", frame: "thin",
              notes: ["E3EBF2", "E4EBDE"], stamp: "8FAAC6", font: "serif", tone: "", rope: "9AA7B0"),
        .init(id: "nature", name: "自然提纯", note: "沙、陶、苔藓色，圆润",
              paper: "EAE4D8", pattern: "plain", ink: "55603F", dateInk: "8C9A6E",
              tapes: ["C9A086", "B9C4A0"], tapePattern: "plain", edge: "round", frame: "round",
              notes: ["E4EBDE", "EFE6D6"], stamp: "8C9A6E", font: "round", tone: "", rope: "8C7A5E"),
        .init(id: "academia", name: "学院手抄", note: "旧纸、双线框、暖一点的照片",
              paper: "EFE6D2", pattern: "double", ink: "4A3B2C", dateInk: "7D5A3C",
              tapes: ["D8C9A8"], tapePattern: "plain", edge: "hair", frame: "double",
              notes: ["F4ECDC"], stamp: "7D5A3C", font: "serif", tone: "warm", rope: "6B5844"),
        .init(id: "sketch", name: "手绘草稿", note: "方格本、圆珠笔蓝、虚线框",
              paper: "F7F6F1", pattern: "graph", ink: "34508A", dateInk: "34508A",
              tapes: ["E6DFA8", "D6E0EC"], tapePattern: "check", edge: "dash", frame: "thin",
              notes: ["FFF8C8", "DDE8F5"], stamp: "34508A", font: "round", tone: "", rope: "34508A"),
        .init(id: "mono", name: "单色极简", note: "只有黑白灰，照片去色",
              paper: "F5F5F3", pattern: "plain", ink: "2B2B2B", dateInk: "2B2B2B",
              tapes: ["D6D6D3"], tapePattern: "plain", edge: "hair", frame: "thin",
              notes: ["EDEDEA"], stamp: "555555", font: "sans", tone: "mono", rope: "6B6B6B"),
        .init(id: "receipt", name: "小票", note: "热敏纸、等宽字、一道道虚线",
              paper: "F7F6F2", pattern: "dashrule", ink: "333333", dateInk: "333333",
              tapes: ["DADAD6"], tapePattern: "dash", edge: "", frame: "thin",
              notes: ["F1F0EC"], stamp: "777777", font: "mono", tone: "mono", rope: "777777"),
        .init(id: "cyan", name: "蓝晒", note: "整页普鲁士蓝，照片像晒出来的",
              paper: "3E5876", pattern: "plain", ink: "E6EDF2", dateInk: "E6EDF2",
              tapes: ["9DB1C4", "7F96AE"], tapePattern: "plain", edge: "hair", frame: "thin",
              notes: ["D7E1EA"], stamp: "E6EDF2", font: "serif", tone: "cyan", rope: "C9D6E2"),
        .init(id: "night", name: "夜航", note: "深夜蓝、星点、浅色字",
              paper: "232C3B", pattern: "stars", ink: "E9E2D3", dateInk: "C9B98F",
              tapes: ["5E6B82", "7A7F94"], tapePattern: "spark", edge: "white", frame: "thin",
              notes: ["D6D3E6", "E9E2D3"], stamp: "C9B98F", font: "serif", tone: "", rope: "C9B98F"),
        .init(id: "chalk", name: "黑板", note: "墨绿黑板、粉笔字",
              paper: "34413A", pattern: "chalk", ink: "ECEBE3", dateInk: "E8D8A8",
              tapes: ["C9C3AE", "B8C2B4"], tapePattern: "plain", edge: "white", frame: "thin",
              notes: ["E8E4D2"], stamp: "E8D8A8", font: "round", tone: "", rope: "D8D2BC"),
    ]

    static func find(_ id: String) -> JournalTheme? { all.first { $0.id == id } }

    /// 换成这个风格：纸和每一样东西的样子跟着换，位置不动
    static func apply(_ t: JournalTheme, to page: inout JournalPage, seed: Int = 0) {
        page.themeID = t.id
        page.paperHex = t.paper
        page.paperPattern = t.pattern
        page.paperWeave = t.weave
        var n = seed
        for i in page.elements.indices {
            n += 1
            var e = page.elements[i]
            switch e.kind {
            case .text:
                e.colorHex = (e.emoji == "date" || e.emoji == "title") ? t.dateInk : t.ink
                e.pattern = t.font
            case .quote:
                e.colorHex = t.ink
            case .strip:
                e.colorHex = t.ink
            case .note:
                e.colorHex = t.notes[n % t.notes.count]
            case .tape:
                e.colorHex = t.tapes[n % t.tapes.count]
                e.pattern = t.tapePattern
                e.inkHex = ""
            case .photo:
                e.pattern = t.edge
                e.tone = t.tone
                e.colorHex = (t.edge == "hair" || t.edge == "dash") ? t.ink : "FFFFFF"
            case .frame:
                e.pattern = t.frame
                e.tone = t.tone
            case .stamp:
                e.colorHex = t.stamp
            case .rope:
                e.colorHex = t.rope
            case .sticker:
                // 画出来的那种跟着字色走；实物贴纸和 emoji 自己带颜色，不动
                if !e.pattern.isEmpty && e.assetName.isEmpty { e.colorHex = t.dateInk }
            default:
                break
            }
            page.elements[i] = e
        }
    }
}

// MARK: - 交给他

/// 她交过来的一张照片：图和从原图里读出来的拍摄信息（读不到的就空着，不编）
struct JournalAskPhoto: Codable, Hashable {
    var name: String
    var time: Date?
    var lat: Double?
    var lon: Double?
    /// 地名（有坐标才去问）
    var place = ""
    /// 「f/1.8 · 1/250s · ISO 64 · 26mm」
    var shot = ""

    /// 写成一行：「14:32 · 青岛 · f/1.8 1/250s ISO 64」
    var line: String {
        var bits: [String] = []
        if let time {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            bits.append(f.string(from: time))
        }
        if !place.isEmpty { bits.append(place) }
        if !shot.isEmpty { bits.append(shot) }
        return bits.joined(separator: " · ")
    }
}

struct JournalAsk: Codable, Identifiable, Hashable {
    var id = UUID()
    /// 哪一天（yyyy-MM-dd）
    var dayKey: String
    var photos: [JournalAskPhoto] = []
    var moods: [String] = []
    var note = ""
    var at = Date()
}

enum JournalPhotoInfo {

    /// 「交给他」那几个感觉
    static let moods = ["安安静静的", "复古一点", "热闹一点·多贴点", "第一张放大", "字少一点", "多写点"]

    /// 从原图读拍摄时间、坐标、光圈快门（JPEG、HEIC 都行；截图和聊天软件存的图一般读不到）
    static func read(_ data: Data) -> JournalAskPhoto {
        var out = JournalAskPhoto(name: "")
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return out }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            out.time = f.date(from: s)
        }
        if var la = gps[kCGImagePropertyGPSLatitude] as? Double,
           var lo = gps[kCGImagePropertyGPSLongitude] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { la = -la }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lo = -lo }
            out.lat = la
            out.lon = lo
        }
        var bits: [String] = []
        if let fn = exif[kCGImagePropertyExifFNumber] as? Double {
            bits.append("f/" + trim(fn))
        }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            bits.append(t >= 1 ? trim(t) + "s" : "1/\(Int((1 / t).rounded()))s")
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
            bits.append("ISO \(iso)")
        }
        if let mm = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, mm > 0 {
            bits.append("\(mm)mm")
        }
        out.shot = bits.joined(separator: " ")
        return out
    }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// 有坐标的问一下地名（区 + 街道或地标）。没网、没坐标就空着
    static func place(lat: Double, lon: Double) async -> String {
        let loc = CLLocation(latitude: lat, longitude: lon)
        guard let p = try? await CLGeocoder().reverseGeocodeLocation(loc).first else { return "" }
        let bits = [p.locality ?? p.administrativeArea, p.areasOfInterest?.first ?? p.subLocality ?? p.name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var seen: [String] = []
        for b in bits where !seen.contains(b) { seen.append(b) }
        return seen.joined(separator: "·")
    }
}
