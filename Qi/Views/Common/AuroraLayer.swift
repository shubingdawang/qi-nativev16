import SwiftUI
import UIKit

// MARK: - 背景里那层会飘的光

/// 一层慢慢飘的光。**全 App 唯一的主效果。**
///
/// ## 它被删过一次，这是第二版
///
/// 她当时自己做完了对照实验：
/// 「我将背景里的光选项关闭，左侧栏就快了不少。把这个功能整个删掉吧。」
///
/// 现在她又问：「左侧栏不卡了，但是我喜欢之前那个效果，
/// 还有其他方法不卡顿的把那个效果拿回来吗。」
///
/// 有。**卡的不是光，是画光的方式。** 上一版有两笔硬开销：
///
///     .blendMode(.overlay / .screen)   每一帧都得把底下已经画好的读回来再算
///     三团实时的 RadialGradient        每一帧都得重新求值
///
/// 而 `WallpaperBackground` 是全 App 每一页的底，侧栏开合那一下**每帧都在重画背景**。
/// 于是每帧一次全屏离屏合成 + 三次渐变求值——那才是她感觉到的那一下顿。
///
/// ## 这一版怎么做的
///
/// **① 三团光只画一次，烤成一张图。** 之后每一帧只是把这张图贴上去，
/// GPU 上一个带纹理的四边形，跟贴壁纸一个价。尺寸按屏幕的四分之一烤
/// （见 `Self.shrink`）——渐变本来就是软的，放大四倍看不出来，
/// 而位图小十六倍。
///
/// **② 不再用混合模式。** 换成普通叠加，照片那一档把浓度调高补回来。
/// 代价是照片壁纸上比原来含蓄一点；换来的是**零离屏合成**。
///
/// **③ 飘还是飘的。** 动的只有整张图的 `offset` 和 `scaleEffect`——
/// 那是 GPU 上一次变换，不重新布局也不重新求值。
/// 上一版那一下贵，贵在「变换 + 混合模式」凑在一起：
/// 一变换就得重新合成一次全屏。现在没有混合模式了，变换就是白来的。
///
/// ⚠️ **别把 `.blendMode` 加回来。** 加回来就等于把那一顿原样请回来。
/// 想让它在照片上更显眼，调 `punch`，不要调混合方式。
struct AuroraLayer: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    /// 关掉就一层都不画。
    ///
    /// ⚠️ **默认关着。** 她删过它一次，再回来该由她自己开，
    /// 而不是升个级又自己冒出来。
    @AppStorage("auroraOn") private var on = false

    /// 系统里开了「减弱动态效果」就不飘。会飘的背景正是那个开关想关掉的东西。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drift = false

    var body: some View {
        if on {
            GeometryReader { geo in
                let img = Self.baked(size: geo.size,
                                     accent: app.settings.accentColor,
                                     dark: scheme == .dark,
                                     punch: punch)
                Image(uiImage: img)
                    .resizable()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(x: drift ? geo.size.width * 0.06 : -geo.size.width * 0.06,
                            y: drift ? geo.size.height * 0.04 : -geo.size.height * 0.04)
                    .scaleEffect(drift ? 1.06 : 1)
                    .animation(reduceMotion ? nil
                               : .easeInOut(duration: 40)
                                   .repeatForever(autoreverses: true),
                               value: drift)
                    .onAppear { drift = true }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    /// 底下铺的是不是一张照片。照片那一档要浓一点，不然整个被照片吃掉。
    private var overPhoto: Bool {
        guard !app.settings.preset.usesGradient,
              !app.settings.preset.ownsBackground else { return false }
        return app.settings.wallpaperMode != "solid"
            && app.settings.wallpaper(scheme) != nil
    }

    /// 光的浓度。
    ///
    /// ⚠️ 比上一版高：上一版靠 `.overlay` 顺着照片的明暗走，
    /// 一点点就够看；现在是普通叠加，得实打实地浓一些。
    private var punch: Double { overPhoto ? 2.4 : 1.4 }

    // MARK: 烤那张图

    /// 烤出来的图缩到屏幕的几分之一。
    ///
    /// ⚠️ 渐变是软的，放大四倍看不出台阶，而位图小十六倍——
    /// 一张三百来 KB 的全屏位图变成二十来 KB。
    private static let shrink: CGFloat = 4

    /// 烤好的那张放着，别每次重画都重烤一遍。
    ///
    /// ⚠️ 按「多大 + 什么颜色 + 深浅 + 多浓」记。这四样任何一样变了
    /// 都得重烤——只按尺寸记的话，她换了主题色，光还是老颜色。
    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor
    static func baked(size: CGSize, accent: Color,
                      dark: Bool, punch: Double) -> UIImage {
        let w = max(1, size.width / shrink)
        let h = max(1, size.height / shrink)
        let key = String(format: "%.0fx%.0f|%@|%d|%.2f",
                         w, h, UIColor(accent).description, dark ? 1 : 0, punch)
        if let hit = cache[key] { return hit }

        let other = companion(accent)
        let r = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = r.image { ctx in
            let c = ctx.cgContext
            blob(c, UIColor(accent), 0.16 * punch,
                 CGPoint(x: w * 0.30, y: h * 0.22), w * 1.15)
            blob(c, UIColor(other), 0.13 * punch,
                 CGPoint(x: w * 0.80, y: h * 0.38), w * 1.0)
            blob(c, UIColor(accent), 0.10 * punch,
                 CGPoint(x: w * 0.50, y: h * 0.82), w * 1.3)
        }
        cache[key] = img
        return img
    }

    /// 一团光：中间最浓，到边上化开。
    ///
    /// ⚠️ 走 `CGGradient` 画，**不是 `blur`**。软边是渐变自己的事，
    /// 高斯模糊那种每一帧都要重算——挂在全屏背景上等于一直烧电。
    /// 她这是随身带一整天的 App，好看不能拿续航换。
    private static func blob(_ c: CGContext, _ color: UIColor,
                             _ peak: Double, _ at: CGPoint, _ size: CGFloat) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [color.withAlphaComponent(CGFloat(peak)).cgColor,
                      color.withAlphaComponent(0).cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: cs, colors: colors,
                                 locations: [0, 1]) else { return }
        c.drawRadialGradient(g, startCenter: at, startRadius: 0,
                             endCenter: at, endRadius: size / 2,
                             options: [])
    }

    /// 陪衬那一团的颜色：把强调色在色相上挪开一点。
    /// **同一个色相三团 = 一块糊掉的色斑**；挪开之后才有层次。
    static func companion(_ c: Color) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double((h + 0.13).truncatingRemainder(dividingBy: 1)),
                     saturation: Double(min(1, s * 0.9)),
                     brightness: Double(b))
    }
}
