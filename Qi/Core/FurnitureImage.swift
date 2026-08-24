import UIKit

// MARK: - 她自己的家具图
//
// 她拿 AI 生成了一版等距家具（2:1、光从左上、风格统一，质量很好），
// 问「这样的可以吗」。可以——但直接扔进来有两个坎：
//
//   ① **底是白的。** 不处理的话每件家具带一个白方块。
//   ② 图周围一圈空白，落脚点会飘。
//
// 这一份就管这两件事：**导进来的时候把背景抠掉、把边裁紧。**
// 她只要截一件下来，剩下的不用管。
//
// ## ⚠️ 抠白底为什么不能直接「白的就透明」
//
// 马桶、浴缸、冰箱、床单**本身就是白的**。
// 一刀切的话它们会被挖成空壳——那比留着白底还糟。
//
// 所以走**从边缘往里漫填**：只有**连着画面外圈**的白才算背景。
// 家具内部那些白被家具的轮廓围着，漫不进去，一个像素都不动。
//
// 这就是「白底」和「白家具」的全部区别：**前者连着外面，后者被围着。**

enum FurnitureImage {

    /// 认成背景的白有多白。
    ///
    /// 230 是留了余地的：AI 生成的白底常常不是纯 255，
    /// 边缘还会有一圈灰灰的抗锯齿。卡太死的话会留一圈脏边。
    private static let whiteFloor: UInt8 = 228
    /// 三个通道之间最多差多少还算「灰白」。
    /// 差得多说明它是有颜色的，那就不是背景
    private static let neutralSpan: Int = 18

    /// 抠掉背景，把像素交出来（RGBA，一像素四个字节）。
    ///
    /// **切整版那边也要用这一份**（`SpriteSheet`），所以单独拎出来——
    /// 抄两份的话，「什么算背景」这条规矩迟早在两处长歪。
    static func strippedPixels(_ cg: CGImage) -> [UInt8]? {
        let w = cg.width, h = cg.height
        guard w > 1, h > 1, w * h <= 6_000_000 else { return nil }

        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &px, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // ── 从外圈往里漫填，只抹掉连着外面的白 ──────────────
        //
        // 用自己的栈，不用递归：一张 1024×1024 的图递归下去会把栈撑爆。
        var seen = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        stack.reserveCapacity(w * 2 + h * 2)

        func isBG(_ i: Int) -> Bool {
            let o = i * 4
            let r = Int(px[o]), g = Int(px[o + 1]), b = Int(px[o + 2])
            let a = px[o + 3]
            if a < 8 { return true }                      // 本来就透明
            guard px[o] >= whiteFloor, px[o + 1] >= whiteFloor,
                  px[o + 2] >= whiteFloor else { return false }
            // 够白，还得够「灰」——偏色的浅色是家具，不是底
            let hi = max(r, max(g, b)), lo = min(r, min(g, b))
            return hi - lo <= neutralSpan
        }

        for x in 0..<w {
            stack.append(x)                   // 上边
            stack.append((h - 1) * w + x)     // 下边
        }
        for y in 0..<h {
            stack.append(y * w)               // 左边
            stack.append(y * w + w - 1)       // 右边
        }

        while let i = stack.popLast() {
            guard i >= 0, i < w * h, !seen[i], isBG(i) else { continue }
            seen[i] = true
            px[i * 4 + 3] = 0                 // 抹成透明
            let x = i % w, y = i / w
            if x > 0     { stack.append(i - 1) }
            if x < w - 1 { stack.append(i + 1) }
            if y > 0     { stack.append(i - w) }
            if y < h - 1 { stack.append(i + w) }
        }
        return px
    }

    /// 把一张图收拾成能直接摆进屋里的样子：**抠背景 + 裁紧**。
    ///
    /// 抠不动就原样返回——**宁可留个白底，也不能把她的图弄坏**。
    static func prepare(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width, h = cg.height
        guard var px = strippedPixels(cg) else { return image }
        guard let ctx = CGContext(
            data: &px, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }

        // ── 裁紧：把四周剩下的空白切掉 ──────────────────────
        //
        // 不裁的话每件家具都带着一圈看不见的边，
        // 摆到格子上会**整体偏移**——而且每件偏得还不一样。
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }   // 整张都空，别动

        guard let out = ctx.makeImage() else { return image }
        let crop = CGRect(x: minX, y: minY,
                          width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cut = out.cropping(to: crop) else {
            return UIImage(cgImage: out, scale: image.scale, orientation: .up)
        }
        return UIImage(cgImage: cut, scale: image.scale, orientation: .up)
    }

    /// 收拾好之后存下来，返回文件名。
    ///
    /// ⚠️ **必须存 PNG**。`ImageStore.save` 走的是 JPEG，
    /// 而 JPEG 没有透明通道——刚抠干净的背景会被填回白色，
    /// 白忙一场。
    static func save(_ image: UIImage) -> String? {
        let fixed = prepare(image)
        guard let data = fixed.pngData() else { return nil }
        return ImageStore.save(data: data, ext: "png")
    }
}
