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
    static func slice(_ image: UIImage) -> [UIImage] {
        guard let cg = image.cgImage else { return [image] }
        let w = cg.width, h = cg.height
        guard w > 8, h > 8, w * h <= 6_000_000 else { return [image] }

        // ① 先把连着外圈的白抹掉
        guard var px = FurnitureImage.strippedPixels(cg) else { return [image] }

        // ② 实心像素的掩码
        var solid = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) where px[i * 4 + 3] > 24 { solid[i] = true }

        // ③ 胖一圈**只为了分组**：差一两个像素没接上的两块会粘成一件
        let r = max(2, min(w, h) / 220)
        var fat = solid
        for y in 0..<h {
            for x in 0..<w where solid[y * w + x] {
                for dy in -r...r {
                    let ny = y + dy
                    guard ny >= 0, ny < h else { continue }
                    for dx in -r...r {
                        let nx = x + dx
                        guard nx >= 0, nx < w else { continue }
                        fat[ny * w + nx] = true
                    }
                }
            }
        }

        // ④ 连通域。用自己的栈，**不用递归**——
        //    一张一千见方的图递归下去会把栈撑爆
        var label = [Int32](repeating: -1, count: w * h)
        var boxes: [(minX: Int, minY: Int, maxX: Int, maxY: Int, area: Int)] = []
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
            boxes.append(box)
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

        // ⑥ 裁出来
        guard let ctx = CGContext(
            data: &px, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let whole = ctx.makeImage()
        else { return [image] }

        var out: [UIImage] = []
        for b in good {
            let rect = CGRect(x: b.minX, y: b.minY,
                              width: b.maxX - b.minX + 1,
                              height: b.maxY - b.minY + 1)
            guard let cut = whole.cropping(to: rect) else { continue }
            out.append(UIImage(cgImage: cut, scale: image.scale, orientation: .up))
        }
        return out.isEmpty ? [image] : out
    }
}
