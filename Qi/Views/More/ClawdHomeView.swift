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
    /// 关掉这一层。点他的气泡回聊天页靠它——
    /// 小屋是盖在聊天页上的一张 sheet，关掉就回去了。
    @Environment(\.dismiss) private var dismiss

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

    /// 这个情绪该不该把手摆起来。
    ///
    /// ⚠️ **别铺太宽。** 手一直在摆就等于没在摆——
    /// 只有"这一下真的高兴"才摆，平时垂着，落差才看得出来。
    static func armPose(_ m: ClawdMood) -> CarryPose {
        switch m {
        case .loving: return .cheer      // 甜的时候：两只手一起摆
        case .happy: return .wave        // 被摸了：招一只手
        case .flail: return .cheer       // 被连戳，甩手抗议
        default: return .none
        }
    }
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

    // ── 她的手（`ClawdTouch.swift`）
    /// 现在选的是哪个手势
    @State private var hand: HandTool = .pat
    /// 拖出来的那只手在屋里的什么位置。nil = 没在拖
    @State private var handAt: CGPoint?
    /// 屋子在外层（“roomPage”）里的左上角。
    ///
    /// ⚠️ 手势条搬到屋子底下之后才需要它：
    /// 拖手那个手势发生在外层，而他站在哪儿是屋子内部的坐标。
    /// 两边差的就是这个原点（见 `toRoom`）。
    @State private var roomOrigin: CGPoint = .zero
    /// 这只手**此刻**是不是压在他身上。
    /// 进去的那一刻算一次，出来再进去算下一次——见 `handChip` 里那段。
    @State private var handOnHim = false
    /// 他的耐心。⚠️ **要活过一次次触碰**，所以是 @State 不是局部变量——
    /// 每碰一次重新算的话，戳第二十下和第一下一样，那就只是个音效按钮。
    @State private var patience = ClawdPatience()
    /// 摸／戳／打的反应正演到什么时候为止。**没演完不让位**，
    /// 跟 `ClawdMood.hold` 一个道理（见 `交接-clawd画法.md` 第三节）。
    @State private var touchUntil = Date.distantPast
    @State private var touchTask: Task<Void, Never>?
    /// 正在捉迷藏：他藏起来了，屋里不画他
    @State private var hiding = false
    /// 藏在哪一件家具后面
    @State private var hideSpot: UUID?
    @State private var hideTask: Task<Void, Never>?
    /// 金币作弊面板开着没有
    @State private var cheating = false
    /// 正要买的那套主题、换到哪一间
    @State private var buying: (theme: RoomTheme, room: HomeRoom)?

    /// 长按商店里某一件之后，正在挑数量和房间的那一件
    @State private var shopping: FurnitureKind?

    /// 正在挑「搬去哪一间」的那一件
    @State private var sending: Furniture?

    /// 底下那个输入框里打了什么
    @State private var himDraft = ""

    /// 已经搬到气泡上的那一句是哪一条。
    /// **靠它认新的**：聊天页里他刚回完的那句要接到气泡上来，
    /// 而这一页每次重画都会读一遍最后那条——不记的话同一句会反复弹。
    @State private var mirrored: UUID?

    @FocusState private var typing: Bool

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

    /// 他画出来有多高（点）。**量出来的，不是算出来的。**
    ///
    /// ⚠️ 他的高度取决于精灵图纸、缩放系数、手上有没有举东西——
    /// 在几何那边（`IsoRoom`）猜不出来。我在那儿猜过两次留白，
    /// 两次都不够，她两次都截图给我看。
    @State private var bodyH: CGFloat = 0

    /// 地板竖着占哪一段。**就是地板，不多不少。**
    ///
    /// ⚠️ 这儿**不再替他扣半个身子**了。
    ///
    /// 她报的：「你貌似套了两层活动范围。」——对。上一版这儿会从两头
    /// 各扣 `bodyH / 2`，那是为了治「他半个身子在屋外」打的补丁；
    /// 而几何那边（`IsoRoom.walkBand`）也曾经扣过一次。
    /// 两层在两个文件里、两套单位，改一处不看另一处就对不上。
    ///
    /// 真正的病根只有一个：**他是按整块的正中摆的，不是按脚。**
    /// 现在在摆的那一步解决（`clawdBody` 里那句 `.offset(y: -bodyH / 2)`），
    /// 这儿就干干净净地只回答「地板在哪儿」。
    private var band: (top: Double, bottom: Double) {
        guard let s = roomSize, s.height > 1 else {
            return (ClawdHomeView.floorTop, ClawdHomeView.floorBottom)
        }
        return IsoRoom.fit(in: s, as: store.projection).walkBand(in: s)
    }

    /// 在竖直位置 y 上横着到哪儿。**地板是菱形，不是矩形**——
    /// 越靠上下两个尖越窄，一律 clamp 到 0.12…0.88 的话他会走到空气里。
    private func span(atY y: Double) -> (lo: Double, hi: Double) {
        guard let s = roomSize, s.width > 1 else { return (0.12, 0.88) }
        return IsoRoom.fit(in: s, as: store.projection).walkSpan(atY: y, in: s)
    }

    /// 把他夹回地板里。**每次量完屋子就叫一次。**
    ///
    /// ## 为什么必须有这一下
    ///
    /// 他的位置存的是「占容器宽高的百分之几」，而地板的形状是算出来的。
    /// 屋子一改（墙加高、地板加深、换投影、转屏），那两个百分比就还停在
    /// 老屋子的位置上——**而他自己不会重新落地**：走路那套只在他决定
    /// 要去哪儿的时候才夹一次，站着不动的时候一次都不夹。
    ///
    /// 她报的「走在最下一排也没有在屋里」有一半是这个：不是范围算错了，
    /// 是他压根没被重新安置过。
    private func settleHim() {
        let p = onFloor(clawdX, clawdY)
        guard abs(p.x - clawdX) > 0.0001 || abs(p.y - clawdY) > 0.0001 else { return }
        clawdX = p.x
        clawdY = p.y
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
                Text("他在屋里 · 停留在本页时每隔数分钟自己说一句 · 产生费用")
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
        // ⚠️ **这一页自己画标题，不用导航栏。**
        //
        // 她说的：「金币在按钮下面的就是之前的，现在没有在按钮下面，
        // 所以改回去。」——中间隔出来的那一行就是导航栏：
        // 它自己占 44 点，上下还各留一截，金币于是被顶下去六十多点。
        // 「关上」删掉之后那一行只剩一个「clawd」，不值一整行；
        // 标题挪进 `header` 的正中间，金币就又贴回最顶上了。
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // 老家具分屋。**得在这儿分**——户型图上那几个数字要用，
            // 只在进了某一间之后才分的话，户型图第一眼全是「还空着」
            store.migrateRoom()
            store.migrateRooms()
            // 格子从 8 变 16 那一次，老坐标乘 2 搬过来。只跑一次。
            store.migrateFiner()
            // 进来就落在他待着的那一间（她要的）
            if viewing == nil, following { viewing = store.clawdRoom }
            startWalking()
            startHim()
            // ⚠️ **进来先记下他此刻说到哪儿了。**
            // 不记的话，她一打开小屋，聊天页里上一次的回复会立刻
            // 弹到气泡上——那句话是十分钟前说的，弹出来像刚说的。
            mirrored = app.lastHisMessageID
            // 到日子了自己换上节日那套（买了才换），过了自己换回来。
            // ⚠️ **放在 onAppear 里就够。** 不用开定时器守着零点——
            // 她开着这一页跨过零点的概率，比多一个常驻定时器的代价小得多。
            if let t = store.syncFestivalTheme() {
                notice = "今天" + t.festival + "，屋子换上「" + t.label + "」了"
            }
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
            // 这两个也得停。⚠️ 藏起来的定时器留着的话，
            // 她切走再回来，他会在毫无缘由的时候"被找到"一次。
            touchTask?.cancel()
            hideTask?.cancel()
            // 切走就停。**他只在这一页开着的时候说话**——
            // 不然她人在别处，钱在后台自己流。
            himTask?.cancel()
            // 屋子的处境跟着这一页走。她回聊天页问别的事的时候，
            // 上下文里不该还挂着一间屋子（见 `AppState.houseContext`）。
            app.houseContext = ""
        }
        // 他在聊天那边说完了，把那句搬到 clawd 的气泡上。
        // 两条都听：`id` 变是来了新的一条，`isStreaming` 落下来是这条说完了。
        .onChange(of: app.lastHisMessageID) { _, _ in mirrorHisReply() }
        .onChange(of: app.lastHisMessage?.isStreaming) { _, _ in mirrorHisReply() }
        .onChange(of: store.linked) { _, on in
            if on { startHim() } else { himTask?.cancel() }
        }
        .confirmationDialog(buying.map { "买「" + $0.theme.label + "」？" } ?? "",
                            isPresented: Binding(get: { buying != nil },
                                                 set: { if !$0 { buying = nil } }),
                            titleVisibility: .visible) {
            if let b = buying {
                Button("花 \(b.theme.price) 币换上") {
                    if store.buyTheme(b.theme) {
                        store.applyTheme(b.theme, to: b.room)
                        notice = b.room.rawValue + "换成「" + b.theme.label + "」了"
                    } else {
                        notice = "币不够，还差 \(b.theme.price - store.coins) 个"
                    }
                    buying = nil
                }
                Button("算了", role: .cancel) { buying = nil }
            }
        } message: {
            Text(buying.map { $0.theme.note + "。买过之后所有房间都能用。" } ?? "")
        }
        .sheet(isPresented: $cheating) {
            CoinCheatSheet(store: store)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "搬到哪一间",
            isPresented: Binding(get: { sending != nil },
                                 set: { if !$0 { sending = nil } }),
            titleVisibility: .visible
        ) {
            if let item = sending {
                // ⚠️ 它现在待的那间不摆出来——搬到原地不是一个选项。
                ForEach(HomeRoom.allCases.filter { $0.rawValue != item.room }) { r in
                    Button(r.rawValue) {
                        store.send(item.id, to: r)
                        say("搬去" + r.rawValue + "了")
                        sending = nil
                    }
                }
            }
            Button("算了", role: .cancel) { sending = nil }
        }
        .sheet(item: $shopping) { kind in
            BuyBox(kind: kind, store: store) { got, room in
                if got > 0 {
                    say(kind.name + "买了 " + String(got) + " 件，放进" + room.rawValue)
                    tab = 0
                } else {
                    say("币不够，再攒攒")
                }
            }
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("把这间屋子给他？", isPresented: $askingLink,
                            titleVisibility: .visible) {
            Button("给他") {
                store.linked = true
                say("他进来了")
            }
            Button("算了", role: .cancel) { }
        } message: {
            // ⚠️ 这段改过一次：原来写的是「启用自动发言……内容与房间的陈设相关」。
            //
            // 她说的：「接他进来有几点太绝对了，并不是接他进来一定要对小屋
            // 做出评价，而是给他一个家，可以在 clawd 的身体里跟我说话。」
            //
            // 所以这一段现在说的是**这件事是什么**，不是「开了一个功能」。
            // 花钱那一条照旧写清楚——铁律第二条，会自己花钱的地方要看得见。
            Text(MD.inline("接进来后，他借着 clawd 的身体待在屋里：底部的输入框可以直接跟他说话，他说的话同时出现在 clawd 的气泡和聊天页里。\n\n停留在本页期间，他还会每隔数分钟自己说一句。\n\n⚠️ 自己说的那一句**不需要手动触发，持续产生费用**。用量在设置中按「clawd 小屋」单独统计。\n\n关闭后不再自己说话。"))
        }
    }

    // MARK: 顶上那条

    private var header: some View {
        headerRow
            // 标题**叠在这一行正中间**，不排进 HStack。
            // 排进去的话它会被两边按钮的宽度推得偏一边，
            // 而两边的宽度是会变的（签到只在没签到时才有）。
            .overlay {
                Text("clawd")
                    .heading(16)
                    .foregroundStyle(Theme.textMain(scheme))
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            // ⚠️ 这一页把导航栏藏了，所以这一行就顶在状态栏底下。
            //
            // 她报的：「clawd 的 UI 太靠上了，整体往下移动，
            // 顶上的 UI 不用和标题同高。」——她说得对：
            // 别的页那儿是导航栏，这一行占着导航栏的位置，
            // 看着就像被推上去顶住了屏幕边。
            //
            // ⚠️ 26 → 48。上一版给的 26 她说「依旧没往下移」——
            // **一个导航栏本身就有 44 点高**，让不够那么多，
            // 看着就还是贴在原处。
            .padding(.top, 48)
            .padding(.bottom, 10)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            // 点金币栏 = 自己改金币。她要的：「再来一个作弊系统，
            // 就是关于我的金币，点击目前的金币栏我可以随意增减我的金币数量。」
            Button { cheating = true } label: {
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
            }
            .buttonStyle(.plain)

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
                    app.houseContext = ""
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

                // 「他在干嘛 · 在哪间」。原来是竖着一块浮在屋子左上角的，
                // 会压住最里面那一格，所以横过来排进这一行。
                ClawdBadge(store: store, viewing: r, onFollow: {
                    enter(store.clawdRoom)
                }, compact: true)

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
                    // ⚠️ **摆在最前面。** 她要的是「整间换成那个样子」，
                    // 不是「墙挑一次、地再挑一次」——
                    // 底下那两栏留给想单独调的时候。
                    // ⚠️ **主题接管了原来那个「整套换」。**
                    // `RoomFinish.suites` 那五套现在是 `RoomTheme.all`
                    // 里价钱为 0 的前五个，一模一样，只是多了带配色的那些。
                    // 两份并存的话，改了一份另一份就开始撒谎。
                    Menu("整套换") {
                        ForEach(RoomTheme.all) { t in
                            Button(themeMenuLabel(t)) { pickTheme(t, in: r) }
                        }
                    }
                    // 立体／平面。⚠️ **摆在最上面这一层**，
                    // 不塞进二级菜单——她要的是「试下换成那种」，
                    // 埋两层深的话试一次都嫌麻烦。
                    Menu("看的角度") {
                        ForEach(RoomProjection.allCases) { p in
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    store.projection = p
                                }
                                notice = "换成" + p.label + "了"
                            } label: {
                                Text(ClawdHomeView.viewLabel(p))
                                if store.projection == p {
                                    Image(systemName: "checkmark")
                                }
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

            roomAndHands
        }
        // ⚠️ 坐标系挂在**屋子和手势条外面这一层**。
        //
        // 手势条搬到屋子底下之后，拖手这件事发生在这一层；
        // 而他站在哪儿是按屋子内部的坐标算的。
        // 两边差着一个屋子的原点，`toRoom` 负责换算。
        .coordinateSpace(name: "roomPage")
        // 正拖着的那只手，跟着手指走。**画在这一层**——
        // 画在屋子里面的话，手指还没进屋那一段它是看不见的。
        .overlay {
            if let at = handAt {
                Text(hand.emoji)
                    .font(.app(40))
                    .position(at)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: handAt == nil)
    }

    /// 屋子 + 底下那排手势。
    private var roomAndHands: some View {
        VStack(spacing: 0) {
            room
                // ⚠️⚠️ **屋子的高度问屏幕要，不要「上面排完剩多少算多少」。**
                //
                // 她连着截了两张图，隔一分钟、同一个 App，
                // 屋子差了将近一倍：「我又看了下 app，又从 p1 变成 p2 了，
                // 所以我才说屋子小。」
                //
                // 去量那两张：墙和地板的比例是 0.48 和 0.49——**一模一样**。
                // 所以不是画法变了，是**整间屋子被整体缩放了 1.8 倍**。
                // 而屋子多大只由一件事决定：`GeometryReader` 拿到多高。
                //
                // 病根就在这儿：`room` 是个 `GeometryReader`，
                // 它拿到的是「这个 VStack 上面几样排完之后**剩下**多少」。
                // 那个数不稳——上面那行提示在不在、sheet 的高度动画走到哪一帧、
                // 第一次布局有没有定下来，都会让它变。
                // 于是同一间屋子，这次画得大、下次画得小。
                //
                // `containerRelativeFrame` 问的是**装着这一页的那个容器**
                // （这张 sheet）有多高——那个数在同一台手机上是定的，
                // 不受上面排了什么影响。减 200 是顶上那几样（标题、币、
                // 三个档、房间名）占的地方。
                //
                // 记一句：**尺寸要问一个稳定的东西要，别问「还剩多少」。**
                // 减 330：顶上那几样（标题、币、三个档、房间名）约 240，
                // 再加底下那排手势约 90。不给它让地方的话，
                // 手势条会被顶到标签栏底下去。
                //
                // ⚠️ **上下多出来一样东西，这个数就得跟着加。**
                // 不加的话多出来的那一截全从底下那排手势身上扣，
                // 手势条会被顶到标签栏底下去。
                // 已经算进去的：顶上那一行往下挪的 42（见 `header`）；
                // 接他进来之后底下那条输入框（见 `himBar`）另加 56。
                .containerRelativeFrame(.vertical) { h, _ in
                    max(280, h - (store.linked ? 386 : 330))
                }
                // ⚠️ **屋子上面不再叠「他在干嘛」那块牌子。**
                // 她说的：「左上的 clawd 有点挡住了，把那行去掉就不会挡到了。」
                // 它挪到上面那条房间名里了（横着的一小条，见 `roomBar`）。

            handBar

            // 跟他说话。**只有接进来之后才有。**
            //
            // 她要的：「在小屋最下面应该新增一个输入框供我给他打字交流。」
            if store.linked { himBar }
        }
        .padding(.bottom, Layout.tabBarExpanded + 12)
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
                            onTapFurniture: { f in
                                // ⚠️ 藏着的时候点家具 = **找他**，不是开家具的菜单。
                                // 两件事抢同一个点击，得让捉迷藏先。
                                guard hiding else { acting = f; return }
                                if f.id == hideSpot {
                                    reveal(found: true)
                                } else {
                                    notice = "不在这儿…"
                                    if app.settings.haptics {
                                        UIImpactFeedbackGenerator(style: .rigid)
                                            .impactOccurred()
                                    }
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                                        if notice == "不在这儿…" { notice = nil }
                                    }
                                }
                            },
                            // ⚠️ **他不在这一间就不画他。**
                            //
                            // 她说的：「clawd 在哪个房间，我打开小屋就会呈现哪个房间。」
                            // 反过来也成立——她翻到别的房间的时候，
                            // 他不该也跟着出现在那儿。想知道他在哪儿，看左上角那个头像。
                            // ⚠️ 捉迷藏藏着的时候也不画——藏起来还看得见就不叫藏
                            clawdHere: shownRoom == store.clawdRoom && !hiding) {
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
                        HStack(spacing: 4) {
                            Text(app.settings.aiName.isEmpty
                                 ? "阿晏" : app.settings.aiName)
                                .font(.app(9, weight: .medium))
                            Spacer(minLength: 6)
                            // 点得动就说出来。气泡上只放得下四十个字，
                            // 整段在聊天页——不写这一句她不会知道能点。
                            Text("看整段")
                                .font(.app(9))
                            Image(systemName: "chevron.right")
                                .font(.app(7, weight: .semibold))
                        }
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
                    // 点一下回聊天页看整段。
                    //
                    // 她说的：「如果整段要到聊天页看的话，
                    // 新增一个点击他说话的气泡回到聊天页吧，
                    // 只在接他进来的时候生效，家具触发的对话不生效。」
                    //
                    // ⚠️ **这一条只挂在他这个气泡上。**
                    // clawd 自己那个（`bubble`，挨着家具说的那些台词）
                    // 是本地写死的话，聊天页里根本没有它——
                    // 点过去只会是一屏跟那句话无关的记录。
                    // 两个气泡本来就是两个 View，所以不用另加判断；
                    // 而 `himLine` 只有接他进来之后才会有值。
                    .contentShape(RoundedRectangle(cornerRadius: 12,
                                                   style: .continuous))
                    .onTapGesture {
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        dismiss()
                    }
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
            // ⚠️⚠️ **手势那一排不在屋里了**，搬到屋子底下去了
            // （见 `handBar`）。她说的：「手势位置在房子中间，很碍事。」
            //
            // 搬出去之后有一件事必须跟着改：**坐标系**。
            // 拖手那个手势现在发生在外面那一层（“roomPage”），
            // 而他是按**屋子内部**的坐标摆的。两边差着一个屋子的原点，
            // 所以这儿把屋子在外层里的位置也记下来（`roomOrigin`），
            // 拖到哪儿先减掉它再跟他比（见 `toRoom`）。
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // 房间那一块有多大、在外层的什么位置。
            // **在 onAppear／onChange 里记**，不在 body 里直接写 @State——
            // 那会边画边改状态，SwiftUI 会警告，严重的时候还会来回重画停不下来。
            .onAppear {
                roomSize = geo.size
                roomOrigin = geo.frame(in: .named("roomPage")).origin
                settleHim()
            }
            .onChange(of: geo.size) { _, v in
                roomSize = v
                roomOrigin = geo.frame(in: .named("roomPage")).origin
                settleHim()
            }
            // 换个投影（立体 ⇄ 平面）也是换了一间屋子的形状
            .onChange(of: store.projection) { _, _ in settleHim() }
        }
        .padding(.horizontal, 16)
        // ⚠️ 底下那条给标签栏的留白**不在这儿**了：
        // 屋子底下现在还有一排手势，留在这里会把两者隔开一大截。
        // 挑到 `roomAndHands` 整块的底下去了。
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
                // 贴哪面墙。
                //
                // 她说的：「等距又不是只有一面墙，两面墙都应该可以放东西才对。
                // 本身靠左墙放的转方向之后就可以放在右墙不突兀了。」
                //
                // ⚠️ 字面写**改完是什么样**，不写「转方向」——
                // 她定的规矩：前端只说作用和用法。
                // 一个只有两档的东西，直接拿另一档当按钮名最清楚。
                //
                // 平面屋里不摆这一条：那一档用的是正面图，本来就不分左右。
                if store.projection == .iso {
                    Button(item.facesRight ? "改为靠左墙" : "改为靠右墙") {
                        store.flipFacing(item.id)
                    }
                }
                // 买过之后也能换一间。
                //
                // 她报的：「家具分区太绝对了，桌子也可以摆在卧室，
                // 但现在只能摆在餐厅。」——买下来归哪一间只是个默认，
                // 可**改这个默认的路以前不存在**：一件东西落在餐厅就出不来了。
                Button("搬到别的房间") { sending = item }
                Button("收起来") { store.toggleHidden(item.id) }
                Button("卖掉，退一半的币", role: .destructive) {
                    store.sell(item.id)
                    say("卖掉了，退回一半的币")
                }
            }
            Button("算了", role: .cancel) { }
        } message: {
            Text("长按可移动至房间内任意位置")
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
    // ⚠️ 这儿**没有 `@ViewBuilder`**，是故意的：底下是一句 `return`。
    // 两个一起写编译器会警告「显式 return 把 result builder 关掉了」——
    // 也就是说那个属性根本没起作用，留着只会让人以为它在起作用。
    private func clawdBody(_ size: CGSize) -> some View {
        // clawd 本人。长按能拎起来放到任何地方，
        // 没人管的时候他自己也会在屋里走来走去。
        //
        // ⚠️ **一格多大：这一段里所有的尺寸都从它算。**
        // 她说「小屋放大 clawd 的活动范围也要放大，连带的你都检查下」——
        // 「连带的」就是这些：他本人、他手上举的、举多高。
        // 写死一个数的话，屋子每改一次就有一样东西悄悄跟不上，
        // 而跟不上要等她截图给我看才发现。
        let tile = IsoRoom.fit(in: size, as: store.projection).tileW
        // ⚠️ **气泡不进这一摞。**
        //
        // 以前气泡跟他排在同一个 `VStack` 里，于是「他这一块」的高度
        // 会随气泡有没有而变——而定位、抬升全都按这个高度算，
        // 结果就是他一说话整只往下沉一截。
        //
        // 现在气泡挂成 overlay 浮在头顶，不占高度（见下面 `.overlay`）。
        return VStack(spacing: 4) {
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
                // ⚠️ 这个 32 **不要跟着图纸改成 40**。
                // 图纸从 32 加宽到 40 之后，多出来的八格全是透明边；
                // 身子还是那 24 格，`scale` 不变它画出来就还是原来那么大。
                // 改成 40 的话身子会当场瘦两成——她抱怨过一次他太小了。
                if let kind = store.carriedKind, store.overhead(kind) {
                    // 举大件（床、柜子）。
                    //
                    // ⚠️⚠️ **这一档必须走 `ClawdRigView`，不能再用
                    // 「`ClawdView` + 上面叠一张床」那套。**
                    //
                    // 叠的那套里，床的高度是 `-tile * 0.46` 硬写的，
                    // 手的位置是另一套算出来的——**两个来源**，
                    // 所以床跟手永远差那么一点，他一动就更明显。
                    //
                    // 换成 rig 之后，手和床都从 `ClawdRig.plan` 的
                    // 同一个 `armUpTop` 里来（见那一档的注释）：
                    // 床就搁在手尖上，对不齐这件事从根上不成立。
                    TimelineView(.animation) { ctx in
                        // 3.2 秒一个来回：举上去 → 撑住 → 沉下来。
                        // ⚠️ 用时钟取进度，不要拿 `@State` 计时——
                        // 这只 clawd 在小屋、聊天页、输入框上同时活着，
                        // 每秒六十次改状态整棵树跟着重画。
                        let beat = (ctx.date.timeIntervalSinceReferenceDate / 3.2)
                            .truncatingRemainder(dividingBy: 1)
                        ClawdRigView(mood: mood,
                                     item: kind.sprite,
                                     worn: store.wornKind?.sprite,
                                     wornID: store.wearing ?? "",
                                     pose: .lift,
                                     scale: tile * 1.47 / 36,
                                     beat: beat,
                                     shadow: true)
                    }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    // ⚠️ **`/ 36` 不是 `/ 32`，`1.47` 不是 `0.87`。**
                    // 除数是图纸宽度（现在 36 格），32 是它还叫 32 格那会儿的老账；
                    // 系数 0.87 → 1.47 是 ×1.5，换图纸那次欠的账：图纸从 54 格缩到 36 格（3 格/单位 → 2 格/单位），躯干跟着从 33 格变成 22 格，**scale 没跟着调，他在所有地方都缩了三分之一**。22 × s_new = 33 × s_old → 每一处 scale 都要 ×1.5 才回到原来那么大。
                    ClawdView(mood: mood, scale: tile * 1.47 / 36, shadow: true,
                              // 小屋里也要戴上。**两边都传**——只给一边的话，
                              // 她在这儿给他戴上帽子，切到聊天页就没了。
                              worn: store.wornKind?.sprite,
                              wornID: store.wearing ?? "",
                              // 高兴的时候**手要摆起来**。
                              // 她说的「随着他的情绪联动的表情，笑、冒爱心等等都没有」——
                              // 冒爱心那条早就有了（`.loving` 那一档），
                              // 缺的是手：以前不管什么情绪，手都是垂着的两块。
                              pose: ClawdHomeView.armPose(mood))
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
        // 量一下他画出来多高。**只量他自己**，气泡不算在内。
        .background {
            GeometryReader { g -> Color in
                let h = g.size.height
                if abs(h - bodyH) > 0.5 {
                    DispatchQueue.main.async { bodyH = h }
                }
                return Color.clear
            }
        }
        // 他说的那句话浮在头顶。**用 overlay 不用 VStack**——
        // overlay 不改变这一块的高度，所以他不会因为说了句话就往下沉。
        .overlay(alignment: .bottom) {
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
                    .offset(y: -bodyH - 8)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        // ⚠️⚠️ **按脚定位，不按正中。**
        //
        // `.position` 摆的是这一块的**正中**。往上抬半个身子之后，
        // 那个定位点就正好落在他脚底下——于是 `clawdX / clawdY` 的含义
        // 从「他的中心在哪儿」变成「他站在哪儿」。
        //
        // 这一句是「他半个身子在屋外」唯一该有的修法。
        // 在几何那边或者 `band` 里替他留白都是补丁：那两处不知道他多高，
        // 只能猜，猜过两次都不够（她两次都截图给我看）。
        .offset(y: -bodyH / 2)
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
                    // 放在能躺的东西上（床）就躺下，别站在床上发呆。
                    // 她要的：「我将它拖动到床上，他应该是上床的动画。」
                    if let act = layDownAct() {
                        mood = .lying
                        store.clawdDoing = .idling
                        say(act)
                        // ⚠️ **躺一会儿再起来溜达。** 立刻 `startWalking()`
                        // 的话他刚躺下就爬起来走了，等于没躺。
                        touchTask?.cancel()
                        touchUntil = Date().addingTimeInterval(9)
                        touchTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 9_000_000_000)
                            if Task.isCancelled { return }
                            mood = .idle
                            startWalking()
                        }
                        return
                    }
                    mood = .idle
                    say(["就待这儿吧", "好", "这儿也不错"].randomElement() ?? "好")
                    startWalking()              // 放下之后重新开始自己溜达
                }
        )

    }

    // MARK: 屋子的主题皮肤

    /// ⚠️ 拼好再给 `Text`。`Text(a + "（" + b + "）")` 那种一行三个 `+`，
    /// 类型检查会在这一行上卡到超时（`查一遍.py` 的 slowexpr 那条查的就是它）。
    static func viewLabel(_ p: RoomProjection) -> String {
        let head = p.label
        let tail = "（" + p.note + "）"
        return head + tail
    }

    /// 菜单里那一行怎么写。**没买的把价钱摆出来**——
    /// 点下去才发现要钱，比一开始就写着更让人不舒服。
    private func themeMenuLabel(_ t: RoomTheme) -> String {
        let head = t.label + "（" + t.note + "）"
        return store.hasTheme(t) ? head : head + " · \(t.price) 币"
    }

    /// 挑了一套：有就换上，没有就问要不要买。
    private func pickTheme(_ t: RoomTheme, in r: HomeRoom) {
        if store.hasTheme(t) {
            store.applyTheme(t, to: r)
            notice = r.rawValue + "换成「" + t.label + "」了"
            return
        }
        // ⚠️ **买之前问一声。** 这是要花她币的，
        // 而菜单里手一滑就点到了——家具那边是有商店页可以看的，
        // 主题只有这一个入口，没有第二道确认就等于误触即扣款。
        buying = (t, r)
    }

    // MARK: 她的手

    /// 手势按钮 + 拖出来的那只手。
    ///
    /// 她说的：「有一个小手掌 ✋🏻 点击切换，然后我可以拖过来摸摸他的头 🫳🏻，
    /// 可以戳他 👈🏻👉🏻，可以轻轻打他 🤜🏻🤛🏻，可以跟他捉迷藏用 👇🏻👆🏻 找他。」
    ///
    /// ⚠️ **点 = 换手势，拖 = 用这个手势碰他。两件事分开。**
    /// 靠划动的方向去猜「这一下是摸还是打」，猜错一次就是
    /// 「我明明在摸他他为什么哭」——而摸和打是这套里情绪差最远的两个。
    /// 屋子底下那一排手势。
    ///
    /// ⚠️ **四个一次全摆出来，不是一个按钮循环切。**
    ///
    /// 原来是一个按钮，点一下换下一个。想用「轻轻打」得先点三下，
    /// 而且点之前根本不知道下一个是什么 —— 她说的「ui 太简单」是这个意思：
    /// 不是不好看，是**看不见自己有什么**。
    ///
    /// ⚠️ **点 = 选，拖 = 用这个手势碰他。两件事分开。**
    /// 靠划动的方向去猜「这一下是摸还是打」，猜错一次就是
    /// 「我明明在摸他他为什么哭」——而摸和打是这套里情绪差最远的两个。
    private var handBar: some View {
        VStack(spacing: 7) {
            // 藏起来的时候顶上多一行「不找了」
            if hiding {
                Button {
                    reveal(found: false)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "eye.slash")
                            .font(.app(10))
                        Text("他藏起来了 · 不找了")
                            .font(.app(11, weight: .medium))
                    }
                    .foregroundStyle(app.settings.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(app.settings.accentColor.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 8) {
                ForEach(HandTool.allCases) { tool in
                    handChip(tool)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .glassBackground(radius: 20, strength: app.settings.glassOpacity)

            Text(hiding ? "点家具找他" : "按住拖到他身上")
                .font(.app(9.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(.top, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hiding)
    }

    /// 一个手势。选中的那个亮起来，拖它就是用它碰他。
    private func handChip(_ tool: HandTool) -> some View {
        let on = hand == tool
        return VStack(spacing: 3) {
            Text(tool.emoji)
                .font(.app(24))
            Text(tool.label)
                .font(.app(9.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? app.settings.accentColor : Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? app.settings.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(on ? app.settings.accentColor.opacity(0.45) : Color.clear,
                              lineWidth: 1)
        )
        .scaleEffect(on ? 1.0 : 0.94)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: on)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // ⚠️⚠️ **碰到就算，不用松手。**
        //
        // 她说的：「手势必须拖到他身上再放掉才能触发，
        // 　修改成我拖着不放在他身上就触发。比如我用戳戳的
        // 　那个手势，拖到他身上一下算是戳一下，我移开再拖到
        // 　他身上等于戳第二下。」
        //
        // 所以判定是**进入他的范围那一刻**触发一次，出去再进来算下一次。
        // `handOnHim` 记着现在在不在里面 —— 没有它的话每一帧 onChanged
        // 都会算一下，手指在他身上停半秒就是几十次戳。
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("roomPage"))
                .onChanged { v in
                    // 拖哪个就用哪个，不用先点一下选中
                    if hand != tool { hand = tool }
                    handAt = v.location
                    guard let size = roomSize else { return }
                    let over = touching(toRoom(v.location), in: size)
                    if over, !handOnHim {
                        handOnHim = true
                        contact(in: size)
                    } else if !over {
                        handOnHim = false
                    }
                }
                .onEnded { v in
                    // 一路滑进去再松手的，进去那一下已经算过了；
                    // 这儿只兜住「一帧都没落在里面就松手」的那种
                    if !handOnHim, let size = roomSize,
                       touching(toRoom(v.location), in: size) {
                        contact(in: size)
                    }
                    handAt = nil
                    handOnHim = false
                }
        )
        .onTapGesture { pickHand(tool) }
    }

    /// 选一个手势
    private func pickHand(_ tool: HandTool) {
        guard hand != tool else { return }
        hand = tool
        if app.settings.haptics {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// 外面那一层（"roomPage"）的点，换算成屋子内部的点。
    ///
    /// ⚠️ 手势条搬到屋子外面之后**必须过这一道**。
    /// 不换算的话拖到屋子上半截才碰得到他 —— 差的正好是屋子的原点。
    private func toRoom(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - roomOrigin.x, y: p.y - roomOrigin.y)
    }


    /// 他现在站的那一格上有没有能躺的东西（床）。有就返回一句台词。
    ///
    /// ⚠️ **判定靠 `IsoShape.actions`，不靠家具的名字。**
    /// 按名字认的话（`kind.hasPrefix("bed")`），她以后加一张沙发床、
    /// 或者从整版图里切一件新的躺具，就得回来改这儿。
    /// `actions` 那张表本来就写着「这件东西能拿它干什么」——
    /// 加新家具的时候顺手写上「躺下」，这儿自动就认。
    private func layDownAct() -> String? {
        guard let size = roomSize, size.width > 1, size.height > 1 else { return nil }
        let geo = IsoRoom.fit(in: size, as: store.projection)
        let here = geo.tile(at: CGPoint(x: clawdX * size.width,
                                        y: clawdY * size.height))
        let (hx, hy) = geo.clamp(Int(here.gx.rounded()), Int(here.gy.rounded()))
        for f in store.furniture(in: shownRoom) where f.gx >= 0 {
            let s = FurnitureCatalog.shape(of: f.kind)
            guard hx >= f.gx, hx < f.gx + max(1, s.w),
                  hy >= f.gy, hy < f.gy + max(1, s.d) else { continue }
            guard s.actions.contains(where: { $0 == "躺下" || $0 == "钻被窝" })
            else { continue }
            return ["躺一会儿", "唔……软的", "就眯一小会儿"].randomElement() ?? "躺一会儿"
        }
        return nil
    }

    /// 这个点落在他身上没有。
    private func touching(_ p: CGPoint, in size: CGSize) -> Bool {
        // 他不在这一间、或者正藏着，就没得碰
        guard shownRoom == store.clawdRoom, !hiding, !held else { return false }
        let tile = IsoRoom.fit(in: size, as: store.projection).tileW
        // ⚠️ 平铺屋拖走了多远也要算进来（见 `ClawdStore.flatPanX`）——
        // 他的画跟着屋子走，判定不跟就永远碰不到他。
        let pan = store.projection == .flat ? store.flatPanX : 0
        let him = CGPoint(x: clawdX * size.width + pan,
                          y: clawdY * size.height)
        let dx = p.x - him.x, dy = p.y - him.y
        // ⚠️ 半径按**他有多高**给，不是按一格多宽。他约 1.47 格高，
        // 而且头顶还顶着说话的气泡，位置会往下挪半个身子。
        // 差几个点就没碰到的话，她会以为这功能是坏的。
        let reach = tile * 1.2
        return dx * dx + dy * dy < reach * reach
    }

    /// 碰到他了：给一次反应。
    private func contact(in size: CGSize) {
        if hand == .seek { hide(in: size); return }

        let r = patience.touch(hand)
        touchTask?.cancel()
        touchUntil = Date().addingTimeInterval(r.hold)
        walkTask?.cancel()                  // 有反应的时候先别走
        withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) { mood = r.mood }
        say(r.line)
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: r.haptic).impactOccurred()
        }
        touchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(r.hold * 1_000_000_000))
            if Task.isCancelled { return }
            // ⚠️ 恼着的时候**不回 idle**，一直板着脸等她哄。
            // 「生气」两秒就自己好了的话，那不叫生气，叫抽搐。
            mood = patience.sulking ? .upset : .idle
            startWalking()
        }
    }

    // MARK: 捉迷藏

    /// 他躲起来了，躲在某一件家具后面。点对了那件才算找到。
    private func hide(in size: CGSize) {
        let here = store.furniture(in: shownRoom).filter { $0.gx >= 0 }
        guard let spot = here.randomElement() else {
            say("这屋里没地方躲呀")
            return
        }
        touchTask?.cancel()
        walkTask?.cancel()
        hideSpot = spot.id
        // 先挪到那件家具那儿，找到的时候他就从那儿冒出来
        let pt = IsoRoom.fit(in: size, as: store.projection).point(Double(spot.gx), Double(spot.gy))
        clawdX = pt.x / size.width
        clawdY = pt.y / size.height
        withAnimation(.easeOut(duration: 0.3)) { hiding = true }
        say("数到十…… 来找我")
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        // ⚠️ 得有个头。找不到就一直躲着的话，她就永远看不到他了。
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            if Task.isCancelled || !hiding { return }
            reveal(found: false)
        }
    }

    /// 找出来了（`found`）／她不玩了或者超时了。
    private func reveal(found: Bool) {
        hideTask?.cancel()
        hideSpot = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { hiding = false }
        mood = found ? .happy : .peeking
        say(found ? ["被找到啦", "嘿嘿", "你好厉害"].randomElement() ?? "被找到啦"
                  : ["我在这儿…", "找不到我吗", "出来啦"].randomElement() ?? "我在这儿…")
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: found ? .medium : .soft).impactOccurred()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if mood == .happy || mood == .peeking { mood = .idle }
            startWalking()
        }
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

    /// 柜子里按**种**归拢：同一种买了几件只占一张卡片，右下角标数量。
    ///
    /// ⚠️ 顺序按**第一件买进来的先后**，不排序也不按 id 排。
    /// 每次进柜子顺序都变的话，她刚放下的那件下次就找不着了。
    private var cabinetGroups: [(kind: FurnitureKind, count: Int)] {
        var order: [String] = []
        var n: [String: Int] = [:]
        for f in store.owned {
            if n[f.kind] == nil { order.append(f.kind) }
            n[f.kind, default: 0] += 1
        }
        return order.compactMap { id in
            guard let k = FurnitureCatalog.kind(id), let c = n[id] else { return nil }
            return (k, c)
        }
    }

    private var cabinet: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: 3), spacing: 12) {
                ForEach(cabinetGroups, id: \.kind.id) { g in
                    let kind = g.kind
                    let out = store.outCount(of: kind.id)
                    let all = g.count
                    VStack(spacing: 6) {
                        // ⚠️ 60 → 34。她报的：「商店里的物品缩略图
                        // 再小一半，现在太大了，下面 clawd 的衣服
                        // 更是大的离谱。」
                        //
                        // 穿戴那几件本来就画得满格（一顶帽子占满整张图），
                        // 跟一张画着整间屋的床图摆在一起，看着就大一圈。
                        FurnitureThumb(kind: kind, height: 34, scale: 1.4)
                            .opacity(out > 0 ? 1 : 0.35)
                        Text(kind.name)
                            .font(.app(10))
                            .foregroundStyle(out > 0
                                             ? Theme.textMain(scheme)
                                             : Theme.textMuted(scheme))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .glassCard(padding: 0)
                    // ⚠️ 穿戴那一类点一下是**穿上／脱下**，不是收起来。
                    // 她报的：「贝雷帽被当成家具放在房间里，
                    // 实际上应该给他直接穿上。」——一顶帽子摆在地板上是很怪。
                    .overlay(alignment: .topTrailing) {
                        if kind.category == .wear, store.wearing == kind.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.app(12))
                                .foregroundStyle(app.settings.accentColor)
                                .padding(5)
                        }
                    }
                    // 右下角那个数：**摆出去几件 / 一共几件**。
                    //
                    // 她要的：「在柜子物品的右下角显示数量，可以重复摆放。」
                    //
                    // ⚠️ 只有一件的时候不标——一个「1/1」是噪音，
                    // 图标暗着就已经说明它收起来了。
                    .overlay(alignment: .bottomTrailing) {
                        if all > 1 {
                            Text(String(out) + "/" + String(all))
                                .font(HomeType.number(9))
                                .foregroundStyle(out > 0
                                                 ? Theme.textSoft(scheme)
                                                 : Theme.textMuted(scheme))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.softFillDeep))
                                .padding(5)
                        }
                    }
                    // 点一下**动一件**，不是一整种：
                    // 柜子里还有存货就摆出去一件，都摆出去了就收回来一件。
                    .onTapGesture {
                        if kind.category == .wear {
                            store.wear(kind.id)
                        } else if !store.putOutOne(kind.id) {
                            store.takeBackOne(kind.id)
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
                Text("点一下摆出一件，都摆出去后再点一下收回一件")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
    }

    // MARK: 商店

    private var shop: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 长按那条路不写出来她找不到。同一件可以买很多份，
                // 长按能挑数量和放进哪一间。
                Text("点一下买一件，长按可以选数量和房间")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))

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

    /// 商店里的一格。**点一下买一件，长按挑数量和房间。**
    ///
    /// 她说的：「家具可以重复购买，不要点一下就放点一下就收……
    /// 在添加家具的时候可以长按选择添加到哪里还有购买数量。」
    ///
    /// ⚠️ 「已有」不再是**灰掉不能点**，只是一个数。
    private func shopItem(_ kind: FurnitureKind) -> some View {
        let have = store.count(of: kind.id)
        let afford = store.coins >= kind.price
        return Button {
            let got = store.buy(kind)
            if got > 0 {
                say(kind.name + "买到了")
                tab = 0
            } else {
                say("币不够，再攒攒")
            }
        } label: {
            VStack(spacing: 5) {
                FurnitureThumb(kind: kind, height: 30, scale: 1.3)
                Text(kind.name)
                    .font(.app(10))
                    .foregroundStyle(Theme.textMain(scheme))
                HStack(spacing: 3) {
                    Circle().fill(HomePalette.amber).frame(width: 6, height: 6)
                    Text("\(kind.price)")
                        .font(HomeType.number(10))
                }
                .foregroundStyle(afford
                                 ? Theme.textSoft(scheme)
                                 : Theme.textMuted(scheme).opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .glassCard(padding: 0)
            .overlay(alignment: .topTrailing) {
                if have > 0 {
                    Text("已有 " + String(have))
                        .font(.app(9))
                        .foregroundStyle(StatusTone.done.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.softFillDeep))
                        .padding(5)
                }
            }
            .opacity(afford ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        // ⚠️ 用 `onLongPressGesture` 而不是 `contextMenu`：
        // 要挑数量和房间，菜单里塞不下一个步进器。
        .onLongPressGesture(minimumDuration: 0.35) {
            if app.settings.haptics {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            shopping = kind
        }
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
                patience.relax()        // 晾着的时候气自己消，见 relax 的注释
                if !patience.sulking, mood == .upset, Date() >= touchUntil {
                    mood = .idle        // 气消了，脸也松开
                }
                // ⚠️ **正在挨戳、正生着气、正藏着，都不许自己走开。**
                // 她刚戳完他他就转身溜达，那一下反应等于没有；
                // 藏起来的人会走的话，就更没法找了。
                guard mood != .happy, !held, !hiding,
                      Date() >= touchUntil, !patience.sulking else { continue }

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

                    let geo = IsoRoom.fit(in: size, as: store.projection)
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

                // 走到谁旁边了。
                //
                // ⚠️ **只看他这一间的**。原来这儿是 store.owned——整个家的家具，
                // 而 x/y 是每间屋子各自的 0…1 坐标：书房里 (0.5, 0.5) 的书架，
                // 跟他站在客厅 (0.5, 0.5) 就算「挨着」。
                // 她报的「他在客厅、在厨房，也会说抽一本出来看看」就是这么来的。
                let near = store.furniture(in: store.clawdRoom)
                    .filter { !$0.hidden && !$0.carried }
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


    // MARK: 跟他说话

    /// 小屋最底下那条输入框。
    ///
    /// 她要的：「在小屋最下面应该新增一个输入框供我给他打字交流。」
    ///
    /// ## 为什么走聊天那条路，而不是另开一条
    ///
    /// 她这句话要同时出现在**聊天页**里（「文字显示在 clawd 的气泡和
    /// 聊天页里」）。另开一条的话，小屋里聊的和聊天页里聊的就是两段
    /// 互相不知道的记忆——她在屋里问过的事，回聊天页再问一遍他会不认。
    ///
    /// 走 `app.send` 就什么都对上了：落进同一段记录、带着同样的上下文、
    /// 用量也照常算。多带的只有一句「他此刻在哪一间、屋里有什么」
    /// （见 `AppState.houseContext`）。
    private var himBar: some View {
        let ready = !himDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            TextField("跟他说点什么", text: $himDraft, axis: .vertical)
                .font(.app(13))
                .lineLimit(1...3)
                .focused($typing)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.softFillDeep))
                .submitLabel(.send)
                .onSubmit { sendToHim() }

            Button {
                sendToHim()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.app(24))
                    .foregroundStyle(ready
                                     ? app.settings.accentColor
                                     : Theme.textMuted(scheme).opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!ready)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func sendToHim() {
        let t = himDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // ⚠️ 没有当前会话就没地方落这句话。**要说出来**——
        // 静悄悄地吞掉的话，她会以为输入框坏了。
        guard let cid = app.activeChatID else {
            notice = "还没有打开的会话，先去聊天页开一个"
            return
        }
        himDraft = ""
        typing = false
        // 发出去之前把这一刻的屋子记下来——他要知道自己站在哪儿。
        //
        // ⚠️ `canArrange: false`：聊天那条路上**没有**动手的那份约定
        // （`RoomMarker.contract`），也没人解析他写的记号。给 true 的话
        // 他会往回复里写 `[[…]]`，那几个字会原样落进她的聊天记录。
        app.houseContext = "【她此刻开着 clawd 的小屋在跟你说话，"
            + "你借着 clawd 的身体待在屋里】\n"
            + store.homeBrief(watching: viewing, canArrange: false)
        app.send(text: t, images: [], in: cid)
    }

    /// 聊天那边他刚说完的那句，搬到 clawd 的气泡上。
    ///
    /// ⚠️ **等它说完再搬**（`isStreaming` 落下来才算）。
    /// 边流边搬的话气泡会一个字一个字地跳，而气泡只有两行的地方。
    private func mirrorHisReply() {
        guard store.linked,
              let last = app.lastHisMessage,
              !last.isStreaming, last.errorText == nil,
              last.id != mirrored else { return }
        let line = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        mirrored = last.id
        guard !line.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            // 气泡上只放前面一截。整段长文该在聊天页看，
            // 挤进一个两行的气泡里等于两边都读不成。
            himLine = line.count > 40 ? String(line.prefix(40)) + "…" : line
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 14_000_000_000)
            withAnimation(.easeOut(duration: 0.3)) { himLine = nil }
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
                // ⚠️ **只看他这一间的**，跟走路那儿同一个理由（见上面那段注释）。
                //
                // 她又报了一次：「即使他在客厅、在厨房，书房有书架，
                // 他就会触发『抽一本出来看看』的台词，但他根本不在书房。」
                // 上一次只修了走路那条路，这一条（接他进来之后隔几分钟问他一句）
                // 漏了——`store.owned` 是整个家的家具，而 x/y 是每间屋子
                // **各自的** 0…1 坐标，书房里 (0.5,0.5) 的书架跟他站在
                // 客厅 (0.5,0.5) 算出来就是「挨着」。
                let near = store.furniture(in: store.clawdRoom)
                    .filter { !$0.hidden && !$0.carried }
                    .min { a, b in
                        abs(a.x - clawdX) + abs(a.y - clawdY)
                            < abs(b.x - clawdX) + abs(b.y - clawdY)
                    }
                // 还得**真的挨着**才算。`min` 只挑出最近的一件，
                // 屋里就一件家具、他站在对角，也会被算成「走到它旁边」。
                // 阈值跟走路那条一致。
                let reallyNear = near.flatMap {
                    (abs($0.x - clawdX) < 0.16 && abs($0.y - clawdY) < 0.20) ? $0 : nil
                }
                let nearName = (reallyNear.flatMap { FurnitureCatalog.kind($0.kind)?.name }) ?? ""
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
                    // 她要的：「文字显示在 clawd 的气泡和聊天页里。」
                    //
                    // ⚠️ **只落记录，不再发一次请求**（见 `noteHouseLine`）——
                    // 这句话刚才已经付过钱了。
                    app.noteHouseLine(line)
                    // 落下去的那条就是气泡上这句，别再当成「新回复」搬一遍
                    mirrored = app.lastHisMessageID
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
