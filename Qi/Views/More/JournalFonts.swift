import SwiftUI
import CoreText

/// 手帐上的中文字体。
///
/// `Font.Design`（serif / rounded / monospaced）只换英文字母，中文一律还是苹方——
/// 所以以前选宋体、黑体、等宽，中文看着一模一样。
/// 这里换成真的中文字体：宋体、楷体、圆体是系统提供、要先下载的那几套
/// （第一次用时自动下，下好之前先用苹方顶着，下好了自己换上）；黑体就是苹方。
///
/// ⚠️ 系统下载的字体**每次启动都要重新启用一遍**才认得出来（下过的不会再下，很快）：
/// 所以下好过的记在 UserDefaults 里，App 一打开就挨个启用。
@MainActor
final class JournalFonts: ObservableObject {

    static let shared = JournalFonts()

    enum Status: Equatable {
        case idle
        case loading(Double)
        case ready
        case failed(String)
    }

    /// 每套字体现在怎么样（换一次就让用到它的字重画）
    @Published private(set) var status: [String: Status] = [:]

    /// 键 → 字体的 PostScript 名
    nonisolated static let names: [String: String] = [
        "": "STSongti-SC-Regular",
        "kai": "STKaiti-SC-Regular",
        "round": "STYuanti-SC-Regular"
    ]

    /// 系统实际给的名字（下好以后以它为准）
    private nonisolated(unsafe) static var resolved: [String: String] = [:]
    private static let doneKey = "journalFontsReady"

    /// 要下载的那几套：键和显示的名字
    static let downloadable: [(String, String)] = [("", "宋体"), ("kai", "楷体"), ("round", "圆体")]

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
            let real = resolved[key] ?? name
            if UIFont(name: real, size: size) != nil { return .custom(real, fixedSize: size) }
            Task { @MainActor in JournalFonts.shared.fetch(key) }
            return .system(size: size, weight: weight, design: key == "round" ? .rounded : .serif)
        }
    }

    func state(_ key: String) -> Status {
        if let s = status[key] { return s }
        if let name = Self.names[key], UIFont(name: Self.resolved[key] ?? name, size: 12) != nil { return .ready }
        return .idle
    }

    /// App 一打开：以前下好过的重新启用
    func activateSaved() {
        let done = UserDefaults.standard.stringArray(forKey: Self.doneKey) ?? []
        for k in done { fetch(k) }
    }

    /// 让系统把这套字体准备好（没下载过就下载）。force = 失败了再试一次
    func fetch(_ key: String, force: Bool = false) {
        guard let name = Self.names[key] else { return }
        switch status[key] {
        case .loading?, .ready?: return
        case .failed?: if !force { return }
        default: break
        }
        if UIFont(name: Self.resolved[key] ?? name, size: 12) != nil {
            status[key] = .ready
            return
        }
        status[key] = .loading(0)
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler([desc] as CFArray, nil) { state, param in
            let info = param as NSDictionary
            switch state {
            case .downloading:
                let pct = (info[kCTFontDescriptorMatchingPercentage as String] as? NSNumber)?.doubleValue ?? 0
                Task { @MainActor in JournalFonts.shared.status[key] = .loading(pct / 100) }
            case .didFailWithError:
                let err = (info[kCTFontDescriptorMatchingError as String] as? NSError)?.localizedDescription ?? "未知错误"
                Task { @MainActor in JournalFonts.shared.status[key] = .failed(err) }
            case .didFinish:
                // 系统给回来的那个（名字以它为准）
                var real = name
                if let list = info[kCTFontDescriptorMatchingResult as String] as? [CTFontDescriptor], let d = list.first,
                   let ps = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String {
                    real = ps
                }
                Task { @MainActor in
                    let fonts = JournalFonts.shared
                    if UIFont(name: real, size: 12) != nil {
                        JournalFonts.resolved[key] = real
                        fonts.status[key] = .ready
                        var done = UserDefaults.standard.stringArray(forKey: JournalFonts.doneKey) ?? []
                        if !done.contains(key) { done.append(key); UserDefaults.standard.set(done, forKey: JournalFonts.doneKey) }
                    } else if case .failed? = fonts.status[key] {
                        // 已经记了失败原因
                    } else {
                        fonts.status[key] = .failed("系统没有提供这套字体")
                    }
                }
            default:
                break
            }
            return true
        }
    }
}

/// 字体那一排下面的一行：要下载的那几套现在怎么样，失败了能重试
struct JournalFontStatusRow: View {
    @ObservedObject private var fonts = JournalFonts.shared
    @Environment(\.colorScheme) private var scheme
    /// 只显示这一套（当前选的）
    let key: String

    var body: some View {
        if let label = JournalFonts.downloadable.first(where: { $0.0 == key })?.1 {
            HStack(spacing: 6) {
                switch fonts.state(key) {
                case .idle:
                    Image(systemName: "arrow.down.circle")
                    Text(label + "需要下载，选中后自动开始")
                case .loading(let p):
                    ProgressView().controlSize(.mini)
                    Text(label + (p > 0 ? "下载中 \(Int(p * 100))%" : "准备下载…"))
                case .ready:
                    Image(systemName: "checkmark.circle")
                    Text(label + "已就绪")
                case .failed(let why):
                    Image(systemName: "exclamationmark.circle")
                    Text(label + "下载失败：" + why)
                        .lineLimit(1)
                    Button("重试") { fonts.fetch(key, force: true) }
                        .font(.app(11, weight: .semibold))
                }
            }
            .font(.app(10.5))
            .foregroundStyle(Theme.textMuted(scheme))
            .padding(.horizontal, 14)
            .onAppear { fonts.fetch(key) }
        }
    }
}
