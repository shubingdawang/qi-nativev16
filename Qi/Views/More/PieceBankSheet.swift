import SwiftUI

/// 切好的家具素材库。
///
/// 她的原话：「我想切割之后增加一个选择切割图片后保存的功能，
/// 这样我就不用一直切割同一张图片了。」
///
/// 存在 `PieceStore` 里（`furniture-pieces.json` + `Images/`），
/// **两样都进备份**，换一版不会没。
struct PieceBankSheet: View {

    /// 挑中了哪一张
    var onPick: (UIImage) -> Void

    @ObservedObject private var bank = PieceStore.shared
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var renaming: FurniturePiece?
    @State private var newName = ""
    @State private var deleting: FurniturePiece?

    /// 换行走这个常量。反斜杠经脚本改动会被吃掉一层、字符串就跨行了——
    /// 这仓库栽过十几次，`strspan.py` 每次都抓得到。
    private let br = String(UnicodeScalar(10))

    private let cols = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    // ── App 自带的。**两套，摆在最前面。**
                    //
                    // 她说「先预存」——那就得一进来就看得见，
                    // 而不是等她自己切出几张图之后才出现。
                    //
                    // ⚠️ 这儿曾经还有一栏「像素（跟屋子同风格）」，**撤了**。
                    // 那十件是我拿她那个半成品素材工厂生成的，她全否了，
                    // 而且否得对——见那次提交里记的四条硬伤
                    // （像素点全是斜的、底部截断、脚下一团黑圈、地毯不完整）。
                    // 不是风格问题，是画错了。
                    builtIn("自带的", KenneyPieces.all, load: KenneyPieces.image)

                    if bank.pieces.isEmpty {
                        // ⚠️ 这段提示以前**她一次都没机会看见**：
                        // 长按菜单里那个入口写着「库空就不显示」，
                        // 于是空的时候进不来，进不来就永远填不满。
                        // 现在入口常驻了（见 ClawdHomeView 那段注释）。
                        EmptyNote(icon: "tray",
                                  title: "你自己那批还是空的",
                                  hint: "上面那些是 App 自带的，随时能用。"
                                      + "想加自己的："
                                      + "回到小屋，点底下那条「从整版图里取家具」，"
                                      + "选一张整版图切开，"
                                      + "然后点某一块选「存进素材库」"
                                      + "，或者直接「全部存进素材库」。" + br + br
                                      + "存进来之后，长按任意家具选「从素材库挑一张」"
                                      + "就能直接换，不用再切一遍同一张图。")
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(bank.pieces) { p in
                                cell(p)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("素材库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { dismiss() }
                }
            }
            .alert("改个名字", isPresented: Binding(
                get: { renaming != nil }, set: { if !$0 { renaming = nil } }
            )) {
                TextField("比如「木床」", text: $newName)
                Button("取消", role: .cancel) { renaming = nil }
                Button("改好了") {
                    if let p = renaming { bank.rename(p.id, to: newName) }
                    renaming = nil
                }
            }
            .confirmationDialog("删掉这块素材？",
                                isPresented: Binding(get: { deleting != nil },
                                                     set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("删掉", role: .destructive) {
                    if let p = deleting { bank.remove(p.id) }
                    deleting = nil
                }
                Button("算了", role: .cancel) { deleting = nil }
            } message: {
                // ⚠️ 这句要写清楚，不然她不敢删。
                // 素材和「已经贴在屋里的那张」是两份文件，删这边不影响那边。
                Text("只删素材库里这一块。已经贴到家具上的图不受影响。")
            }
        }
    }

    /// 自带的那一栏。两套走同一个，只是名字和取图的地方不同。
    ///
    /// ⚠️ 挑中之后**直接把 `UIImage` 交出去就完了**，
    /// 不往她的素材库里存一份。存了的话每台手机都多几百 KB，
    /// 还会跟着她的备份来回搬——而它们本来就在每一版 App 里。
    /// 她真的用上某一件，那一件才会存成她自己的图（外面 `onPick` 那边做）。
    @ViewBuilder
    private func builtIn(_ title: String, _ items: [(String, String)],
                         load: @escaping (String) -> UIImage?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(items, id: \.1) { label, file in
                    Button {
                        guard let img = load(file) else { return }
                        onPick(img)
                        dismiss()
                    } label: {
                        VStack(spacing: 4) {
                            if let img = load(file) {
                                Image(uiImage: img)
                                    .resizable()
                                    // ⚠️ 像素图放大要用**最近邻**，
                                    // 默认那种平滑插值会把它糊成一团。
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(height: 58)
                            } else {
                                Color.clear.frame(height: 58)
                            }
                            Text(label)
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12,
                                                     style: .continuous)
                            .fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func cell(_ p: FurniturePiece) -> some View {
        Button {
            guard let img = bank.image(p) else { return }
            onPick(img)
            dismiss()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    // 棋盘格垫底：看得出背景抠干净没有
                    Checkerboard(squares: 10)
                        .fill(scheme == .dark
                              ? Color.white.opacity(0.06)
                              : Color.black.opacity(0.05))
                    if let img = bank.image(p) {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .padding(4)
                    }
                }
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text(p.name.isEmpty ? "没名字" : p.name)
                    .font(.app(11))
                    .foregroundStyle(p.name.isEmpty
                                     ? Theme.textMuted(scheme)
                                     : Theme.textMain(scheme))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                newName = p.name
                renaming = p
            } label: {
                Label("改个名字", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleting = p
            } label: {
                Label("删掉", systemImage: Icon.trash)
            }
        }
    }
}
