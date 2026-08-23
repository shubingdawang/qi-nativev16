import SwiftUI
import PhotosUI

/// 像素工坊。写一句话，或者给一张图，让他画成像素的。
struct PixelStudioView: View {

    @ObservedObject private var store = PixelStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var prompt = ""
    @State private var reference: UIImage?
    @State private var picking: PhotosPickerItem?
    @State private var busy = false
    @State private var notice: String?
    @State private var result: PixelArt?
    @State private var revising = false
    @State private var revision = ""
    /// 预览底：0 深色，1 花色，2 浅色
    @State private var backdrop = 0
    @AppStorage("pixelModel") private var chosenModel = ""

    private var me: String { app.settings.userName.isEmpty ? "我" : app.settings.userName }

    /// 所有能画图的模型。名字里带 image 的通常就是。
    private var painters: [(provider: Provider, model: String)] {
        var out: [(Provider, String)] = []
        for p in app.providers where p.enabled {
            for m in p.enabledModels where m.id.lowercased().contains("image") {
                out.append((p, m.id))
            }
        }
        return out
    }

    /// 现在用哪个。两家价钱不一样，所以让你自己挑。
    private var painter: (provider: Provider, model: String)? {
        if let pick = painters.first(where: { $0.model == chosenModel }) { return pick }
        return painters.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                if painter == nil {
                    Text("没找到能画图的模型。去「设置 → 供应商」里把带 image 的模型打开，比如 gemini-image 或 gpt-image-2。")
                        .font(.app(12))
                        .foregroundStyle(.orange)
                        .padding(12)
                        .glassCard(padding: 0)
                }

                // 结果
                if let art = result ?? store.items.first {
                    preview(art)
                }

                composer

                if !store.items.isEmpty {
                    Text("画过的")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.top, 4)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                             count: 3), spacing: 10) {
                        ForEach(store.items) { art in
                            Button {
                                result = art
                            } label: {
                                if let img = ImageStore.load(
                                    art.cutoutName.isEmpty ? art.fileName : art.cutoutName) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .interpolation(.none)   // 像素图放大不能糊
                                        .scaledToFit()
                                        .frame(height: 84)
                                        .frame(maxWidth: .infinity)
                                        .background(RoundedRectangle(cornerRadius: 10)
                                            .fill(Theme.softFillDeep))
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    saveToStickers(art)
                                } label: {
                                    Label("保存到表情库", systemImage: Icon.sticker)
                                }
                                Button(role: .destructive) {
                                    store.remove(art)
                                    if result?.id == art.id { result = nil }
                                } label: {
                                    Label("删掉", systemImage: Icon.trash)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("像素")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: picking) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { reference = img }
                }
            }
        }
    }

    // MARK: 预览

    private func preview(_ art: PixelArt) -> some View {
        VStack(spacing: 10) {
            ZStack {
                backdropView
                if let img = ImageStore.load(
                    art.cutoutName.isEmpty ? art.fileName : art.cutoutName) {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(20)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // 换底看边缘。深色底看有没有黑方块，花色底看有没有毛边。
            Picker("", selection: $backdrop) {
                Text("深色底").tag(0)
                Text("花色底").tag(1)
                Text("浅色底").tag(2)
            }
            .pickerStyle(.segmented)

            Text(backdrop == 0
                 ? "深色底 —— 没有黑方块就说明透明是真的"
                 : (backdrop == 1 ? "花色底 —— 看边缘有没有毛边" : "浅色底 —— 看细节够不够"))
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))

            HStack(spacing: 8) {
                Button {
                    revision = ""
                    revising = true
                } label: {
                    Text("改一改")
                        .font(.app(13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.softFillDeep))
                }
                .buttonStyle(.plain)

                Button {
                    saveToStickers(art)
                } label: {
                    Text("保存到表情库")
                        .font(.app(13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(app.settings.accentColor.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Theme.textMain(scheme))

            if revising {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("哪儿不对？比如「耳朵再尖一点」「换成蓝眼睛」", text: $revision, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                    HStack(spacing: 8) {
                        Button("算了") { revising = false }
                            .font(.app(12))
                        Spacer()
                        Button("照这个改") {
                            Task { await run(revise: art) }
                        }
                        .font(.app(13, weight: .medium))
                        .disabled(revision.isEmpty || busy)
                    }
                }
            }

            if !art.revisions.isEmpty {
                Text("改过 \(art.revisions.count) 次")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .glassCard(padding: 0)
    }

    @ViewBuilder
    private var backdropView: some View {
        switch backdrop {
        case 0:
            Color(red: 0.13, green: 0.13, blue: 0.13)
        case 1:
            // 棋盘格，一眼能看出毛边
            Checkerboard(squares: 22)
                .fill(Theme.textMuted(scheme).opacity(0.22))
                .background(Color.white.opacity(0.9))
        default:
            Color(red: 0.97, green: 0.96, blue: 0.94)
        }
    }

    // MARK: 输入

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if painters.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(painters, id: \.model) { item in
                            Button {
                                chosenModel = item.model
                            } label: {
                                Text(item.model)
                                    .font(.app(11))
                                    .foregroundStyle(chosenModel == item.model
                                                     ? Theme.textMain(scheme)
                                                     : Theme.textMuted(scheme))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(
                                        chosenModel == item.model
                                        ? app.settings.accentColor.opacity(0.25)
                                        : Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("两家价钱不一样，按需要挑。有参考图的话，擅长照图改的那个更合适。")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            TextField("想画什么？写清楚主体、姿势、颜色", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

            HStack(spacing: 10) {
                if let reference {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: reference)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        Button {
                            self.reference = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.app(14))
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                    }
                } else {
                    PhotosPicker(selection: $picking, matching: .images) {
                        VStack(spacing: 3) {
                            Image(systemName: "photo.badge.plus")
                                .font(.app(15))
                            Text("参考图")
                                .font(.app(9))
                        }
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(Theme.textMuted(scheme).opacity(0.5)))
                    }
                }

                Button {
                    Task { await run(revise: nil) }
                } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().scaleEffect(0.7) }
                        Text(busy ? "在画…" : "画一张")
                            .font(.app(14, weight: .medium))
                    }
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 13)
                        .fill(app.settings.accentColor.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .disabled(busy || prompt.isEmpty || painter == nil)
            }

            if let notice {
                Text(notice)
                    .font(.app(11))
                    .foregroundStyle(.orange)
            }

            Text("给参考图的话，可以说「照这张画成像素的」「把图里这只画成开心的」。生成的是透明底，能直接当表情包发。")
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(12)
        .glassCard(padding: 0)
    }

    // MARK: 干活

    private func run(revise art: PixelArt?) async {
        guard let pick = painter else { return }
        let provider = pick.provider
        let model = pick.model
        busy = true
        notice = nil

        var text: String
        var ref = reference
        if let art {
            // 改的时候把上一张当参考，不然改完就不是同一只了
            text = art.prompt + "。这次要改的地方：" + revision
            ref = ImageStore.load(art.fileName) ?? reference
        } else {
            text = prompt
        }

        do {
            let raw = try await PixelGen.generate(
                prompt: PixelGen.buildPrompt(text),
                reference: ref, provider: provider, model: model)

            // 抠背景 → 裁掉四周空白，都在后台做
            let processed = await Task.detached(priority: .userInitiated) {
                let cut = PixelGen.removeKeyColor(raw) ?? raw
                return PixelGen.trim(cut)
            }.value

            guard let originalName = ImageStore.savePNG(raw),
                  let cutName = ImageStore.savePNG(processed)
            else {
                notice = "存不下来，空间可能满了"
                busy = false
                return
            }

            var item = PixelArt(prompt: text, fileName: originalName,
                                cutoutName: cutName, author: me)
            if let art {
                item.revisions = art.revisions + [revision]
            }
            store.add(item)
            result = item
            revising = false
            revision = ""
        } catch {
            notice = error.localizedDescription
        }
        busy = false
    }

    private func saveToStickers(_ art: PixelArt) {
        let name = art.cutoutName.isEmpty ? art.fileName : art.cutoutName
        guard let img = ImageStore.load(name), let data = img.pngData() else { return }
        if var made = StickerStore.shared.add(data: data, ext: "png", owner: "user") {
            made.name = art.displayName
            made.description = "像素图：" + art.prompt
            StickerStore.shared.update(made)
            notice = "存进表情包了"
        }
    }
}

/// 棋盘格，用来看透明边缘
struct Checkerboard: Shape {
    var squares: Int = 20

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = rect.width / CGFloat(squares)
        let rows = Int(ceil(rect.height / size))
        for r in 0..<rows {
            for c in 0..<squares where (r + c) % 2 == 0 {
                path.addRect(CGRect(x: CGFloat(c) * size, y: CGFloat(r) * size,
                                    width: size, height: size))
            }
        }
        return path
    }
}
