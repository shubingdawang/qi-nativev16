import SwiftUI
import UIKit

/// 裁剪一张图：拖框里面挪位置，拖四个角改大小；可以切成正方形。点「好」交出裁好的图
struct ImageCropView: View {
    let image: UIImage
    let done: (UIImage) -> Void
    let cancel: () -> Void

    @EnvironmentObject private var app: AppState
    /// 框（占显示出来的图的比例，0...1）
    @State private var box = CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)
    @State private var start: CGRect?
    @State private var square = false

    private var upright: UIImage {
        guard image.imageOrientation != .up else { return image }
        return UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
    }

    var body: some View {
        let img = upright
        VStack(spacing: 0) {
            HStack {
                Button("取消") { cancel() }
                Spacer()
                Text("裁剪").font(.app(15, weight: .semibold))
                Spacer()
                Button("好") { done(crop(img)) }.fontWeight(.semibold)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(.white)

            GeometryReader { geo in
                let fit = fitted(img.size, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: img).resizable().frame(width: fit.width, height: fit.height)
                    // 框外压暗
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: fit))
                        p.addRect(rect(in: fit))
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    let r = rect(in: fit)
                    // 框：拖里面挪
                    Rectangle()
                        .stroke(.white, lineWidth: 1.5)
                        .background(Color.white.opacity(0.001))
                        .overlay(grid)
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        .gesture(DragGesture()
                            .onChanged { v in
                                let s = start ?? box
                                if start == nil { start = box }
                                var b = s
                                b.origin.x = min(1 - s.width, max(0, s.minX + v.translation.width / fit.width))
                                b.origin.y = min(1 - s.height, max(0, s.minY + v.translation.height / fit.height))
                                box = b
                            }
                            .onEnded { _ in start = nil })
                    // 四个角：拖着改大小
                    ForEach(0..<4, id: \.self) { corner in
                        handle
                            .position(x: corner % 2 == 0 ? r.minX : r.maxX, y: corner < 2 ? r.minY : r.maxY)
                            .gesture(DragGesture()
                                .onChanged { v in resize(corner, v.translation, fit) }
                                .onEnded { _ in start = nil })
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .padding(20)

            Toggle("正方形", isOn: $square)
                .font(.app(14))
                .foregroundStyle(.white)
                .tint(app.settings.accentColor)
                .padding(.horizontal, 24).padding(.bottom, 28)
                .onChange(of: square) { _, on in if on { makeSquare(img.size) } }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var handle: some View {
        Circle().fill(.white).frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.3), radius: 3)
            .contentShape(Circle().inset(by: -12))
    }

    private var grid: some View {
        GeometryReader { g in
            Path { p in
                for k in 1...2 {
                    let x = g.size.width * CGFloat(k) / 3, y = g.size.height * CGFloat(k) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: g.size.height))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.4), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }

    private func fitted(_ s: CGSize, in area: CGSize) -> CGSize {
        let k = min(area.width / max(1, s.width), area.height / max(1, s.height))
        return CGSize(width: s.width * k, height: s.height * k)
    }

    private func rect(in fit: CGSize) -> CGRect {
        CGRect(x: box.minX * fit.width, y: box.minY * fit.height, width: box.width * fit.width, height: box.height * fit.height)
    }

    private func resize(_ corner: Int, _ t: CGSize, _ fit: CGSize) {
        let s = start ?? box
        if start == nil { start = box }
        let dx = t.width / fit.width, dy = t.height / fit.height
        var x0 = s.minX, y0 = s.minY, x1 = s.maxX, y1 = s.maxY
        if corner % 2 == 0 { x0 = min(x1 - 0.06, max(0, x0 + dx)) } else { x1 = max(x0 + 0.06, min(1, x1 + dx)) }
        if corner < 2 { y0 = min(y1 - 0.06, max(0, y0 + dy)) } else { y1 = max(y0 + 0.06, min(1, y1 + dy)) }
        var b = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        if square {
            // 正方形：按图的真实比例换算，取短的那边
            let aspect = fit.width / max(1, fit.height)
            let side = min(b.width * aspect, b.height)
            let w = side / aspect, h = side
            b = CGRect(x: corner % 2 == 0 ? x1 - w : x0, y: corner < 2 ? y1 - h : y0, width: w, height: h)
        }
        box = b
    }

    private func makeSquare(_ size: CGSize) {
        let aspect = size.width / max(1, size.height)
        let side = min(box.width * aspect, box.height)
        box = CGRect(x: box.minX, y: box.minY, width: side / aspect, height: side)
    }

    private func crop(_ img: UIImage) -> UIImage {
        guard let cg = img.cgImage else { return img }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let r = CGRect(x: box.minX * W, y: box.minY * H, width: box.width * W, height: box.height * H).integral
        guard let c = cg.cropping(to: r) else { return img }
        return UIImage(cgImage: c, scale: img.scale, orientation: .up)
    }
}
