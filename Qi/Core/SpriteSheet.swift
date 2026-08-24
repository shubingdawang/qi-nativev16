import UIKit

// MARK: - 一整版图里，自己把每一件抠出来
//
// 她说：「但我不会这样无规则裁切……」
//
// 她说得对，那个活儿不该她干。二十件家具手动裁二十次，
// 还得每次对准边界——这正是计算机该干的事。
//
// ## 怎么找
//
// 她那批图有一个很好的性质：**背景是一整片连通的白，
// 家具是浮在上面的一座座孤岛。**
//
// 于是：
//   ① 从画面外圈往里漫填，把连着外面的白抹成透明（`FurnitureImage` 那一套）
//   ② 剩下的不透明像素做**连通域**，每一座孤岛就是一件家具
//   ③ 每座岛的外接矩形裁下来，就是一张单件图
//
// ## ⚠️ 一件东西可能是好几座岛
//
// 冰箱顶上那个篮子、挂架下面吊着的小瓶子、床上那只猫——
// 它们跟主体之间常常差着一两个像素没接上。
// 直接按连通域切，一件家具会被切成三四块碎片。
//
// 所以分组之前先把图**胖一圈**（膨胀几像素）：
// 差一两个像素的两块会粘上，变成同一座岛；
// 真正隔得远的两件家具中间空着一大片，胖一圈也粘不到一起。
//
// **胖只用来分组，裁的时候用原图**——不然每件都会带一圈毛边。

enum SpriteSheet {

    /// 太小的当噪点扔掉。
    ///
    /// 按整张图的大小按比例算，不写死像素——
    /// 她可能导一张 512 的，也可能导一张 2048 的。
    private static func minArea(_ w: Int, _ h: Int) -> Int {
        max(64, (w * h) / 900)
    }

    /// 把一整版切成一件一件。
    ///
    /// 切不出来（背景不是连通的白、或者整张就是一件）就返回原图那一张，
    /// **不会两手空空**。
    ///
    /// `grow` 是「胖一圈」胖多少像素，**不传就自己按图的大小估**。
    /// 传 0 就是纯连通域：**差一个像素没接上的两块也会分家**——
    /// 「拆开这一块」走的就是这一档。
    static func slice(_ image: UIImage, grow: Int? = nil) -> [UIImage] {
        guard let cg = image.cgImage else { return [image] }
        let w = cg.width, h = cg.height
        guard w > 8, h > 8, w * h <= 6_000_000 else { return [image] }

        // ① 先把连着外圈的白抹掉
        guard let px = FurnitureImage.strippedPixels(cg) else { return [image] }

        // ② 实心像素的掩码
        var solid = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) where px[i * 4 + 3] > 24 { solid[i] = true }

        // ③ 胖一圈**只为了分组**：差一两个像素没接上的两块会粘成一件
        //
        // ⚠️ **这个数以前太大了。** 原来是 `min(w,h)/220`——
        // 一张 1500 见方的图会胖 6 个像素，也就是**相隔 12 像素以内
        // 的两件东西会被当成一件**。她那版整版图里灯和微波炉挨得很近，
        // 于是被粘成了一块（她说的「不是单独切割」）。
        //
        // 现在小一半。宁可切碎一点——切碎了她长按「拆开这一块」的反面
        // 是「合起来」，而**粘在一起是没法从图上分开的**，
        // 只能重切一遍。两种错里，切碎是能补救的那一种。
        let r = grow ?? max(1, min(w, h) / 450)
        var fat = solid
        if r > 0 {
            // ⚠️ **分两趟横竖各胖一次**，别写成里外四层循环。
            //
            // 四层的写法是「每个实心像素往周围 (2r+1)² 个格子刷一遍」——
            // 她那种两千见方的整版图有上百万个实心像素，
            // 乘出来就是几千万到上亿次写，卡在那儿几十秒不动。
            // 她说的「一直在弹正在载入中」就是这个。
            //
            // 方块形状的膨胀是**可分离**的：先横着摊一遍，再竖着摊一遍，
            // 结果跟四层循环一模一样，次数从 (2r+1)² 降到 2(2r+1)。
            var pass = [Bool](repeating: false, count: w * h)
            for y in 0..<h {
                let row = y * w
                for x in 0..<w where solid[row + x] {
                    let lo = max(0, x - r), hi = min(w - 1, x + r)
                    for nx in lo...hi { pass[row + nx] = true }
                }
            }
            for y in 0..<h {
                let row = y * w
                for x in 0..<w where pass[row + x] {
                    let lo = max(0, y - r), hi = min(h - 1, y + r)
                    for ny in lo...hi { fat[ny * w + x] = true }
                }
            }
        }

        // ④ 连通域。用自己的栈，**不用递归**——
        //    一张一千见方的图递归下去会把栈撑爆
        var label = [Int32](repeating: -1, count: w * h)
        // ⚠️ `id` 得留着。**裁的时候要用它把别人家的像素抹掉**——
        // 见下面第 ⑥ 步。以前这儿只留了外接矩形，
        // 于是「哪些像素是这一件的」这条信息算出来又扔了。
        var boxes: [(id: Int32, minX: Int, minY: Int,
                     maxX: Int, maxY: Int, area: Int)] = []
        var stack: [Int] = []

        for start in 0..<(w * h) where fat[start] && label[start] < 0 {
            let id = Int32(boxes.count)
            var box = (minX: w, minY: h, maxX: -1, maxY: -1, area: 0)
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            label[start] = id

            while let i = stack.popLast() {
                let x = i % w, y = i / w
                // 外接矩形按**原图**的实心像素算，胖出来那一圈不算
                if solid[i] {
                    box.area += 1
                    if x < box.minX { box.minX = x }
                    if x > box.maxX { box.maxX = x }
                    if y < box.minY { box.minY = y }
                    if y > box.maxY { box.maxY = y }
                }
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let j = ny * w + nx
                    guard fat[j], label[j] < 0 else { continue }
                    label[j] = id
                    stack.append(j)
                }
            }
            boxes.append((id: id, minX: box.minX, minY: box.minY,
                          maxX: box.maxX, maxY: box.maxY, area: box.area))
        }

        // ⑤ 扔掉噪点，按**从上到下、从左到右**排好——
        //    跟她看图的顺序一致，配对的时候才不用找
        let good = boxes
            .filter { $0.area >= minArea(w, h) && $0.maxX >= $0.minX }
            .sorted { a, b in
                // 同一「行」的算平齐：差不到半件的高度就按左右排
                let band = max(40, h / 24)
                if abs(a.minY - b.minY) > band { return a.minY < b.minY }
                return a.minX < b.minX
            }
        guard !good.isEmpty else { return [image] }

        // ⑥ 裁出来——**只带走属于这一件的像素**
        //
        // ## 她说对了的那件事
        //
        // 「家具都是不规则的，你现在按规则切割，除非家具都各自占一格，
        //   不然不可能切割正确的，总会切割到边上的家具。」
        //
        // 对。图片这个东西**必须是矩形**，这没得商量；
        // 但矩形里装的**内容不必**。以前这儿是 `cropping(to:)` 完事——
        // 一件等距家具的轮廓是斜的菱形，它的外接矩形四个角必然空着，
        // 而旁边那件的一角正好探进来，就一起被带走了。
        // 她那张「床看着像一整个房间」就是这么来的。
        //
        // 现在多做一步：裁完之后**把标号不是这一件的像素抹成透明**。
        // 连通域标号第 ④ 步就算好了，以前算完就扔了。
        //
        // 于是每一块交出去的都是「一件家具 + 一圈透明」，
        // 不管它的轮廓多不规则。
        var out: [UIImage] = []
        for b in good {
            let bw = b.maxX - b.minX + 1
            let bh = b.maxY - b.minY + 1
            guard bw > 0, bh > 0 else { continue }
            var cut = [UInt8](repeating: 0, count: bw * bh * 4)
            for y in 0..<bh {
                let srcRow = (b.minY + y) * w
                let dstRow = y * bw
                for x in 0..<bw {
                    let s = srcRow + b.minX + x
                    // **两个条件都要**：得是实心的（不是被抠掉的背景），
                    // 而且得是这一件的（不是邻居探进来的那一角）
                    guard solid[s], label[s] == b.id else { continue }
                    let so = s * 4, dof = (dstRow + x) * 4
                    cut[dof] = px[so]
                    cut[dof + 1] = px[so + 1]
                    cut[dof + 2] = px[so + 2]
                    cut[dof + 3] = px[so + 3]
                }
            }
            guard let ctx = CGContext(
                data: &cut, width: bw, height: bh,
                bitsPerComponent: 8, bytesPerRow: bw * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let made = ctx.makeImage()
            else { continue }
            out.append(UIImage(cgImage: made, scale: image.scale, orientation: .up))
        }
        return out.isEmpty ? [image] : out
    }
}
