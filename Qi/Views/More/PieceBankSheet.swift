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

    private let cols = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    if bank.pieces.isEmpty {
                        EmptyNote(icon: "tray",
                                  title: "素材库还是空的",
                                  hint: "在「从整版图里取家具」中切开一整版后，"
                                      + "点某一块选「存进素材库」，或直接「全部存进素材库」。")
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
