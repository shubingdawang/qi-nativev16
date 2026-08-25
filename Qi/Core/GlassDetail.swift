import SwiftUI
import UIKit

/// 玻璃的边和面。
///
/// ## 她给的两张参考不是同一种东西
///
/// 她特意分开标了：
/// · **模糊玻璃** = 苹果那种毛玻璃（`.ultraThin/thin/regular` 那套）
/// · **磨砂玻璃** = 表面被打毛的那种，**有细密的颗粒**，不是把背后糊掉
///
/// 之前这两档在代码里几乎是同一个东西（都是 material + 一点白），
/// 所以她说「磨砂根本就是一整块，换全黑背景也看不出磨砂质感」。
/// 换黑底看不出来，是因为那一档**压根没有任何表面质感**——
/// 它只是一块半透明的板。
///
/// ## 而她真正看到的那道光，是我加的
///
/// 她说「反倒是像顶上有光打下来」。**那句话精确指到了东西**：
/// `GlassSheen` 是一个椭圆白色渐变，中心压在卡片**上方偏左**、
/// 浅色下白到 0.55，盖在所有三档玻璃上面。
/// 那不是玻璃受光，那是一盏射灯。
///
/// ## 现在按那篇文章的第 4 条重做
///
/// > 边缘一定要有层次：高光、描边、阴影，缺一不可。
/// > 毛玻璃高级不高级，80% 看边。
/// > 一层很淡的白色内高光，表现玻璃受光；
/// > 一层极细的描边，让边界不散；
/// > 一层非常轻的阴影，把卡片从背景里托起来。
/// > 注意，阴影一定要轻，不然就会从「玻璃」变成「悬浮塑料片」。
///
/// ⚠️ 关键词是**轻**。这三层每一层都该是「不盯着看就注意不到」的程度——
/// 上一版那道射灯之所以刺眼，就是因为它是唯一一层，只好使劲。
/// 三层都在的时候，每一层都可以很淡。
// ⚠️ **第三层「很轻的阴影」撤了，而且短期内别再试。**
//
// 上一版把 `.shadow` 挂在 `GlassSurface` 上，结果她说「玻璃完全不对」——
// 一屏卡片全成了灰白平板，壁纸一点都透不上来。
//
// 原因不是阴影难看：**`.shadow` 会强制离屏渲染，而离屏那一下
// 把 `Material` 的背景采样打断了**。系统那块玻璃靠的是
// 「实时读它背后的画面再糊」，一旦被拍进独立图层，它背后什么都没有，
// 只能退化成一块近似的纯色。
//
// 那几个阴影常量也一起删了——**留着就是等着有人再把它加回去**。
// 真要做这一层，得把阴影画在**玻璃外面**（比如底下垫一个挖空了卡片形状的
// 模糊黑块），不能套在玻璃这一层上。那是另一件事，以后单独做。

/// 边缘那两层（高光 + 描边）。阴影不在这儿——
/// 阴影得画在**卡片底下**，而这一层是叠在上面的。
struct GlassEdge: View {

    var radius: CGFloat = Theme.cardRadius
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        ZStack {
            // ① 很淡的白色内高光：**只在边上**，上缘亮、往下几乎没有。
            //
            // ⚠️ 这一层跟上一版那道椭圆射灯的区别是「在哪儿」：
            // 射灯照在**面**上（所以像有盏灯），
            // 这一层只走**边**（所以像玻璃厚度的受光面）。
            // 玻璃的厚度是从边上读出来的，不是从面上。
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(scheme == .dark ? 0.20 : 0.42),
                              location: 0),
                        .init(color: .white.opacity(scheme == .dark ? 0.05 : 0.11),
                              location: 0.45),
                        .init(color: .white.opacity(scheme == .dark ? 0.02 : 0.06),
                              location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
                // 糊掉半个点，边光才是「渗出来的」不是「描上去的」
                .blur(radius: 0.6)

            // ② 极细的描边，让边界不散。
            // 浅色下用暗边（白边贴白底等于没有），深色下用白边。
            shape.strokeBorder(
                scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07),
                lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// 磨砂的那层颗粒。
///
/// ## 为什么是自己生成的，不是一张图
///
/// 仓库是公开的，第三方素材一张都不能进（那等于再分发）。
/// 而颗粒本来就该是随机的，用代码生成比找图更合适：
/// 一块 64×64 的噪点，平铺开来就是一整面磨砂。
///
/// ⚠️ **只生成一次**（`static let`）。
/// 每次画都生成一遍的话，那是每帧四千次随机数 + 一次位图构造——
/// 「小屋特别特别卡」那一轮的教训，同样的错不能在这儿再犯一遍。
///
/// ⚠️ 颗粒要**细**且**淡**。上上一版做过一次颗粒，她说「像撒了一把沙子」——
/// 那次是又粗又重。她这次给的参考图里，颗粒细到要凑近才看得见，
/// 远看只是一层柔和的雾面。所以：scale 用 2（一个噪点半个点大），
/// 透明度压到很低，让它只负责「这块表面不是光滑的」。
enum GlassGrain {

    /// 一小块噪点，平铺用。白色，透明度随机。
    static let tile: UIImage = make()

    private static func make() -> UIImage {
        let n = 64
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        // 定死的种子：每次启动长得一模一样。
        // 随机的颗粒没必要每次都不同，定死了还省一次「为什么这次不一样」的困惑。
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(n * n) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            // 取高位：低位的周期短，直接用会出现肉眼可见的条纹
            let v = Double((seed >> 33) % 256) / 255
            // 预乘 alpha：白色 + 随机透明度 → RGB 三个通道都等于 alpha
            let a = UInt8(v * 30)
            bytes[i * 4 + 0] = a
            bytes[i * 4 + 1] = a
            bytes[i * 4 + 2] = a
            bytes[i * 4 + 3] = a
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: n, height: n,
                               bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: n * 4,
                               space: space, bitmapInfo: info,
                               provider: provider, decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent)
        else { return UIImage() }
        // scale 2：一个噪点半个点，远看是雾面，凑近才是颗粒
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
    }
}

/// 铺在磨砂表面上的那层颗粒。
struct GlassGrainLayer: View {

    var radius: CGFloat = Theme.cardRadius
    /// 浓度。跟着「玻璃浓度」那根滑块走一点点，但上限压得很死。
    var strength: Double = 1

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(uiImage: GlassGrain.tile)
            .resizable(resizingMode: .tile)
            // 深色下颗粒要更淡：白点打在暗面上本来就比打在亮面上显眼
            .opacity((scheme == .dark ? 0.42 : 0.55) * min(1, max(0.3, strength)))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .allowsHitTesting(false)
            // ⚠️ **不加 `blendMode(.overlay)`。**
            // 混合模式配上系统 material 的结果我没法在这台机器上验，
            // 而它有可能整层看不见——那就等于白做，而且是**看不出白做**的那种。
            // 普通叠加的白点在深浅两套底上都一定看得见，先要这个确定性。
    }
}
