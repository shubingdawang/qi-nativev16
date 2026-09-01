import SwiftUI
import UIKit

/// App 自带的那几件等距家具。
///
/// ## 来源和授权
///
/// **Kenney.nl，CC0 1.0**。图上自己印着「个人、教育、商用都免费，
/// 不需要书面许可，署名／捐赠自愿」——所有授权里最干净的一档，
/// 比 CC BY 还少一层（连署名都不要求）。
/// 来历写在 `Resources/Kenney/家具来历.txt`。
///
/// ## ⚠️ 她看中的那套用不了
///
/// 她看的是 `furniture-kit` 那张预览——暖色、圆润，
/// 床沙发浴缸厨房一整套，正是这间屋子要的形状。
/// **但那个包是 3D 模型**（140 个文件，Category 3D），
/// 我们没有 3D 渲染器，一件都取不出来。
///
/// Kenney 的 **2D 等距**只有 `isometric-miniature` 这一个系列
/// （bases / dungeon / farm / library / prototype），**全是中世纪奇幻风**。
/// 挑得出来最接近「居家」的，是 library 里那些书架、长桌、椅子、地毯、烛台——
/// 凑起来是**一角书房**，不是一个家。
///
/// 所以自带的是「能用的那十五件」，不是「她想要的那一套」。
/// 这个差别得摆在明面上，别让她以为暖色那套忘了扒。
///
/// ## 为什么不复制进她的相册目录
///
/// 这些图**一直待在 App 包里**，不往 `Documents/Images` 里抄一份。
/// 抄的话每台手机都多几百 KB，还会跟着她的备份来回搬——
/// 而它们本来就在每一版 App 里，搬它们没有任何意义。
///
/// 她真的挑中某一件之后，那一件才会被存成她自己的一张图
/// （走 `FurnitureImage.save`，跟她自己导的一样）。
/// **在那之前，它只是一张摆出来给她看的样品。**
enum KenneyPieces {

    /// (给她看的名字, 图片资源名)
    static let all: [(String, String)] = [
        ("书架", "kn_bookcasebooks"),
        ("玻璃书柜", "kn_bookcaseglass"),
        ("宽书架", "kn_bookcasewidebooks"),
        ("带桌书架", "kn_bookcasewidebooksdesk"),
        ("书立", "kn_bookstand"),
        ("长桌", "kn_longtable"),
        ("长桌配椅", "kn_longtablechairs"),
        ("摆好的长桌", "kn_longtabledecorated"),
        ("椅子", "kn_librarychair"),
        ("烛台", "kn_candlestand"),
        ("双烛台", "kn_candlestanddouble"),
        ("陈列柜", "kn_displaycase"),
        ("书陈列柜", "kn_displaycasebooks"),
        ("长地毯", "kn_floorcarpet"),
        ("小地毯", "kn_floorcarpetsmall"),
    ]

    /// ⚠️ `NSCache` 不是字典：内存紧张的时候系统会自己清掉几张。
    /// 素材库那一屏会同时画十几张，用无上限的字典存着，
    /// 翻几次就把内存吃满了。
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
