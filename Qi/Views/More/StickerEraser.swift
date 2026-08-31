import SwiftUI

/// 擦贴纸。手指抹到哪儿，哪儿就透明。
///
/// 她定的：「可以新增一个橡皮擦的功能，因为有些素材没有扣干净
/// 或者没有扣完整，我干脆自己拿橡皮擦擦擦好了。」
///
/// 她是对的——那 44 张是脚本自动抠的，
/// 总有几张边上带一块纸、或者少了半只翅膀。
/// 与其我再去调阈值（调好这张、调坏那张），不如把橡皮给她。
///
/// ## 擦完存哪儿
///
/// ⚠️ **不改包里那张原图**。包里的是只读的，而且一张原图可能贴了好几处，
/// 改了会牵连别处。擦完的结果**另存成她自己的一张图**（走 `ImageStore`），
/// 那一件元素改指向新的那张。
///
/// 所以：擦坏了就把这一张删掉重贴，原图一直是干净的。
struct StickerEraser: View {

    /// 要擦的那张（包里的资源名，或者她自己那张的文件名）
    let source: UIImage
    /// 擦完了给出去：新图的文件名
    var onDone: (String) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 擦过的那些道。每一道是一串点 + 那一道多粗。
    ///
    /// ⚠️ **存道不存像素**：这样「撤一步」就是把最后一道扔掉，
    /// 不用留一堆图片副本。真正落到像素上是在最后存盘那一下。
    @State private var strokes: [(pts: [CGPoint], size: CGFloat)] = []
    @State private var current: [CGPoint] = []
    @State private var brush: CGFloat = 26
    /// 画布实际多大——手指的坐标要换算成图上的坐标
    @State private var canvas: CGSize = .zero
    @State private var saving = false

    /// 放大了多少倍、挪到哪儿了。
    ///
    /// 她定的：「贴纸不能放大缩小，擦细小的地方很麻烦。」
    ///
    /// ⚠️ **缩放和平移只作用在「看」上，不动那些擦过的道。**
    /// 道存的是**画布坐标**（没缩放时的那一套），
    /// 所以放大擦完再缩回去，位置是对的；
    /// 存盘那一步也不用管当时缩放到了几倍。
    @State private var zoom: CGFloat = 1
    @State private var zoomLive: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panLive: CGSize = .zero

    private var scaleNow: CGFloat { zoom * zoomLive }
    private var panNow: CGSize {
        CGSize(width: pan.width + panLive.width, height: pan.height + panLive.height)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack(spacing: 14) {
                    Text("一根手指抹过去就擦掉，两根手指捏着放大。擦坏了点「撤一步」。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))

                    board

                    HStack(spacing: 10) {
                        Text("笔头")
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))
                        Slider(value: $brush, in: 8...70)
                            .tint(app.settings.accentColor)
                        Text("\(Int(brush))")
                            .font(.app(11, design: .monospaced))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .frame(width: 24)
                    }
                    .padding(.horizontal, 20)

                    HStack(spacing: 12) {
                        if scaleNow > 1.05 {
                            Text(String(format: "%.1f×", scaleNow))
                                .font(.app(11, design: .monospaced))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Button("回到原大") {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    zoom = 1; zoomLive = 1
                                    pan = .zero; panLive = .zero
                                }
                            }
                        }
                        Button("撤一步") {
                            if !strokes.isEmpty { strokes.removeLast() }
                        }
                        .disabled(strokes.isEmpty)
                        Button("全都不擦了") { strokes.removeAll() }
                            .disabled(strokes.isEmpty)
                    }
                    .font(.app(13))
                    .foregroundStyle(app.settings.accentColor)

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }
            .navigationTitle("擦一擦")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("好了") { save() }
                        .fontWeight(.semibold)
                        .disabled(strokes.isEmpty || saving)
                }
            }
        }
    }

    /// 擦的那块板。
    ///
    /// ⚠️ 底下垫一层**棋盘格**：贴纸本来就是透明底，
    /// 在纯色上擦的话「擦掉了」和「本来就是白的」看着一模一样。
    private var board: some View {
        GeometryReader { geo in
            ZStack {
                CheckerBoard()
                Image(uiImage: source)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        // 擦过的地方盖一层「挖掉」的路径。
                        // 这儿只是**给她看**的预览，真正落到像素是在 `save()`。
                        Canvas { ctx, _ in
                            for s in strokes + [(current, brush)] {
                                guard s.pts.count > 1 else { continue }
                                var p = Path()
                                p.move(to: s.pts[0])
                                for pt in s.pts.dropFirst() { p.addLine(to: pt) }
                                ctx.stroke(p, with: .color(.white),
                                           style: StrokeStyle(lineWidth: s.size,
                                                              lineCap: .round,
                                                              lineJoin: .round))
                            }
                        }
                        .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            // ⚠️ 缩放**加在最外面**，而擦的那一笔记的是缩放前的坐标——
            // `v.location` 在被 `scaleEffect` 变换过的视图里，
            // 报回来的仍然是这个视图自己的坐标系（也就是没缩放时那一套）。
            // 所以放大之后擦，道的位置照样是对的，存盘那步一点都不用改。
            .scaleEffect(scaleNow)
            .offset(panNow)
            .contentShape(Rectangle())
            .gesture(
                // 一根手指 = 擦
                DragGesture(minimumDistance: 0)
                    .onChanged { v in current.append(v.location) }
                    .onEnded { _ in
                        if current.count > 1 { strokes.append((current, brush)) }
                        current = []
                    }
            )
            // 两根手指 = 缩放和挪。
            // ⚠️ 走 `simultaneousGesture`：跟上面那条并存，
            // 用 `.gesture` 串起来的话两条会互相抢，表现是「有时候擦、有时候缩」。
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in zoomLive = v.magnification }
                    .onEnded { v in
                        zoom = min(6, max(1, zoom * v.magnification))
                        zoomLive = 1
                        // 缩回 1 倍就把挪过的也归位——
                        // 不然会出现「明明是原始大小，图却在屏幕外」
                        if zoom <= 1.01 { pan = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        // 只有放大了才让挪。1 倍时挪它没有意义，
                        // 而且会跟擦那一笔抢手势。
                        guard scaleNow > 1.05 else { return }
                        panLive = v.translation
                    }
                    .onEnded { v in
                        guard scaleNow > 1.05 else { return }
                        pan = CGSize(width: pan.width + v.translation.width,
                                     height: pan.height + v.translation.height)
                        panLive = .zero
                    }
            )
            .onAppear { canvas = geo.size }
            .onChange(of: geo.size) { _, n in canvas = n }
        }
        .aspectRatio(1, contentMode: .fit)
        // ⚠️ 裁一下：放大之后图会顶出这块地方，
        // 不裁的话会盖到底下的笔头滑块上，手指一碰就误触。
        .clipped()
        .padding(.horizontal, 24)
    }

    /// 把擦的那几道真的落到像素上，存成她自己的一张图。
    private func save() {
        saving = true
        // 手指坐标是在**画布**上量的，图片是按 scaledToFit 摆进去的，
        // 所以要先算出图片在画布里实际占的那块，再换算过去。
        let iw = source.size.width, ih = source.size.height
        guard iw > 0, ih > 0, canvas.width > 0 else { dismiss(); return }
        let scale = min(canvas.width / iw, canvas.height / ih)
        let drawW = iw * scale, drawH = ih * scale
        let offX = (canvas.width - drawW) / 2
        let offY = (canvas.height - drawH) / 2

        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = false
        fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: source.size, format: fmt).image { c in
            source.draw(at: .zero)
            let g = c.cgContext
            // ⚠️ `.clear` 才是「擦成透明」。用白色画等于涂白，
            // 贴到纸上就是一块白疤——那正是她要去掉的东西。
            g.setBlendMode(.clear)
            g.setLineCap(.round)
            g.setLineJoin(.round)
            for s in strokes {
                guard s.pts.count > 1 else { continue }
                g.setLineWidth(s.size / scale)
                g.beginPath()
                for (i, pt) in s.pts.enumerated() {
                    let x = (pt.x - offX) / scale
                    let y = (pt.y - offY) / scale
                    if i == 0 { g.move(to: CGPoint(x: x, y: y)) }
                    else { g.addLine(to: CGPoint(x: x, y: y)) }
                }
                g.strokePath()
            }
        }
        if let name = ImageStore.savePNG(out) {
            onDone(name)
        }
        dismiss()
    }
}

/// 透明底下面垫的那层棋盘格。
struct CheckerBoard: View {
    var square: CGFloat = 10

    var body: some View {
        Canvas { ctx, size in
            let a = Color.black.opacity(0.05)
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : square
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: square, height: square)),
                             with: .color(a))
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}
