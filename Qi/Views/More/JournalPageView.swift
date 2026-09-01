import SwiftUI
import PhotosUI

/// 做一页手帐。
///
/// 一页就是一块自由画布：拖到哪儿放哪儿，两指能转能缩放。
/// **不做网格、不做对齐**——手帐好看恰恰在于它是歪的。
struct JournalPageView: View {

    @State var page: JournalPage

    @ObservedObject private var store = JournalStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 选中的那样东西。选中了才显示它的调节条。
    @State private var picked: UUID?
    /// 选中的那块文字里，点中的是第几个字。`nil` = 整块。
    /// 她要的「每个字单独选颜色和大小」全靠它。
    @State private var charFocus: Int?
    /// 正在拖的那一下挪了多远（不落库，松手才写回去）
    @State private var dragBy: CGSize = .zero
    @State private var pinchScale: Double = 1
    @State private var twist: Double = 0

    @State private var showingPalette = true
    @State private var showingQuotes = false
    @State private var showingPapers = false
    /// 她自己那批贴纸。见 `MyStickers`。
    @State private var mine: [String] = MyStickers.all()
    /// 正在从相册挑要导进库里的那几张
    @State private var importing = false
    @State private var importPick: [PhotosPickerItem] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var editingText: JournalElement?
    @State private var draftText = ""
    @State private var showingPhotoPicker = false
    /// 正在擦哪一件。`nil` = 没在擦。
    @State private var erasing: ErasePick?

    /// 要擦的那一件：哪个元素、擦的是哪张图
    struct ErasePick: Identifiable {
        let id: UUID
        let image: UIImage
    }

    /// 这一件有没有可擦的像素。
    ///
    /// ⚠️ 三种来源要分清：
    /// · `imageName` —— 她自己那张（照片、或者上次擦完存下来的）
    /// · `assetName` —— 包里那 44 张实物贴纸
    /// · 画出来的形状和 emoji —— **没有像素**，擦不了
    private func erasableImage(_ e: JournalElement) -> UIImage? {
        if !e.imageName.isEmpty { return ImageStore.load(e.imageName) }
        if !e.assetName.isEmpty { return JournalKit.stickerImage(e.assetName) }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            canvas
            if showingPalette { palette }
        }
        .navigationTitle(page.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        // ⚠️ 走 `PhotoPickHost`，**不直接挂在这一页上**：
        // 这一页订阅着 `app`，AppState 一变就重求值，
        // 正在弹的选择器会被当场撤掉（那个病这仓库里栽过四次）。
        .background(PhotoPickHost(open: $importing, picked: $importPick,
                                  maxCount: 20))
        .onChange(of: importPick) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for it in items {
                    // ⚠️ 拿 `Data` 不拿 `UIImage`：过一遍 UIImage 再存
                    // 会丢掉原始编码，而**透明底就是在那一步没的**。
                    if let d = try? await it.loadTransferable(type: Data.self) {
                        MyStickers.add(d)
                    }
                }
                importPick = []
                mine = MyStickers.all()
            }
        }
        .toolbar {
            // 「给他看」。**默认关**——手帐上常常是随手写的心事，
            // 她点头他才看得见。开了他就能把这一页原样画成图看见，
            // 也能往右下角贴一张便签。
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    page.shared.toggle()
                    store.save(page)
                } label: {
                    Image(systemName: page.shared ? "person.2.fill" : "person.2")
                        .foregroundStyle(page.shared
                                         ? app.settings.accentColor
                                         : Theme.textMuted(scheme))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showingPalette.toggle() }
                } label: {
                    Image(systemName: showingPalette ? "chevron.down" : "plus.circle")
                }
            }
        }
        .onDisappear { store.save(page) }
        .sheet(isPresented: $showingQuotes) {
            QuotePickerSheet { text, who in
                var e = JournalKit.make(.quote)
                e.text = text
                e.who = who
                e.z = nextZ
                page.elements.append(e)
                picked = e.id
                charFocus = nil
                store.save(page)
            }
        }
        .sheet(item: $editingText) { e in
            textEditor(for: e)
        }
        .sheet(item: $erasing) { pick in
            StickerEraser(source: pick.image) { name in
                // ⚠️ 擦完存的是**她自己的一张新图**，所以改成走 `imageName`，
                // 并且把 `assetName` 清掉——包里那张是只读的，
                // 而且同一张原图可能贴了好几处，动它会牵连别处。
                commit(pick.id) {
                    $0.imageName = name
                    $0.assetName = ""
                }
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem,
                      matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
    }

    private var nextZ: Int { (page.elements.map(\.z).max() ?? 0) + 1 }

    // MARK: 画布

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                // 纸。**跟快照共用同一份** `JournalPaperView`——
                // 纸纹在这儿画一套、那儿画一套的话，
                // 他看到的那张迟早跟她屏幕上的对不上
                JournalPaperView(hex: page.paperHex, pattern: page.paperPattern,
                                 weave: page.paperWeave)
                    .onTapGesture { picked = nil; charFocus = nil }

                ForEach(page.elements.sorted { $0.z < $1.z }) { e in
                    element(e, in: geo.size)
                }
            }
            // 手柄要按「手指相对元素中心转了多少度」来算，
            // 所以得有一个跟这张纸对齐的坐标系。
            .coordinateSpace(name: Self.canvasSpace)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    /// 这张纸的坐标系。手柄算角度要用。
    static let canvasSpace = "journal"

    @ViewBuilder
    private func element(_ e: JournalElement, in size: CGSize) -> some View {
        let live = picked == e.id
        let scale = e.scale * (live ? pinchScale : 1)
        let angle = e.angle + (live ? twist : 0)
        let center = CGPoint(x: e.x * size.width + (live ? dragBy.width : 0),
                             y: e.y * size.height + (live ? dragBy.height : 0))

        render(e)
            // ⚠️⚠️ **整块都要能碰，不只是画出来的那几个像素。**
            //
            // 她报的：「夹子换了款式之后就不能拖动了，
            // 点击也没有虚线边框（就是选中）出现。」
            //
            // 回形针那一款是 `PaperClip().stroke(…, lineWidth: 2.4)`——
            // **一条两点四宽的线**，除了这条线，整块都是透明的，
            // 手指落在别处什么都收不到。别的款式是填充的形状，所以是好的，
            // 她换了款才发现。
            //
            // 补一块实心的感应区，从此所有款式一个样。
            // （这已经是这个病的第六次了，见 `scripts/hitarea.py`。）
            .contentShape(Rectangle())
            .overlay {
                // 选中的圈一下。
                //
                // ⚠️ 这个框**贴着元素自己**，跟着它一起缩放旋转。
                // 上一版是写死的 `frame(width: 200, height: 120)` 摆在中心——
                // 一枚夹子才十几点宽，框比它大十几倍；
                // 一张大照片又框不住。既指不准是哪一件，也看不出它多大。
                if live {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(app.settings.accentColor,
                                      style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            // ⚠️ 手柄挂在**缩放和旋转之后**：这样它自己不跟着变大变斜，
            // 元素缩到很小的时候它还是那么大、还是正的，指头按得着。
            .overlay(alignment: .bottomTrailing) {
                if live { handle(e, center: center) }
            }
            .position(center)
            .onTapGesture {
                // ⚠️ 选中之后再点**不再自动开编辑器**——
                // 改文字现在有自己的钮（见 `firstBar` 里那个「改文字」）。
                // 以前这一下会把「点某个字」也吃掉。
                if picked != e.id {
                    picked = e.id
                    charFocus = nil
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { v in
                        picked = e.id
                        charFocus = nil
                        dragBy = v.translation
                    }
                    .onEnded { v in
                        commit(e.id) {
                            $0.x = min(1.05, max(-0.05,
                                $0.x + v.translation.width / size.width))
                            $0.y = min(1.05, max(-0.05,
                                $0.y + v.translation.height / size.height))
                            $0.z = nextZ
                        }
                        dragBy = .zero
                    }
            )
            // 两指捏合／旋转照旧留着——东西够大的时候那才是最顺手的。
            // 小东西走上面那个手柄。
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        picked = e.id
                        charFocus = nil
                        pinchScale = v.magnification
                    }
                    .onEnded { v in
                        commit(e.id) {
                            $0.scale = min(4, max(0.3, $0.scale * v.magnification))
                        }
                        pinchScale = 1
                    }
            )
            .simultaneousGesture(
                RotateGesture()
                    .onChanged { v in
                        picked = e.id
                        charFocus = nil
                        twist = v.rotation.degrees
                    }
                    .onEnded { v in
                        commit(e.id) { $0.angle += v.rotation.degrees }
                        twist = 0
                    }
            )
    }

    /// 选中之后右下角那个小圆点：**一根手指按住它，转圈就是转，
    /// 往外拉就是放大**。
    ///
    /// ## 为什么非要有它
    ///
    /// 她报了两次，第二次说得最清楚：
    /// 「我发现手帐有一些是可以放大缩小旋转的，但是必须要两只手都在物体上，
    /// 　但如果物体很小的话，我很难旋转。」
    ///
    /// 一点没错——`MagnifyGesture` / `RotateGesture` 要求**两根手指都落在
    /// 这个元素身上**。一枚夹子十几点宽、一张贴纸四十几点，
    /// 两根手指根本排不下；就算排下了，指尖也把那个东西整个盖住了，
    /// 转到哪儿全靠猜。
    ///
    /// 手柄把这件事变成一根手指的事，而且**手指在物体外面**，看得见。
    ///
    /// ## 怎么算
    ///
    /// 拿手指相对**元素中心**的向量：
    ///   · 长度之比 = 缩放（往外拉变大，往里推变小）
    ///   · 夹角之差 = 旋转
    /// 一次手势同时给这两样，跟真的用手捏着一个角在转是一回事。
    private func handle(_ e: JournalElement, center: CGPoint) -> some View {
        Circle()
            .fill(app.settings.accentColor)
            .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
            .frame(width: 20, height: 20)
            // 感应区比看得见的那个圆大一圈——20 点的圆按起来是勉强的
            .contentShape(Circle().inset(by: -10))
            .offset(x: 10, y: 10)
            .gesture(
                DragGesture(coordinateSpace: .named(Self.canvasSpace))
                    .onChanged { v in
                        let a = CGVector(dx: v.startLocation.x - center.x,
                                         dy: v.startLocation.y - center.y)
                        let b = CGVector(dx: v.location.x - center.x,
                                         dy: v.location.y - center.y)
                        let r0 = sqrt(a.dx * a.dx + a.dy * a.dy)
                        let r1 = sqrt(b.dx * b.dx + b.dy * b.dy)
                        // 起手离中心太近的话，比例会炸——那时候就只转不缩
                        pinchScale = r0 > 12 ? min(4, max(0.25, r1 / r0)) : 1
                        twist = (atan2(b.dy, b.dx) - atan2(a.dy, a.dx)) * 180 / .pi
                    }
                    .onEnded { _ in
                        let s = pinchScale
                        let t = twist
                        commit(e.id) {
                            $0.scale = min(4, max(0.25, $0.scale * s))
                            $0.angle += t
                            $0.z = nextZ
                        }
                        pinchScale = 1
                        twist = 0
                    }
            )
    }

    private func commit(_ id: UUID, _ change: (inout JournalElement) -> Void) {
        guard let i = page.elements.firstIndex(where: { $0.id == id }) else { return }
        change(&page.elements[i])
        store.save(page)
    }

    // MARK: 每样东西长什么样

    /// 画出一样东西。
    /// **不叫 body(of:)**——View 协议本身有个 body，同名太容易出岔子。
    ///
    /// 一个元素长什么样。**整段搬去 JournalSnapshot.swift 了**——
    /// 编辑页和「给他看的那张快照」必须是同一份渲染器，
    /// 两份迟早会长歪，那时候他看到的就不再是她看到的了。
    @ViewBuilder
    private func render(_ e: JournalElement) -> some View {
        // ⚠️ **选中和没选中画的是同一份。**
        //
        // 上一版这儿是「选中的文字换成逐字渲染、让她点字」，两个毛病：
        //   ① 逐字排版跟整块 `Text` 的排版不一样，一选中**位置就跳**
        //      （她报的「文字在编辑模式的时候位置有些问题」）；
        //   ② 点字压根点不着——父层那句「已经选中了再点就是改内容」
        //      把这一下抢走了，所以她「无法选择单独一个字改色」。
        //
        // 现在选字挪到底下工具条那一排小方块上（见 `charStrip`）：
        // 画布不变形，选字也不跟拖拽、缩放、旋转抢手势。
        JournalElementView(e)
    }

    /// 钉在右边那两个放大缩小
    private func sizeButton(_ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.app(13))
                .foregroundStyle(Theme.textSoft(scheme))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func charButton(_ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.app(12))
                .foregroundStyle(Theme.textSoft(scheme))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    /// 把第 `at` 个字改成这个颜色。
    ///
    /// ⚠️ 数组可能比正文短（她后来又加了字），所以**先补齐再写**，
    /// 不然下标就越界了。补出来的位置留空字符串，取的时候会退回整块的颜色。
    private func setChar(_ e: inout JournalElement, at: Int, hex: String) {
        let n = Array(e.text).count
        guard at >= 0, at < n else { return }
        if e.charColors.count < n {
            e.charColors += Array(repeating: "", count: n - e.charColors.count)
        }
        e.charColors[at] = hex
    }

    /// 把第 `at` 个字放大缩小。规矩同上。
    private func setCharSize(_ e: inout JournalElement, at: Int, mul: Double) {
        let n = Array(e.text).count
        guard at >= 0, at < n else { return }
        if e.charScales.count < n {
            e.charScales += Array(repeating: 1, count: n - e.charScales.count)
        }
        let now = e.charScales[at] > 0 ? e.charScales[at] : 1
        e.charScales[at] = max(0.5, min(3.0, now * mul))
    }

    // MARK: 底下那排素材

    private var palette: some View {
        VStack(spacing: 10) {
            if let id = picked,
               let e = page.elements.first(where: { $0.id == id }) {
                selectedBar(e)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(JournalKind.allCases, id: \.self) { kind in
                        Button {
                            add(kind)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: kind.icon)
                                    .font(.app(15))
                                // ⚠️ `title` 不是 `rawValue`：
                                // rawValue 是存档里的词，改不得（见 JournalKind）。
                                Text(kind.title)
                                    .font(.app(9))
                            }
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(width: 52, height: 46)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showingPapers.toggle()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "doc.plaintext")
                                .font(.app(15))
                            Text("纸底")
                                .font(.app(9))
                        }
                        .foregroundStyle(Theme.textSoft(scheme))
                        .frame(width: 52, height: 46)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            }

            if showingPapers {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        // 现成的几张纸之外，也能自己调一个——
                        // 她说「所有选择颜色的地方都加上调色盘」
                        ColorPicker("", selection: Binding(
                            get: { Color(hexString: page.paperHex) ?? Color(hexString: "F3E9D8")! },
                            set: { page.paperHex = $0.hexString; store.save(page) }
                        ), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 42, height: 30)

                        ForEach(JournalKit.papers, id: \.1) { name, hex in
                            Button {
                                page.paperHex = hex
                                store.save(page)
                            } label: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hexString: hex) ?? .gray)
                                    .frame(width: 42, height: 30)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(app.settings.accentColor,
                                                          lineWidth: page.paperHex == hex ? 2 : 0)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }

                // 纸上的纹路。**每一格就是那张纸本身的小样**——
                // 写「格纹」两个字她还得先点一次才知道长什么样
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(JournalKit.paperPatterns, id: \.1) { name, key in
                            Button {
                                page.paperPattern = key
                                store.save(page)
                            } label: {
                                JournalPaperView(hex: page.paperHex, pattern: key,
                                                 weave: page.paperWeave)
                                    .frame(width: 42, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(app.settings.accentColor,
                                                          lineWidth: page.paperPattern == key ? 2 : 0)
                                    }
                                    .overlay(alignment: .bottom) {
                                        Text(name)
                                            .font(.app(8))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                            .padding(.bottom, 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }

                // 纸的织纹。**跟上面那排格线是两层**：
                // 格线是印在纸上的，织纹是纸本身的质地，可以同时有。
                // 这一排是真实拍的布纹（CC0，见 Resources/Weave/织纹来历.txt），
                // 不是画的——画不出亚麻那种毛边。
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(JournalKit.weaves, id: \.1) { name, key in
                            Button {
                                // 再点一下取消，跟胶带那边一个规矩
                                page.paperWeave = (page.paperWeave == key) ? "" : key
                                store.save(page)
                            } label: {
                                JournalPaperView(hex: page.paperHex,
                                                 pattern: "plain", weave: key)
                                    .frame(width: 42, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(app.settings.accentColor,
                                                          lineWidth: page.paperWeave == key ? 2 : 0)
                                    }
                                    .overlay(alignment: .bottom) {
                                        Text(name)
                                            .font(.app(8))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                            .padding(.bottom, 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// 选中之后那一排：换色、置顶、删掉。
    /// 胶带和画出来的贴纸底下多一排——**第二层颜色**。
    private func selectedBar(_ e: JournalElement) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // 一个字一个小方块，点哪个选哪个。
            // ⚠️ 选字**在这儿选，不在画布上点**——画布上点会跟拖拽、
            // 缩放、旋转抢手势，而且逐字渲染会让那块字的位置跳。
            if e.kind == .text, !e.text.isEmpty {
                charStrip(e)
            }
            firstBar(e)
            // 她定的：「可以给贴纸单独图案和背景选色，
            // 比如一个素底点点图案的胶带，我想做红白配色，
            // 我就可以把底色选红色、圆点点选白色。」
            //
            // ⚠️ 只给**画出来的**那两种。emoji 贴纸和照片没有「第二层」，
            // 给它们摆一排点不动的颜色只会让人以为坏了。
            if e.kind == .tape || (e.kind == .sticker && !e.pattern.isEmpty) {
                secondBar(e)
            }
            // 相框、照片边、便签、夹子、邮票各自的几种样子。
            // 她定的：「相框、便签、夹子、邮票需要多种风格，
            // 照片需要可以选择边框。」
            if let styles = Self.styles(for: e.kind) {
                styleBar(e, styles)
            }
            // 那几样光看名字猜不出来的，选中的时候在底下说一句。
            //
            // 她报的：「剪贴不知道是什么作用，目前看起来作用跟照片差不多。」
            // ——那一档确实跟照片不一样（原样存，保住透明底），
            // 但**界面上一个字都没说过**，而它跟照片长得又几乎一模一样。
            // 名字已经改成「透明贴」了，这一行再补一句它到底干嘛的。
            if !e.kind.hint.isEmpty {
                Text(e.kind.hint)
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            }
        }
    }

    /// 这一类有没有可选的样子。没有就返回 nil，那一排不出现。
    static func styles(for kind: JournalKind) -> [(String, String)]? {
        switch kind {
        case .frame: return JournalKit.frameStyles
        case .photo: return JournalKit.photoEdges
        case .note:  return JournalKit.noteStyles
        case .clip:  return JournalKit.clipStyles
        case .stamp: return JournalKit.stampStyles
        case .quote: return JournalKit.quoteStyles
        default:     return nil
        }
    }

    /// 挑样子那一排。**摆名字不摆缩略图**——
    /// 这几种的区别在边和角上，缩到 30 点根本分不出来，
    /// 不如老老实实写「木框」「胶片」。
    private func styleBar(_ e: JournalElement, _ styles: [(String, String)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Text("样子")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(width: 26)
                ForEach(styles, id: \.1) { name, key in
                    let on = e.pattern == key
                    Button {
                        commit(e.id) { $0.pattern = key }
                    } label: {
                        Text(name)
                            .font(.app(12, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? .white : Theme.textSoft(scheme))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(on
                                ? app.settings.accentColor.opacity(0.85)
                                : Theme.softFillDeep))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    /// 那一排字。点一个就选中它，再点一下取消。
    ///
    /// 选中的那个会被下面那排颜色和大小按钮作用到；
    /// 一个都没选就是整块一起改（老行为）。
    private func charStrip(_ e: JournalElement) -> some View {
        let chars = Array(e.text)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(chars.indices, id: \.self) { i in
                    let on = charFocus == i
                    Button {
                        charFocus = on ? nil : i
                        if app.settings.haptics {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    } label: {
                        Text(chars[i] == Self.nl ? "⏎" : String(chars[i]))
                            .font(.app(14, weight: .medium, design: .serif))
                            .foregroundStyle(e.inkAt(i))
                            .frame(width: 27, height: 27)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(on ? app.settings.accentColor.opacity(0.22)
                                      : Theme.softFillDeep))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(app.settings.accentColor,
                                                  lineWidth: on ? 1.6 : 0)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    /// ⚠️ 换行走常量，别在上面写字面量。
    private static let nl: Character = "\n"

    /// 第二层颜色。胶带是花纹，贴纸是底下那圈白边。
    private func secondBar(_ e: JournalElement) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Text(e.kind == .tape ? "花纹" : "衬底")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(width: 26)
                // 头一个是「还原成白」——她十有八九还是最常用白的。
                Button {
                    commit(e.id) { $0.inkHex = "" }
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle().strokeBorder(
                                e.hasInk ? Theme.softStroke : app.settings.accentColor,
                                lineWidth: e.hasInk ? 1 : 2)
                        }
                }
                .buttonStyle(.plain)
                ForEach(JournalKit.stickerInks, id: \.1) { _, hex in
                    Button {
                        commit(e.id) { $0.inkHex = hex }
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().strokeBorder(
                                    app.settings.accentColor,
                                    lineWidth: e.inkHex == hex ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    /// 选中之后第一排：会滚的那半 + 钉在右边的那半。
    private func firstBar(_ e: JournalElement) -> some View {
        HStack(spacing: 0) {
            scrollingBar(e)
            pinnedBar(e)
        }
        .frame(height: 38)
    }

    private func scrollingBar(_ e: JournalElement) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                // 点中某个字之后，这一排先出现「这个字」的三个钮：
                // 放大、缩小、还原。不点字就不出现——不占地方。
                if e.kind == .text, let at = charFocus {
                    // 选中的是哪个字，上面那一排已经高亮了，这儿不再重复摆一遍
                    charButton("textformat.size.smaller") {
                        commit(e.id) { setCharSize(&$0, at: at, mul: 1 / 1.18) }
                    }
                    charButton("textformat.size.larger") {
                        commit(e.id) { setCharSize(&$0, at: at, mul: 1.18) }
                    }
                    charButton("arrow.uturn.backward") {
                        commit(e.id) {
                            if at < $0.charScales.count { $0.charScales[at] = 1 }
                            if at < $0.charColors.count { $0.charColors[at] = "" }
                        }
                    }
                    Divider().frame(height: 20)
                }
                ForEach(colorsFor(e.kind), id: \.1) { _, hex in
                    Button {
                        // ⚠️ 点中了某个字就**只改那一个字**。
                        // 她要的：「可以每个字单独点击颜色选，
                        // 点击颜色后打的字就是这个颜色。」
                        // 没点中字就还是整块换色（原来那个行为）。
                        if let at = charFocus, e.kind == .text {
                            commit(e.id) { setChar(&$0, at: at, hex: hex) }
                        } else {
                            commit(e.id) { $0.colorHex = hex }
                        }
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex) ?? .gray)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle().strokeBorder(
                                    app.settings.accentColor,
                                    lineWidth: e.colorHex == hex ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                }

                // 胶带的花纹。画出来的，所以换个颜色就是另一卷。
                if e.kind == .tape {
                    ForEach(JournalKit.tapePatterns, id: \.1) { name, key in
                        Button {
                            commit(e.id) { $0.pattern = key }
                        } label: {
                            JournalTapeView(color: e.color, pattern: key,
                                            ink: e.hasInk ? e.ink : nil,
                                            width: 34, height: 18)
                                .overlay {
                                    if e.pattern == key {
                                        Rectangle()
                                            .strokeBorder(app.settings.accentColor,
                                                          lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                }

                if e.kind == .sticker || e.kind == .stamp {
                    // 画出来的那几张。**摆在 emoji 前面**——
                    // 这一排才是新东西，摆后面她翻不到
                    if e.kind == .sticker {
                        // ── 实物贴纸排在最前面。
                        // 她说画出来的那种「很怪，本身就是色块」——
                        // 所以真东西该先摆出来，画的那些退到后面当补充。
                        // ── 她自己导进来的那些，**排在最前面**。
                        //
                        // 自带那批有八十多张，她刚导进来的那一张要是排在后面，
                        // 得横着划半天才找得到——而那张恰恰是她这会儿想贴的。
                        //
                        // 见 `MyStickers`：有些素材（比如いらすとや）条款允许
                        // 「自己用」但不允许「打包再分发」，这条路走的是前者。
                        Button {
                            importing = true
                        } label: {
                            VStack(spacing: 1) {
                                Image(systemName: "plus")
                                    .font(.app(13))
                                Text("导入")
                                    .font(.app(8))
                            }
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(width: 30, height: 30)
                            .padding(3)
                            .background(RoundedRectangle(cornerRadius: 8,
                                                         style: .continuous)
                                .fill(Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)

                        ForEach(mine, id: \.self) { file in
                            Button {
                                if e.assetName.isEmpty && e.pattern.isEmpty {
                                    commit(e.id) { $0.assetName = file }
                                } else {
                                    addSticker(asset: file, near: e)
                                }
                            } label: {
                                Group {
                                    if let img = JournalKit.stickerImage(file) {
                                        Image(uiImage: img).resizable().scaledToFit()
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 30, height: 30)
                                .padding(3)
                                .background(RoundedRectangle(cornerRadius: 8,
                                                             style: .continuous)
                                    .fill(Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)
                            // 长按删掉这一张。**只从她的库里删，不动已经贴出去的**——
                            // 贴出去那些是页面上的东西，跟库里这一张是两回事。
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    MyStickers.remove(file)
                                    mine = MyStickers.all()
                                } label: {
                                    Label("从我的库里删掉", systemImage: Icon.trash)
                                }
                            }
                        }

                        ForEach(JournalKit.realStickers, id: \.1) { _, file in
                            Button {
                                // ⚠️ **手上这张已经有图了就再贴一张，不是换掉。**
                                //
                                // 她报的：「手帐贴纸只能贴一个。」——
                                // 以前不管点第几张都是改当前选中那一个，
                                // 于是贴第二张的时候第一张就没了。
                                //
                                // 现在：刚加出来那个空贴纸，第一次点是填进去；
                                // 已经填过了，再点就是**新贴一张**。
                                // 想换掉的话，把那张删了重贴——
                                // 比「有时候是换、有时候是加」好懂得多。
                                if e.assetName.isEmpty && e.pattern.isEmpty {
                                    commit(e.id) { $0.assetName = file }
                                } else {
                                    addSticker(asset: file, near: e)
                                }
                            } label: {
                                Group {
                                    if let img = JournalKit.stickerImage(file) {
                                        Image(uiImage: img).resizable().scaledToFit()
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 30, height: 30)
                                .padding(3)
                                .background(RoundedRectangle(cornerRadius: 8,
                                                             style: .continuous)
                                    .fill(e.assetName == file
                                          ? app.settings.accentColor.opacity(0.20)
                                          : Color.clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(JournalKit.stickerShapes, id: \.1) { name, key in
                            Button {
                                // 规矩同上：空的就填，填过了就再贴一张
                                if !e.assetName.isEmpty || !e.pattern.isEmpty {
                                    addSticker(shape: key, near: e)
                                    return
                                }
                                commit(e.id) {
                                    // 挑了画的那种，就把实物那张清掉（理由同上）
                                    $0.assetName = ""
                                    $0.pattern = key
                                    // 从 emoji 换过来的时候还没有颜色，给一个
                                    if $0.colorHex.isEmpty || $0.colorHex == "FFFFFF" {
                                        $0.colorHex = JournalKit.stickerInks.first?.1 ?? "8FAE84"
                                    }
                                }
                            } label: {
                                JournalStickerView(
                                    shape: key,
                                    color: e.pattern == key
                                        ? e.color
                                        : (Color(hexString: "A8A296") ?? .gray),
                                    side: 20,
                                    backing: e.hasInk ? e.ink : nil)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }
                    ForEach(JournalKit.stickers.prefix(12), id: \.self) { s in
                        Button {
                            // 挑了 emoji 就是不要画的那张了
                            commit(e.id) { $0.emoji = s; $0.pattern = "" }
                        } label: {
                            Text(s).font(.app(20))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if e.kind == .photo || e.kind == .frame || e.kind == .cutout {
                    small("贴图") { showingPhotoPicker = true }
                }

                small("拉正") { commit(e.id) { $0.angle = 0 } }
                // ⚠️ 「改文字」得单独给个钮。
                // 以前是「选中之后再点一下」进编辑，可现在点字是选那个字——
                // 一个动作不能既是选字又是改内容。
                // 擦一擦。只给**有图**的那几种——
                // 画出来的贴纸和 emoji 没有像素可擦。
                if let img = erasableImage(e) {
                    small("擦一擦") { erasing = ErasePick(id: e.id, image: img) }
                }
                if e.kind == .text || e.kind == .note || e.kind == .quote {
                    small("改文字") {
                        draftText = e.text
                        editingText = e
                    }
                }
                // ⚠️ 「置顶／删掉」**搬出去了**，钉在右边不跟着滚。
                // 她报的：「删除等等功能要拖动到最后很麻烦。」
                // 那一排现在有选字、字号、两排颜色、样子……越加越长，
                // 而「删掉」是最常用的一个，凭什么排在最远。
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
        }
    }

    /// 钉在右边那两个：置顶、删掉。
    ///
    /// ⚠️ 底下垫一层玻璃**并且不透明**：它压在会滚动的那一排上面，
    /// 透的话底下的按钮会从它背后透出来，看着像两层字叠在一起。
    private func pinnedBar(_ e: JournalElement) -> some View {
        HStack(spacing: 7) {
            // ⚠️ 大小给**按钮**，不只靠捏合。
            //
            // 她报的：「贴纸不能放大缩小，就像表情工坊那样。」
            // 捏合其实一直都在（`MagnifyGesture`），但一张贴纸才几十点宽，
            // 两根手指落上去根本压不准，而且一碰就先把它拖走了。
            // 点两下按钮是**看得见也点得着**的那个办法。
            sizeButton("minus.magnifyingglass") {
                commit(e.id) { $0.scale = max(0.25, $0.scale / 1.2) }
            }
            sizeButton("plus.magnifyingglass") {
                commit(e.id) { $0.scale = min(5, $0.scale * 1.2) }
            }
            small("置顶") { commit(e.id) { $0.z = nextZ } }
            small("删掉") {
                if !e.imageName.isEmpty { ImageStore.delete(e.imageName) }
                page.elements.removeAll { $0.id == e.id }
                picked = nil
                charFocus = nil
                store.save(page)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func small(_ t: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t)
                .font(.app(11))
                .foregroundStyle(Theme.textSoft(scheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    private func colorsFor(_ kind: JournalKind) -> [(String, String)] {
        switch kind {
        case .tape:          return JournalKit.tapes
        case .note:          return JournalKit.notes
        case .text, .quote:  return JournalKit.inks
        // 画出来的贴纸跟着颜色走，所以这一排给的是贴纸色不是墨水色
        case .sticker:       return JournalKit.stickerInks
        default:             return JournalKit.inks
        }
    }

    // MARK: 加一样

    /// 再贴一张贴纸，落在刚才那张旁边。
    ///
    /// ⚠️ **落在旁边而不是画布中间**：她刚在某个位置贴了一张，
    /// 下一张多半也是想放在那附近。丢回中间的话她得再拖一次。
    private func addSticker(asset: String = "", shape: String = "",
                            near old: JournalElement) {
        var e = JournalKit.make(.sticker)
        e.assetName = asset
        e.pattern = shape
        if !shape.isEmpty {
            e.colorHex = old.colorHex.isEmpty
                ? (JournalKit.stickerInks.first?.1 ?? "8FAE84") : old.colorHex
        }
        e.z = nextZ
        e.x = min(0.95, max(0.05, old.x + Double.random(in: 0.06...0.14)))
        e.y = min(0.95, max(0.05, old.y + Double.random(in: -0.06...0.10)))
        e.angle = Double.random(in: -8...8)
        page.elements.append(e)
        picked = e.id
        charFocus = nil
        store.save(page)
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func add(_ kind: JournalKind) {
        if kind == .quote {
            showingQuotes = true
            return
        }
        var e = JournalKit.make(kind)
        e.z = nextZ
        // 落在画布中间偏上一点，随机错开一点点，
        // 连着加几个不会全叠在同一个点上
        e.x = 0.5 + Double.random(in: -0.12...0.12)
        e.y = 0.4 + Double.random(in: -0.12...0.12)
        page.elements.append(e)
        picked = e.id
        charFocus = nil
        store.save(page)
        if kind == .photo || kind == .frame || kind == .cutout {
            showingPhotoPicker = true
        }
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item, let id = picked else { return }
        // 是不是「剪贴」那一样。**这决定了怎么存**：
        // 剪贴那种是透明底的 PNG，走 `save(_ image:)` 会被重编码成 jpg，
        // 透明的地方全变成白块——那张贴纸就废了。
        let cut = page.elements.first { $0.id == id }?.kind == .cutout
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let name: String?
            if cut {
                // 原样落盘，一个字节都不重编码
                name = ImageStore.saveOriginal(data)
            } else if let image = UIImage(data: data) {
                name = ImageStore.save(image)
            } else {
                name = nil
            }
            guard let name else { return }
            await MainActor.run {
                commit(id) {
                    if !$0.imageName.isEmpty { ImageStore.delete($0.imageName) }
                    $0.imageName = name
                }
                photoItem = nil
            }
        }
    }

    private func textEditor(for e: JournalElement) -> some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack {
                    TextEditor(text: $draftText)
                        .scrollContentBackground(.hidden)
                        .font(.app(15))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.softFillDeep))
                        .padding(16)
                    Spacer()
                }
            }
            .navigationTitle("改字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("算了") { editingText = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("好") {
                        commit(e.id) { $0.text = draftText }
                        editingText = nil
                    }
                }
            }
        }
    }
}

// MARK: - 从收藏里挑一句

/// **她收藏一句话的时候多半就是想把它留下来**，
/// 让她再抄一遍是浪费。所以这儿直接把星标过的句子摆出来，点一句就贴上去。
struct QuotePickerSheet: View {

    var onPick: (String, String) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""

    private struct Item: Identifiable {
        let id = UUID()
        let text: String
        let who: String
        let at: Date
    }

    private var items: [Item] {
        var out: [Item] = []
        for c in app.conversations {
            for m in c.messages where m.starred {
                let t = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                let who = m.role == .user
                    ? (app.settings.userName.isEmpty ? "我" : app.settings.userName)
                    : (m.senderName.isEmpty
                       ? (app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName)
                       : m.senderName)
                out.append(Item(text: t, who: who, at: m.createdAt))
            }
        }
        let sorted = out.sorted { $0.at > $1.at }
        guard !keyword.isEmpty else { return sorted }
        return sorted.filter { $0.text.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if items.isEmpty {
                            Text(keyword.isEmpty
                                 ? "还没有收藏的句子。在聊天里长按一句话就能收藏。"
                                 : "没搜到")
                                .font(.app(12))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.top, 50)
                        }
                        ForEach(items) { item in
                            Button {
                                onPick(item.text, item.who)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.text)
                                        .font(.app(14))
                                        .foregroundStyle(Theme.textMain(scheme))
                                        .lineLimit(4)
                                        .multilineTextAlignment(.leading)
                                    Text(item.who)
                                        .font(.app(10))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .glassCard(padding: 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .searchable(text: $keyword, prompt: "搜收藏的句子")
            .navigationTitle("插入收藏的句子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关掉") { dismiss() }
                }
            }
        }
    }
}
