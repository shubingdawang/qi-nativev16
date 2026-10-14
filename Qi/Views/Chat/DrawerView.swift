import SwiftUI

/// 抽屉那一页：他留下的便签和像素小画，按时间倒着排。打开就算看过了
struct DrawerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DrawerStore.shared
    /// 这一次打开之前就没看过的（这一次里还标着「新」）
    @State private var fresh: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if store.items.isEmpty {
                    EmptyNote(icon: "tray", title: "抽屉还是空的",
                              hint: "他想留给你、又不用你马上回的话，或者一幅很小的画，会悄悄放在这里。")
                        .padding(.top, 50)
                }
                ForEach(store.items) { item in
                    card(item)
                        .contextMenu {
                            Button(role: .destructive) { store.remove(item.id) } label: {
                                Label("拿出抽屉", systemImage: Icon.trash)
                            }
                        }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .navigationTitle("抽屉")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fresh = Set(store.items.filter { !$0.seen }.map(\.id))
            store.markSeen()
        }
    }

    private func card(_ item: DrawerItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.kind == "pixel" {
                DrawerPixel(item: item)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else {
                Text(item.text)
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            HStack {
                Text(item.at.formatted(date: .abbreviated, time: .shortened))
                    .font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                if fresh.contains(item.id) {
                    Text("新").font(.app(10.5, weight: .medium)).foregroundStyle(app.settings.accentColor)
                }
            }
        }
        .padding(16)
        .glassCard(padding: 0)
    }
}

/// 一幅像素小画：每个数字画成一个色块，放大不糊
struct DrawerPixel: View {
    let item: DrawerItem

    var body: some View {
        let side = min(240, CGFloat(max(item.w, item.h)) * 12)
        Canvas { gc, size in
            let k = min(size.width / CGFloat(item.w), size.height / CGFloat(item.h))
            let ox = (size.width - k * CGFloat(item.w)) / 2, oy = (size.height - k * CGFloat(item.h)) / 2
            for y in 0..<item.h {
                for x in 0..<item.w {
                    let i = y * item.w + x
                    guard i < item.grid.count else { continue }
                    let ci = item.grid[i]
                    guard ci > 0, ci < item.palette.count, let c = DrawerMarker.color(item.palette[ci]) else { continue }
                    gc.fill(Path(CGRect(x: ox + CGFloat(x) * k, y: oy + CGFloat(y) * k, width: k + 0.3, height: k + 0.3)),
                            with: .color(c))
                }
            }
        }
        .frame(width: side, height: side * CGFloat(item.h) / CGFloat(max(1, item.w)))
    }
}
