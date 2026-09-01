import SwiftUI
import PhotosUI

/// clawd 的家。
///
/// 房间是一整块可以摆东西的地方：长按拿起来，拖到哪儿放哪儿。
/// clawd 会自己走动，挨到哪件东西就做出相应的反应。
struct ClawdHomeView: View {

    @ObservedObject private var store = ClawdStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var tab = 0            // 0 房间，1 柜子，2 商店
    // 家具的拖拽整个搬进 `IsoRoomView` 了（它自己管落在哪一格），
    // 这儿那两个状态没人用了
    /// 地板从房间高度的百分之几开始。
    ///
    /// ⚠️ 这儿以前写着「墙和地板的分界线画在 0.62」——**那句已经不作数了**。
    /// 平面的墙和地板早就换成 `IsoRoomView` 那间立体屋了，
    /// 分界线由 `IsoRoom.fit` 现算，不再是一个写死的比例。
    /// 他是**脚站在这个 y 上**的，所以能站的范围要比分界线再低一点，
    /// 不然半只身子会插进墙里——她说的「他现在可以走到墙壁的区域」就是这个。
    /// 地板范围。**跟 ClawdStore 那两个是同一件事**——
    /// 以前界面一套、store 里 clamp 又一套，于是家具能拖到墙上去。
    /// ⚠️ **这两个只是兜底。** 真正管用的是下面的 `band` / `span`——
    /// 它们从 `IsoRoom.fit` 现算，屋子挪到哪儿他的活动范围就跟到哪儿。
    /// 只有在还没量出房间多大的那一帧才会退回这两个数。
    static var floorTop: Double { ClawdStore.floorTop }
    static var floorBottom: Double { ClawdStore.floorBottom }

    @State private var mood: ClawdMood = .idle
    @State private var clawdX: Double = 0.5
    /// 他现在站在房间高度的百分之几。以前写死在 0.78，只能左右走。
    @State private var clawdY: Double = 0.78
    /// 正被拎在手上
    @State private var held = false
    /// 朝哪边走。左右翻个身，看着才像在走而不是在平移。
    @State private var facingLeft = false
    /// 这一趟走多久。远一点就走久一点。
    @State private var walkSeconds: Double = 2.4
    @State private var bubble: String?
    @State private var bubbleTask: Task<Void, Never>?
    @State private var walkTask: Task<Void, Never>?
    @State private var notice: String?
    /// 点开小菜单的那件家具
    @State private var acting: Furniture?
    /// 阿晏在这屋里说的话（接进来之后才有）
    @State private var himLine: String?
    @State private var himTask: Task<Void, Never>?
    /// 正在问她要不要接他进来
    @State private var askingLink = false

    /// 她此刻在看哪一间。**`nil` = 在看户型图**。
    ///
    /// 她说的：「clawd 在哪个房间，我打开小屋就会呈现哪个房间，
    /// 而我可以换房间看其他的。」——所以进来那一下落在他那间，
    /// 之后她想看哪间看哪间。
    @State private var viewing: HomeRoom?
    /// 她是不是**跟着他**。跟着的话他换屋，画面也跟着换；
    /// 她自己点去别间之后就不跟了——**不能把她的视线拽走**。
    @State private var following = true

    /// 「从整版图里取家具」那张纸开着没有
    @State private var importingSheet = false
    /// 正在换墙纸还是换地板
    enum DecorTarget { case wall, floor }
    @State private var decorTarget: DecorTarget = .wall
    @State private var pickingDecor = false
    @State private var decorPick: PhotosPickerItem?
    /// 正在给哪一件换图
    @State private var dressing: Furniture?
    @State private var pickingImage = false
    @State private var dressPick: PhotosPickerItem?
    /// 正在从素材库挑图
    @State private var pickingPiece = false

    /// 房间那一块有多大。算「他该坐在凳子的哪个点」要用——
    /// **跟画屋子那边用的是同一个 `IsoRoom.fit`**，各算各的必然对不齐。
    @State private var roomSize: CGSize?

    /// 屋子这一页现在画的是哪一间。
    /// `viewing` 还没定下来的时候（刚进来那一帧）就跟着他。
    private var shownRoom: HomeRoom { viewing ?? store.clawdRoom }

    // MARK: 他能站在哪儿
    //
    // 她报的：「房间虽然整体往上挪了，但是 clawd 的活动区域并没有往上挪。」
    //
    // 根子是**两套坐标各写各的**：屋子归 `IsoRoom.fit` 算，
    // 他归 `ClawdStore.floorTop/floorBottom` 那两个写死的比例。
    // 屋子的摆法一改，他就还留在原地。
    //
    // 现在都从**同一份几何**里现算。`IsoRoom` 那边只此一份，
    // 画屋子、摆家具、他走路，三处用的是同一个 `fit` 的结果。

    /// 地板竖着占哪一段
    private var band: (top: Double, bottom: Double) {
        guard let s = roomSize, s.height > 1 else {
            return (ClawdHomeView.floorTop, ClawdHomeView.floorBottom)
        }
        return IsoRoom.fit(in: s).walkBand(in: s)
    }

    /// 在竖直位置 y 上横着到哪儿。**地板是菱形，不是矩形**——
    /// 越靠上下两个尖越窄，一律 clamp 到 0.12…0.88 的话他会走到空气里。
    private func span(atY y: Double) -> (lo: Double, hi: Double) {
        guard let s = roomSize, s.width > 1 else { return (0.12, 0.88) }
        return IsoRoom.fit(in: s).walkSpan(atY: y, in: s)
    }

    /// 把一个点夹回地板里
    private func onFloor(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        let b = band
        let yy = min(b.bottom, max(b.top, y))
        let s = span(atY: yy)
        return (min(s.hi, max(s.lo, x)), yy)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // 接进来了就一直摆着这一行。铁律第二条：会自己花钱的地方，
            // 得让她看得见它开着。
            if store.linked {
                Text("停留在本页时，每隔数分钟生成一句发言 · 产生费用")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Picker("", selection: $tab) {
                Text("房间").tag(0)
                Text("柜子").tag(1)
                Text("商店").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            switch tab {
            case 0:
                if let viewing {
                    roomPage(viewing)
                } else {
                    ScrollView {
                        FloorPlanView(store: store) { enter($0) }
                            .padding(.horizontal, 16)
                            .padding(.bottom, Layout.tabBarExpanded + 16)
                    }
                }
            case 1:
                // 柜子那一档顶上挂着「换成我的家具图」——
                // 她的东西都在这一档，图也归这儿最顺手
                VStack(spacing: 0) {
                    sheetEntry
                    cabinet
                }
            default: shop
            }
        }
        .navigationTitle("clawd")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 老家具分屋。**得在这儿分**——户型图上那几个数字要用，
            // 只在进了某一间之后才分的话，户型图第一眼全是「还空着」
            store.migrateRoom()
            store.migrateRooms()
            // 进来就落在他待着的那一间（她要的）
            if viewing == nil, following { viewing = store.clawdRoom }
            startWalking()
            startHim()
        }
        // 他换屋了：她**跟着他**的时候画面才跟着换。
        // 她自己点去别间之后就不跟了——半路把她的视线拽走最讨厌。
        .onChange(of: store.clawdRoom) { _, r in
            guard following else { return }
            withAnimation(.easeInOut(duration: 0.28)) { viewing = r }
        }
        .onDisappear {
            walkTask?.cancel()
            bubbleTask?.cancel()
            // 切走就停。**他只在这一页开着的时候说话**——
            // 不然她人在别处，钱在后台自己流。
            himTask?.cancel()
        }
        .onChange(of: store.linked) { _, on in
            if on { startHim() } else { himTask?.cancel() }
        }
        .confirmationDialog("在此房间启用自动发言？", isPresented: $askingLink,
                            titleVisibility: .visible) {
            Button("接入") {
                store.linked = true
                say("他进来了")
            }
            Button("算了", role: .cancel) { }
        } message: {
            Text(MD.inline("启用后，停留在本页期间每隔数分钟自动生成一句发言，内容与房间的陈设相关。\n\n⚠️ 该功能会自动发起请求，不需要手动触发，因此**持续产生费用**。用量在设置中按「clawd 小屋」单独统计。\n\n关闭后不再发起请求。"))
        }
    }

    // MARK: 顶上那条

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(HomePalette.amber)
                    .frame(width: 9, height: 9)
                Text("\(store.coins)")
                    .font(HomeType.number(14, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.softFillDeep))

            if store.canCheckIn {
                Button {
                    let got = store.checkIn()
                    say("今天也来啦，捡到 \(got) 个币")
                } label: {
                    Text("签到")
                        .font(.app(12, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(app.settings.accentColor.opacity(0.28)))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            // 把阿晏接进来。
            //
            // 接进来之后他**会自己隔一阵冒一句**——这是她挑的那一档，
            // 也就是说这一项会自己花钱。所以第一次打开要先问一声，
            // 按钮底下也一直写着，用量在设置里按「clawd 小屋」单记。
            Button {
                if store.linked {
                    store.linked = false
                    himTask?.cancel()
                    himLine = nil
                    say("他先出去了")
                } else {
                    askingLink = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.linked ? "person.2.fill" : "person.2")
                        .font(.app(11))
                    Text(store.linked ? "他在" : "接他进来")
                        .font(.app(11))
                }
                .foregroundStyle(store.linked
                                 ? app.settings.accentColor
                                 : Theme.textMuted(scheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }


    // MARK: 一间屋

    /// 进某一间
    private func enter(_ r: HomeRoom) {
        withAnimation(.easeInOut(duration: 0.24)) {
            viewing = r
            // 点进的是他那间 = 又跟上了
            following = (r == store.clawdRoom)
        }
    }

    /// 一间屋整页：上面一条（名字 + 回户型图），中间是屋子，
    /// 左上角挂着他的头像。
    @ViewBuilder
    private func roomPage(_ r: HomeRoom) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.24)) { viewing = nil }
                } label: {
                    Label("整个家", systemImage: "square.grid.2x2")
                        .font(.app(11.5))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                // 换这一间的墙纸和地板。
                //
                // **按房间分开**：厨房贴瓷砖、卧室铺木地板，这才叫一个家。
                // 图走的是跟家具图同一套（抠白底、裁紧），她导什么进来都行。
                Menu {
                    // 内置的几套。**排在最上面**——
                    // 她大多数时候只是想让屋子好看点，
                    // 不是真想去相册里翻一张图。
                    Menu("内置墙面") {
                        ForEach(RoomFinish.Wall.allCases) { w in
                            Button(w.label) {
                                store.setWallpaper(w.token, for: r)
                                notice = r.rawValue + "的墙换成了" + w.label
                            }
                        }
                    }
                    Menu("内置地面") {
                        ForEach(RoomFinish.Floor.allCases) { f in
                            Button(f.label) {
                                store.setFlooring(f.token, for: r)
                                notice = r.rawValue + "的地换成了" + f.label
                            }
                        }
                    }
                    Divider()
                    Button("用我自己的图当墙纸") { decorTarget = .wall; pickingDecor = true }
                    Button("用我自己的图当地板") { decorTarget = .floor; pickingDecor = true }
                    if !store.wallpaper(of: r).isEmpty || !store.flooring(of: r).isEmpty {
                        Button("换回原来那版", role: .destructive) {
                            store.undressRoom(r)
                            notice = r.rawValue + "换回原来那版了"
                        }
                    }
                } label: {
                    Image(systemName: "paintbrush")
                        .font(.app(12))
                        .foregroundStyle(app.settings.accentColor)
                }

                Image(systemName: r.icon)
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
                Text(r.rawValue)
                    .heading(15)
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
            // ⚠️ 挂在**这一条**上，不是挂在下面那个 room 上。
            // 「点了没反应，切到别的档才弹出来」那次的教训：
            // 弹窗要挂在按钮活着的那个分支上。
            // ⚠️ 弹窗挪进了不订阅任何东西的宿主，见 `PickHosts.swift`。
        // 挂在这一页上会被 AppState 的每一次变化撤掉。
            .background(SinglePhotoPickHost(open: $pickingDecor, picked: $decorPick))
            .onChange(of: decorPick) { _, picked in
                guard let picked else { return }
                Task { @MainActor in
                    defer { decorPick = nil }
                    guard let data = try? await picked.loadTransferable(type: Data.self),
                          let raw = UIImage(data: data) else {
                        notice = "这张图读不出来"
                        return
                    }
                    // 缩一下再收拾。整版原图动辄上千万像素，
                    // 抠背景那一步是按像素数走的（切整版那儿栽过）
                    let img = ImageStore.downscale(raw, maxSide: 1600)
                    let ok = decorTarget == .wall
                        ? store.dressRoom(r, wall: img, floor: nil)
                        : store.dressRoom(r, wall: nil, floor: img)
                    notice = ok
                        ? (decorTarget == .wall ? "墙纸贴上了" : "地板铺好了")
                        : "这张图存不下来"
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    notice = nil
                }
            }

            room
                .overlay(alignment: .topLeading) {
                    // 左上角那个头像 + 一行「他在干嘛」（她要的）。
                    // 点它 = 跳到他那一间。
                    ClawdBadge(store: store, viewing: r) {
                        enter(store.clawdRoom)
                    }
                    .padding(.leading, 18)
                    .padding(.top, 4)
                }
        }
    }

    // MARK: 房间

    private var room: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // ⚠️ 平面的墙和地板、还有那一整段家具摆放，**全换成立体屋了**。
                //
                // 她要的：「小屋不仅仅是一个平面，是一个立体的小屋，
                // 家具放在上面有立体感……不穿模不卡顿。」
                //
                // 几何、遮挡、摆放规则都在 `IsoRoom` / `IsoRoomView` 里：
                // 地板 8×8 格等距，家具按格子摆、占几格由目录说了算，
                // **谁挡谁由「格X + 格Y」决定**——远的先画、近的压在上面。
                // 穿模不是修好的，是这个顺序让它不可能发生。
                IsoRoomView(store: store,
                            room: shownRoom,
                            clawdX: clawdX, clawdY: clawdY,
                            // 这两个是画他影子／算他深度用的，
                            // **跟他自己走的那套是同一份几何**了
                            floorTop: band.top,
                            floorBottom: band.bottom,
                            onTapFurniture: { acting = $0 },
                            // ⚠️ **他不在这一间就不画他。**
                            //
                            // 她说的：「clawd 在哪个房间，我打开小屋就会呈现哪个房间。」
                            // 反过来也成立——她翻到别的房间的时候，
                            // 他不该也跟着出现在那儿。想知道他在哪儿，看左上角那个头像。
                            clawdHere: shownRoom == store.clawdRoom) {
                    // ⚠️ 他**画在 IsoRoomView 里面**，不再叠在它上面。
                    // 那样他永远压在所有家具前面；现在他进那个深度排序，
                    // 站在床里侧就被床挡住。见 `clawdBody`。
                    clawdBody(geo.size)
                }



                // 他说的话。
                //
                // 跟 clawd 的气泡长得不一样，也不跟着 clawd 走——
                // 挂在屋子顶上，带他的名字。**得让她一眼看出这句是谁说的**：
                // clawd 那些是本地写死的台词，这一句是真的问了他。
                if let himLine {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName)
                            .font(.app(9, weight: .medium))
                            .foregroundStyle(app.settings.accentColor)
                        Text(MD.inline(himLine))
                            .font(.app(12))
                            .foregroundStyle(Theme.textMain(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 220, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(scheme == .dark
                                  ? Color.white.opacity(0.13)
                                  : Color.white.opacity(0.92))
                    )
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let notice {
                    Text(notice)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // 房间那一块有多大。**在 onAppear／onChange 里记**，
            // 不在 body 里直接写 @State——那会边画边改状态，SwiftUI 会警告，
            // 严重的时候还会来回重画停不下来。
            .onAppear { roomSize = geo.size }
            .onChange(of: geo.size) { _, v in roomSize = v }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Layout.tabBarExpanded + 12)
        // 家具的小菜单挂在房间这一层，不跟外面「接他进来」那个挤在同一个 View 上。
        // 两个 confirmationDialog 叠在同一处，SwiftUI 只认得住一个。
        .confirmationDialog(
            acting.flatMap { FurnitureCatalog.kind($0.kind)?.name } ?? "这件",
            isPresented: Binding(get: { acting != nil },
                                 set: { if !$0 { acting = nil } }),
            titleVisibility: .visible
        ) {
            if let item = acting {
                // ⚠️⚠️ **素材库排在相册前面，而且永远都在。**
                //
                // 她报的：「clawd 小屋我没找到素材库在哪里。
                // 　我长按家具点击『用我的图』弹出来的是让我在相册导入，
                // 　这个地方应该连接的是素材库，
                // 　因为只有素材库是我已经确定好的图。」
                //
                // 两件事都栽在同一句话上——上一版这儿写着
                // 「素材库是空的就不摆这一条，一个点进去什么都没有的入口只是噪音」。
                //
                // 那句话是错的，而且错得跟念头池、动态那两次一模一样：
                // **一个空着才需要被发现的入口，恰恰在空着的时候被藏了起来。**
                // 库是空的 → 入口不出现 → 她永远填不满它 → 库永远是空的。
                // `PieceBankSheet` 里那段「素材库还是空的，去哪儿切」的提示
                // 写得好好的，可她一次都没机会看见。
                //
                // 顺序也倒过来：**素材库在前，相册在后**。
                // 她说得对——素材库里那些是她已经切好、确定要用的；
                // 相册是原始素材，还得再切一遍。默认该给确定的那个。
                Button("从素材库挑一张") {
                    dressing = item
                    pickingPiece = true
                }
                Button(item.imageName.isEmpty ? "从相册挑一张原图" : "再换一张原图") {
                    dressing = item
                    pickingImage = true
                }
                if !item.imageName.isEmpty {
                    Button("换回画的这版") { store.undress(item.id) }
                }
                Button("收起来") { store.toggleHidden(item.id) }
                Button("卖掉，退一半的币", role: .destructive) {
                    store.sell(item.id)
                    say("卖掉了，退回一半的币")
                }
            }
            Button("算了", role: .cancel) { }
        } message: {
            Text("长按可以把它搬到屋里任何地方")
        }
        // ⚠️ 「从整版图里取家具」那个 sheet **不在这儿**，挂在按钮自己身上
        // （见 `sheetEntry`）。它以前挂在这一层，而这一层是**房间那一档**——
        // 她在「柜子」那一档点按钮的时候，这个 `.sheet` 压根不在视图树里，
        // 所以点了没反应；等她切回房间，视图树里有了，它才补弹出来。
        // 她说的「点击柜子里的换成我的家具图没反应，点击房间之后才弹出来」
        // 一字不差就是这个。
        //
        // 记一句：**弹窗要挂在「按钮活着的那个分支」上**，
        // 不能挂在一个 switch 只走其中一路的公共尾巴上。
        // ⚠️ 挂在**跟家具菜单同一层**。
        // 挂在别处的话就是「点了没反应」那个老坑（见下面那段注释）。
        .sheet(isPresented: $pickingPiece) {
            PieceBankSheet { img in
                if let target = dressing { _ = store.dressUp(target.id, with: img) }
                dressing = nil
                pickingPiece = false
            }
        }
        // ⚠️ 弹窗挪进了不订阅任何东西的宿主，见 `PickHosts.swift`。
        // 挂在这一页上会被 AppState 的每一次变化撤掉。
        .background(SinglePhotoPickHost(open: $pickingImage, picked: $dressPick))
        .onChange(of: dressPick) { _, picked in
            guard let picked, let target = dressing else { return }
            Task { @MainActor in
                defer { dressPick = nil; dressing = nil }
                guard let data = try? await picked.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else {
                    notice = "这张图读不出来"
                    return
                }
                if store.dressUp(target.id, with: img) {
                    let n = FurnitureCatalog.kind(target.kind)?.name ?? "它"
                    notice = n + "换成你的图了"
                } else {
                    notice = "换不上，这张图存不下来"
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                notice = nil
            }
        }
    }

    // MARK: clawd 本人
    //
    // ⚠️ **这一整块现在是交给 `IsoRoomView` 去摆的**，不再自己叠在屋子上面。
    //
    // 以前他画在 `IsoRoomView` 后面 —— 也就是**永远压在所有家具前面**。
    // 家具之间的遮挡一直是对的，只有他不对：站在床里侧也整只露在床前面。
    //
    // 现在他作为一条 `Drawable` 进那个深度排序，跟家具用同一把尺。
    // 手势、朝向、走路动画还留在这儿（搬过去要连着走路那一整套一起搬，不值），
    // `IsoRoomView` 只负责**把这块内容插在正确的位置**。
    @ViewBuilder
    private func clawdBody(_ size: CGSize) -> some View {
        // clawd 本人。长按能拎起来放到任何地方，
        // 没人管的时候他自己也会在屋里走来走去。
        //
        // ⚠️ **一格多大：这一段里所有的尺寸都从它算。**
        // 她说「小屋放大 clawd 的活动范围也要放大，连带的你都检查下」——
        // 「连带的」就是这些：他本人、他手上举的、举多高。
        // 写死一个数的话，屋子每改一次就有一样东西悄悄跟不上，
        // 而跟不上要等她截图给我看才发现。
        let tile = IsoRoom.fit(in: size).tileW
        return VStack(spacing: 4) {
            if let bubble {
                Text(bubble)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMain(scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(scheme == .dark
                                  ? Color.white.opacity(0.14)
                                  : Color.white.opacity(0.92))
                    )
                    .fixedSize()
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 2) {
                // ⚠️⚠️ **他多大是从一格多大**算出来的，不写死。
                //
                // 原来这儿写着 1.25，注释解释说「1.8 倍的他有 58 点宽，
                // 比一格（约 40 点）还宽一半……收到 1.25 之后他大概占一格」。
                //
                // 那个数当时是对的，**但它把「一格 40 点」焊死在了里面**。
                // 她这次说「小屋太小了，记得小屋放大 clawd 的活动范围也要放大，
                // 连带的你都检查下」——查到的就是这一处：
                // 屋子一变大，格子跟着变大，他却还是 40 点，越来越像个小玩具。
                //
                // 现在按**她当初调好的那个比例**（0.87 格宽）跟着格子走。
                // 屋子怎么变，他都还是「大概占一格」——
                // 那才是她那句「屋子像是能住人的」真正的意思。
                //
                // 32 是他那张图纸的宽度（`ClawdSprites` 每张都是 32 格）。
                ClawdView(mood: mood, scale: tile * 0.87 / 32, shadow: true)
                    // 大件**举过头顶**（她画的那张参考图就是这个动作）。
                    // 聊天页读的是同一个 store、同一套判断，所以两边一模一样：
                    // 这边在搬床，切过去那边也在搬床，也是举着的。
                    .overlay(alignment: .top) {
                        if let kind = store.carriedKind, store.overhead(kind) {
                            // ⚠️ 他手上那件东西也**跟着格子走**，理由同上。
                            // 屋子一变大，他跟着大了，手里举的还是原来那么小，
                            // 看着像举了个模型——这两处是 `isohard.py` 揪出来的。
                            PixelSpriteView(sprite: kind.sprite,
                                            scale: tile * 1.05 / 32)
                                .offset(y: -tile * 0.46)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                // 小东西还是端在手边
                if let kind = store.carriedKind, !store.overhead(kind) {
                    PixelSpriteView(sprite: kind.sprite, scale: tile * 1.2 / 32)
                        .offset(y: -tile * 0.17)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
                // 被拎起来的时候整只抬高一点、影子也跟着散开
                .scaleEffect(held ? 1.14 : 1)
                .shadow(color: .black.opacity(held ? 0.26 : 0),
                        radius: 10, y: 8)
                // 走路的时候左右翻个身，朝着要去的方向。
                //
                // **这一下不能带动画**。外面那几条 `.animation(...)`
                // 会把它也接管掉，于是 x 从 1 连续变到 -1——
                // 中间要经过 0，看着就是整只被压扁再翻过来，
                // 也就是她说的「走路还会转圈」。
                // 加一条时长为 0 的动画把它单独摘出来。
                .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
                .animation(nil, value: facingLeft)
                // 精灵那块 Canvas 是不接触摸的，得自己补一块感应区，
                // 不然点也点不到、更别说长按拖
                .contentShape(Rectangle().inset(by: -10))
        }
        .position(x: clawdX * size.width, y: clawdY * size.height)
        // 拖的时候要跟手，所以不给动画；自己走的时候才慢慢挪过去
        .animation(held ? nil : .easeInOut(duration: walkSeconds), value: clawdX)
        .animation(held ? nil : .easeInOut(duration: walkSeconds), value: clawdY)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: held)
        .onTapGesture {
            // 手上有东西的时候，点他＝**现在就放下**。
            //
            // 走完一趟他自己会放（见 startWalking），但那要等几秒。
            // 她递过去多半是想指个地方，不该逼她干等——
            // 点一下就搁在他脚边。
            if let kind = store.carriedKind {
                store.putDown(at: CGPoint(x: clawdX, y: clawdY))
                mood = .idle
                say(store.overhead(kind) ? "呼……放下了" : "好，搁这儿")
                if app.settings.haptics {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                return
            }
            mood = .happy
            say(tapLine())
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if mood == .happy { mood = .idle }
            }
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    held = true
                    walkTask?.cancel()          // 拎着的时候别让他自己乱跑
                    mood = .happy
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    say(["诶——", "放我下来", "飞起来了", "唔？"].randomElement() ?? "诶")
                }
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(_, let drag?) = value {
                        // 夹回**地板那个菱形**里，不是夹回一个矩形。
                        // 她说的「活动区域没往上挪」这儿也算一处。
                        let p = onFloor(drag.location.x / size.width,
                                        drag.location.y / size.height)
                        clawdX = p.x
                        clawdY = p.y
                    }
                }
                .onEnded { _ in
                    guard held else { return }
                    held = false
                    mood = .idle
                    say(["就待这儿吧", "好", "这儿也不错"].randomElement() ?? "好")
                    startWalking()              // 放下之后重新开始自己溜达
                }
        )

    }

    // MARK: 柜子

    /// 「从整版图里取家具」的入口
    private var sheetEntry: some View {
        Button {
            importingSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .font(.app(13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("换成我的家具图")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("导入整版素材图，系统自动分割为独立家具，你只需为每件标注名称")
                        .font(.app(10.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(app.settings.accentColor)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.8)
        }
        .buttonStyle(.plain)
        // 弹窗挂在按钮自己身上。**这一档在的时候它才在**，
        // 不会像以前那样点了没动静、切回房间才冒出来。
        .sheet(isPresented: $importingSheet) {
            SheetImportView(store: store)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var cabinet: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: 3), spacing: 12) {
                ForEach(store.owned) { item in
                    if let kind = FurnitureCatalog.kind(item.kind) {
                        VStack(spacing: 6) {
                            PixelSpriteView(sprite: kind.sprite, scale: 2.4)
                                .frame(height: 60)
                                .opacity(item.hidden ? 0.35 : 1)
                            Text(kind.name)
                                .font(.app(10))
                                .foregroundStyle(item.hidden
                                                 ? Theme.textMuted(scheme)
                                                 : Theme.textMain(scheme))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassCard(padding: 0)
                        // ⚠️ 穿戴那一类点一下是**穿上／脱下**，不是收起来。
                        // 她报的：「贝雷帽被当成家具放在房间里，
                        // 实际上应该给他直接穿上。」——一顶帽子摆在地板上是很怪。
                        .overlay(alignment: .topTrailing) {
                            if kind.category == .wear, store.wearing == item.kind {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.app(12))
                                    .foregroundStyle(app.settings.accentColor)
                                    .padding(5)
                            }
                        }
                        .onTapGesture {
                            if kind.category == .wear {
                                store.wear(item.kind)
                            } else {
                                store.toggleHidden(item.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Layout.tabBarExpanded + 12)

            if store.owned.isEmpty {
                Text("柜子还空着，去商店买点什么")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.top, 50)
            } else {
                Text("点一下收起来或者摆回房间")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
    }

    // MARK: 商店

    private var shop: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(FurnitureKind.Category.allCases) { cat in
                    let list = FurnitureCatalog.all.filter { $0.category == cat }
                    if !list.isEmpty {
                        Text(cat.rawValue)
                            .font(.app(13, weight: .semibold))
                            .foregroundStyle(Theme.textMain(scheme))

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                                 count: 3), spacing: 10) {
                            ForEach(list) { kind in
                                shopItem(kind)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
    }

    private func shopItem(_ kind: FurnitureKind) -> some View {
        let owned = store.has(kind.id)
        let afford = store.coins >= kind.price
        return Button {
            guard !owned else { return }
            if store.buy(kind) {
                say("\(kind.name)买到了")
                tab = 0
            } else {
                say("币不够，再攒攒")
            }
        } label: {
            VStack(spacing: 5) {
                PixelSpriteView(sprite: kind.sprite, scale: 2.2)
                    .frame(height: 54)
                Text(kind.name)
                    .font(.app(10))
                    .foregroundStyle(Theme.textMain(scheme))
                if owned {
                    Text("已有")
                        .font(.app(9))
                        .foregroundStyle(StatusTone.done.color)
                } else {
                    HStack(spacing: 3) {
                        Circle().fill(HomePalette.amber).frame(width: 6, height: 6)
                        Text("\(kind.price)")
                            .font(HomeType.number(10))
                    }
                    .foregroundStyle(afford
                                     ? Theme.textSoft(scheme)
                                     : Theme.textMuted(scheme).opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .glassCard(padding: 0)
            .opacity(owned ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: 它自己的小动作

    /// 隔一会儿自己挪一下。
    ///
    /// 现在是**满屋子走**，不只是左右平移：横竖都换一个位置，
    /// 走多远就走多久（近的两秒、远的四秒多），走的时候朝着要去的方向翻身。
    /// 挪到哪件东西旁边就说一句跟那件东西有关的话。
    private func startWalking() {
        walkTask?.cancel()
        walkTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 5...12) * 1_000_000_000)
                if Task.isCancelled { return }
                guard mood != .happy, !held else { continue }

                // 隔一会儿换一间屋。
                //
                // 她说的：「clawd 可以决定自己要去哪个房间，
                // 他凑近房间门口就会进入这个房间。」
                //
                // ⚠️ **这一步不调模型、不花钱**——现在是动画在替他决定去哪儿。
                // 等接上阿晏，这个决定才会变成他自己下的（下一轮）。
                // 手上抱着东西、正被拎着的时候不换屋，
                // 那会看着像东西凭空搬走了。
                if store.carrying == nil, !held, Double.random(in: 0...1) < 0.18 {
                    let before = store.clawdRoom
                    store.wanderToAnotherRoom()
                    if store.clawdRoom != before {
                        say(["去" + store.clawdRoom.rawValue + "看看",
                             "换个地方待着", "我去那边"].randomElement() ?? "换个地方")
                        // 进新屋从门口开始走
                        let entry = onFloor(0.5, band.top + 0.02)
                        clawdX = entry.x
                        clawdY = entry.y
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        store.clawdDoing = .walking
                    }
                    continue
                }

                // 找件家具玩一下。**她要的「每件家具三到四个互动」就是这儿。**
                //
                // ⚠️ 这一整套**一分钱不花**：挑哪件、做哪个动作、嘀咕哪一句，
                // 全是本机随机。他自己在屋里过日子，不该跟她的账单挂钩。
                if store.carrying == nil, !held,
                   let size = roomSize, size.width > 1,
                   Double.random(in: 0...1) < 0.42,
                   let item = store.furniture(in: store.clawdRoom).randomElement(),
                   let kind = FurnitureCatalog.kind(item.kind),
                   let chosen = RoomActs.acts(for: kind.id).randomElement() {

                    let geo = IsoRoom.fit(in: size)
                    let p = RoomActs.spot(of: item, kindID: kind.id,
                                          in: geo, act: chosen)
                    // 屏幕上那个点换回 0…1，走路那套还是老样子
                    let onIt = onFloor(p.x / size.width, p.y / size.height)
                    let tx = onIt.x
                    let ty = onIt.y

                    facingLeft = tx < clawdX
                    walkSeconds = 1.4
                    mood = .walking
                    store.clawdDoing = .walking
                    clawdX = tx
                    clawdY = ty
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    if Task.isCancelled { return }
                    guard !held else { continue }

                    mood = chosen.mood
                    store.clawdDoing = doing(for: chosen, kind: kind)
                    say(chosen.lines.randomElement() ?? chosen.name)
                    try? await Task.sleep(
                        nanoseconds: UInt64(chosen.seconds * 1_000_000_000))
                    if Task.isCancelled { return }
                    mood = .idle
                    store.clawdDoing = .idling
                    continue
                }

                // **只在地板上走。** 地板是哪一块由 `IsoRoom.fit` 现算，
                // 以前这儿是 0.22…0.90——0.22 在墙上，所以他会走进墙里去。
                // **只在地板上走**，而且是**菱形**的地板：
                // 先随便挑一个深度，再按那个深度上地板有多宽挑左右。
                let b = band
                let targetY = Double.random(in: b.top...b.bottom)
                let sp = span(atY: targetY)
                let targetX = sp.hi > sp.lo
                    ? Double.random(in: sp.lo...sp.hi)
                    : sp.lo
                let dist = ((targetX - clawdX) * (targetX - clawdX)
                            + (targetY - clawdY) * (targetY - clawdY)).squareRoot()

                facingLeft = targetX < clawdX
                walkSeconds = 1.6 + dist * 3.2
                // 走的这一路上换成"在忙活"那两帧，腿看着像在倒腾
                mood = store.carrying == nil ? .walking : .hauling
                // 头像底下那一行**说的是他真在做的事**
                store.clawdDoing = store.carrying == nil ? .walking : .arranging
                clawdX = targetX
                clawdY = targetY

                try? await Task.sleep(nanoseconds: UInt64(walkSeconds * 1_000_000_000))
                if Task.isCancelled { return }
                if mood == .walking || mood == .hauling {
                    mood = store.carrying == nil ? .idle : .carrying
                    store.clawdDoing = store.carrying == nil ? .idling : .arranging
                }

                // **搬到地方就放下。**
                //
                // 她报的：「拖给他之后他不放下」——对，以前他会一直举着，
                // 举一辈子。递给他是让他**帮忙搬**，不是让他抱着不动。
                // 现在走完这一趟就搁在脚边，说一句放下了。
                if let kind = store.carriedKind {
                    store.putDown(at: CGPoint(x: clawdX, y: clawdY))
                    mood = .idle
                    say(store.overhead(kind)
                        ? "呼……放这儿行吗"
                        : "搁这儿了")
                }

                // 走到谁旁边了
                let near = store.owned.filter { !$0.hidden && !$0.carried }
                    .min { a, b in
                        let da = abs(a.x - clawdX) + abs(a.y - clawdY)
                        let db = abs(b.x - clawdX) + abs(b.y - clawdY)
                        return da < db
                    }
                if let near,
                   abs(near.x - clawdX) < 0.16, abs(near.y - clawdY) < 0.20,
                   let kind = FurnitureCatalog.kind(near.kind),
                   Bool.random() {
                    say(kind.reaction)
                }
            }
        }
    }

    // MARK: 他在这屋里

    /// 接进来之后，隔几分钟问他一句。
    ///
    /// 三条自觉：
    ///   · 只在这一页开着的时候跑（onDisappear 就 cancel）
    ///   · 三到六分钟才一次，一次几十个 token
    ///   · 一次只带"屋里有什么、clawd 刚走到谁旁边"，不带聊天记录
    private func startHim() {
        himTask?.cancel()
        guard store.linked else { return }
        himTask = Task { @MainActor in
            // 头一句先等一会儿再说，别一进页面就跳出来
            try? await Task.sleep(nanoseconds: UInt64.random(in: 25...50) * 1_000_000_000)
            while !Task.isCancelled {
                guard store.linked else { return }
                let near = store.owned.filter { !$0.hidden && !$0.carried }
                    .min { a, b in
                        abs(a.x - clawdX) + abs(a.y - clawdY)
                            < abs(b.x - clawdX) + abs(b.y - clawdY)
                    }
                let nearName = (near.flatMap { FurnitureCatalog.kind($0.kind)?.name }) ?? ""
                let said = await app.clawdSays(
                    room: store.roomBrief(),
                    near: nearName,
                    carrying: store.carriedKind?.name ?? "",
                    home: store.homeBrief(watching: viewing),
                    canArrange: true)
                if Task.isCancelled { return }

                // 他在那句话里顺手写的记号：换屋、搬东西、把收起来的拿出来。
                // **解析出来照做，再把记号剥干净**——她看到的是一句正常的话。
                // 这一整套跟那句话挤在同一次请求里，一分钱不多花。
                let line = said.map { applyHisMarkers($0) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let line, !line.isEmpty {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        himLine = line
                    }
                    try? await Task.sleep(nanoseconds: 14_000_000_000)
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: 0.3)) { himLine = nil }
                }
                try? await Task.sleep(
                    nanoseconds: UInt64.random(in: 180...360) * 1_000_000_000)
            }
        }
    }

    /// 头像底下那一行，按他此刻在做的事写。
    ///
    /// ⚠️ **说的是真事**。「正在吃下午茶」得是他真的凑到蛋糕跟前了，
    /// 不是随机挑一句好听的。
    private func doing(for act: RoomAct, kind: FurnitureKind) -> ClawdDoing {
        switch kind.category {
        case .food:  return .eating
        case .drink: return .drinking
        default: break
        }
        switch act.name {
        case "躺下", "钻被窝":     return .sleeping
        case "抽一本", "踮脚够":   return .reading
        case "打开看", "按两下", "打滚", "踩上去": return .playing
        case "浇水", "摆正":       return .arranging
        default:                  return .idling
        }
    }

    /// 他那句话里的记号：照做，然后把记号剥掉。
    ///
    /// ⚠️ **一次只让他动一件**。她开着这一页看着呢——
    /// 东西一件件挪是布置，一口气全挪是家被翻了。
    @discardableResult
    private func applyHisMarkers(_ raw: String) -> String {
        let (clean, acts) = RoomMarker.parse(raw)
        var done = false
        for act in acts where !done {
            switch act {
            case .go(let r):
                guard r != store.clawdRoom else { continue }
                store.clawdRoom = r
                store.clawdDoing = .moving
                let spot = onFloor(0.5, band.top + 0.02)
                clawdX = spot.x
                clawdY = spot.y
                done = true

            case .move(let name, let to):
                guard let f = store.find(named: name) else { continue }
                store.send(f.id, to: to)
                store.clawdDoing = .arranging
                notice = "他把" + name + "搬去了" + to.rawValue
                done = true

            case .takeOut(let name):
                guard let got = store.takeOut(named: name) else { continue }
                store.clawdDoing = .arranging
                notice = "他把" + got + "拿出来摆上了"
                done = true
            }
        }
        if done {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                notice = nil
            }
        }
        return clean
    }

    private func say(_ text: String) {
        bubbleTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { bubble = text }
        bubbleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) { bubble = nil }
        }
    }

    private func tapLine() -> String {
        ["唔", "干嘛呀", "在呢", "别戳了", "痒", "嗯？"].randomElement() ?? "唔"
    }

    private func pickUpLine(_ kind: FurnitureKind) -> String {
        ["我的\(kind.name)…", "要搬去哪儿", "诶", "轻点"].randomElement() ?? "诶"
    }
}
