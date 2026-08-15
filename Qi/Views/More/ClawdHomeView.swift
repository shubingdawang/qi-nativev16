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
    @State private var bubble: String?
    @State private var bubbleTask: Task<Void, Never>?
    @State private var walkTask: Task<Void, Never>?
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            header

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
        .onAppear { startWalking() }
        .onDisappear {
            walkTask?.cancel()
            bubbleTask?.cancel()
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(app.settings.accentColor.opacity(0.28)))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            // 把阿晏接进来
            Button {
                store.linked.toggle()
                say(store.linked ? "他进来了" : "他先出去了")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.linked ? "person.2.fill" : "person.2")
                        .font(.system(size: 11))
                    Text(store.linked ? "他在" : "接他进来")
                        .font(.system(size: 11))
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
                            .contextMenu {
                                Button {
                                    store.toggleHidden(item.id)
                                } label: {
                                    Label("收起来", systemImage: "eye.slash")
                                }
                                Button(role: .destructive) {
                                    store.sell(item.id)
                                    say("卖掉了，退回一半的币")
                                } label: {
                                    Label("卖掉", systemImage: "arrow.uturn.left")
                                }
                            }
                    }
                }

                // clawd
                VStack(spacing: 4) {
                    if let bubble {
                        Text(bubble)
                            .font(.system(size: 11))
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
                    ClawdView(mood: mood, scale: 1.8)
                }
                .position(x: clawdX * geo.size.width, y: geo.size.height * 0.78)
                .animation(.easeInOut(duration: 2.4), value: clawdX)
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

                if let notice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Layout.tabBarExpanded + 12)
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
                                .font(.system(size: 10))
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
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.top, 50)
            } else {
                Text("点一下收起来或者摆回房间")
                    .font(.system(size: 10))
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
                            .font(.system(size: 13, weight: .semibold))
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
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMain(scheme))
                if owned {
                    Text("已有")
                        .font(.system(size: 9))
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

    /// 隔一会儿挪一下，挪到哪件东西旁边就说一句相关的
    private func startWalking() {
        walkTask?.cancel()
        walkTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 6...14) * 1_000_000_000)
                if Task.isCancelled { return }
                guard mood != .happy else { continue }

                clawdX = Double.random(in: 0.15...0.85)

                // 走到谁旁边了
                let near = store.owned.filter { !$0.hidden }
                    .min { abs($0.x - clawdX) < abs($1.x - clawdX) }
                if let near, abs(near.x - clawdX) < 0.16,
                   let kind = FurnitureCatalog.kind(near.kind),
                   Bool.random() {
                    say(kind.reaction)
                }
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
