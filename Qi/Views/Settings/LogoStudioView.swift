import SwiftUI

// MARK: - 做一个自己的图标
//
// 规则和「为什么生成的图当不了真 App 图标」都写在 `LogoGen.swift` 开头。

struct LogoStudioView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var subject = ""
    @State private var made: [(image: UIImage, corner: LogoGen.Corner)] = []
    @State private var busy = false
    @State private var picked: Int?
    @State private var notice: String?
    @State private var task: Task<Void, Never>?
    /// 按了第几次。用来换角度和变体——**连着按不会重复**。
    @State private var round = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputCard
                    if !made.isEmpty { grid }
                    if busy { progress }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, Layout.tabBarExpanded + 20)
            }
        }
        .navigationTitle("做个图标")
        .navigationBarTitleDisplayMode(.inline)
        .alert("图标", isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } }
        )) {
            Button("好") { notice = nil }
        } message: { Text(notice ?? "") }
        .onDisappear { task?.cancel() }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("想要一只什么")
                .font(.app(14, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))

            TextField("一只圆圆的、有点困的青蛙", text: $subject, axis: .vertical)
                .lineLimit(1...3)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

            Text(MD.inline("""
            **用大白话写就行**，别写「极简」「高级感」那种词——那套规则里最要紧的一条就是别用设计术语，写得越像人话，画出来越有它自己的样子。

            **一次画一张。** 看一眼，不行再按一次；满意了就停在那儿。每按一次换一个角度和姿势，连着按不会重复。
            """))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                start()
            } label: {
                HStack(spacing: 7) {
                    if busy { ProgressView().scaleEffect(0.75) }
                    Text(busy ? "画着呢…" : (made.isEmpty ? "画一张看看" : "再来一张"))
                        .font(.app(14))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 13)
                    .fill(app.settings.accentColor.opacity(busy ? 0.5 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(busy || subject.trimmingCharacters(in: .whitespaces).isEmpty)

            Text(MD.inline("⚠️ 每次点击生成一张，调用一次模型并产生一次费用。"))
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(15)
        .glassBackground(radius: 18, strength: app.settings.glassOpacity)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.8)
            Text("画着呢，几秒钟")
                .font(.app(12))
                .foregroundStyle(Theme.textMuted(scheme))
            Spacer()
            Button("不要了") { task?.cancel(); busy = false }
                .font(.app(12))
                .foregroundStyle(app.settings.accentColor)
        }
        .padding(.horizontal, 4)
    }

    // MARK: 画出来的那些

    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(made.count == 1 ? "画好了" : "挑一张（\(made.count) 张）")
                .font(.app(14, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(made.indices, id: \.self) { i in
                    Button {
                        picked = (picked == i) ? nil : i
                    } label: {
                        VStack(spacing: 5) {
                            Image(uiImage: made[i].image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 18,
                                                            style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(picked == i
                                                      ? app.settings.accentColor : .clear,
                                                      lineWidth: 2.5)
                                }
                            Text(made[i].corner.label)
                                .font(.app(9))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if let i = picked, made.indices.contains(i) {
                actions(for: made[i].image)
            }
        }
    }

    private func actions(for image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("这张可以拿去")
                .font(.app(13, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))

            HStack(spacing: 8) {
                pill("当他的头像") { setAvatar(image, key: "ai") }
                pill("当我的头像") { setAvatar(image, key: "user") }
            }
            HStack(spacing: 8) {
                pill("存到相册") {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    notice = "存好了。"
                }
                pill("存进图片库") {
                    if let name = ImageStore.save(image) {
                        MediaStore.shared.items.append(
                            MediaItem(fileName: name, kind: "photo", folder: "图标"))
                        notice = "放进相册的「图标」文件夹了。"
                    }
                }
            }

            Text(MD.inline("""
            ⚠️ **它当不了真正的 App 图标。**

            iOS 的备用图标必须在**构建的时候**就打进包里，运行时换不了——这是系统的规矩，不是我没做。

            想真的换掉桌面上那个图标：把这张存下来发给我，我放进下一次构建里，它就会出现在「设置 → 外观 → App 图标」那一排里。
            """))
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
    }

    private func pill(_ title: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(.app(12))
                .foregroundStyle(app.settings.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(app.settings.accentColor.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 动作

    private func setAvatar(_ image: UIImage, key: String) {
        guard let name = ImageStore.save(image) else { return }
        if key == "ai" { app.settings.aiAvatarName = name }
        else { app.settings.userAvatarName = name }
        notice = "换好了。"
    }

    private func start() {
        let text = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 画图那类模型得单独挑——**跟聊天那个不是一个**
        guard let painter = app.providers.first(where: { p in
            p.enabled && p.enabledModels.contains { $0.id.lowercased().contains("image") }
        }), let model = painter.enabledModels
            .first(where: { $0.id.lowercased().contains("image") })?.id
        else {
            notice = "还没有能画图的模型。去「设置 → 供应商」开一个带 image 的。"
            return
        }
        // **不清空已经画出来的**——她按「再来一张」是想比一比，
        // 把上一张擦掉等于逼她凭记忆选。
        busy = true
        task = Task {
            do {
                let (img, corner) = try await LogoGen.one(
                    subject: text, round: round, provider: painter, model: model)
                await MainActor.run {
                    made.append((img, corner))
                    // 新画的那张自动选中：多半就是要看它
                    picked = made.count - 1
                    round += 1
                    busy = false
                }
            } catch {
                await MainActor.run {
                    busy = false
                    notice = "没画出来：\(error.localizedDescription)"
                }
            }
        }
    }
}
