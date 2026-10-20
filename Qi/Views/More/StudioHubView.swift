import SwiftUI
import PhotosUI

/// 表情工坊：拼豆、零件、动图三样合在一处。
///
/// 拼豆画图 → 导出时存成表情、零件、衣服，或者直接去做动图；
/// 零件就是标了「零件」的拼豆板，长按回到拼豆页接着改，动图里「逐帧」能把它加进来。
struct StudioHubView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = BeadStore.shared

    @State private var tab = 0
    @State private var editing: BeadProject?
    @State private var animating: GifStart?
    @State private var photo: PhotosPickerItem?
    @State private var pickingBead = false

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $tab) {
                Text("拼豆").tag(0)
                Text("零件").tag(1)
                Text("动图").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            switch tab {
            case 0: BeadListView()
            case 1: partsPage
            default: gifPage
            }
        }
        .navigationTitle("表情工坊")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $editing) { p in BeadEditorView(projectID: p.id) }
        .fullScreenCover(item: $animating) { g in GifMakerView(image: g.image, name: g.name, startSection: g.section) }
        .sheet(isPresented: $pickingBead) { beadPicker }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    animating = GifStart(image: img, name: "")
                }
                photo = nil
            }
        }
    }

    // MARK: 零件

    private var parts: [BeadProject] { store.projects.filter { $0.asPart == true } }

    private var partsPage: some View {
        ScrollView {
            if parts.isEmpty {
                EmptyNote(icon: "puzzlepiece", title: "还没有零件",
                          hint: "在拼豆里画好一块（一只手、一顶帽子、一颗爱心），导出时点「存成零件」。动图「逐帧」里能把零件加进来一起动。")
                    .padding(.top, 40)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(parts) { p in
                    VStack(spacing: 6) {
                        BeadThumb(project: p)
                            .aspectRatio(1, contentMode: .fit)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.softFillDeep))
                        Text(p.name).font(.app(12)).lineLimit(1)
                    }
                    .padding(8)
                    .glassCard(padding: 0)
                    .contentShape(Rectangle())
                    // 长按回到拼豆页接着改；改完零件跟着变
                    .onLongPressGesture { editing = p }
                    .contextMenu {
                        Button { editing = p } label: { Label("回到拼豆页修改", systemImage: "pencil") }
                        Button {
                            animating = GifStart(image: BeadStore.render(p, look: .pixel, cellPx: 8), name: p.name)
                        } label: { Label("制作动图", systemImage: "sparkles") }
                        Button {
                            var q = p; q.asPart = false; store.save(q)
                        } label: { Label("移出零件", systemImage: "minus.circle") }
                    }
                }
            }
            .padding(.horizontal, 16)
            Text("长按零件回到拼豆页修改")
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.top, 8)
                .padding(.bottom, Layout.tabBarExpanded + 12)
        }
    }

    // MARK: 动图

    private var gifPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("挑一张图做动图：加动作、特效、文字，或者在「逐帧」里自己一帧一帧摆。")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                entry("从拼豆挑", "circle.grid.3x3") { pickingBead = true }
                PhotosPicker(selection: $photo, matching: .images) {
                    entryLabel("从相册挑", "photo")
                }
                .buttonStyle(.plain)
                entry("从表情包挑（进去以后点「从表情包挑」）", "face.smiling") {
                    animating = GifStart(image: nil, name: "")
                }
                if !store.projects.isEmpty {
                    Text("最近的拼豆").font(.app(12, weight: .medium)).foregroundStyle(Theme.textSoft(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10)], spacing: 10) {
                        ForEach(store.projects.prefix(12)) { p in
                            Button {
                                animating = GifStart(image: BeadStore.render(p, look: .pixel, cellPx: 8), name: p.name, section: 4)
                            } label: {
                                BeadThumb(project: p)
                                    .aspectRatio(1, contentMode: .fit)
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
    }

    /// 挑一块拼豆：直接进动图「逐帧」
    private var beadPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                    ForEach(store.projects) { p in
                        Button {
                            pickingBead = false
                            let img = BeadStore.render(p, look: .pixel, cellPx: 8)
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                animating = GifStart(image: img, name: p.name, section: 4)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                BeadThumb(project: p)
                                    .aspectRatio(1, contentMode: .fit)
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                                Text(p.name).font(.app(11)).lineLimit(1).foregroundStyle(Theme.textMain(scheme))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(WallpaperBackground())
            .navigationTitle("挑一块拼豆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { pickingBead = false } } }
        }
    }

    private func entry(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { entryLabel(title, icon) }.buttonStyle(.plain)
    }

    private func entryLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.app(15)).foregroundStyle(app.settings.accentColor).frame(width: 24)
            Text(title).font(.app(14)).foregroundStyle(Theme.textMain(scheme))
            Spacer()
            Image(systemName: "chevron.right").font(.app(11)).foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(14)
        .glassCard(padding: 0)
    }
}
