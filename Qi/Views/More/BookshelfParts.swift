import SwiftUI

// MARK: - 书房的几样零件：接着读那张卡、书脊、书架那块板
//
// 样子参考了 Dog-ear（AteIceCream）那套看书 UI 的思路：书脊颜色从封面取、
// 书架能切书脊 / 封面两种摆法、点一本先从架子上抽出来一点再翻开。这里是本机重写的一份。

/// 书脊什么颜色：她挑过就用她的；有封面就从封面取一个主色；都没有按书名算一个定死的色
enum SpineTone {

    nonisolated(unsafe) private static var cache: [String: Color] = [:]

    @MainActor
    static func color(for book: Book) -> Color {
        if !book.spineHex.isEmpty, let c = Color(hexString: book.spineHex) { return c }
        if !book.coverName.isEmpty {
            if let hit = cache[book.coverName] { return hit }
            if let img = ImageStore.thumb(book.coverName, maxPixel: 48), let c = average(img) {
                cache[book.coverName] = c
                return c
            }
        }
        return BookshelfView.spineTone(for: book)
    }

    /// 封面的平均色，压暗一点、收一点饱和度，当书脊不刺眼
    private static func average(_ img: UIImage) -> Color? {
        guard let cg = img.cgImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(0.5, s * 0.85)), brightness: Double(min(0.78, max(0.38, b * 0.9))))
    }

    /// 浅色书脊上字要深色
    static func light(_ c: Color) -> Bool {
        var w: CGFloat = 0
        UIColor(c).getWhite(&w, alpha: nil)
        return w > 0.72
    }

    /// 改书脊颜色时能挑的几种（都低饱和）
    static let choices: [String] = ["C9CF8A", "8FA8A0", "E8E2D2", "7C9CB8", "B07A5A",
                                    "D9C9A8", "6B5D7A", "C98B96", "4F6B5A", "5A606E"]
}

/// 架子上的一本：竖着的书脊，高矮不一。点一下先抽出来一点，再翻开
struct ShelfSpineView: View {
    let book: Book
    let onOpen: () -> Void

    @State private var pulled = false

    private var height: CGFloat {
        let seed = abs(book.id.uuidString.hashValue)
        return 96 + CGFloat(seed % 31)
    }

    var body: some View {
        let tone = SpineTone.color(for: book)
        let ink: Color = SpineTone.light(tone) ? Color(red: 0.35, green: 0.29, blue: 0.22) : .white.opacity(0.95)
        return Text(book.coverTitle)
            .font(.app(11, weight: .semibold, design: .serif))
            .foregroundStyle(ink)
            .lineLimit(nil)
            .frame(width: 15)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
            .frame(width: 27, height: height, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(colors: [tone, tone.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
            )
            // 书脊右边一道暗、顶上一道亮，像一本有厚度的书
            .overlay(alignment: .trailing) {
                Rectangle().fill(.black.opacity(0.10)).frame(width: 3)
            }
            .overlay(alignment: .bottom) {
                if book.progress > 0.01 {
                    Rectangle().fill(ink.opacity(0.5)).frame(width: 27 * book.progress, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .overlay(alignment: .top) {
                if book.shared {
                    Circle().fill(ink.opacity(0.7)).frame(width: 4, height: 4).padding(.top, 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(pulled ? 0.28 : 0.16), radius: pulled ? 8 : 2, x: pulled ? 4 : 1, y: pulled ? 8 : 2)
            .rotationEffect(.degrees(pulled ? -6 : 0), anchor: .bottom)
            .offset(y: pulled ? -14 : 0)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { pulled = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    onOpen()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeOut(duration: 0.2)) { pulled = false }
                    }
                }
            }
    }
}

/// 封面朝外立在架子上的一本
struct ShelfStandingCover: View {
    let book: Book
    let onOpen: () -> Void
    @State private var pulled = false

    var body: some View {
        BookCover(book: book)
            .frame(width: 66, height: 94)
            .rotation3DEffect(.degrees(pulled ? -18 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading)
            .offset(y: pulled ? -8 : 0)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { pulled = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    onOpen()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeOut(duration: 0.2)) { pulled = false }
                    }
                }
            }
    }
}

/// 书架那块板：浅色、有一点厚度和投影
struct ShelfBoard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(colors: scheme == .dark
                                 ? [Color.white.opacity(0.22), Color.white.opacity(0.08)]
                                 : [Color.white.opacity(0.95), Color(red: 0.85, green: 0.83, blue: 0.80)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(height: 10)
            .shadow(color: .black.opacity(0.14), radius: 5, y: 5)
    }
}

/// 一颗小胶囊
struct ShelfChip: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text)
            .font(.app(11))
            .foregroundStyle(Theme.textSoft(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.softFillDeep))
    }
}
