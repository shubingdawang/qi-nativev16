import SwiftUI

/// 套装卡片上那张小图：clawd 穿着这一整套的样子。
/// 身子照 `scripts/wear_art.py` 里 `body()` 的坐标画，衣服按 `ClawdRig.wearOrder` 一层层叠上去。
struct WearSetPreview: View {
    let pieces: [String]

    private static let skin = Color(red: 0xF2 / 255, green: 0x71 / 255, blue: 0x5F / 255)

    private var ordered: [String] {
        pieces.sorted {
            (ClawdRig.wearOrder.firstIndex(of: ClawdRig.wearSlot($0)) ?? 0)
                < (ClawdRig.wearOrder.firstIndex(of: ClawdRig.wearSlot($1)) ?? 0)
        }
    }

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let u = size.width / 18            // 图纸 18 个单位宽，左上角在 (-1, -1)
                    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                        Path(CGRect(x: (x + 1) * u, y: (y + 1) * u, width: w * u, height: h * u))
                    }
                    for x: CGFloat in [3, 5, 9, 11] { ctx.fill(r(x, 13, 1, 2), with: .color(Self.skin)) }
                    ctx.fill(r(2, 6, 11, 7), with: .color(Self.skin))
                    ctx.fill(r(0, 9, 2, 2), with: .color(Self.skin))
                    ctx.fill(r(13, 9, 2, 2), with: .color(Self.skin))
                    ctx.fill(r(4, 7, 1, 2), with: .color(.black))
                    ctx.fill(r(10, 7, 1, 2), with: .color(.black))
                }
                ForEach(ordered, id: \.self) { id in
                    if let img = FurnitureCatalog.wornImage(of: id) {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.none)
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
