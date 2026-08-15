import SwiftUI

/// 全 App 的图标统一走这里。规矩：
/// 线性、圆角、粗细一致、跟着主题色走，不用任何 emoji。
/// 标题和选项行不配图标，只有入口和动作才配。
enum Icon {
    static let chat        = "bubble.left.and.bubble.right"
    static let workshop    = "square.on.square"
    static let notes       = "book.closed"
    static let settings    = "gearshape"
    static let gallery     = "photo.on.rectangle.angled"
    static let sticker     = "face.smiling"
    static let footprint   = "chart.dots.scatter"
    static let games       = "gamecontroller"
    static let heart       = "heart"
    static let body        = "waveform.path.ecg"
    static let diary       = "text.book.closed"
    static let memory      = "brain"
    static let cycle       = "drop"
    static let tools       = "wrench.and.screwdriver"
    static let model       = "cpu"
    static let send        = "arrow.up"
    static let stop        = "stop.fill"
    static let mic         = "mic"
    static let add         = "plus"
    static let compose     = "square.and.pencil"
    static let close       = "xmark"
    static let refresh     = "arrow.clockwise"
    static let trash       = "trash"
    static let star        = "star"
    static let share       = "square.and.arrow.up"
    static let select      = "checkmark.circle"
    static let pin         = "pin"
    static let search      = "magnifyingglass"
    static let chevron     = "chevron.right"
}

/// 统一的图标样式：细一点、圆头、跟主题色
struct ThemedIcon: View {
    let name: String
    var size: CGFloat = 18
    var weight: Font.Weight = .regular
    var color: Color? = nil

    @EnvironmentObject private var app: AppState

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color ?? app.settings.accentColor)
    }
}

// MARK: - 文件夹图形

/// 手画的文件夹：后面一张浅色纸，前面一片跟主题色走。
/// 相册、表情包这些入口用它，比一个方框好看得多。
struct FolderIcon: View {

    var tint: Color
    var size: CGFloat = 64
    /// 里面露出来的那张"纸"
    var showPaper: Bool = true

    var body: some View {
        ZStack {
            // 后片
            FolderBack()
                .fill(tint.opacity(0.28))

            // 中间露出的纸
            if showPaper {
                RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                    .fill(.white.opacity(0.92))
                    .frame(width: size * 0.62, height: size * 0.44)
                    .offset(y: -size * 0.04)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            }

            // 前片
            FolderFront()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .frame(width: size, height: size * 0.92)
        .shadow(color: tint.opacity(0.25), radius: 8, y: 4)
    }
}

/// 文件夹后面那片（带一个小凸起的标签）
struct FolderBack: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = w * 0.13
        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: 0, y: 0, width: w, height: h),
            cornerSize: CGSize(width: r, height: r),
            style: .continuous
        )
        return p
    }
}

/// 文件夹前面那片，上沿是个平缓的斜坡
struct FolderFront: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let top = h * 0.46          // 前片从这个高度开始
        let r = w * 0.13
        var p = Path()
        p.move(to: CGPoint(x: 0, y: top + h * 0.10))
        // 左上角圆一点
        p.addQuadCurve(to: CGPoint(x: w * 0.10, y: top),
                       control: CGPoint(x: 0, y: top))
        // 上沿的小坡
        p.addLine(to: CGPoint(x: w * 0.40, y: top))
        p.addQuadCurve(to: CGPoint(x: w * 0.52, y: top - h * 0.07),
                       control: CGPoint(x: w * 0.47, y: top - h * 0.07))
        p.addLine(to: CGPoint(x: w - r, y: top - h * 0.07))
        p.addQuadCurve(to: CGPoint(x: w, y: top + h * 0.02),
                       control: CGPoint(x: w, y: top - h * 0.07))
        // 右边下来
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: h),
                       control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: r, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - r),
                       control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}
