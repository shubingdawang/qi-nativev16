import SwiftUI

/// 一整套配色。不只是主题色，连纸底、面板、字色都一起换。
///
/// 「家」那套有条军规值得记着：**橘是限量的**——一屏最多出现一处，
/// 发送键、当前选中、或者唯一的主按钮，三选一。
/// 列表、图标、标题、进度条一律不准用橘。要强调就靠字重和面板色，
/// 不靠喷漆。这条一破，整屏就花了。
enum ThemePreset: String, CaseIterable, Identifiable, Codable {
    case original = "original"
    case home = "home"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "原来的"
        case .home:     return "家"
        }
    }

    var note: String {
        switch self {
        case .original: return "跟着主题色走，什么都能染"
        case .home:     return "暖纸底、炭字、橘限量。状态只用四种颜色说话。"
        }
    }
}

/// 「家」那套的色值
enum HomePalette {
    static let paper       = Color(hexString: "FAF9F5")!   // 页面底
    static let panel       = Color(hexString: "F0EEE6")!   // 气泡、卡片、面板
    static let ink         = Color(hexString: "2B2A27")!   // 正文
    static let inkSoft     = Color(hexString: "8A867C")!   // 灰字
    static let orange      = Color(hexString: "C96442")!   // 限量主色
    static let amber       = Color(hexString: "E3A13A")!   // 提醒、闹钟
    static let bodyPink    = Color(hexString: "E8A0B4")!   // 经期、心情
    static let sage        = Color(hexString: "96B08F")!   // 完成、健康、好消息
    static let sageLight   = Color(hexString: "E7EDE2")!   // 打勾标记的底

    // 深色下同一套的位置关系，整体压暗但保持冷暖
    static let paperDark   = Color(hexString: "1C1B19")!
    static let panelDark   = Color(hexString: "26241F")!
    static let inkDark     = Color(hexString: "E8E4DA")!
    static let inkSoftDark = Color(hexString: "938E82")!
}

/// 状态只用四种颜色说话，两种形态：一个点，或者一枚小牌。
///
/// 全 App 就这四种，不再有第五种。看久了会形成条件反射——
/// 绿是好消息，黄是要做的事，粉是她的身体，橘是唯一那件重点。
enum StatusTone {
    case done      // 完成、健康、好消息
    case remind    // 提醒、闹钟
    case body      // 她的身体
    case focus     // 唯一重点，稀有

    var color: Color {
        switch self {
        case .done:   return HomePalette.sage
        case .remind: return HomePalette.amber
        case .body:   return HomePalette.bodyPink
        case .focus:  return HomePalette.orange
        }
    }

    var fill: Color {
        switch self {
        case .done:   return HomePalette.sage.opacity(0.20)
        case .remind: return HomePalette.amber.opacity(0.20)
        case .body:   return HomePalette.bodyPink.opacity(0.22)
        case .focus:  return HomePalette.orange.opacity(0.16)
        }
    }
}

/// 一个小圆点。放在文字前面表示状态。
struct StatusDot: View {
    let tone: StatusTone
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
    }
}

/// 一枚小牌，比如「已完成」「21:00 提醒」「经期 · 第5天」
struct StatusChip: View {
    let tone: StatusTone
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(scheme == .dark ? tone.color : tone.color.opacity(0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tone.fill))
    }
}

// MARK: - 字

/// 字体定死在这几行，别再多。
/// 宋体只在大标题出场，物以稀为贵；正文一律系统无衬线。
enum HomeType {
    /// 页面头：宋体大标题，不加粗——全家的脸
    static func pageTitle(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
    /// 小标题：系统黑体加粗
    static func section(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold)
    }
    /// 正文
    static func body(_ size: CGFloat = 15.5) -> Font {
        .system(size: size)
    }
    /// 说明文字
    static let caption = Font.system(size: 12.5)
    /// 数字一律等宽，竖着排才对得齐
    static func number(_ size: CGFloat = 15.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// 正文行高
    static let lineSpacing: CGFloat = 15.5 * 0.7
}

// MARK: - 手绘图标

/// 手绘感的图标：线宽 1.8、圆头收笔。
/// 用系统图标但统一笔法，比混着 emoji 干净——emoji 在这套里清零。
struct HandIcon: View {
    let name: String
    var size: CGFloat = 17
    var tone: Color? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tone ?? (scheme == .dark
                                      ? HomePalette.inkDark
                                      : HomePalette.ink))
    }
}
