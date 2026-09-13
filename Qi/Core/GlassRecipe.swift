import SwiftUI

// MARK: - 另一套玻璃配方

/// 「三块玻璃的配方」那份参考里的做法，做成**可以跟现在这套换着比**的一档。
///
/// 她说的：
/// > 现在的磨砂我有点不满意，你怕糊代码就存档一下原来的换成她这样的，
/// > 模糊和磨砂都换，玻璃的他更好的话就换，不好就不换，就看哪个更流畅。
///
/// ## 为什么是「多一档」而不是「改掉」
///
/// 「存档」最稳的做法不是把旧代码抄进一个没人调用的文件——那种archive
/// 一个版本之后就烂了（改了别处它编译不过，谁也不会去修）。
/// **让两套都活着、在设置里切**，旧那套就一直是能跑的。
/// 她比完了说留哪个，再删另一个。
///
/// ## 三档怎么对上那份参考
///
///     参考里的        我们的        怎么办
///     毛玻璃（通透亮面）  模糊        换成它：中模糊 + 薄纱渐变 + 顶部内高光
///     磨砂玻璃（乳白哑光） 磨砂        换成它：大模糊 + **厚纱** + 颗粒
///     液态玻璃（会折射）  通透        **不换**——见下面
///
/// ⚠️ **液态那档不换。** 参考里的液态是拿一张内联 SVG 的 `feDisplacementMap`
/// 把背景折弯，那是浏览器的滤镜；而 iOS 26 上我们用的是**系统真的液态玻璃**
/// （`.glassEffect`），比任何仿的都准。拿 CSS 那套去替系统那块，是往回走。
///
/// ⚠️ **`saturate()` 做不了。** 那份配方里 `backdrop-filter: blur() saturate(1.5)`
/// 那个饱和度提升，在 SwiftUI 里没有对应的东西（`Material` 不给调，
/// 而 `.saturation()` 作用在**自己的内容**上，不是背后的画面）。
/// 这一条只能缺着——不是忘了。
enum GlassRecipe {

    /// 磨砂：大模糊 + **厚纱** + 颗粒。
    ///
    /// ⚠️⚠️ **厚纱才是这一档的关键**，不是颗粒。
    ///
    /// 参考里那句说到根上了：
    /// > 深色下如果纱太薄，玻璃颜色会完全被背后内容左右——
    /// > 卡片后面暗就死黑、后面亮就发飘。
    /// > **厚纱（50%~70%）让玻璃有自己的颜色**，才稳。
    ///
    /// 我们现在这一档几乎只有系统材质本身（自己加的白只有 `extra * 0.10`），
    /// 所以它**没有自己的颜色**——她说的「有点不满意」就是这个。
    ///
    /// 浅色照抄那份配方的 55%→42%；深色不能照抄（白纱在深色下是一块灰板），
    /// 换成同样厚的**暗纱**，再补一点白让它还是块玻璃而不是个洞。
    static func veil(dark: Bool, strength: Double) -> LinearGradient {
        let k = min(1, max(0.35, strength))
        if dark {
            return LinearGradient(
                colors: [.black.opacity(0.40 * k), .black.opacity(0.30 * k)],
                startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: [.white.opacity(0.55 * k), .white.opacity(0.42 * k)],
            startPoint: .top, endPoint: .bottom)
    }

    /// 深色下那一点白。没有它，厚暗纱看着是个洞，不是玻璃。
    static func sheen(dark: Bool) -> Color {
        dark ? .white.opacity(0.07) : .clear
    }

    /// 毛玻璃的薄纱：22% → 10%，上亮下沉。
    static func thinVeil(dark: Bool, strength: Double) -> LinearGradient {
        let k = min(1, max(0.35, strength))
        if dark {
            return LinearGradient(
                colors: [.white.opacity(0.10 * k), .white.opacity(0.04 * k)],
                startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: [.white.opacity(0.22 * k), .white.opacity(0.10 * k)],
            startPoint: .top, endPoint: .bottom)
    }

    /// **上缘那一线高光**——`inset 0 1px 0 rgba(255,255,255,.5)`。
    ///
    /// 参考里管它叫「灵魂」：
    /// > 灵魂是那条 `inset 0 1px 0` 的白色内阴影——上缘一线高光，
    /// > 玻璃立刻「薄」起来。
    ///
    /// ⚠️ 这**不是一圈描边**。渐变到 `.center` 就化没，
    /// 所以只有顶上那一线有，侧面和底边一点都没有。
    /// 她定过「气泡不该有边框」，那说的是一圈匀的线——别把这个改成那个。
    static func topLine(dark: Bool) -> LinearGradient {
        LinearGradient(
            colors: [.white.opacity(dark ? 0.22 : 0.50), .white.opacity(0)],
            startPoint: .top, endPoint: .center)
    }
}
