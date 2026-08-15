import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 设置页。
///
/// 以前这里是系统的 Form，白底、灰分组线，跟 App 别处那套壁纸 + 玻璃
/// 完全是两套东西，翻进来像走错了门。现在改成跟聊天页同一套材质：
/// 壁纸透上来，内容是一张张玻璃卡片，卡片之间靠间距分组，不靠灰线。
struct SettingsView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showingImporter = false
    @State private var exportURL: URL?
    @State private var alertMessage: String?
    @State private var showingClearConfirm = false
    @State private var wallpaperItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    appearanceCard
                    generalCard
                    servicesCard
                    backendCard
                    dataCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
            .background(Color.clear)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("设置")
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: wallpaperItem) { _, item in loadWallpaper(item) }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                importBackup(result)
            }
            .sheet(item: Binding(
                get: { exportURL.map { ExportFile(url: $0) } },
                set: { _ in exportURL = nil }
            )) { file in
                ShareSheet(items: [file.url])
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog("确定要清空全部对话吗？", isPresented: $showingClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    for c in app.conversations { app.deleteConversation(c.id) }
                    app.ensureActive(in: .chat)
                    app.ensureActive(in: .workshop)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("聊天记录和里面的图片都会删掉，删了找不回来。建议先导出一份备份。")
            }
        }
    }

    // MARK: 外观

    private var appearanceCard: some View {
        SettingsCard(title: "外观") {
            // 深浅色
            HStack(spacing: 12) {
                Text("颜色模式")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                SegmentedChips(
                    items: AppearanceMode.allCases.map { ($0.label, $0) },
                    selection: $app.settings.appearance)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            SettingsDivider()

            // 主题色
            VStack(alignment: .leading, spacing: 10) {
                Text("主题色")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
                HStack(spacing: 12) {
                    // 这儿只摆常用的几个，剩下的和自定义色号都在「自定义主题」里
                    ForEach(AppearanceView.accentPresets.prefix(5), id: \.1) { name, hex in
                        Button {
                            app.settings.accentHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex) ?? .gray)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Theme.textMain(scheme).opacity(0.55),
                                                      lineWidth: app.settings.accentHex.uppercased() == hex ? 2 : 0)
                                        .padding(-3)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            SettingsDivider()

            NavigationLink {
                AppearanceView()
            } label: {
                SettingsRowLabel(title: "自定义主题", chevron: true)
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink {
                AppIconPickerView()
            } label: {
                SettingsRowLabel(title: "App 图标", chevron: true)
            }
            .buttonStyle(.plain)

            SettingsDivider()

            // 壁纸
            VStack(alignment: .leading, spacing: 10) {
                Text("背景")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
                HStack(spacing: 10) {
                    PhotosPicker(selection: $wallpaperItem, matching: .images) {
                        Text("换张图片")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(app.settings.accentColor.opacity(0.22)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let name = app.settings.wallpaperName,
                           !app.settings.wallpaperHistory.contains(name) {
                            app.settings.wallpaperHistory.insert(name, at: 0)
                        }
                        app.settings.wallpaperName = nil
                        app.settings.wallpaperDim = 0
                    } label: {
                        Text("恢复默认")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                    .disabled(app.settings.wallpaperName == nil)
                    .opacity(app.settings.wallpaperName == nil ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    // MARK: 通用

    private var generalCard: some View {
        SettingsCard(title: "通用设置") {
            SettingsField(title: "我", placeholder: "你的名字", text: $app.settings.userName)
            SettingsDivider()
            SettingsField(title: "对方", placeholder: "它的名字", text: $app.settings.aiName)
            SettingsDivider()

            HStack {
                Text("带上多少历史")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                Picker("", selection: $app.settings.contextLimit) {
                    Text("全部").tag(0)
                    Text("最近 10 条").tag(10)
                    Text("最近 20 条").tag(20)
                    Text("最近 40 条").tag(40)
                }
                .labelsHidden()
                .tint(Theme.textSoft(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            SettingsDivider()

            Toggle(isOn: $app.settings.enterToSend) {
                Text("回车当发送用")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsNote("历史带得越多，对方越记得住前面说过什么，但每次请求也更费钱。回车默认就是换行。")
        }
    }

    // MARK: 模型与服务

    private var servicesCard: some View {
        SettingsCard(title: "模型与服务") {
            NavigationLink { ProviderListView() } label: {
                SettingsRowLabel(title: "供应商", value: "\(app.providers.count)", chevron: true)
            }
            .buttonStyle(.plain)
            SettingsDivider()

            NavigationLink { VoiceInputSettingsView() } label: {
                SettingsRowLabel(title: "语音输入", value: app.settings.voiceInput.title, chevron: true)
            }
            .buttonStyle(.plain)
            SettingsDivider()

            NavigationLink { SearchSettingsView() } label: {
                SettingsRowLabel(title: "联网搜索", value: app.settings.searchEngine.title, chevron: true)
            }
            .buttonStyle(.plain)
            SettingsDivider()

            NavigationLink { VoiceSettingsView() } label: {
                SettingsRowLabel(title: "语音服务", value: app.activeVoice?.name ?? "未启用", chevron: true)
            }
            .buttonStyle(.plain)
            SettingsDivider()

            NavigationLink { MCPListView() } label: {
                SettingsRowLabel(title: "MCP", value: mcpSummary, chevron: true)
            }
            .buttonStyle(.plain)
            SettingsDivider()

            NavigationLink { WakeSettingsView() } label: {
                SettingsRowLabel(title: "自己醒来",
                                 value: app.settings.wake.enabled ? "开着" : "关着",
                                 chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 后端

    private var backendCard: some View {
        SettingsCard(title: "后端服务") {
            SettingsField(title: "心跳引擎", placeholder: "http://…:8000",
                          text: $app.settings.pulseBaseURL, mono: true)
            SettingsDivider()
            SettingsField(title: "主动消息", placeholder: "http://…:3000",
                          text: $app.settings.adminBaseURL, mono: true)
            SettingsNote("你电脑上跑的那两个服务。填局域网或 Tailscale 地址都行。电脑没开的时候，心跳页会显示最后一次读到的数据。")
        }
    }

    // MARK: 数据

    private var dataCard: some View {
        SettingsCard(title: "数据") {
            Button { exportBackup() } label: {
                SettingsRowLabel(title: "导出备份", icon: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            SettingsDivider()

            Button { showingImporter = true } label: {
                SettingsRowLabel(title: "导入备份", icon: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            SettingsDivider()

            Button { showingClearConfirm = true } label: {
                SettingsRowLabel(title: "清空全部对话", icon: "trash", tint: .red)
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutCard: some View {
        SettingsCard {
            SettingsRowLabel(title: "版本", value: appVersion)
            SettingsDivider()
            SettingsRowLabel(title: "对话数", value: "\(app.conversations.count)")
        }
    }

    private var mcpSummary: String {
        let on = app.mcpServers.filter { $0.enabled }
        if on.isEmpty { return app.mcpServers.isEmpty ? "未连接" : "已关闭" }
        let tools = on.reduce(0) { $0 + $1.enabledTools.count }
        return "\(on.count) 个 · \(tools) 工具"
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: 壁纸

    private func loadWallpaper(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let name = ImageStore.save(image, quality: 0.9)
            else { return }
            await MainActor.run {
                // 旧的不删，收进历史里，随时能换回去
                if let old = app.settings.wallpaperName,
                   !app.settings.wallpaperHistory.contains(old) {
                    app.settings.wallpaperHistory.insert(old, at: 0)
                }
                app.settings.wallpaperName = name
                app.settings.wallpaperHistory.removeAll { $0 == name }
                wallpaperItem = nil
            }
        }
    }

    // MARK: 备份

    private struct Backup: Codable {
        var providers: [Provider]
        var conversations: [Conversation]
        var settings: AppSettings
    }

    private struct ExportFile: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private func exportBackup() {
        app.saveNow()
        let backup = Backup(
            providers: app.providers,
            conversations: app.conversations,
            settings: app.settings
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(backup) else {
            alertMessage = "导出失败，数据编码出错。"
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "栖备份-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            alertMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertMessage = "选文件失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let backup = try decoder.decode(Backup.self, from: data)
                app.providers = backup.providers
                app.conversations = backup.conversations
                app.settings = backup.settings
                app.saveNow()
                alertMessage = "导入成功。"
            } catch {
                alertMessage = "这个文件读不了，可能不是本 App 导出的备份。\n\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 卡片和行

/// 一张玻璃卡片，上面可以顶一个小标题。分组靠卡片之间的间距，不靠灰线。
struct SettingsCard<Content: View>: View {

    var title: String? = nil
    @ViewBuilder var content: Content

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) { content }
                .glassBackground(radius: 20, strength: app.settings.glassOpacity)
        }
    }
}

/// 卡片里行与行之间那道线。很淡，只是把两行分开，不是框。
struct SettingsDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(Theme.textMuted(scheme).opacity(0.18))
            .frame(height: 0.6)
            .padding(.leading, 16)
    }
}

/// 一行：左边名字，右边一小段现在的值，可以带箭头
struct SettingsRowLabel: View {

    var title: String
    var value: String? = nil
    var icon: String? = nil
    var chevron: Bool = false
    var tint: Color? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(tint ?? Theme.textSoft(scheme))
                    .frame(width: 20)
            }
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(tint ?? Theme.textMain(scheme))
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// 一行可以直接改的字段
struct SettingsField: View {

    var title: String
    var placeholder: String
    @Binding var text: String
    var mono: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer(minLength: 8)
            TextField(placeholder, text: $text)
                .font(.system(size: mono ? 13 : 15, design: mono ? .monospaced : .default))
                .textInputAutocapitalization(mono ? .never : .sentences)
                .autocorrectionDisabled(mono)
                .keyboardType(mono ? .URL : .default)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .frame(maxWidth: 190)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// 卡片底下那段小字说明
struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textMuted(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 12)
    }
}

/// 自己画的分段选择器。系统那个 `.segmented` 是不透明的一块，
/// 摆在玻璃卡片上像贴了张贴纸。
struct SegmentedChips<T: Hashable>: View {

    let items: [(String, T)]
    @Binding var selection: T

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.1) { label, value in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        selection = value
                    }
                } label: {
                    Text(label)
                        .font(.system(size: 12.5, weight: selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value
                                         ? Theme.textMain(scheme)
                                         : Theme.textMuted(scheme))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background {
                            if selection == value {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(scheme == .dark ? 0.14 : 0.85))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Theme.softFillDeep))
    }
}

/// 系统分享面板
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
