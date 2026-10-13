import SwiftUI

/// 「做成 clawd 的衣服」：她画的穿着衣服的 clawd → 抠出衣服 → 穿上。
///
/// 自动认出 clawd 的颜色、对齐好；她要做的只是看一眼、不对就点颜色或挪一挪。
struct OutfitCutView: View {

    @State var cut: OutfitCutter
    var name: String = ""
    /// 改的是衣柜里已有的那一件：存的时候替掉它
    var replacing: String? = nil

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
                    slotPicker
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
                baseScale = cut.scale
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

    /// 这是什么：整套衣服，还是只是一顶帽子、一副眼镜……
    private var slotPicker: some View {
        let options: [(ClawdRig.WearSlot, String)] = [(.outer, "整套"), (.head, "帽子"), (.face, "脸上"),
                                                      (.neck, "脖子"), (.back, "背上"), (.feet, "脚上")]
        return VStack(alignment: .leading, spacing: 6) {
            Text("这是什么").font(.app(12.5, weight: .medium)).foregroundStyle(Theme.textSoft(scheme))
            Picker("", selection: Binding(get: { cut.slot }, set: { cut.setSlot($0); baseScale = cut.scale; refresh() })) {
                ForEach(options, id: \.0) { o in Text(o.1).tag(o.0) }
            }
            .pickerStyle(.segmented)
            Text(cut.isOutfit ? "画的是穿着衣服的 clawd：抠掉他自己的颜色，穿上后袖子跟着手转。"
                              : "只画了这一件：直接摆到他身上，大小位置用下面的滑条调。")
                .font(.app(10.5)).foregroundStyle(Theme.textMuted(scheme))
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
            slider("衣服大小", value: Binding(get: { cut.scale / max(0.0001, baseScale) },
                                           set: { zoomTo($0) }), range: 0.5...1.6)
            HStack(spacing: 10) {
                nudge("左", "arrow.left") { cut.offX -= 0.25; refresh() }
                nudge("右", "arrow.right") { cut.offX += 0.25; refresh() }
                nudge("上", "arrow.up") { cut.offY -= 0.25; refresh() }
                nudge("下", "arrow.down") { cut.offY += 0.25; refresh() }
            }
            HStack {
                Toggle(cut.drawnEyeCenter() != nil ? "眼睛按我画的位置" : "眼睛露在衣服外面",
                       isOn: Binding(get: { cut.eyesOnTop },
                                     set: { cut.eyesOnTop = $0; cut.autoFit(); refresh() }))
                    .font(.app(13))
                    .tint(app.settings.accentColor)
                Spacer(minLength: 12)
                Button {
                    cut.autoFit(); baseScale = cut.scale
                    cut.eyeNudgeX = 0; cut.eyeNudgeY = 0; cut.eyeScale = 1
                    refresh()
                } label: {
                    Label("自动对齐", systemImage: "wand.and.stars").font(.app(12.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.settings.accentColor)
            }
            if cut.eyesOnTop {
                slider("眼睛左右", value: Binding(get: { cut.eyeNudgeX },
                                              set: { cut.eyeNudgeX = $0; refresh() }), range: -6...6)
                slider("眼睛上下", value: Binding(get: { cut.eyeNudgeY },
                                              set: { cut.eyeNudgeY = $0; refresh() }), range: -8...8)
                slider("眼睛大小", value: Binding(get: { cut.eyeScale },
                                              set: { cut.eyeScale = $0; refresh() }), range: 0.6...1.8)
            }
            Text(cut.coveredEyes() > 0 && !cut.eyesOnTop
                 ? "眼睛还被衣服盖住一点，可以挪一挪，或者打开「眼睛露在衣服外面」。"
                 : "眨眼、闭眼这些表情跟着他走。")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassCard(padding: 0)
    }

    /// 自动对齐时的大小，滑条以它为 1
    @State private var baseScale: Double = 1

    private func zoomTo(_ v: Double) {
        let want = baseScale * v
        guard cut.scale > 0 else { return }
        zoom(want / cut.scale)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.app(12.5)).foregroundStyle(Theme.textSoft(scheme))
                .frame(width: 66, alignment: .leading)
            Slider(value: value, in: range).tint(app.settings.accentColor)
        }
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
        guard let item = CustomWearStore.shared.addOutfit(cut.render(), name: n.isEmpty ? "我画的衣服" : n,
                                                           eyesOnTop: cut.eyesOnTop, slot: cut.slot,
                                                           design: cut.design, replacing: replacing) else {
            done = "没存上，再试一次。"
            return
        }
        if wearNow, !ClawdStore.shared.isWearing(item.id) { ClawdStore.shared.wear(item.id) }
        done = wearNow ? "做好了，clawd 已经穿上。去聊天页和小屋看他动起来。" : "已存进「我做的衣服」。"
    }
}
