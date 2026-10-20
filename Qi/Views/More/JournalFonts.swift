import SwiftUI
import CoreText

/// 手帐上的中文字体。
///
/// `Font.Design`（serif / rounded / monospaced）只换英文字母，中文一律还是苹方——
/// 所以以前选宋体、黑体、等宽，中文看着一模一样。
/// 这里换成真的中文字体：宋体、楷体、圆体是系统自带、要先下载的那几套（第一次用时自动下，
/// 下好之前先用苹方顶着，下好了自己换上）；黑体就是苹方。
@MainActor
final class JournalFonts: ObservableObject {

    static let shared = JournalFonts()

    /// 下好了、能用的（换一次就让用到它的字重画）
    @Published private(set) var ready: Set<String> = []
    private var asked: Set<String> = []

    /// 键 → 字体的 PostScript 名
    nonisolated static let names: [String: String] = [
        "": "STSongti-SC-Regular",
        "kai": "STKaiti-SC-Regular",
        "round": "STYuanti-SC-Regular"
    ]

    nonisolated static func font(_ key: String, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch key {
        case "sans":
            return .system(size: size, weight: weight)
        case "mono":
            return .system(size: size, weight: weight, design: .monospaced)
        case "type":
            // 打字机：大日期、数字用（系统自带）
            return .custom("AmericanTypewriter-Semibold", fixedSize: size)
        case "label":
            // 小标签：等宽，配着拉开的字距用
            return .custom("Menlo-Regular", fixedSize: size)
        default:
            guard let name = names[key] else { return .system(size: size, weight: weight, design: .serif) }
            if UIFont(name: name, size: size) != nil { return .custom(name, fixedSize: size) }
            Task { @MainActor in JournalFonts.shared.fetch(key) }
            return .system(size: size, weight: weight, design: key == "round" ? .rounded : .serif)
        }
    }

    /// 让系统把这套字体准备好（没下载过就下载）。只问一次
    func fetch(_ key: String) {
        guard let name = Self.names[key], !asked.contains(key) else { return }
        asked.insert(key)
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler([desc] as CFArray, nil) { state, _ in
            if state == .didFinish {
                Task { @MainActor in
                    if UIFont(name: name, size: 12) != nil { JournalFonts.shared.ready.insert(key) }
                }
            }
            return true
        }
    }
}
