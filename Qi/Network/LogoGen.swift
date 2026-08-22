import Foundation
import UIKit

// MARK: - 做一个原创图标
//
// 出处：s1dashu/ip-as-logo-skill。它本身**不是代码，是一套提示词规则**——
// 怎么把一个角色写成一句能画出好图标的话。规则照抄：
//
//   · **4–7 个大形状**拼出一个主体剪影，别堆细节
//   · 圆润、讨喜、一眼认得出的轮廓
//   · **三个语义色**：角色两个 + 背景一个纯色
//   · 背景**降一点饱和度**，让它沉下去、别抢角色
//   · 角色从**左下或右下角**探出来，不居中
//   · 占满画面的 **85–95%**
//   · 每张都是**独立的整图**，不是拼在一起的六宫格
//     （原规则是「一次出六张」，**这一条她改了**，见下面 `one`）
//   · 提示词里**不写设计术语**——写「一只圆圆的、有点困的青蛙」，
//     不写「负空间」「视觉重心」
//
// ## 一件必须说清楚的事
//
// **生成的图当不了真正的 App 图标。** iOS 的备用图标必须在**构建的时候**
// 就打进包里，运行时换不了——这是系统的规矩，绕不过去。
// 所以这一页做出来的图能当头像、能存下来，
// 想真的换 App 图标，得把它给我、放进下一次构建里。

enum LogoGen {

    /// 角色从哪个角探出来。**只有这两个**——照那套规则。
    enum Corner: String, CaseIterable, Identifiable {
        case lowerLeft, lowerRight
        var id: String { rawValue }
        var label: String { self == .lowerLeft ? "左下探出" : "右下探出" }
        var phrase: String {
            self == .lowerLeft
                ? "emerging from the lower-left corner of the square"
                : "emerging from the lower-right corner of the square"
        }
    }

    /// 把她那句大白话，写成一句能画出图标的话。
    ///
    /// **她写什么就用什么**——不替她加形容词。
    /// 那套规则里最要紧的一条就是「别用设计术语」，
    /// 我要是自作主张加一串「极简主义」「高级感」，画出来的反而是通用货。
    static func prompt(_ subject: String, corner: Corner, seed: Int) -> String {
        // 三个语义色：角色两个 + 背景一个。让模型自己选，但**说清楚只能三个**
        var s = """
        A simple cute mascot logo. One single character, built from only \
        4 to 7 large basic rounded shapes, forming one bold readable silhouette. \
        Lovable and friendly. Flat vector style, thick soft shapes, \
        no outlines, no gradients, no texture, no shadow.
        """
        s += " Exactly three colors total: two colors for the character, "
        s += "one solid muted background color with gently lowered saturation."
        s += " The character is " + corner.phrase
        s += ", filling about 85 to 95 percent of the square frame, cropped by the edges."
        s += " Square 1:1 composition. No text, no letters, no watermark, no border."
        s += " Subject: " + subject
        // 六张要长得不一样。给一个变体提示，不是随机噪声——
        // 说「换个姿势/换个配色」比塞一串随机数管用。
        let hints = [
            "Variation: a calm neutral pose.",
            "Variation: slightly tilted head, one small playful detail.",
            "Variation: a different color pairing, same silhouette language."
        ]
        s += " " + hints[seed % hints.count]
        return s
    }

    /// **一次画一张。**
    ///
    /// ⚠️ 原来这儿是「一次出六张」（那套规则是这么写的）。**她说不要**，
    /// 理由很实在：
    ///
    ///   > 一次出六张不满意的、或者终于已经有满意的，就很亏。
    ///
    /// 对。六张是给「一次要挑一批」的人用的，
    /// 她要的是**一张能用的图标**——第二张就够好的时候，
    /// 后面那四张全是白花的钱。
    ///
    /// 所以改成一张一张来：画一张、看一眼、不行再来。
    /// `round` 是她按了第几次，用来换角度和变体——**连着按不会重复**。
    static func one(subject: String,
                    round: Int,
                    provider: Provider,
                    model: String) async throws -> (UIImage, Corner) {
        // 左下、右下轮着来；变体三个一循环。
        // 这样按六次刚好走完原来那六张，但**每一次都是她自己决定要不要按**。
        let corner = Corner.allCases[round % Corner.allCases.count]
        let seed = (round / Corner.allCases.count) % 3
        let p = prompt(subject, corner: corner, seed: seed)
        let img = try await PixelGen.generate(
            prompt: p, reference: nil, provider: provider, model: model)
        return (img, corner)
    }
}
