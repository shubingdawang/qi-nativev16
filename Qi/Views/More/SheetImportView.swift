import SwiftUI
import PhotosUI

/// 从一整版图里取家具。
///
/// 她说：「但我不会这样无规则裁切……」
///
/// 那就别裁。**她导一整版进来，App 自己把每一件找出来**，
/// 她只要点一下「这块是床」。
///
/// 二十件家具，她做二十次手动裁切 → 现在是导一次 + 点二十下配对。
/// 而且配对这件事**只有她能做**（哪块是哪件是她的意思），
/// 裁切这件事**只有机器该做**（对边界、抠背景是苦力活）。
/// 分工分对了，两边都轻松。
struct SheetImportView: View {

    @ObservedObject var store: ClawdStore

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var pick: PhotosPickerItem?
    @State private var pieces: [UIImage] = []
    @State private var working = false
    @State private var assigning: Int?
    /// 已经配好的：第几块 → 配给了哪一件
    @State private var done: [Int: String] = [:]

    private let cols = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Look.gap) {

                        PhotosPicker(selection: $pick, matching: .images) {
                            Label(pieces.isEmpty ? "选一张整版图" : "换一张",
                                  systemImage: "photo.on.rectangle")
                                .font(.app(14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14)
                                    .fill(app.settings.accentColor.opacity(0.28)))
                                .foregroundStyle(Theme.textMain(scheme))
                        }

                        if working {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("正在把每一件找出来…")
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }

                        if pieces.isEmpty && !working {
                            EmptyNote(icon: "scissors",
                                      title: "导一整版进来就行",
                                      hint: "白底的等距家具图，一整版扔进来，"
                                          + "我把每一件单独抠出来。\n"
                                          + "你只要点一下「这块是床」。")
                        } else if !pieces.isEmpty {
                            SectionHeader(title: "找到 \(pieces.count) 件") {
                                Text("点一块配给家具")
                                    .font(.app(11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(pieces.indices, id: \.self) { i in
                                    piece(i)
                                }
                            }
                            Text("**没配上的不用管**——它们不会进屋，也不占地方。"
                                 + "配错了点同一块再配一次就行。")
                                .font(.app(10.5))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .padding(.leading, 4)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("从整版图里取家具")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { dismiss() }
                }
            }
            .onChange(of: pick) { _, item in load(item) }
            .confirmationDialog("这块是哪件家具？",
                                isPresented: Binding(get: { assigning != nil },
                                                     set: { if !$0 { assigning = nil } }),
                                titleVisibility: .visible) {
                // 只列**她已经买了的**——没买的配了也摆不出来
                ForEach(myKinds, id: \.0) { pair in
                    Button(pair.1) { assign(to: pair.0) }
                }
                Button("算了", role: .cancel) { assigning = nil }
            } message: {
                Text("配给哪件，那件在屋里就用这张图。随时能在屋里长按换回来。")
            }
        }
    }

    // MARK: 一块

    private func piece(_ i: Int) -> some View {
        let name = done[i]
        return Button {
            assigning = i
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    // 棋盘格垫在底下：**这样她才看得出背景抠干净没有**。
                    // ⚠️ 用的是像素工坊里那一个（`Checkerboard` 是个 Shape）——
                    // 我一开始在这儿又写了一个同名的，扫重名的脚本当场逮住。
                    // 第三次栽在重名上了，这回是脚本先看见的。
                    Checkerboard(squares: 10)
                        .fill(scheme == .dark
                              ? Color.white.opacity(0.06)
                              : Color.black.opacity(0.05))
                    Image(uiImage: pieces[i])
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                }
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(name == nil
                                      ? Color.clear
                                      : app.settings.accentColor.opacity(0.7),
                                      lineWidth: 1.5)
                }

                Text(name ?? "还没配")
                    .font(.app(10))
                    .foregroundStyle(name == nil
                                     ? Theme.textMuted(scheme)
                                     : app.settings.accentColor)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    /// 她买过的那些种类（同一种只列一次）
    private var myKinds: [(String, String)] {
        var seen: Set<String> = []
        var out: [(String, String)] = []
        for f in store.owned {
            guard !seen.contains(f.kind),
                  let k = FurnitureCatalog.kind(f.kind) else { continue }
            seen.insert(f.kind)
            out.append((f.kind, k.name))
        }
        return out
    }

    // MARK: 干活

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        working = true
        pieces = []
        done = [:]
        Task {
            defer { working = false }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else { return }
            // 切图是纯算力活，**别占着主线程**——
            // 一张两千见方的图能算好几百毫秒，卡在主线程上界面会僵一下
            let cut = await Task.detached(priority: .userInitiated) {
                SpriteSheet.slice(img)
            }.value
            pieces = cut
        }
    }

    private func assign(to kindID: String) {
        guard let i = assigning, pieces.indices.contains(i) else { return }
        let img = pieces[i]
        // 这一种她可能买了好几件（两张床），**全都换上**
        for f in store.owned where f.kind == kindID {
            _ = store.dressUp(f.id, with: img)
        }
        done[i] = FurnitureCatalog.kind(kindID)?.name
        assigning = nil
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
