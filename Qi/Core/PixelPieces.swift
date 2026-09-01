import SwiftUI
import UIKit

/// 自带家具的第二套：**像素风，跟 clawd 那间屋是同一路**。
///
/// ## 怎么来的
///
/// 她给了一个半成品素材工厂（`pixel-asset-factory-v11`），
/// 转述 ChatGPT 的话是「目前只做到脑子还没做手」。
///
/// 跑了一遍，情况比那句话乐观：**手其实是有的**。
/// 引擎里等距投影、顶／前／侧三面明暗、描边、噪点纹理全都写好了。
/// 真正缺的只有两样：
///   ① 示例还在叫旧类名（`PixelRenderer` → `PixelClusterRenderer`），
///      所以一跑就 ImportError，看着像没做完
///   ② **没有「画哪些东西」的那份清单**——引擎知道怎么画一个盒子，
///      但没人告诉它「一张床是九个盒子、腿在哪儿、被子多厚」
///
/// 补的是第 ② 样，见 `scripts/画家具.py`。**她那个引擎一行没改。**
///
/// ## 为什么要有这一套，明明已经有 Kenney 了
///
/// Kenney 那批是**深色木头的中世纪图书馆**风（而且她想要的暖色居家那套
/// 是 3D 模型，取不出来）。摆进这间奶油色的屋子里会跳。
///
/// 这一套是按她这间屋的配色生成的：暖木、米白、粉、淡蓝。
/// 明暗关系和描边跟 clawd 本人是同一路——**摆在一起像一个世界的**。
///
/// ## 以后要加新的
///
/// 改 `scripts/画家具.py` 里那张 `ITEMS` 表：一件家具就是几个盒子的
/// 坐标和尺寸，写完跑一遍就出图。**不用一行行敲像素**——
/// 屋里原来那些手写的 `"..pp.."` 加一件要摆四十行字符，改个颜色得重打。
enum PixelPieces {

    /// (给她看的名字, 图片资源名)
    static let all: [(String, String)] = [
        ("床", "px_bed"),
        ("沙发", "px_sofa"),
        ("桌子", "px_table"),
        ("椅子", "px_chair"),
        ("书架", "px_shelf"),
        ("衣柜", "px_wardrobe"),
        ("床头柜", "px_nightstand"),
        ("落地灯", "px_lamp"),
        ("盆栽", "px_plant"),
        ("地毯", "px_rug"),
    ]

    /// ⚠️ `NSCache` 不是字典：内存紧张的时候系统会自己清掉几张。
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String) -> UIImage? {
        let key = name as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}
