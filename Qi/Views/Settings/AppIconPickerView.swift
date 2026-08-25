import SwiftUI
import UIKit

/// 换桌面上那个图标。
///
/// iOS 只允许在打包时就放进去的那几个里面选，不能拿任意一张图去当图标——
/// 所以这里是几个预置的配色，不是从相册挑。
struct AppIconPickerView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var failed: String?

    private struct Option: Identifiable {
        /// nil 表示用回默认那个
        let key: String?
        let title: String
        let preview: String
        var id: String { key ?? "default" }
    }

    // 原来这儿写死了六个"配色"，可外框的颜色早就去掉了，
    // 六张图长得一模一样，选哪个都没区别。现在只留「原来的」，
    // 别的**全看 AppIcons 文件夹里有什么**——放几张就是几张。
    private let builtin: [Option] = [
        .init(key: nil, title: "原来的", preview: "AppIcon")
    ]

    /// 你自己往 AppIcons 文件夹里放的那些，构建时被带进来了
    private var mine: [Option] {
        guard let url = Bundle.main.url(forResource: "UserIcons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return list.compactMap { item in
            guard let key = item["key"], let name = item["name"] else { return nil }
            return Option(key: key, title: name, preview: "UserIcon-\(key)")
        }
    }

    private var options: [Option] { builtin + mine }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(options) { option in
                        Button {
                            apply(option.key)
                        } label: {
                            VStack(spacing: 7) {
                                ZStack {
                                    if let img = preview(option) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .frame(width: 62, height: 62)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    } else {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Theme.softFillDeep)
                                            .frame(width: 62, height: 62)
                                    }

                                    // 选中标记放在右下角，不给图标本身描边——
                                    // 描一圈会把图标原本的形状框住，看着不干净
                                    if current == option.key {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.app(17))
                                            .foregroundStyle(app.settings.accentColor, .white)
                                            .offset(x: 25, y: 25)
                                    }
                                }
                                Text(option.title)
                                    .font(.app(11))
                                    .foregroundStyle(current == option.key
                                                     ? Theme.textMain(scheme)
                                                     : Theme.textMuted(scheme))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)

                if let failed {
                    Text(failed)
                        .font(.app(12))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("更换后 iOS 会弹出系统提示，该提示无法关闭。桌面图标可能延迟数秒刷新。")
                    if mine.isEmpty {
                        Text("往仓库根目录的 AppIcons 文件夹里丢图片，文件名就是这里显示的名字，推上去重新构建，这儿就会多出来几张。放几张显示几张。\n\niOS 规定备用图标必须打包时就在，不给 App 运行时新增，所以没法直接从相册选。")
                    } else {
                        Text("除了「原来的」，这 \(mine.count) 张全是 AppIcons 文件夹里的。想加想删，改那个文件夹再构建一次。")
                    }
                }
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))

                // 自己做一个。
                // ⚠️ 做出来的**当不了这一排里的图标**（那些必须构建时打进包），
                // 但能当头像、能存下来、能给我放进下一次构建——
                // 这一点在那一页里写清楚了，不在这儿吊她胃口。
                NavigationLink { LogoStudioView() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars").font(.app(14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("做一个自己的")
                                .font(.app(14))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text("一次画一张，满意为止。做出来的要放进下次构建才能当图标")
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .foregroundStyle(app.settings.accentColor)
                    .padding(14)
                    .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .background { WallpaperBackground() }
        .navigationTitle("App 图标")
        .navigationBarTitleDisplayMode(.inline)
        // 每次进来、以及从系统那个提示回来之后，都以系统那份为准重读一遍
        .onAppear { current = UIApplication.shared.alternateIconName }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            current = UIApplication.shared.alternateIconName
        }
    }

    /// 找这一项该显示哪张图。
    ///
    /// 「原来的」那张在资源目录里，名字不一定拿得到，所以多试几种叫法；
    /// 实在找不着就交给外面画一块空占位，不至于整格是黑的。
    private func preview(_ option: Option) -> UIImage? {
        if let img = UIImage(named: option.preview) { return img }
        guard option.key == nil else { return nil }
        for name in ["AppIcon", "AppIcon-1024", "AppIcon60x60"] {
            if let img = UIImage(named: name) { return img }
        }
        // 最后一招：问系统要当前正在用的那个图标
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last {
            return UIImage(named: last)
        }
        return nil
    }

    private func apply(_ key: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            failed = "这台设备不支持换图标。"
            return
        }
        UIApplication.shared.setAlternateIconName(key) { error in
            Task { @MainActor in
                if let error {
                    failed = "没换成：" + error.localizedDescription
                } else {
                    failed = nil
                    if app.settings.haptics {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
                // **不管成没成，都以系统那份为准重读一次。**
                //
                // 她说「即使更换了依旧还是勾选的原先的图标，但是桌面上的已经更改了」——
                // 症结是这儿原来写的是 `current = key`（拿我们**以为**的值去更新）。
                // 系统弹那个提示的时候 App 会走一遍失焦/回焦，
                // 中间任何一步没对上，勾就跟真实状态脱节了。
                // 直接问系统「现在到底是哪个」，就不会有这种偏差。
                current = UIApplication.shared.alternateIconName
            }
        }
    }
}
