import SwiftUI

// MARK: - 手帐：他也看得见的那一半
//
// 出处：KKarsyline/shared-page。它做的是一本「你和 AI 一起管的日历」，
// 而**整份东西里最要紧的一条**是这个：
//
//   > 手机把每一天渲染成一张 PNG，AI 看到的就是她屏幕上那一页——
//     贴纸、照片、便签，摆在哪儿就是哪儿。
//
// 为什么这一条是关键：手帐**本来就不是文字**。
// 把它转述成「今天贴了三张贴纸、写了两行字」，等于把一幅拼贴念成一张清单——
// 歪着贴的那张邮票、压在照片角上的那道胶带、故意留白的右下角，全没了。
// 那些才是她做这一页的理由。
//
// 所以这儿走同一条路：**把她那一页原样画成一张图递给他**，
// 另外附一份文字清单当索引（他要引用某一段字的时候用得上）。
//
// ⚠️ 这个文件里的 `JournalElementView` 就是**编辑页在用的那个渲染器**，
// 不是另画一遍。**必须是同一份**——两份迟早会长歪，
// 那时候他看到的就不再是她看到的了，这套东西的意义也就没了。

/// 一个元素长什么样。编辑页和快照都用它。
struct JournalElementView: View {

    let e: JournalElement

    init(_ e: JournalElement) { self.e = e }

    var body: some View {
            switch e.kind {
            case .text:
                Text(e.text)
                    .font(.app(17, weight: .medium, design: .serif))
                    .foregroundStyle(e.color)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 220)

            case .tape:
                // 胶带：半透明一条，两头是撕开的毛边
                Rectangle()
                    .fill(e.color.opacity(0.62))
                    .frame(width: 110, height: 26)
                    .overlay {
                        // 撕口那两道
                        HStack {
                            Rectangle().fill(.white.opacity(0.25)).frame(width: 3)
                            Spacer()
                            Rectangle().fill(.white.opacity(0.25)).frame(width: 3)
                        }
                    }

            case .sticker:
                Text(e.emoji).font(.app(34))

            case .stamp:
                // 邮票：锯齿边靠一圈白点做出来
                Text(e.emoji.isEmpty ? "📮" : e.emoji)
                    .font(.app(26))
                    .frame(width: 54, height: 62)
                    .background {
                        ZStack {
                            Rectangle().fill(Color(hexString: "F6F2E8")!)
                            Rectangle()
                                .strokeBorder(e.color.opacity(0.5),
                                              style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        }
                    }

            case .clip:
                // 夹子：一个圆角小方块加一道内线
                RoundedRectangle(cornerRadius: 3)
                    .fill(e.color)
                    .frame(width: 20, height: 30)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                            .padding(4)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)

            case .note:
                Text(e.text)
                    .font(.app(13))
                    .foregroundStyle(Color(hexString: "3A362E")!)
                    .padding(10)
                    .frame(width: 110, alignment: .topLeading)
                    .frame(minHeight: 90, alignment: .topLeading)
                    .background(e.color)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)

            case .photo:
                if let img = ImageStore.load(e.imageName) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipped()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                }

            case .frame:
                // 拍立得：白框，底下留一条写字的地方
                VStack(spacing: 0) {
                    if let img = ImageStore.load(e.imageName) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 116, height: 116).clipped()
                    } else {
                        Rectangle().fill(Color(hexString: "DDD8CE")!)
                            .frame(width: 116, height: 116)
                            .overlay {
                                Text("点两下贴图")
                                    .font(.app(10))
                                    .foregroundStyle(Color(hexString: "8A8378")!)
                            }
                    }
                    Text(e.text)
                        .font(.app(10))
                        .foregroundStyle(Color(hexString: "6B655A")!)
                        .frame(width: 116, height: 26)
                }
                .padding(7)
                .background(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)

            case .quote:
                // 摘句：带引号，底下写是谁说的
                VStack(alignment: .leading, spacing: 5) {
                    Text("「" + e.text + "」")
                        .font(.app(14, design: .serif))
                        .foregroundStyle(e.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if !e.who.isEmpty {
                        Text("—— " + e.who)
                            .font(.app(10))
                            .foregroundStyle(e.color.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: 190)
                .padding(10)
                .background {
                    Rectangle().fill(Color.white.opacity(0.42))
                }
            }
    }
}

// MARK: - 一整页（不带任何交互）

/// 一页手帐的**纯画面**。编辑页那些拖拽、选中框、虚线都不在这儿——
/// 快照要的就是「她看到的样子」，不该带上编辑器的脚手架。
struct JournalCanvas: View {

    let page: JournalPage
    /// 画多大。快照用固定尺寸，屏幕上用实际尺寸。
    var size: CGSize

    var body: some View {
        ZStack {
            (Color(hexString: page.paperHex) ?? Color(hexString: "F3E9D8")!)
                .overlay { GrainOverlay(opacity: 0.05) }

            ForEach(page.elements.sorted { $0.z < $1.z }) { e in
                JournalElementView(e)
                    .scaleEffect(e.scale)
                    .rotationEffect(.degrees(e.angle))
                    .position(x: e.x * size.width, y: e.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 渲染成一张图

@MainActor
enum JournalSnapshot {

    /// 一页画多大。**竖着的 3:4**，跟她手机上看到的比例一致。
    static let size = CGSize(width: 900, height: 1200)

    /// 把一页手帐画成 PNG。
    ///
    /// 用 `ImageRenderer` 直接渲染 SwiftUI 那棵树——
    /// 不截屏、不用她配合、不需要那一页正开着。
    /// 她随手做的一页，他什么时候想看都能看到当时的样子。
    static func png(_ page: JournalPage) -> UIImage? {
        let renderer = ImageRenderer(content:
            JournalCanvas(page: page, size: size)
                .environment(\.colorScheme, .light)   // 手帐是纸，永远按浅色画
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    /// 那一页的**文字清单**。
    ///
    /// 图给他看「长什么样」，这份清单给他「引得出原话」——
    /// 他要说「你写的那句『今天很累但值得』」的时候，
    /// 得有个地方能一字不差地拿到那句话，从图上认字是会认错的。
    static func outline(_ page: JournalPage) -> String {
        var lines: [String] = []
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE"
        lines.append("【" + f.string(from: page.day) + "】"
                     + (page.title.isEmpty ? "" : page.title))

        // 按她摆的位置从上到下、从左到右念一遍，
        // 跟图上的顺序对得上，他才好指「左上角那张」
        let sorted = page.elements.sorted {
            abs($0.y - $1.y) > 0.06 ? $0.y < $1.y : $0.x < $1.x
        }
        for e in sorted {
            switch e.kind {
            case .text:
                lines.append("· 写着：" + e.text)
            case .note:
                lines.append("· 便签：" + e.text)
            case .quote:
                lines.append("· 摘了一句：「" + e.text + "」"
                             + (e.who.isEmpty ? "" : "——" + e.who))
            case .frame:
                lines.append("· 一张拍立得"
                             + (e.text.isEmpty ? "" : "，底下写着「" + e.text + "」"))
            case .photo:
                lines.append("· 一张照片")
            case .sticker:
                lines.append("· 贴了 " + e.emoji)
            case .stamp:
                lines.append("· 一张邮票 " + e.emoji)
            case .tape:
                lines.append("· 一道胶带")
            case .clip:
                lines.append("· 一个夹子")
            }
        }
        if page.elements.isEmpty { lines.append("（这一页还是空的）") }
        return lines.joined(separator: "\n")
    }
}
