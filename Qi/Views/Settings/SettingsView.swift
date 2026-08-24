import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 打包／还原正在做到哪一步。
///
/// 存在的唯一理由是**跨线程**：干活在后台，报进度要落到界面上。
/// `@MainActor` 的 class 天生是 Sendable 的，所以可以放心传进后台闭包；
/// 改 `line` 的时候再 `Task { @MainActor in … }` 跳回来。
@MainActor final class BackupChore: ObservableObject {
    @Published var line: String?
}

/// 设置页。
///
/// 以前这里是系统的 Form，白底、灰分组线，跟 App 别处那套壁纸 + 玻璃
/// 完全是两套东西，翻进来像走错了门。现在改成跟聊天页同一套材质：
/// 壁纸透上来，内容是一张张玻璃卡片，卡片之间靠间距分组，不靠灰线。
struct SettingsView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showingImporter = false
    /// 占了多少地方。**进这一页才算**——要走几百个文件，
    /// 每次刷设置都算一遍太亏
    @State private var usage: StorageUsage.Report?
    @State private var measuring = false

    /// 选好了、还没决定怎么放的那份备份
    /// 选好的那份备份**放在临时目录里的一个副本**，不是整包读进内存。
    /// 她说「导入备份有点卡」——卡在把几百兆读成一个 Data 上。
    @State private var pendingBackup: URL?
    /// 正在打包／还原，界面上压一层，别让她以为死机了。
    ///
    /// ⚠️ **这个不能是 `@State`。** 打包跑在后台线程上，
    /// 它要一路报「正在装第 30 / 400 个」回来——
    /// 而后台那个闭包是 `@Sendable` 的，里头碰 `@State`（等于碰这个 View）
    /// 现在是警告、到 Swift 6 就是错误。
    /// 换成一个 `@MainActor` 的小对象就干净了：
    /// **标了 `@MainActor` 的 class 本身就是 Sendable 的**，
    /// 传进后台闭包合法，改它的时候再跳回主线程。
    @StateObject private var chore = BackupChore()
    @State private var exportURL: URL?
    @State private var alertMessage: String?
    @State private var showingClearConfirm = false
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var userAvatarItem: PhotosPickerItem?
    @State private var aiAvatarItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack {
                // NavigationStack 自己会铺一层不透明的系统底色，
                // 光把 ScrollView 设成透明是没用的——壁纸在它下面，透不上来。
                // 所以这儿得自己再铺一张。
                WallpaperBackground()

                ScrollView {
                    VStack(spacing: Look.gap + 6) {
                        PageHero(title: "设置",
                                 subtitle: "模型、外观、记忆、备份都在这儿")
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
            }
            .scrollDismissesKeyboard(.interactively)
            // ⚠️ 标题空着是**故意的**：这一页顶上有 `PageHero`，
            // 导航栏再写一遍就是一屏两个「设置」（她报的）。
            .navigationTitle("")
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: wallpaperItem) { _, item in loadWallpaper(item) }
            .onChange(of: userAvatarItem) { _, item in loadAvatar(item, into: \.userAvatarName) }
            .onChange(of: aiAvatarItem) { _, item in loadAvatar(item, into: \.aiAvatarName) }
            .fileImporter(
                isPresented: $showingImporter,
                // 只写 .json 的话，从微信/QQ 存下来的那份会是灰的选不中——
                // 那些文件系统认不出类型，只当成一坨 data。所以两种都收。
                // ⚠️ 记忆库那些 txt 也得选得中（`identity.txt`）
                allowedContentTypes: [.json, .text, .plainText, .data],
                // **能多选**（她报的）。整包备份本来只有一个文件，
                // 但她常常是拿着记忆库那一堆 json 过来的——
                // 多选之后这个口两种都收，见 `importBackup`。
                allowsMultipleSelection: true
            ) { result in
                importBackup(result)
            }
            .sheet(item: Binding(
                get: { exportURL.map { ExportFile(url: $0) } },
                set: { _ in exportURL = nil }
            )) { file in
                ShareSheet(items: [file.url])
            }
            // 打包／还原都要跑一会儿（她的图多的时候是几十秒）。
            // **得让她看得见它在动**，不然跟死机没有区别——
            // 而且这一层还挡住了误触：这中间点别的地方会把事情搅乱。
            .overlay {
                if let busy = chore.line {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(busy)
                                .font(.app(13))
                                .foregroundStyle(Theme.textMain(scheme))
                                .multilineTextAlignment(.center)
                            Text("别退出去，弄完自己会消失")
                                .font(.app(10.5))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        .padding(24)
                        .glassBackground(radius: 18)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: chore.line)
            .confirmationDialog("这份备份怎么放？", isPresented: Binding(
                get: { pendingBackup != nil },
                set: { if !$0 { pendingBackup = nil } }
            ), titleVisibility: .visible) {
                Button("只补没有的（推荐）") {
                    if let u = pendingBackup { applyBackup(u, mode: .merge) }
                    pendingBackup = nil
                }
                Button("整个盖掉", role: .destructive) {
                    if let u = pendingBackup { applyBackup(u, mode: .overwrite) }
                    pendingBackup = nil
                }
                Button("取消", role: .cancel) { pendingBackup = nil }
            } message: {
                Text("「只补没有的」：现在有的一个字都不动，只把这份备份里多出来的加进来。"
                     + "同一个窗口两边各聊了一段的话，两段会按时间并到一起。\n\n"
                     + "「整个盖掉」：回到备份那一天的样子，这之后聊的会没掉。"
                     + "换手机、重装才需要它。")
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好") { alertMessage = nil }
            } message: {
                Text(MD.inline(alertMessage ?? ""))
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
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                SegmentedChips(
                    items: AppearanceMode.allCases.map { ($0.label, $0) },
                    selection: $app.settings.appearance)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            SettingsDivider()

            // 主题色不在这儿摆了——「自定义主题」里那一整套（八个预设 + 自己填色号）
            // 才是全的，外面再放五个圆点就是同一件事做两遍。
            NavigationLink {
                AppearanceView()
            } label: {
                SettingsRowLabel(title: "自定义主题", value: currentAccentName, chevron: true)
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

            // 背景。壁纸的事全在这一格里办完，「自定义主题」里不再重复一遍。
            VStack(alignment: .leading, spacing: 10) {
                Text("背景")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))

                HStack(spacing: 10) {
                    PhotosPicker(selection: $wallpaperItem, matching: .images) {
                        Text("换张图片")
                            .font(.app(14, weight: .medium))
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
                            .font(.app(14, weight: .medium))
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

                // 换过的那些不删，随时点回去
                if !app.settings.wallpaperHistory.isEmpty {
                    Text("换过的")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.top, 2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(app.settings.wallpaperHistory, id: \.self) { name in
                                if let img = ImageStore.cached(name) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 52, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8)
                                        )
                                        .onTapGesture { useWallpaper(name) }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                ImageStore.delete(name)
                                                app.settings.wallpaperHistory.removeAll { $0 == name }
                                            } label: {
                                                Label("彻底删掉", systemImage: Icon.trash)
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if app.settings.wallpaperName != nil {
                    HStack {
                        Text("压暗")
                            .font(.app(13))
                            .foregroundStyle(Theme.textSoft(scheme))
                        Spacer()
                        Text("\(Int(app.settings.wallpaperDim * 100))%")
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .padding(.top, 2)
                    Slider(value: $app.settings.wallpaperDim, in: 0...0.6)
                        .tint(app.settings.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    /// 名字 + 头像那一行
    @ViewBuilder
    private func nameRow(title: String,
                         placeholder: String,
                         text: Binding<String>,
                         avatar: Binding<String?>,
                         item: Binding<PhotosPickerItem?>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.app(15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .font(.app(15))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .frame(maxWidth: 150)

            PhotosPicker(selection: item, matching: .images) {
                AvatarView(name: text.wrappedValue.isEmpty ? title : text.wrappedValue,
                           image: avatar.wrappedValue.flatMap { ImageStore.cached($0) },
                           size: 34)
                    .overlay {
                        Circle().strokeBorder(Theme.softStroke, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contextMenu {
            if avatar.wrappedValue != nil {
                Button(role: .destructive) {
                    if let old = avatar.wrappedValue { ImageStore.delete(old) }
                    avatar.wrappedValue = nil
                } label: {
                    Label("不要头像了", systemImage: Icon.trash)
                }
            }
        }
    }

    /// 从相册挑了一张，存下来当头像
    private func loadAvatar(_ item: PhotosPickerItem?, into keyPath: WritableKeyPath<AppSettings, String?>) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let name = ImageStore.save(image, quality: 0.9)
            else { return }
            await MainActor.run {
                if let old = app.settings[keyPath: keyPath] { ImageStore.delete(old) }
                app.settings[keyPath: keyPath] = name
                userAvatarItem = nil
                aiAvatarItem = nil
            }
        }
    }

    /// 现在用的是哪个预设色，摆在「自定义主题」那行后面当提示
    private var currentAccentName: String {
        AppearanceView.accentPresets
            .first { $0.1 == app.settings.accentHex.uppercased() }?.0 ?? "自定义"
    }

    private func useWallpaper(_ name: String) {
        let current = app.settings.wallpaperName
        app.settings.wallpaperName = name
        app.settings.wallpaperHistory.removeAll { $0 == name }
        if let current, !app.settings.wallpaperHistory.contains(current) {
            app.settings.wallpaperHistory.insert(current, at: 0)
        }
    }

    // MARK: 通用

    private var generalCard: some View {
        // 分成两小块写。SwiftUI 的 ViewBuilder 一层最多认十个，
        // 这张卡片的行数早就超了，得靠 Group 收一收。
        SettingsCard(title: "通用设置") {
            // 它认识你的声音到什么程度了。
            //
            // 语气不是拿写死的阈值判的，是**跟你自己的平时比**——
            // 所以它得先认识你的平时。攒够八条之前它一个字都不说，
            // 那会儿说什么都是瞎猜。
            //
            // 全程本机算，一分钱不花，一个字节不上传。
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("听你的语气")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer()
                    Text(VoiceBaseline.shared.ready
                         ? "已经认识你了"
                         : "还在认识你 \(VoiceBaseline.shared.progress.have)"
                           + "/\(VoiceBaseline.shared.progress.need)")
                        .font(.app(12))
                        .foregroundStyle(VoiceBaseline.shared.ready
                                         ? app.settings.accentColor
                                         : Theme.textMuted(scheme))
                }
                Text(MD.inline("这一条**不用你做任何事**：以后每次按住说话，它自己在旁边听一耳朵——"
                     + "音量、语速、停顿有多长。攒够 \(VoiceBaseline.shared.progress.need) 条之后，"
                     + "再说话就会跟你自己的平时比一比，明显偏了才在那条语音上标一句"
                     + "「比平时轻」「比平时快」，他看得见。\n\n"
                     + "攒够之前它一个字都不说——那会儿说什么都是瞎猜。"
                     + "全程在这台手机上算，不花钱、不上传。"
                     + "换了麦克风、感冒一周之后不准了，可以让它重新认识你。"))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Button {
                    VoiceBaseline.shared.reset()
                } label: {
                    Text("重新认识我的声音")
                        .font(.app(12))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsDivider()

            // 勿扰。
            //
            // 「自己醒来」里那个安静时段管的是**每天固定那几个钟头**，
            // 这个管的是**眼下这一阵**：要出门、在开会、现在想安静。
            // 开着的时候他打不了电话、也不会自己醒来找你——
            // **挡的是他来找你，不是你去找他**，你照样随时能开口。
            //
            // 也可以直接跟他说「我要出门了，开勿扰」，他会自己按。
            Toggle(isOn: Binding(get: { app.dndOn },
                                 set: { app.setDND($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("勿扰")
                            .font(.app(15))
                            .foregroundStyle(Theme.textMain(scheme))
                        if !app.dndNote.isEmpty {
                            Text(app.dndNote)
                                .font(.app(10))
                                .foregroundStyle(app.settings.accentColor)
                        }
                    }
                    Text("他不打电话、也不自己醒来找你。你找他不受影响")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsDivider()

            Group {
                // 名字和头像放一行：右边那枚圆点一按就去相册挑
                nameRow(title: "我",
                        placeholder: "你的名字",
                        text: $app.settings.userName,
                        avatar: $app.settings.userAvatarName,
                        item: $userAvatarItem)
                SettingsDivider()
                nameRow(title: "对方",
                        placeholder: "它的名字",
                        text: $app.settings.aiName,
                        avatar: $app.settings.aiAvatarName,
                        item: $aiAvatarItem)
            }

            SettingsDivider()

            Group {
            Toggle(isOn: $app.settings.toolConfirm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("操作前确认")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("他要删东西、装卸小屋、真打电话之前，先弹一下问你")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            SettingsNote("只拦这几件**做了不好收拾**的。存图、写记忆、做标记一律不问——"
                         + "写错了你看得见，也改得回来。每件都问的话，问到最后你只会闭着眼睛按「好」。"
                         + "\n\n90 秒没人点就当这次不做：免得你把手机扣下走了，他那边一直吊着。")
            SettingsDivider()

            Toggle(isOn: $app.settings.segmentAssistant) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("他分段发")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("让他自己决定在哪儿断句，一段一个气泡")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsDivider()

            Toggle(isOn: $app.settings.segmentUser) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我分段发")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(MD.inline("打完先攒着，等你不说了再一起发出去。"
                         + "图、文件、语音、表情**都会一起等**——"
                         + "所以「先说一句再发语音」和「先发语音再补一句」都行"))
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if app.settings.segmentUser {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("等多久")
                            .font(.app(13))
                            .foregroundStyle(Theme.textSoft(scheme))
                        Spacer()
                        Text("\(Int(app.settings.segmentUserDelay)) 秒")
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    Slider(value: $app.settings.segmentUserDelay, in: 2...30, step: 1)
                        .tint(app.settings.accentColor)
                    Text("最后一句发完开始数。这段时间里又发了一条就重新数，直到你真的不说了，才一次性交给他。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            }

            SettingsDivider()

            Group {
            HStack {
                Text("带上多少历史")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                // ⚠️ 这儿以前是 `Picker`（菜单样式）。她报的「字体大小不同」
                // 就是它：**Picker 的选中项走系统字号**，比同一张卡里
                // 「备用模型」「辅助模型」那两行（自己写的 14）明显大一号，
                // 四行值并排看着高低不齐。
                // 换成跟那两行一模一样的 Menu + Text，字号才归一。
                Menu {
                    Button("全部") { app.settings.contextLimit = 0 }
                    Button("最近 10 条") { app.settings.contextLimit = 10 }
                    Button("最近 20 条") { app.settings.contextLimit = 20 }
                    Button("最近 40 条") { app.settings.contextLimit = 40 }
                } label: {
                    Text(Self.historyLabel(app.settings.contextLimit))
                        .font(.app(14))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            // 说明**贴着它自己那一项**，不堆到卡片最底下（她提的）。
            // 隔着五六行才讲的那句话，读到的时候已经忘了在讲哪一项。
            SettingsNote("历史带得越多，对方越记得住前面说过什么，但每次请求也更费钱。",
                         title: "说明")

            SettingsDivider()

            // 主的额度满了接着用谁
            HStack {
                Text("备用模型")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                Menu {
                    Button("不启用") { app.settings.fallbackModel = "" }
                    // ⚠️ 她报的第 7 条：「『自动挑』『不接』没有其他选项」。
                    // 原因是这儿只列 `enabledModels`——**模型那一栏没逐个打勾的话，
                    // 这个菜单就是空的**，看着像没得选。
                    // 现在没打勾的时候就把这家的全部列出来：
                    // 她想指定哪个就指定哪个，不用先回去打勾。
                    ForEach(app.providers.filter { $0.enabled }) { p in
                        ForEach(p.enabledModels.isEmpty ? p.models : p.enabledModels) { m in
                            Button(p.name + " · " + m.id) {
                                app.settings.fallbackModel = p.id.uuidString + "|" + m.id
                            }
                        }
                    }
                } label: {
                    Text(fallbackLabel)
                        .font(.app(14))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            SettingsNote("""
            主的那个额度满了（429 / 余额不足）的时候，**原地换成这个接着说**，不用换窗。

            换的是对面那台机器，不是这一窗：聊天记录、浓缩件、工具、身体状态一样都不动。断在半路的那半句会抹掉重发，所以你看到的是完整的一段话，不是两截拼的。

            气泡里会留一行「换了个模型接着说」——**你得知道这段是谁说的**，不然回头看会以为他忽然变了个人。

            只认额度和限流那几种错。网络断了、地址填错了不会换——那种换谁都一样。
            """, title: "说明")

            SettingsDivider()

            // 跑杂活的那个模型
            HStack {
                Text("辅助模型")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                Menu {
                    Button("自动选择") { app.settings.helperModel = "" }
                    ForEach(app.providers.filter { $0.enabled }) { p in
                        ForEach(p.enabledModels.isEmpty ? p.models : p.enabledModels) { m in
                            Button(p.name + " · " + m.id) {
                                app.settings.helperModel = p.id.uuidString + "|" + m.id
                            }
                        }
                    }
                } label: {
                    Text(helperLabel)
                        .font(.app(14))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            SettingsNote("""
            「杂活」是指**不是他在跟你说话**的那些活：给表情写关键词、翻译、总结通话、看图、以后接进来的看视频听声音。

            以前一律「挑第一个能用的供应商」——可能挑到一个不会看图的，也可能挑到最贵的那个。在这儿指一个便宜又能看图的（比如 Gemini），杂活走它，聊天还是走你在输入框上面选的那个。

            选「自动挑」就是回到老样子。
            """, title: "说明")

            SettingsDivider()

            HStack {
                Text("滚雪球压缩")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                Menu {
                    Button("关") { app.settings.compactEvery = 0 }
                    Button("每 40 条") { app.settings.compactEvery = 40 }
                    Button("每 60 条") { app.settings.compactEvery = 60 }
                    Button("每 100 条") { app.settings.compactEvery = 100 }
                } label: {
                    Text(app.settings.compactEvery == 0
                         ? "关" : "每 \(app.settings.compactEvery) 条")
                        .font(.app(14))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            SettingsNote("""
            聊太长的时候，前面的原文压成一份**浓缩件**，后面接着往下滚——第二次压的是「上一次的浓缩件 + 这一段新的」，不是并列存好几份。这样一个窗口可以一直聊下去，不用换窗。

            上面那条「带上多少历史」是**直接砍**：砍掉的就是没了，聊到三百条他就不记得前两百条自己说过什么了。压缩是把它换成一份更短的，不是丢掉。

            除了浓缩件，还会留一份**他真说过的原话**（一字不改，机械挑的、不花钱）。摘要保得住事，保不住语气——「他说他不想你熬夜」和他原话「几点了。睡。」不是一回事。

            ⚠️ **每压一次多发一次请求。** 按每 60 条算，大约三十个回合多花一次。只在你发消息那一轮里顺带压，不会自己在后台跑。

            某一窗压成了什么、想立刻压一次，在那一窗的「对话设定」里看。
            """, title: "说明")

            SettingsDivider()

            Toggle(isOn: $app.settings.enterToSend) {
                Text("回车当发送用")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsNote("默认不是——**换行就是换行**。想一按就发再打开它。",
                         title: "说明")
            }
        }
    }

    // MARK: 模型与服务

    private var servicesCard: some View {
        // 同样，六行加上中间的分隔线超过十个，拿 Group 分成两半
        SettingsCard(title: "模型与服务") {
            Group {
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
            }

            SettingsDivider()

            Group {
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

                NavigationLink { MemoryLibraryView() } label: {
                    SettingsRowLabel(title: "记忆库",
                                     value: app.settings.localMemory
                                        ? MemoryStore.shared.summaryLine : "走 MCP",
                                     chevron: true)
                }
                .buttonStyle(.plain)
                SettingsDivider()

                NavigationLink { WakeSettingsView() } label: {
                    SettingsRowLabel(title: "自动唤醒",
                                     value: app.settings.wake.enabled ? "开着" : "关着",
                                     chevron: true)
                }
                .buttonStyle(.plain)
            }
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
            SettingsDivider()
            SettingsField(title: "网易云（可留空）", placeholder: "http://…:3000",
                          text: $app.settings.neteaseBaseURL, mono: true)
            SettingsNote("前两个是你电脑上跑的那两个服务。填局域网或 Tailscale 地址都行。电脑没开的时候，心跳页会显示最后一次读到的数据。\n\n**网易云这一栏可以不填。** 手机会直接打网易云的公开接口——整首歌、带歌词（有翻译就中英一起），不用开电脑、不用登录、不用配任何东西。\n\n这一栏只解决一件事：**VIP 的歌**。那个要登录态，只能走你电脑上的 NeteaseCloudMusicApi（netease-music-mcp 底下用的就是它，填它的地址，不是那个项目自己的 API server——前者路由公开稳定，后者版本一动就可能变）。\n\n顺序是：填了就先用你电脑那套 → 没通就直连 → 直连也没有才退回 iTunes 三十秒试听。一路退到底也不会让你一首都听不成。")
        }
    }

    // MARK: 数据

    private var dataCard: some View {
        SettingsCard(title: "数据") {
            // 上次备份是什么时候。
            //
            // 她用 AltStore 侧载，**免费账号签的包七天到期**，
            // 过期就得重装，重装等于从零开始。所以超过七天就在这儿变色，
            // 不是唠叨，是这台机器上真实存在的期限。
            HStack(spacing: 8) {
                Image(systemName: BackupClock.overdue
                      ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.app(13))
                    .foregroundStyle(BackupClock.overdue
                                     ? (Color(hexString: "E5544B") ?? .red)
                                     : StatusTone.done.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BackupClock.note)
                        .font(.app(14, weight: BackupClock.overdue
                                      ? .medium : .regular))
                        .foregroundStyle(Theme.textMain(scheme))
                    if BackupClock.overdue {
                        Text("包七天就到期，过期得重装。导一份出来放网盘里。")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            SettingsDivider()

            storageRow

            SettingsDivider()

            Button { exportBackup() } label: {
                SettingsRowLabel(title: "导出备份", icon: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            SettingsNote("导出的是**整包**：聊天记录、供应商和密钥、记忆库（身份、说好的规矩、那封信、承诺、日记、心情）、备忘、通话记录、经期、念头池、clawd 小屋——所有存成 json 的都在里面。\n\n**图片和录音不在**：壁纸、表情、像素画、语音是单独的文件，装进来备份会从几百 KB 涨到几百 MB。\n\n以前那版只有聊天记录、供应商和设置三样，记忆库整个没在里面。手里要是还留着旧备份，建议重新导一份。")

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

            // 有文件解不开的时候才出现。
            //
            // 这种事以前是**完全静默**的：解不开就当成"没有"，
            // 接着下一次保存把空的写回去，原来那份就真没了。
            // 现在坏的那份会被挪到一边留着，这里把文件名摆出来——
            // 至少你知道发生过，也知道去哪儿捞。
            if !Storage.salvaged.isEmpty {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("有 \(Storage.salvaged.count) 份数据这次没读进来")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Color(hexString: "E5544B") ?? .red)
                    Text(Storage.salvaged.joined(separator: "\n"))
                        .font(.app(10, design: .monospaced))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text("原件已经改名留在 App 的文稿目录里，没有被覆盖。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var aboutCard: some View {
        SettingsCard {
            // 版本号那一行删掉了（她说的）：它写死在工程里永远是 1.0，
            // 跟下面那个打包时间**说的是同一件事，而且说得更差**——
            // 摆两行只会让人以为它们不一样。
            SettingsRowLabel(title: "这一版打包于", value: buildDate)
            SettingsDivider()
            SettingsRowLabel(title: "絮语窗口", value: "\(chatCount)")
            SettingsDivider()
            SettingsRowLabel(title: "消息总数", value: "\(messageCount)")

            SettingsNote("认「我装的是不是最新那版」就看上面那个打包时间。\n\n清空全部对话之后「絮语窗口」会是 1 而不是 0：群聊是常驻的、工坊有一个固定窗口，再加一个新开的空窗口，清干净了也还剩这三个壳子。看「消息总数」才知道内容有没有真的清掉。")
        }
    }

    /// 只数絮语里的普通窗口。群聊和工坊是常驻的壳子，
    /// 混进来会让人以为"怎么清都清不掉"。
    private var chatCount: Int {
        app.conversations.filter {
            $0.space == ChatSpace.chat.rawValue && !$0.isGroup
        }.count
    }

    private var messageCount: Int {
        app.conversations.reduce(0) { $0 + $1.messages.count }
    }

    /// 包是什么时候打的。
    ///
    /// 版本号写死在工程里不会变，但包里 Info.plist 的落盘时间每次构建都是新的，
    /// 拿它当"这是哪一版"最准，也不用每次记得手动改版本号。
    private var buildDate: String {
        guard let url = Bundle.main.url(forResource: "Info", withExtension: "plist"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date
        else { return "不知道" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }

    private var mcpSummary: String {
        let on = app.mcpServers.filter { $0.enabled }
        if on.isEmpty { return app.mcpServers.isEmpty ? "未连接" : "已关闭" }
        let tools = on.reduce(0) { $0 + $1.enabledTools.count }
        return "\(on.count) 个 · \(tools) 工具"
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

    // MARK: 占了多少地方

    /// 分门别类摆出来。**不给「一键清理」**——
    /// 该删哪张图只有她知道，一个按钮替她决定，删掉的就回不来了。
    /// 这儿只负责让她看见，删还是去相册、回收站那些地方各自删。
    @ViewBuilder
    private var storageRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.app(13))
                    .foregroundStyle(app.settings.accentColor)
                Text("占了多少地方")
                    .font(.app(14))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 0)
                if let u = usage {
                    Text(StorageUsage.human(u.total))
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                } else if measuring {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("计算") { measureStorage() }
                        .font(.app(12))
                        .buttonStyle(.plain)
                        .foregroundStyle(app.settings.accentColor)
                }
            }

            if let u = usage {
                ForEach(u.items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.app(12))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text(item.note)
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        Spacer(minLength: 0)
                        Text(StorageUsage.human(item.bytes))
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                if u.freeOnDevice > 0 {
                    Text("这台手机还剩 " + StorageUsage.human(u.freeOnDevice))
                        .font(.app(10.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                Text("图片是最能长的那一摊。回收站里那些三十天后自己清；"
                     + "想早点腾出来，去「相册 → 回收站」里清。")
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func measureStorage() {
        guard !measuring else { return }
        measuring = true
        Task {
            // 走几百个文件，别卡着界面
            let r = await Task.detached(priority: .utility) {
                StorageUsage.measure()
            }.value
            usage = r
            measuring = false
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
        // 先把内存里攒着没落盘的都写下去，再整个目录扫一遍。
        //
        // **不再手写要带哪几样。** 上一版只装了 providers / conversations /
        // settings，记忆库、备忘、通话、承诺、经期、clawd 小屋全都不在里面——
        // 而记忆库是这个 App 里最不可替代的东西，她还每七天重装一次。
        //
        // 记忆库那边每改一次就自己落盘了，这儿不用再催它。
        app.saveNow()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "栖备份-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        // **整个打包过程搬到后台。**
        //
        // 以前这几行是直接在主线程上跑的：扫一遍目录、把每张图读进来、
        // 转 base64、再把几百兆序列化成一整块——她按下按钮那一刻界面就冻住了。
        // 现在后台跑，前台压一层「正在打包」，她看得见它在动。
        chore.line = "正在打包…"
        // 引用先取出来。**别在后台闭包里写 `chore.xxx`**——
        // 那等于把整个 View 捕获进一个 Sendable 闭包里。
        let prog = chore
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                BackupBundle.write(to: url) { line in
                    Task { @MainActor in prog.line = line }
                }
            }.value

            chore.line = nil
            guard report.bytes > 0 else {
                alertMessage = "导出失败，一个字节都没写出来。"
                return
            }
            exportURL = url
            BackupClock.markDone()

            // ⚠️ **图片的数目一定要报给她看。**
            //
            // 她说「图片并没有备份，没有备份图片我之前写的关键词全都白瞎了」——
            // 一个 json 文件从外表看不出里面有没有图，她只能等到还原那天才发现。
            // 现在导完当场写清楚：几份数据、几个图片语音、多大。
            // 是 0 就是 0，当场就知道。
            let mb = Double(report.bytes) / 1024 / 1024
            // ⚠️ 数字**别走 `String(format:)` 的 `%d`**——那个要的是 32 位，
            // 喂个 Swift 的 Int 进去在 64 位上是要出岔子的。插值最省事。
            var msg = String(format: "打好了，%.1f MB。", mb)
                + "\n\n· \(report.files) 份数据"
                + "\n· **\(report.blobs) 个图片语音**"
            if report.blobs == 0 {
                msg += "\n\n⚠️ **一张图都没装进去。**"
                    + "要么这台手机上确实还没有图，要么就是出问题了——跟我说一声。"
            }
            if !report.skipped.isEmpty {
                msg += "\n\n有 \(report.skipped.count) 个太大了没装（单个超过 20 MB，"
                    + "一般是视频）。"
            }
            msg += "\n\n存到「文件」里最稳，微信传大文件容易截断。"
            alertMessage = msg
        }
    }

    /// 选完文件先**问一句怎么放**，别闷头盖。
    ///
    /// 她的原话：「导入备份应该不是覆盖而是增加……只增加目前没有的，
    /// 已有的忽略。」——所以默认是「只补没有的」，
    /// 「整个盖掉」留给换手机、重装那种真的想回到那一天的场合。
    /// 「带上多少历史」现在选的是哪一档
    static func historyLabel(_ n: Int) -> String {
        n <= 0 ? "全部" : "最近 \(n) 条"
    }

    /// 辅助模型现在选的是谁
    private var helperLabel: String {
        let saved = app.settings.helperModel
        guard !saved.isEmpty, let cut = saved.firstIndex(of: "|"),
              let pid = UUID(uuidString: String(saved[saved.startIndex..<cut])),
              let p = app.providers.first(where: { $0.id == pid })
        else { return "自动选择" }
        return p.name + " · " + String(saved[saved.index(after: cut)...])
    }

    /// 备用那个现在选的是谁
    private var fallbackLabel: String {
        let saved = app.settings.fallbackModel
        guard !saved.isEmpty, let cut = saved.firstIndex(of: "|"),
              let pid = UUID(uuidString: String(saved[saved.startIndex..<cut])),
              let p = app.providers.first(where: { $0.id == pid })
        else { return "不启用" }
        return p.name + " · " + String(saved[saved.index(after: cut)...])
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertMessage = "选文件失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }

            // ① 只选了一个、而且真是整包备份 → 走还原那条路
            if urls.count == 1 {
                let needsStop = url.startAccessingSecurityScopedResource()
                defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

                // **先复制到临时目录，不读进内存。**
                //
                // 两个理由：
                //   ① 她选的那个 URL 是有安全作用域的，出了这个闭包就作废了，
                //      而还原要跑好一会儿——必须先拿到一份自己的
                //   ② 一份几百兆的备份读成 Data 就是几百兆内存，
                //      而复制文件是文件系统的事，一个字节都不进内存
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("待还原-" + UUID().uuidString + ".json")
                try? FileManager.default.removeItem(at: copy)
                guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else {
                    alertMessage = "这份文件读不出来。"
                    return
                }
                // 只看开头那几 KB 就够认出它是不是整包——**不用全读**
                if BackupBundle.looksLikeBundle(fileAt: copy) {
                    pendingBackup = copy
                    return
                }
                // 不是整包，但也可能是老备份（只有 providers/conversations/settings）。
                // 老备份都很小，读进来无所谓。
                if let data = try? Data(contentsOf: copy),
                   (try? JSONDecoder().decode(Backup.self, from: data)) != nil {
                    pendingBackup = copy
                    return
                }
                try? FileManager.default.removeItem(at: copy)
            }

            // ② 其余一律**转给记忆库那套**。
            //
            // 她拿 `memories.json` / `identity.txt` 这些走到这个口来，
            // 以前只会得到一句「没有 files 也没有 conversations」——
            // 那句话没错，但它把她堵在这儿了。
            // 同一个「导入」按钮，两种都收才对。
            let report = MemoryStore.shared.importFiles(urls)
            alertMessage = "这些不是整包备份，当成**记忆库的文件**导了：\n\n"
                + report.text
        }
    }

    /// 真正动手那一下。
    ///
    /// **跑在后台**，前台压一层「正在还原」。以前这一整套（读整包、解析、
    /// 一个个写回去）都在主线程上，她说的「导入备份有点卡」就是这个。
    private func applyBackup(_ url: URL, mode: BackupBundle.Mode) {
        chore.line = "正在还原…"
        let prog = chore
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                BackupBundle.restore(from: url, mode: mode) { line in
                    Task { @MainActor in prog.line = line }
                }
            }.value
            chore.line = nil
            finishRestore(outcome, url: url, mode: mode)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func finishRestore(_ outcome: BackupBundle.Restored,
                               url: URL, mode: BackupBundle.Mode) {
        do {
            switch outcome {
            case .bundle(let count, let pics):
                // **还原完立刻把内存也换掉。**
                //
                // 以前这儿只写盘，然后请她「完全关掉 App 再打开」。
                // 她照做了，聊天记录还是没出来——因为写完盘到她关掉 App 之间，
                // 只要界面上任何一处动了一下（甚至只是退出到后台），
                // 内存里那份**旧的** conversations 就会被存回去，
                // 把刚还原的盖掉。
                //
                // 现在还原完当场重读一遍，聊天记录立刻就在。
                app.reloadAfterRestore()
                alertMessage = (mode == .merge ? "补进来了 " : "还原了 ") + "\(count) 份数据"
                    + (pics > 0
                       ? "、**\(pics) 个图片语音**。"
                       // 一张图都没回来，说清楚是为什么——
                       // 别让她再一次以为图在里面
                       : "。\n\n⚠️ **这份备份里一张图都没有**"
                         + "（要么它是没带图的旧版备份，要么这些图这边本来就有了）。")
                    + (mode == .merge
                       ? "\n\n**只补了这边没有的**，你现在的聊天记录一条都没动。"
                         + "同一个窗口两边各聊了一段的话，两段会按时间并到一起。"
                       : "\n\n整个盖过去了。")
                    + "\n\n小屋、表情工坊那几处是开 App 那会儿读进内存的，"
                    + "**保险起见还是把 App 完全关掉再打开一次**。"
            case .legacy:
                // 她手里可能还留着以前导出的老备份，照样认。
                // **老备份只有三样，没法按 id 合并**（那时候还没有整包结构），
                // 所以这一支只在「整个盖掉」的时候才真的写进去。
                guard mode == .overwrite else {
                    alertMessage = "这是很老的那种备份（只有供应商、聊天记录和设置），"
                        + "它没法只挑没有的补——要用它就得选「整个盖掉」。"
                    return
                }
                // 老备份只有三样，都很小，整个读进来无所谓
                guard let data = try? Data(contentsOf: url) else {
                    alertMessage = "这份文件读不出来了。"
                    return
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let backup = try decoder.decode(Backup.self, from: data)
                app.providers = backup.providers
                app.conversations = backup.conversations
                app.settings = backup.settings
                app.saveNow()
                alertMessage = "导入成功。\n\n"
                    + "这是旧版的备份，里面只有供应商、聊天记录和设置，"
                    + "记忆库、备忘、通话记录那些不在里面。"
            case .unreadable(let why):
                alertMessage = why
            }
        } catch {
            alertMessage = "这个文件读不了，可能不是本 App 导出的备份。\n\(error.localizedDescription)"
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
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                // 原来是一行灰字飘在卡片上面。现在是「一个小点 · 名字 ·
                // 一道淡出去的线」——同样一行字，但它落在页面上了。
                SectionHeader(title)
            }
            VStack(spacing: 0) { content }
                .glassBackground(radius: 20, strength: app.settings.glassOpacity)
        }
    }
}

/// 卡片里行与行之间那道线。很淡，只是把两行分开，不是框。
///
/// 现在它**往右边淡出去**：两头齐的实线是「格子」，
/// 一头淡的是「间隔」——这一页要的是后者。
struct SettingsDivider: View {
    var body: some View {
        Hairline()
            .padding(.leading, 16)
            .padding(.trailing, 8)
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
                    .font(.app(14))
                    .foregroundStyle(tint ?? Theme.textSoft(scheme))
                    .frame(width: 20)
            }
            Text(title)
                .font(.app(15))
                .foregroundStyle(tint ?? Theme.textMain(scheme))
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.app(13))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.app(12, weight: .semibold))
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
                .font(.app(15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer(minLength: 8)
            TextField(placeholder, text: $text)
                .font(.app(mono ? 13 : 15, design: mono ? .monospaced : .default))
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
    /// 收起来的时候那一行写什么。不传就用「这是什么」。
    var title: String = "这是什么"

    init(_ text: String, title: String = "这是什么") {
        self.text = text
        self.title = title
    }

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var app: AppState
    /// **默认收着。** 她说全摊开「很杂乱」——
    /// 这些说明是给「第一次看不懂」的时候用的，不是每次进设置都要重读一遍。
    @State private var open = false

    /// 把 `**重点**` 真的画成粗体。
    ///
    /// 以前这里是 `Text(text)`，而 text 是个**变量**——
    /// SwiftUI 只对写死的字面量解析 markdown，拿变量渲染的时候
    /// 那两对星号是原样显示出来的。整个设置页里所有说明文字都中了这一枪。
    ///
    /// 但也不能简单换成 `Text(.init(text))`：markdown 会把换行吃掉，
    /// 而这些说明大多靠 `\n\n` 分段。所以按行拆开各自解析，再用换行拼回去，
    /// 粗体有了，分段也还在。
    private var rendered: AttributedString {
        var out = AttributedString()
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            if i > 0 { out += AttributedString("\n") }
            if let a = try? AttributedString(markdown: line) {
                out += a
            } else {
                out += AttributedString(line)
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.app(11))
                    Image(systemName: "chevron.down")
                        .font(.app(8, weight: .semibold))
                        .rotationEffect(.degrees(open ? 0 : -90))
                    Spacer()
                }
                .foregroundStyle(app.settings.accentColor.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                Text(rendered)
                    .font(.app(11))
                    // ⚠️ 以前是 `textMuted`。那一档是给「附注、时间戳、
                    // 一眼扫过去就行」的字用的——**而这段是正文**，
                    // 她展开它就是为了读。深色下 muted 压得太低，
                    // 她的原话是「完全看不见」。换成 soft 那一档。
                    .foregroundStyle(Theme.textSoft(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
                        .font(.app(12.5, weight: selection == value ? .semibold : .regular))
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
