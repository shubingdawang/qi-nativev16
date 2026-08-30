import SwiftUI

/// 一个字一个颜色、一个字一个大小的那种文字块。
///
/// 她要的：「可以每个字单独点击颜色选，点击颜色后打的字就是这个颜色，
/// 然后字体可以每个字都自由缩放。」
///
/// ## 为什么要单独写一个排版
///
/// 逐字上色就得把一句话拆成一个个 `Text`。而一排 `HStack` 是不会换行的——
/// 写长一点就直接顶出纸外面去了。
///
/// SwiftUI 自带的 `Layout` 能自己算换行，所以这儿写一个最小的流式排版：
/// **一个个往右摆，摆不下就换一行。** 字号不一样也不怕，
/// 每一行的高度按那一行里最高的那个字算。
///
/// ⚠️ 只在**真的逐字设过**的时候才走这条路（见 `hasPerChar`）。
/// 没设过的还是一个 `Text` 画完——那条路快得多，
/// 而且换行、断词、标点避头尾全是系统在管，比我们算得好。
struct FlowRow: Layout {

    var spacing: CGFloat = 0
    var lineGap: CGFloat = 2
    /// 换行的时候按这个宽度算
    var maxWidth: CGFloat = 220

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let limit = min(proposal.width ?? maxWidth, maxWidth)
        var x: CGFloat = 0, y: CGFloat = 0
        var lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > limit {
                widest = max(widest, x - spacing)
                y += lineH + lineGap
                x = 0; lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: max(0, widest), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let limit = min(proposal.width ?? maxWidth, maxWidth)
        var x: CGFloat = 0, y: CGFloat = 0
        var lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > limit {
                y += lineH + lineGap
                x = 0; lineH = 0
            }
            // ⚠️ 底对齐，不是顶对齐。
            // 大小不一的字混排的时候，人眼认的是**底下那条线**——
            // 顶对齐会让小字浮在半空中，像打错了。
            v.place(at: CGPoint(x: bounds.minX + x,
                                y: bounds.minY + y + lineH),
                    anchor: .bottomLeading,
                    proposal: .unspecified)
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

/// 手帐上那一块字。逐字设过就一个字一个字画，没设过就整块画。
struct JournalCharText: View {

    let element: JournalElement
    var base: CGFloat = 17
    var weight: Font.Weight = .medium
    var design: Font.Design = .serif
    var maxWidth: CGFloat = 220
    /// 编辑的时候点中的是第几个字。`nil` = 不在编辑
    var focus: Int?
    var onTapChar: ((Int) -> Void)?

    var body: some View {
        if element.hasPerChar || onTapChar != nil {
            let chars = Array(element.text)
            FlowRow(maxWidth: maxWidth) {
                ForEach(chars.indices, id: \.self) { i in
                    let ch = chars[i]
                    // 换行符自己不占位置，但要让排版断在这儿——
                    // 塞一个跟整行一样宽的透明块，下一个字自然被挤到下一行。
                    if ch == Self.br {
                        Color.clear.frame(width: maxWidth, height: 1)
                    } else {
                        Text(String(ch))
                            .font(.app(base * element.sizeAt(i),
                                       weight: weight, design: design))
                            .foregroundStyle(element.inkAt(i))
                            .background {
                                if focus == i {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.22))
                                        .padding(-1)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onTapChar?(i) }
                    }
                }
            }
        } else {
            // 快路：没逐字设过就照旧一个 Text 画完。
            // 换行、断词、标点避头尾全归系统管，比我们算得好。
            Text(element.text)
                .font(.app(base, weight: weight, design: design))
                .foregroundStyle(element.color)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth)
        }
    }

    /// ⚠️ 换行走常量。反斜杠经脚本改动会被吃掉一层、字符串就跨行了。
    private static let br: Character = "\n"
}
