import SwiftUI

// MARK: - 牌摊在桌上的样子

/// 翻开之后，**按牌阵本来的形状把牌摆出来**。
///
/// 她说的：「塔罗牌排布参考，增添一点新的花样，不然画面太空。」
///
/// ## 为什么要有这一块
///
/// 翻开之后原来只有一条竖的列表：牌 + 一段解释、牌 + 一段解释。
/// 那是**读**出来的结果，不是**摊**出来的结果——
/// 而塔罗这件事一半的意思就在「哪张压着哪张、哪张在上方」这个形状里：
/// 凯尔特十字的第二张是**横着压在第一张上**的，
/// 排成一列的话那层意思整个没了。
///
/// 底下那条列表留着（要读的还是得读），这一块加在它上面。
struct TarotTable: View {

    let cards: [DrawnCard]
    /// 牌阵的名字。按它认形状，认不出就按张数排一排
    let spreadName: String
    var tint: Color = .purple
    /// 点某一张
    var onTap: (DrawnCard) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let slots = Self.layout(spreadName, count: cards.count)
            let w = geo.size.width
            let h = geo.size.height
            // 牌宽跟着张数走：十张的凯尔特十字得比三张的小一圈
            let cw = min(w * 0.17, h * 0.30)
            ZStack {
                velvet
                moonAndStars(in: geo.size)

                ForEach(Array(cards.enumerated()), id: \.element.id) { i, d in
                    let s = i < slots.count ? slots[i] : Slot(0.5, 0.5)
                    Button {
                        onTap(d)
                    } label: {
                        VStack(spacing: 3) {
                            TarotCardFace(card: d.card,
                                          reversed: d.reversed,
                                          width: cw)
                            // 位置名（「过去」「阻碍」…）。
                            // ⚠️ **压着横放那张不写**——两行字会叠在一起。
                            if !d.position.isEmpty, !s.flat {
                                Text(d.position)
                                    .font(.app(8.5))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    // ⚠️ 横放那张要**转 90 度**，不是换个位置。
                    // 凯尔特十字的第二张「阻碍」就是横着压上去的，
                    // 摆正了它就只是第二张牌而已。
                    .rotationEffect(.degrees(s.flat ? 90 : s.tilt))
                    .zIndex(s.flat ? 5 : Double(i))
                    .shadow(color: .black.opacity(0.45), radius: 5, x: 1, y: 4)
                    .position(x: w * s.x, y: h * s.y)
                }
            }
        }
    }

    // MARK: 桌面

    /// 绒布。**一块深紫的底 + 中间一团光**，牌摆上去才像摆在桌上。
    private var velvet: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color(hexString: "3E2358") ?? .purple,
                                 Color(hexString: "1E1230") ?? .black],
                        center: .center, startRadius: 10, endRadius: 320)
                )
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        }
    }

    /// 一弯月和几颗星。
    ///
    /// ⚠️ **位置是定死的，不随机。** 每次翻开都换一处的话，
    /// 同一次占卜截图两次会是两张不同的图——她会以为是花的。
    private func moonAndStars(in size: CGSize) -> some View {
        let stars: [(CGFloat, CGFloat, CGFloat)] = [
            (0.09, 0.14, 1.6), (0.19, 0.31, 1.1), (0.31, 0.09, 1.3),
            (0.63, 0.11, 1.2), (0.78, 0.26, 1.7), (0.91, 0.13, 1.1),
            (0.13, 0.78, 1.2), (0.46, 0.93, 1.0), (0.87, 0.82, 1.5)
        ]
        return ZStack {
            // 月牙：一个圆挖掉另一个圆
            Circle()
                .fill(Color(hexString: "F3E6C4") ?? .yellow)
                .frame(width: size.width * 0.10)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color(hexString: "2A1840") ?? .black)
                        .frame(width: size.width * 0.088)
                        .offset(x: size.width * 0.022,
                                y: -size.width * 0.012)
                }
                .clipShape(Circle())
                .opacity(0.5)
                .position(x: size.width * 0.86, y: size.height * 0.14)

            ForEach(stars.indices, id: \.self) { i in
                let s = stars[i]
                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: s.2, height: s.2)
                    .position(x: size.width * s.0, y: size.height * s.1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 每张摆哪儿

    /// 一张牌在桌上的位置。`x`/`y` 是占整块的百分之几。
    struct Slot {
        var x: Double
        var y: Double
        /// 歪几度。**一点点就够**，歪多了像摔在桌上的
        var tilt: Double = 0
        /// 横着压上去的那张（凯尔特十字的「阻碍」）
        var flat: Bool = false

        init(_ x: Double, _ y: Double, tilt: Double = 0, flat: Bool = false) {
            self.x = x; self.y = y; self.tilt = tilt; self.flat = flat
        }
    }

    /// 牌阵 → 每张摆哪儿。
    ///
    /// ⚠️ 按**名字**认，认不出就排成一排。名字对不上不该整块空掉——
    /// 以后加新牌阵的人只要在这儿补一行，补之前也照样看得见牌。
    static func layout(_ name: String, count: Int) -> [Slot] {
        switch name {
        case "单张":
            return [Slot(0.5, 0.46)]

        case "三张":
            // 过去 → 现在 → 将来。中间那张**略高一点**，读的时候先看它
            return [Slot(0.20, 0.50, tilt: -2),
                    Slot(0.50, 0.44),
                    Slot(0.80, 0.50, tilt: 2)]

        case "抉择":
            // 底下是现状，左右分岔，顶上那张是「你没看到的」
            return [Slot(0.50, 0.76),
                    Slot(0.22, 0.48, tilt: -4),
                    Slot(0.78, 0.48, tilt: 4),
                    Slot(0.50, 0.20)]

        case "关系":
            // 你 —— 你们之间 —— 对方，走向摆在正上方
            return [Slot(0.19, 0.58, tilt: -3),
                    Slot(0.81, 0.58, tilt: 3),
                    Slot(0.50, 0.58),
                    Slot(0.50, 0.20)]

        case "凯尔特十字":
            // 左边一个十字，右边一竖列四张。**这是这个牌阵的全部意思**：
            // 第二张横着压在第一张上，所以它 `flat`。
            return [Slot(0.34, 0.50),              // 现状
                    Slot(0.34, 0.50, flat: true),  // 阻碍（横压）
                    Slot(0.34, 0.82),              // 根源
                    Slot(0.14, 0.50),              // 过去
                    Slot(0.34, 0.18),              // 可能
                    Slot(0.54, 0.50),              // 将来
                    Slot(0.82, 0.86),              // 你自己
                    Slot(0.82, 0.63),              // 外界
                    Slot(0.82, 0.40),              // 期待或恐惧
                    Slot(0.82, 0.17)]              // 结果

        default:
            // 认不出的牌阵：一排摆开，摆不下就折行
            guard count > 0 else { return [] }
            let perRow = count <= 5 ? count : (count + 1) / 2
            let rows = Int(ceil(Double(count) / Double(perRow)))
            return (0..<count).map { i in
                let r = i / perRow
                let c = i % perRow
                let inRow = min(perRow, count - r * perRow)
                let x = Double(c + 1) / Double(inRow + 1)
                let y = rows == 1 ? 0.5 : Double(r + 1) / Double(rows + 1)
                return Slot(x, y)
            }
        }
    }

    /// 这个牌阵摆出来要多高（点）。张数多的要高一些，不然挤成一团。
    static func height(for name: String) -> CGFloat {
        switch name {
        case "单张":       return 190
        case "三张":       return 200
        case "抉择":       return 260
        case "关系":       return 250
        case "凯尔特十字": return 330
        default:          return 230
        }
    }
}
