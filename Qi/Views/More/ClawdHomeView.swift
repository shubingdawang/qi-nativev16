import SwiftUI

/// clawd 的家。
///
/// 房间是一整块可以摆东西的地方：长按拿起来，拖到哪儿放哪儿。
/// clawd 会自己走动，挨到哪件东西就做出相应的反应。
struct ClawdHomeView: View {

    @ObservedObject private var store = ClawdStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var tab = 0            // 0 房间，1 柜子，2 商店
    @State private var dragging: UUID?
    @State private var dragPoint: CGPoint = .zero
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

    var body: some View {
        VStack(spacing: 0) {
            header

            // 接进来了就一直摆着这一行。铁律第二条：会自己花钱的地方，
            // 得让她看得见它开着。
            if store.linked {
                Text("他在这屋里，开着这一页的时候会自己隔几分钟说一句 · 花钱")
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
            case 0: room
            case 1: cabinet
            default: shop
            }
        }
        .navigationTitle("clawd")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startWalking()
            startHim()
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
        .confirmationDialog("把他接进这间屋子？", isPresented: $askingLink,
                            titleVisibility: .visible) {
            Button("接进来") {
                store.linked = true
                say("他进来了")
            }
            Button("算了", role: .cancel) { }
        } message: {
            Text("接进来之后，你开着这一页的时候，他会隔几分钟自己冒一句——看看你给他布置的这个家。\n\n这是**真的问他**，所以会花钱，而且不用你点。用量在设置里按「clawd 小屋」单独记着。\n\n关掉就不花了。")
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

    // MARK: 房间

    private var room: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 墙和地板
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(scheme == .dark
                              ? Color(hexString: "2A2622")!
                              : Color(hexString: "EFE7D9")!)
                        .frame(height: geo.size.height * 0.62)
                    Rectangle()
                        .fill(scheme == .dark
                              ? Color(hexString: "3A322A")!
                              : Color(hexString: "D9C9AE")!)
                }

                // 家具
                ForEach(store.owned.filter { !$0.hidden }) { item in
                    if let kind = FurnitureCatalog.kind(item.kind) {
                        PixelSpriteView(sprite: kind.sprite, scale: 3.2)
                            .position(
                                x: (dragging == item.id ? dragPoint.x : item.x) * geo.size.width,
                                y: (dragging == item.id ? dragPoint.y : item.y) * geo.size.height
                            )
                            .scaleEffect(dragging == item.id ? 1.12 : 1)
                            .shadow(color: .black.opacity(dragging == item.id ? 0.22 : 0),
                                    radius: 8, y: 4)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                                       value: dragging == item.id)
                            // **长按拖不动的根子在这一行**。
                            //
                            // PixelSpriteView 里那块 Canvas 自己写着
                            // allowsHitTesting(false)，所以它整个不接触摸——
                            // 外面挂多少手势都落在空气上。clawd 本人早就补过这块，
                            // 家具一直没补。顺手放大一圈：一件家具才几十个点，
                            // 手指按不准。
                            .contentShape(Rectangle().inset(by: -12))
                            // 单击开小菜单。
                            //
                            // 这两件事以前挂在 .contextMenu 上——**而 contextMenu
                            // 本身就是长按触发的**，跟下面这个长按拖拽抢同一个手势，
                            // 谁也抢不干净。收起来和卖掉挪到单击这边，长按就干干净净
                            // 只管搬东西。
                            .onTapGesture { acting = item }
                            .gesture(
                                LongPressGesture(minimumDuration: 0.28)
                                    .onEnded { _ in
                                        dragging = item.id
                                        dragPoint = CGPoint(x: item.x, y: item.y)
                                        if app.settings.haptics {
                                            UIImpactFeedbackGenerator(style: .medium)
                                                .impactOccurred()
                                        }
                                        say(pickUpLine(kind))
                                    }
                                    .sequenced(before: DragGesture())
                                    .onChanged { value in
                                        if case .second(_, let drag?) = value {
                                            dragPoint = CGPoint(
                                                x: drag.location.x / geo.size.width,
                                                y: drag.location.y / geo.size.height)
                                        }
                                    }
                                    .onEnded { _ in
                                        if dragging == item.id {
                                            store.move(item.id, to: dragPoint)
                                        }
                                        dragging = nil
                                    }
                            )
                    }
                }

                // clawd 本人。长按能拎起来放到任何地方，
                // 没人管的时候他自己也会在屋里走来走去。
                VStack(spacing: 4) {
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
                        ClawdView(mood: mood, scale: 1.8, shadow: true)
                        // 手上那件。跟聊天页读的是同一个 store，所以两边同步。
                        if let kind = store.carriedKind {
                            PixelSpriteView(sprite: kind.sprite, scale: 1.5)
                                .offset(y: -8)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                        // 被拎起来的时候整只抬高一点、影子也跟着散开
                        .scaleEffect(held ? 1.14 : 1)
                        .shadow(color: .black.opacity(held ? 0.26 : 0),
                                radius: 10, y: 8)
                        // 走路的时候左右翻个身，朝着要去的方向
                        .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
                        // 精灵那块 Canvas 是不接触摸的，得自己补一块感应区，
                        // 不然点也点不到、更别说长按拖
                        .contentShape(Rectangle().inset(by: -10))
                }
                .position(x: clawdX * geo.size.width, y: clawdY * geo.size.height)
                // 拖的时候要跟手，所以不给动画；自己走的时候才慢慢挪过去
                .animation(held ? nil : .easeInOut(duration: walkSeconds), value: clawdX)
                .animation(held ? nil : .easeInOut(duration: walkSeconds), value: clawdY)
                .animation(.spring(response: 0.28, dampingFraction: 0.6), value: held)
                .onTapGesture {
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
                                clawdX = min(0.92, max(0.08, drag.location.x / geo.size.width))
                                clawdY = min(0.94, max(0.10, drag.location.y / geo.size.height))
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
                        Text(himLine)
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
    }

    // MARK: 柜子

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
                        .onTapGesture { store.toggleHidden(item.id) }
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

                let targetX = Double.random(in: 0.12...0.88)
                let targetY = Double.random(in: 0.22...0.90)
                let dist = ((targetX - clawdX) * (targetX - clawdX)
                            + (targetY - clawdY) * (targetY - clawdY)).squareRoot()

                facingLeft = targetX < clawdX
                walkSeconds = 1.6 + dist * 3.2
                // 走的这一路上换成"在忙活"那两帧，腿看着像在倒腾
                mood = store.carrying == nil ? .walking : .hauling
                clawdX = targetX
                clawdY = targetY

                try? await Task.sleep(nanoseconds: UInt64(walkSeconds * 1_000_000_000))
                if Task.isCancelled { return }
                if mood == .walking || mood == .hauling {
                    mood = store.carrying == nil ? .idle : .carrying
                }

                // 走到谁旁边了
                let near = store.owned.filter { !$0.hidden }
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
                let near = store.owned.filter { !$0.hidden }
                    .min { a, b in
                        abs(a.x - clawdX) + abs(a.y - clawdY)
                            < abs(b.x - clawdX) + abs(b.y - clawdY)
                    }
                let nearName = (near.flatMap { FurnitureCatalog.kind($0.kind)?.name }) ?? ""
                let line = await app.clawdSays(
                    room: store.roomBrief(),
                    near: nearName,
                    carrying: store.carriedKind?.name ?? "")
                if Task.isCancelled { return }
                if let line {
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
