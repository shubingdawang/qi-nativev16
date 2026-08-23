import SwiftUI

// MARK: - 回收站
//
// 她要的：「被删除的图片会在里面存 30 天，30 天后自动消失，
// 删错了可以将它复原。」
//
// ⚠️ **回收站不进备份**（她定的，见 `BackupBundle.skipFromBackup`）——
// 删掉的东西留在这台手机上给她反悔，但不该跟着备份走到下一台手机上。
// 换手机之后那些就是真的没了，这一点在下面写清楚了。

struct TrashView: View {

    @ObservedObject private var store = TrashStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var notice: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.items.isEmpty {
                        empty
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.items) { item in
                                cell(item)
                            }
                        }
                        note
                    }
                }
                .padding(16)
                .padding(.bottom, Layout.tabBarExpanded)
            }
        }
        .navigationTitle("回收站")
        .navigationBarTitleDisplayMode(.inline)
        .alert("回收站", isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } }
        )) {
            Button("好") { notice = nil }
        } message: { Text(notice ?? "") }
    }

    private func cell(_ item: TrashItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    let url = TrashStore.dir.appendingPathComponent(
                        item.fileName.isEmpty
                            ? (item.children.first?.fileName ?? "")
                            : item.fileName)
                    if let img = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.18)
                            .overlay {
                                Image(systemName: "folder")
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                    }
                }
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                // 删掉的东西压一层灰——**一眼看出这不是还在库里的那些**
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.black.opacity(0.18))
                }

                if item.kind == "folder" {
                    Text("\(item.children.count) 张")
                        .font(.app(9))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }

            Text(item.name)
                .font(.app(11))
                .foregroundStyle(Theme.textMain(scheme))
                .lineLimit(1)
            Text(item.place + " · 还剩 \(daysLeft(item)) 天")
                .font(.app(9))
                .foregroundStyle(Theme.textMuted(scheme))
                .lineLimit(1)

            Button {
                if store.restore(item.id) {
                    notice = "「\(item.name)」放回去了。"
                } else {
                    notice = "放不回去了。"
                }
            } label: {
                Text("放回去")
                    .font(.app(11))
                    .foregroundStyle(app.settings.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(app.settings.accentColor.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    /// 还剩几天。**写出来**——不写的话「三十天」只是一句承诺，
    /// 她没法知道某一张还剩多久。
    private func daysLeft(_ item: TrashItem) -> Int {
        let used = Date().timeIntervalSince(item.at) / 86400
        return max(0, Int((TrashStore.keepDays - used).rounded(.up)))
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.app(30, weight: .light))
                .foregroundStyle(app.settings.accentColor.opacity(0.5))
            Text("回收站是空的")
                .font(.app(13))
                .foregroundStyle(Theme.textMuted(scheme))
            Text("他删掉的表情和照片会先放这儿三十天，\n删错了随时能放回去。")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme).opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private var note: some View {
        Text("""
        删掉的东西在这儿放 **30 天**，到期自动消失，那之后就真的没了。

        ⚠️ **回收站不进备份。** 换手机、重装之后，这里面的东西不会跟过去——那时候它们就是真的删掉了。这是故意的：备份该带的是你留下的东西，不是你扔掉的。
        """)
            .font(.app(11))
            .foregroundStyle(Theme.textMuted(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}
