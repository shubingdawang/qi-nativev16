import SwiftUI
import PhotosUI

/// 大富翁的棋盘，画出来的那一版。
///
/// 她说这一页太单调。原来棋盘是一行等宽字符：
/// `［🔵🎯］［🎯］［💬］…` ——二十格排成一条，走到第几格全靠数，
/// 手机上还得横着滚。**它是「一份状态的文字打印」，不是一张棋盘。**
///
/// 现在是真的一圈：二十格围成方的，中间那块写着回合、该谁、两个人的家当。
///
/// 素材那件事按老规矩办（跟手帐、飞行棋一样）：
/// **画法我写好，图她自己放。** 仓库还是公开的，我不往里 commit 下载来的图；
/// 她想换成自己的，右上角「换成我的图」挑一张就行，随时能换回画的这版。
struct MonopolyBoard: View {

    @ObservedObject var game: MonopolyGame

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 她自己放进来的底图（文件名）。空 = 用画的那版。
    @AppStorage("monopolyBoardImage") private var boardImage = ""
    @State private var picking: PhotosPickerItem?

    /// 二十格围一圈：上边 6、右边 4、下边 6、左边 4，正好摆进 6×6。
    /// 0 号在左上角，顺时针走。
    static func spot(_ i: Int) -> (col: Int, row: Int) {
        switch i {
        case 0...5:   return (i, 0)
        case 6...9:   return (5, i - 5)
        case 10...15: return (15 - i, 5)
        default:      return (0, 20 - i)
        }
    }

    /// 每种格子一个色。**不用一堆 emoji 顶事**——
    /// 一圈二十个 emoji 挤在一起看不出哪格是哪格，颜色才分得开。
    static func tint(_ kind: String) -> Color {
        switch kind {
        case "start":   return Color(hexString: "E0B978")!
        case "truth":   return Color(hexString: "94B4D6")!
        case "shop":    return Color(hexString: "A3C79C")!
        case "jail":    return Color(hexString: "B79ec4")!
        case "chance":  return Color(hexString: "E5AE80")!
        case "mystery": return Color(hexString: "AEA69A")!
        default:        return Color(hexString: "DE9DB0")!   // task
        }
    }

    static func glyph(_ kind: String) -> String {
        switch kind {
        case "start":   return "flag.checkered"
        case "truth":   return "bubble.left.and.bubble.right.fill"
        case "shop":    return "cart.fill"
        case "jail":    return "lock.fill"
        case "chance":  return "sparkles"
        case "mystery": return "questionmark"
        default:        return "heart.fill"
        }
    }

    /// 棋子颜色。引擎里存的是 🔵🔴 这种，换成能画的。
    static func tokenColor(_ emoji: String) -> Color {
        switch emoji {
        case "🔴": return Color(hexString: "D96A6A")!
        case "🟢": return Color(hexString: "6FAE72")!
        case "🟡": return Color(hexString: "D9B44A")!
        case "🟣": return Color(hexString: "9B7BC4")!
        case "🟠": return Color(hexString: "DE9046")!
        default:   return Color(hexString: "5A8FD0")!       // 🔵
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let side = min(geo.size.width, 460)
                let cell = side / 6
                ZStack {
                    // 她自己的底图（放过就有）
                    if !boardImage.isEmpty, let ui = ImageStore.load(boardImage) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .opacity(0.85)
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.softFillDeep)
                    }

                    ForEach(0..<20, id: \.self) { i in
                        let p = Self.spot(i)
                        tile(i, size: cell)
                            .frame(width: cell, height: cell)
                            .position(x: (CGFloat(p.col) + 0.5) * cell,
                                      y: (CGFloat(p.row) + 0.5) * cell)
                    }

                    center
                        .frame(width: cell * 4 - 10, height: cell * 4 - 10)
                        .position(x: side / 2, y: side / 2)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity)
            }
            .frame(height: boardSide)

            HStack(spacing: 12) {
                PhotosPicker(selection: $picking, matching: .images) {
                    Label(boardImage.isEmpty ? "换成我的图" : "再换一张", systemImage: "photo")
                        .font(.app(11))
                        .foregroundStyle(app.settings.accentColor)
                }
                if !boardImage.isEmpty {
                    Button("用画的这版") { boardImage = "" }
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .onChange(of: picking) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let name = ImageStore.save(image) else { return }
                await MainActor.run {
                    boardImage = name
                    picking = nil
                }
            }
        }
    }

    /// 棋盘多高。屏幕窄就跟着窄，但别超过 460——
    /// 再大格子里也就那点东西，反而空。
    private var boardSide: CGFloat {
        min(UIScreen.main.bounds.width - 32, 460)
    }

    // MARK: 一格

    private func tile(_ i: Int, size: CGFloat) -> some View {
        let kind = game.tileKind(i)
        let tint = Self.tint(kind)
        let here = [game.s.p1, game.s.p2].filter { $0.pos == i }

        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.40 : 0.30))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint.opacity(0.55), lineWidth: 1)

            VStack(spacing: 2) {
                Image(systemName: Self.glyph(kind))
                    .font(.system(size: size * 0.24))
                    .foregroundStyle(tint)
                Text("\(i)")
                    .font(.app(8))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            // 棋子。两个人踩同一格就并排站，不叠着——叠着看不出来有两个人。
            if !here.isEmpty {
                HStack(spacing: 2) {
                    ForEach(here, id: \.name) { p in
                        Circle()
                            .fill(Self.tokenColor(p.color))
                            .frame(width: size * 0.22, height: size * 0.22)
                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.2))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                }
                .offset(y: size * 0.30)
            }
        }
        .padding(2)
    }

    // MARK: 中间那块

    private var center: some View {
        VStack(spacing: 8) {
            Text("回合 \(game.s.turnCount) / \(game.s.totalRounds)")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))

            Text("该 \(game.s.turn) 掷")
                .heading(17)
                .foregroundStyle(Theme.textMain(scheme))
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                seat(game.s.p1)
                seat(game.s.p2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
    }

    private func seat(_ p: MonopolyGame.Player) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Self.tokenColor(p.color))
                .frame(width: 8, height: 8)
            Text(p.name)
                .font(.app(11.5, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text("第 \(p.lap + 1) 圈")
                .font(.app(9.5))
                .foregroundStyle(Theme.textMuted(scheme))
            Text("\(p.coins)")
                .font(.app(10.5, weight: .medium))
                .foregroundStyle(Color(hexString: "D9A63C")!)
            if !p.hand.isEmpty {
                Text("\(p.hand.count) 张")
                    .font(.app(9.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
    }
}

/// 还没开局时摆在介绍上面的那一圈空棋盘。
///
/// 纯装饰，不接引擎——所以不需要有局在跑也画得出来。
/// 中间搁一对骰子，让它看着像「等着开」，而不是「坏了」。
struct MonopolyRingPreview: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, 240)
            let cell = side / 6
            ZStack {
                ForEach(0..<20, id: \.self) { i in
                    let kind = i == 0 ? "start" : (Mono.special[i] ?? "task")
                    let p = MonopolyBoard.spot(i)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MonopolyBoard.tint(kind).opacity(scheme == .dark ? 0.38 : 0.28))
                        .overlay {
                            Image(systemName: MonopolyBoard.glyph(kind))
                                .font(.system(size: cell * 0.30))
                                .foregroundStyle(MonopolyBoard.tint(kind))
                        }
                        .frame(width: cell - 3, height: cell - 3)
                        .position(x: (CGFloat(p.col) + 0.5) * cell,
                                  y: (CGFloat(p.row) + 0.5) * cell)
                }
                Image(systemName: "dice")
                    .font(.system(size: cell * 1.1, weight: .light))
                    .foregroundStyle(app.settings.accentColor.opacity(0.7))
                    .position(x: side / 2, y: side / 2)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 240)
    }
}
