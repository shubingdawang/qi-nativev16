import SwiftUI

/// 选中几句话之后生成的那张分享图。
/// 注意：这张图是离屏渲染出来的，系统的毛玻璃材质在离屏时会失效，
/// 所以这里用半透明白 + 壁纸模糊自己拼出同样的观感。
struct ShareCardView: View {

    let messages: [ChatMessage]
    let settings: AppSettings
    let wallpaper: UIImage?

    private var accent: Color { settings.accentColor }

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 14) {
                ForEach(messages) { message in
                    row(message)
                }

                HStack {
                    Spacer()
                    Text(dateLine)
                        .font(.app(10))
                        .foregroundStyle(Color.black.opacity(0.35))
                }
                .padding(.top, 2)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
            .padding(20)
        }
        .frame(width: 720)
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: 背景

    private var background: some View {
        ZStack {
            if let wallpaper {
                Image(uiImage: wallpaper)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 18)
                    .overlay(Color.white.opacity(0.18))
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.30), accent.opacity(0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .background(Color(white: 0.97))
            }
        }
    }

    // MARK: 一条消息

    private func row(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        let name = isUser
            ? (settings.userName.isEmpty ? "我" : settings.userName)
            : (settings.aiName.isEmpty ? "他" : settings.aiName)
        let avatarName = isUser ? settings.userAvatarName : settings.aiAvatarName

        return HStack(alignment: .top, spacing: 10) {
            avatar(avatarName, fallback: String(name.prefix(1)))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.app(13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.72))
                    Text(timeText(message.createdAt))
                        .font(.app(10))
                        .foregroundStyle(Color.black.opacity(0.35))
                }

                if !message.imageNames.isEmpty {
                    // ⚠️ **有几张摆几张**，不再只摆前三张。
                    //
                    // 她报的：「多张图片一起发送（photostack 形式）长按分享后
                    // 只显示三张图片，而我这个勾选的有 9 张。」——
                    // 以前这儿写死了 `prefix(3)` 加一排 `HStack`，
                    // 一行摆三张，第四张起直接丢掉。
                    //
                    // 改成三列的网格：三张是一行，九张是三行，谁都不丢。
                    // 一格宽度按张数缩一点，多的时候整张卡不会太长。
                    let names = message.imageNames
                    let side: CGFloat = names.count <= 3 ? 92 : (names.count <= 6 ? 78 : 66)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 6),
                                             count: min(3, names.count)),
                              spacing: 6) {
                        ForEach(names, id: \.self) { n in
                            if let img = ImageStore.load(n) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: side, height: side)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.app(15))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isUser
                                      ? accent.opacity(0.24)
                                      : Color.white.opacity(0.75))
                        )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func avatar(_ name: String?, fallback: String) -> some View {
        Group {
            if let name, let img = ImageStore.load(name) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(accent.opacity(0.30))
                    Text(fallback)
                        .font(.app(15, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: messages.first?.createdAt ?? Date())
    }
}

// MARK: - 渲染成图片

enum ShareCardRenderer {

    @MainActor
    static func render(messages: [ChatMessage], settings: AppSettings) -> UIImage? {
        let wallpaper = settings.wallpaperName.flatMap { ImageStore.load($0) }
        let view = ShareCardView(messages: messages, settings: settings, wallpaper: wallpaper)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3            // 三倍图，存下来清楚
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 包一层，好让 sheet 认得出来
struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
