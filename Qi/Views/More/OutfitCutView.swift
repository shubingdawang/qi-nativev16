import SwiftUI

/// 「做成 clawd 的衣服」：她画的穿着衣服的 clawd → 抠出衣服 → 穿上。
///
/// 自动认出 clawd 的颜色、对齐好；她要做的只是看一眼、不对就点颜色或挪一挪。
struct OutfitCutView: View {

    @State var cut: OutfitCutter
    var name: String = ""

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var title = ""
    @State private var wearNow = true
    @State private var done: String?
    @State private var shown: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    colorsCard
                    adjustCard
                    HStack {
                        TextField("名字，如：小恐龙", text: $title)
                            .font(.app(14))
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                        Toggle("存好就穿上", isOn: $wearNow).font(.app(12.5)).fixedSize()
                    }
                    .tint(app.settings.accentColor)
                    Button(action: save) {
                        Text("做成衣服").font(.app(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Capsule().fill(app.settings.accentColor))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(WallpaperBackground())
            .navigationTitle("做成 clawd 的衣服")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
            .onAppear {
                if title.isEmpty { title = name }
                refresh()
            }
            .alert(done ?? "", isPresented: Binding(get: { done != nil }, set: { if !$0 { done = nil } })) {
                Button("好") { dismiss() }
            }
        }
    }

    private func refresh() { shown = cut.preview() }

    private var preview: some View {
        ZStack {
            TransparencyGrid()
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(6)
            }
        }
        .frame(width: 250, height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottom) {
            Text("袖子跟着手转，别的跟着身子走")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.bottom, 6)
        }
    }

    private var colorsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("哪些是 clawd 自己的颜色（会抠掉）")
                .font(.app(12.5, weight: .medium))
                .foregroundStyle(Theme.textSoft(scheme))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 8)], spacing: 8) {
                ForEach(cut.colors, id: \.self) { hex in
                    let on = cut.clawdColors.contains(hex)
                    Button {
                        if on { cut.clawdColors.remove(hex) } else { cut.clawdColors.insert(hex) }
                        cut.autoFit()
                        refresh()
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hexString: hex) ?? .clear)
                            .frame(height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12), lineWidth: 0.6))
                            .overlay {
                                if on {
                                    Image(systemName: "scissors")
                                        .font(.app(12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 1)
                                }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(app.settings.accentColor, lineWidth: on ? 2.2 : 0).padding(-2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("带剪刀的颜色会被抠掉，露出 clawd 真的身子和脸。点一下可以加上或去掉。")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(14)
        .glassCard(padding: 0)
    }

    private var adjustCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                nudge("缩小", "minus.magnifyingglass") { zoom(1 / 1.05) }
                nudge("放大", "plus.magnifyingglass") { zoom(1.05) }
                nudge("左", "arrow.left") { cut.offX -= 0.5; refresh() }
                nudge("右", "arrow.right") { cut.offX += 0.5; refresh() }
                nudge("上", "arrow.up") { cut.offY -= 0.5; refresh() }
                nudge("下", "arrow.down") { cut.offY += 0.5; refresh() }
            }
            Button {
                cut.autoFit(); refresh()
            } label: {
                Label("自动对齐", systemImage: "wand.and.stars").font(.app(12.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(app.settings.accentColor)
        }
        .padding(14)
        .glassCard(padding: 0)
    }

    /// 绕 clawd 身子中心放大缩小
    private func zoom(_ k: Double) {
        let cx = (OutfitCutter.target.x0 + OutfitCutter.target.x1) / 2
        let by = OutfitCutter.target.y1
        cut.offX = cx - (cx - cut.offX) * k
        cut.offY = by - (by - cut.offY) * k
        cut.scale *= k
        refresh()
    }

    private func nudge(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.app(14))
                Text(label).font(.app(9.5))
            }
            .foregroundStyle(Theme.textSoft(scheme))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let n = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item = CustomWearStore.shared.addOutfit(cut.render(), name: n.isEmpty ? "我画的衣服" : n) else {
            done = "没存上，再试一次。"
            return
        }
        if wearNow, !ClawdStore.shared.isWearing(item.id) { ClawdStore.shared.wear(item.id) }
        done = wearNow ? "做好了，clawd 已经穿上。去聊天页和小屋看他动起来。" : "已存进「我做的衣服」。"
    }
}
