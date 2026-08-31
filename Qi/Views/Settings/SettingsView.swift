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
    /// 占了多少地方。**进这一页才算**——要走几百个文件，
    /// 每次刷设置都算一遍太亏
    @State private var usage: StorageUsage.Report?
    /// 「重新采集声音样本」的确认和回执
    @State private var askResetVoice = false
    @State private var voiceResetDone = false
    @State private var measuring = false
    /// 正在「查一遍图」（`MediaAudit`）
    @State private var auditing = false

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
    /// ⚠️ 要观察它：抓的时候那句「在找…」和池子里的条数都得跟着变，
    /// 只读 `TopicPool.shared` 不订阅的话这一段是死的。
    @ObservedObject private var topics = TopicPool.shared
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
            // ⚠️ 选文件那个弹窗**不在这一层了**，挪进了 `ImportButton`。
            //
            // 她报的：「点击导入备份弹出文件后会自己关闭」
            // 「第一次导入了五次才成功」——都是同一个根：
            // 这一页订阅着 `app`，**它里任何一个 `@Published` 变化都会重建 body**
            // （后台存盘完了、身体推进了一格、话题池抓完一轮…），
            // 而重建那一下就把正在弹的选择器撤掉了。
            //
            // 而且这一层一口气挂了五个 presentation，它们之间还会抢。
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
                            Text("请勿退出，完成后自动关闭")
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
                    // ⚠️ 走 `SettingsSlider`，**不要写成 `Slider(value: $app.settings.…)`**。
                    //
                    // 这一条以前就是裸的 `Slider` 直接绑全局设置：手指划一下
                    // 一秒六十次改 `AppSettings`，每次都让整个 App 重新求值、
                    // 屏幕上每一块玻璃重画一次模糊。拖起来卡，拖完切到聊天页
                    // 那一下要一次把几百条气泡全部重建——直接被系统杀掉，
                    // 在她那儿就是**闪回主屏**。工坊那边气泡少，所以没事。
                    //
                    // `SettingsSlider` 的规矩是：拖的时候只在自己心里改，
                    // **松手才写回全局**。这个页面上别的滑块早就都走它了，
                    // 只有这一根漏了。
                    SettingsSlider(
                        title: "压暗",
                        value: $app.settings.wallpaperDim,
                        range: 0...0.6,
                        step: nil,
                        readout: "\(Int(app.settings.wallpaperDim * 100))%",
                        tint: app.settings.accentColor,
                        scheme: scheme)
                        .padding(.top, 2)
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
                Text(MD.inline("无需手动操作：每次按住说话时自动采样——"
                     + "音量、语速、停顿有多长。攒够 \(VoiceBaseline.shared.progress.need) 条之后，"
                     + "再说话就会跟你自己的平时比一比，明显偏了才在那条语音上标一句"
                     + "「比平时轻」「比平时快」，他看得见。\n\n"
                     + "攒够之前它一个字都不说——那会儿说什么都是瞎猜。"
                     + "全程在这台手机上算，不花钱、不上传。"
                     + "换了麦克风、感冒一周之后不准了，可以让它重新认识你。"))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                // ⚠️ 要先问一句。
                //
                // 她报的：「我点击『重新采集声音样本』没反应，最好再加一个确认，
                // 免得手误清掉了。我有点不确定这个了，我写下面的 bug 时
                // 回去看了一眼从 2/8 变成 0/8 了，也就是说重新采样了。」
                //
                // 两件事一起坏：**它做了，但一个字都不说**——
                // 于是「像没反应」和「手误就清了」是同一个原因。
                // 攒满八条要说八次话，清掉的代价不小，值得挡一下。
                Button {
                    askResetVoice = true
                } label: {
                    Text("重新采集声音样本")
                        .font(.app(12))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .confirmationDialog("重新采集声音样本",
                                    isPresented: $askResetVoice,
                                    titleVisibility: .visible) {
                    Button("清掉，重新认识我", role: .destructive) {
                        VoiceBaseline.shared.reset()
                        voiceResetDone = true
                    }
                    Button("算了", role: .cancel) {}
                } message: {
                    Text("已经攒下的样本会清空，要重新说满八条才会再开始比对。")
                }
                .alert("清好了", isPresented: $voiceResetDone) {
                    Button("好") { voiceResetDone = false }
                } message: {
                    // 做完了要**说一声**——上一版就是做了不吭声，
                    // 她以为没反应，回头才发现已经清了。
                    Text("样本已清空，重新说满八条语音后会再开始比对。")
                }
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
                    Text("不发起通话，也不自动唤醒。主动对话不受影响")
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
                    Text("执行删除、装卸小屋、发起通话前先弹出确认")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            SettingsNote("仅对不可逆的操作发起确认。存图、写记忆、做标记等可撤销的操作不询问。"
                         + "\n\n确认请求 90 秒无响应则视为拒绝，本次操作不执行。")
            SettingsDivider()

            Toggle(isOn: $app.settings.segmentAssistant) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("他分段发")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("由模型决定分段位置，每段单独成一个气泡")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsDivider()

            typingSection

            SettingsDivider()

            Toggle(isOn: $app.settings.segmentUser) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我分段发")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(MD.inline("输入框旁边多一个「暂存」键：按它把这一条攒进这一轮，"
                         + "按发送键把攒着的一起发出。"
                         + "图、文件、语音、表情**都能攒**，"
                         + "所以「先说一句再发语音」和「先发语音再补一句」都行。"
                         + "**不限时**，攒多久都行"))
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            // ⚠️ 「等多久」那根滑块删了：现在没有倒计时了，攒着的东西
            // 只在按发送键的时候才走。`segmentUserDelay` 那个字段还在
            // `AppSettings` 里，**只为一件事：让旧设置文件还解得开**。
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
            SettingsNote("携带的历史消息越多，上下文连贯性越好，单次请求的费用也越高。",
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
                            // ⚠️ 显示 `displayName`，不是 `m.id`。
                            //
                            // 她说「备用模型和辅助模型并没有给我选择的余地，
                            // 每个模型价格不同，我需要筛选」——
                            // 菜单里其实一直有东西，但摆出来的是接口要的那串原始 id。
                            // 一屏长得差不多的型号，她当然无从选起。
                            // `displayName` 是她自己能改的（供应商 → 模型），
                            // 想把价格写进去就写进去——**价格只有她知道，
                            // 我内置一份价目表只会过期后说假话。**
                            Button(p.name + " · " + m.displayName) {
                                app.settings.fallbackModel = p.id.uuidString + "|" + m.id
                            }
                        }
                    }
                } label: {
                    // ⚠️ 这儿以前挂着一个上下箭头。**她定的：去掉。**
                    //
                    // 她的原话：「全部和每 60 条没有这个符号，
                    // 有些有有些没有就会显得很怪，干脆都不要有，
                    // 点击能出现选项就行。」
                    //
                    // 她对。一屏上同一类东西（右边那一列可点的值）
                    // 只有两个带箭头、别的都不带，**那个箭头就不再是
                    // 「这里能点」的记号，而是一处不整齐**——
                    // 反而让不带箭头的那几行看着像不能点。
                    // 要么全带要么全不带；这一页历来是全不带，那就跟着。
                    HStack(spacing: 3) {
                        Text(fallbackLabel)
                            .font(.app(14))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            SettingsNote("""
            主模型返回额度或限流错误（429、余额不足）时，自动切换至此模型继续当前回复，无需新建窗口。

            切换只更换请求的目标模型：聊天记录、浓缩件、工具与身体状态均不变更。已输出的残句会撤销后重发，最终显示为完整的一段回复。

            切换后的消息下方标注「换了个模型接着说」，用于标识来源。

            仅额度与限流类错误触发切换。网络中断、地址错误等不触发。
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
                            Button(p.name + " · " + m.displayName) {
                                app.settings.helperModel = p.id.uuidString + "|" + m.id
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(helperLabel)
                            .font(.app(14))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            SettingsNote("""
            辅助模型承担非对话类任务：为表情生成关键词、翻译、通话摘要、图像识别、视频抽帧识别。

            指定后，上述任务固定使用该模型；对话仍使用输入框上方所选的模型。

            选择「自动选择」时，按供应商顺序取第一个可用模型。
            """, title: "说明")

            SettingsDivider()

            // ⚠️ 话题池要摆在辅助模型**那段说明之后**。
            //
            // 上一版我插在了「辅助模型」和它自己那段说明中间，
            // 于是话题池底下挂着两个「说明」：
            // 一个是它自己的，一个是上面那一项被挤下来的。
            //
            // 记一句：**往设置页插一项之前，先看清楚上一项的说明在哪儿。**
            // 这一页是「开关 + 说明」成对的，插在对中间就把一对拆成了两截。
            topicSection

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
            对话超过阈值时，将较早的消息压缩为一份浓缩件，后续对话在其之上继续。再次压缩时以「上一份浓缩件 + 新增消息」为输入，始终只保留一份。

            与上方「带上多少历史」的区别：后者直接截断，超出部分不再进入请求；压缩则将其替换为更短的文本，内容仍在。

            浓缩件之外另保留一份原文摘录，由本机按规则选取，不调用模型、不产生费用。摘要保留事件，原文保留措辞。

            ⚠️ 每次压缩额外产生一次请求。按每 60 条压缩一次计，约每三十轮对话增加一次。压缩在发送消息时同步进行，不在后台运行。

            单个窗口的压缩结果与手动压缩入口位于该窗口的「对话设定」。
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

            SettingsNote("开启后回车键为发送；关闭时回车键为换行。默认关闭。",
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
                SettingsDivider()

                NavigationLink { HealthAccessView() } label: {
                    SettingsRowLabel(title: "健康和待办",
                                     value: healthSummary, chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 健康和待办现在给了哪几样
    private var healthSummary: String {
        var on: [String] = []
        if app.settings.healthAccess { on.append("健康") }
        if app.settings.todoAccess { on.append(app.settings.todoWrite ? "待办·可写" : "待办") }
        return on.isEmpty ? "都关着" : on.joined(separator: "、")
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
            SettingsNote("前两项为本地服务地址，支持局域网或 Tailscale 地址。服务不可达时，心跳页显示最后一次成功读取的数据。\n\n**网易云一项可留空。** 留空时直接调用网易云公开接口，可获取完整音频与歌词（含译文），无需本地服务或登录。\n\n该项仅用于获取 VIP 音源，需要登录态，须指向本地部署的 NeteaseCloudMusicApi（填写其地址，而非项目自带的 API server）。\n\n取源顺序：本地服务 → 公开接口 → iTunes 三十秒试听。")
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

            // ⚠️ 这段话**说反过一次**。它一直写着「图片和录音不在」，
            // 而从 v3 起图片语音就在里面了。她说「图片并没有备份」的时候，
            // 这段话是站在她那边帮腔的——一份写错的说明比没有说明更坏。
            SettingsNote("导出为完整数据包，包含：聊天记录、供应商配置与密钥、记忆库（身份、规则、信件、承诺、日记、心情）、备忘、通话记录、经期、念头池、clawd 小屋等全部 JSON 存档。\n\n**图片与音频一并打包**：壁纸、表情、像素画、语音等独立文件均在包内，因此文件体积为数十至数百 MB。单个超过 20 MB 的文件不予打包，导出完成后列出。\n\n导出结果中的图片语音数量为写入完成后重新统计所得。显示为 0 即表示包内不含任何图片或音频。\n\n回收站内容不进入备份。")

            SettingsDivider()

            ImportButton(title: "导入备份", icon: "square.and.arrow.down") { result in
                importBackup(result)
            }

            SettingsDivider()

            // ⚠️ 她两次说的是同一件事：「显示备份了多少张图片，
            // 可是相册里看不见，只能看见文字。」
            //
            // 之前 App 里**没有任何一处**能回答「文件到底还在不在」——
            // 记录在、图没了，界面上就是一个名字底下空一块，
            // 不报错，也不说话。她只能对着一屏空白猜。
            // 这一行是来结束猜的。
            Button { auditMedia() } label: {
                SettingsRowLabel(title: auditing ? "正在查…" : "查一遍文件",
                                 icon: "checklist")
            }
            .buttonStyle(.plain)
            .disabled(auditing)

            SettingsNote("校验记录与文件的一致性，覆盖相册、表情、语音条、歌曲音频四类。相册仅显示文字、语音条无法播放、歌曲无法播放，均为两者不一致所致。**仅检查，不删除任何文件。**")

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

            SettingsNote("上方的打包时间用于确认当前安装的构建版本。\n\n清空全部对话后「絮语窗口」计数为 1 而非 0：群聊窗口常驻、工坊有一个固定窗口，另加一个新建的空窗口，均为空壳。判断内容是否清除应查看「消息总数」。")
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

    /// 查一遍图。见 `MediaAudit`——记录和文件对不上的时候，
    /// 这是唯一一处说得出「丢了几张」的地方。
    private func auditMedia() {
        guard !auditing else { return }
        auditing = true
        Task {
            let r = await MediaAudit.run(app: app)
            auditing = false
            alertMessage = r.text
        }
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
            // ⚠️ 报的是 `verified` 不是 `blobs`。
            //
            // `blobs` 是「我打算装几个」，`verified` 是**写完之后
            // 把成品重新扫一遍数出来的**。她说过两次「显示有图、实际没有」，
            // 上一版报的恰恰是前者——写不进去的时候它照样报一个漂亮的数。
            // 从今往后这一行只许说实话。
            //
            // ⚠️ 数字**别走 `String(format:)` 的 `%d`**——那个要的是 32 位，
            // 喂个 Swift 的 Int 进去在 64 位上是要出岔子的。插值最省事。
            var msg = String(format: "打好了，%.1f MB。", mb)
                + "\n\n· \(report.files) 份数据"
                + "\n· **\(report.verified) 个图片语音**（写完数过一遍的）"
            // ⚠️ **拆开摆出来。**
            //
            // 她说「相册里就一个文件夹一个 gif，数字却从 6 变 8 变 10」。
            // 那个数没错，错的是只报一个总数：它数的是整个 Documents 里的
            // 图和声音（聊天发过的、壁纸、像素画、语音条、删表情剩下的孤儿…），
            // 而她看的是相册里有几张。
            // **一个总数答不了「为什么是 10」，只会让她再猜一次。**
            for (label, n) in report.breakdown {
                msg += "\n　　· " + label + "：\(n)"
            }
            if report.writeFailed {
                msg += "\n\n⚠️ **中途有写不进去的地方，这份包不能当数。**"
                    + "多半是手机没空间了——腾一点出来再导一次，"
                    + "导完对一下上面那个数。"
            } else if report.verified < report.blobs {
                msg += "\n\n⚠️ **本来要装 \(report.blobs) 个，成品里只数出 \(report.verified) 个。**"
                    + "这份包是残的，别拿它当备份——跟我说一声。"
            } else if report.verified == 0 {
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

    /// 把存的那串「供应商id|模型id」翻成人看的名字。
    ///
    /// ⚠️ 翻出来的是 `displayName`，不是模型 id。
    /// 存的必须是 id（那是发给接口的），**看的必须是她取的名字**——
    /// 她把价格写在名字里，而这一行原来把它扔了。
    private func modelLabel(_ saved: String, empty: String) -> String {
        guard !saved.isEmpty, let cut = saved.firstIndex(of: "|"),
              let pid = UUID(uuidString: String(saved[saved.startIndex..<cut])),
              let p = app.providers.first(where: { $0.id == pid })
        else { return empty }
        let mid = String(saved[saved.index(after: cut)...])
        let shown = p.models.first(where: { $0.id == mid })?.displayName ?? mid
        return p.name + " · " + shown
    }

    // MARK: 打字的节奏

    /// 两个开关，**分量完全不同**，所以分开摆、分开写说明。
    ///
    /// 上面那个说的是她**发出来那句话**的附加信息；
    /// 下面那个是把她**没打算让他看见的那一下**递出去。
    @ViewBuilder
    private var typingSection: some View {
        Toggle(isOn: $app.settings.typingRhythm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("记录输入节奏")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(MD.inline("在消息上附一句「这句打了多久、中间停过几次」。"
                     + "**仅记录时长与次数，不记录内容**。"
                     + "本机计算，不额外计费"))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .tint(app.settings.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)

        Toggle(isOn: $app.settings.typingWithheld) {
            VStack(alignment: .leading, spacing: 2) {
                Text("告知未发出的输入")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(MD.inline("输入较长内容后全部删除、且后续 90 秒未发送任何消息时，"
                     + "告知模型此事发生过。"
                     + "**删除后重新输入并发送的不计入**。"
                     + "内容不会被记录，仅告知字数与次数"))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .tint(app.settings.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)

        SettingsNote("""
        输入节奏：发送时在消息前附一句说明（如「这句她打了 47 秒、中间停了 3 次」）。输入时长不足 25 秒且停顿少于 2 次的不附。

        未发出的输入：判定条件为删除 8 字以上、且此后 90 秒内未发送任何消息。删除后重新输入并发送的，判定自动撤销。

        两项均不记录输入内容。存储的仅为时间戳、字数与次数。

        两项均为本机计算，不联网、不调用模型。
        """, title: "说明")
    }

    // MARK: 话题池

    /// 话题池那一段。
    ///
    /// 它做的事：定期从网上捞一批近期信息，用一个**便宜模型**筛成 0~3 条，
    /// 放进池子；他自己去翻，觉得有意思就主动跟她开口。
    ///
    /// ⚠️ 为什么模型要单独选：辅助模型还要看图看视频，
    /// 得挑个视觉能力过得去的；筛话题只是读几十行字挑三条，
    /// 那个可以便宜得多。绑在一个字段上她就只能迁就贵的那头。
    @ViewBuilder
    private var topicSection: some View {
        Toggle(isOn: $app.settings.topicPoolOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("话题池")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(MD.inline("定期联网抓取近期信息，由下方模型筛选后留下 0～3 条，"
                     + "供模型主动开启话题。**抓取与筛选不占用对话上下文**"))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .tint(app.settings.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)

        if app.settings.topicPoolOn {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("筛选模型")
                        .font(.app(13))
                        .foregroundStyle(Theme.textSoft(scheme))
                    Spacer(minLength: 8)
                    Menu {
                        Button("跟随辅助模型") { app.settings.topicModel = "" }
                        ForEach(app.providers.filter { $0.enabled }) { p in
                            ForEach(p.enabledModels.isEmpty ? p.models : p.enabledModels) { m in
                                Button(p.name + " · " + m.displayName) {
                                    app.settings.topicModel = p.id.uuidString + "|" + m.id
                                }
                            }
                        }
                    } label: {
                        Text(modelLabel(app.settings.topicModel, empty: "跟随辅助模型"))
                            .font(.app(13))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .lineLimit(1)
                    }
                }

                HStack {
                    Text("抓取间隔")
                        .font(.app(13))
                        .foregroundStyle(Theme.textSoft(scheme))
                    Spacer()
                    Text("\(Int(app.settings.topicEveryHours)) 小时")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                Slider(value: $app.settings.topicEveryHours, in: 2...24, step: 1)
                    .tint(app.settings.accentColor)

                HStack(spacing: 10) {
                    Button {
                        // 手动跑一轮。**不看间隔**——她按了就是要现在抓。
                        guard let reach = app.topicReach() else { return }
                        Task { @MainActor in
                            TopicPool.shared.busy = "在找…"
                            _ = await TopicScout.run(
                                app: app, reach: reach,
                                interests: EmotionEngine.shared.state.likeHints
                                    .prefix(3).map(\.text)) { line in
                                TopicPool.shared.busy = line
                            }
                            TopicPool.shared.busy = nil
                        }
                    } label: {
                        Text(topics.busy ?? "现在抓一轮")
                            .font(.app(13))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(topics.busy != nil)
                    Spacer()
                    Text("池子里 \(topics.pending.count) 条")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                if !topics.lastError.isEmpty {
                    Text(topics.lastError)
                        .font(.app(11))
                        .foregroundStyle(.orange)
                }

                // 池子里现在有什么。**她也能看、也能扔**——
                // 那份文档里「Agent 和人类决定」那一行说的就是这个。
                ForEach(topics.pending.prefix(5)) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top) {
                            Text(t.title)
                                .font(.app(12.5))
                                .foregroundStyle(Theme.textMain(scheme))
                            Spacer(minLength: 6)
                            Button {
                                topics.remove(t.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.app(9))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            .buttonStyle(.plain)
                        }
                        if !t.summary.isEmpty {
                            Text(t.summary)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .lineLimit(3)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.softFillDeep))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }

        SettingsNote("""
        每隔设定的时长联网抓取一批近期信息，交由筛选模型判断，最多保留 3 条放入话题池。

        池中条目 48 小时后过期。模型可自行查看并决定是否开启话题，也可全部忽略。

        筛选模型独立于辅助模型：该任务仅需处理文本，可选用更低价的模型。留空则跟随辅助模型。

        抓取与筛选在后台完成，不进入对话上下文。
        """, title: "说明")
    }

    /// 辅助模型现在选的是谁
    private var helperLabel: String {
        modelLabel(app.settings.helperModel, empty: "自动选择")
    }

    /// 备用那个现在选的是谁
    private var fallbackLabel: String {
        modelLabel(app.settings.fallbackModel, empty: "不启用")
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
            case .bundle(let count, let pics, let already, let failed):
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
                // ⚠️ 图那一半**分三个数报**：放回去的、本来就有的、没成的。
                //
                // 以前只有一个「N 个图片语音」。N 是 0 的时候，
                // 「这边本来就都有」和「一张都没成」写的是同一句话，
                // 她只能从一个 0 里猜——而她猜的方向恰好是错的那个。
                var picNote = ""
                if pics > 0 { picNote += "、**\(pics) 个图片语音**" }
                if already > 0 { picNote += "（另有 \(already) 个这边本来就有，没动）" }
                picNote += "。"
                if pics == 0 && already == 0 && failed == 0 {
                    picNote = "。\n\n⚠️ **这份备份里一个图片语音都没有**"
                        + "（多半是没带图的旧版备份）。"
                }
                if failed > 0 {
                    picNote += "\n\n⚠️ **有 \(failed) 个图片语音没能放回去**"
                        + "（解不开或者写不进去）。要是相册里空着一片，就是这些。"
                        + "先看看手机还有没有空间，再导一次。"
                }
                alertMessage = (mode == .merge ? "补进来了 " : "还原了 ") + "\(count) 份数据"
                    + picNote
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
                // ⚠️⚠️ **这儿钉死 1，不读 `glassOpacity`。**
                //
                // 她报的：「模糊程度的滑块依旧拖不动，甚至点击都没有反应。」
                // 我上一版猜是样品重画太贵，猜错了——真正的病根是个自噬循环：
                //
                //   模糊那根滑块**就坐在这张卡上**，
                //   而这张卡的底读的正是它调的那个值。
                //   手指一动 → `glassOpacity` 变 → 整张卡的玻璃重建 →
                //   连同滑块一起换了个新的 → 手势当场断掉。
                //
                // 所以「拖不动」和「点了没反应」是同一件事：
                // 它每次刚接住手指就把自己拆了重建。
                //
                // 设置页的卡片本来也不该跟着这一档走——
                // 那一档是给聊天界面调的，不是给设置页调的。
                .glassBackground(radius: 20, strength: 1)
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
    /// 折叠时那一行的标题。不传就用「说明」。
    ///
    /// ⚠️ 默认值从「这是什么」改成了「说明」。
    /// 她定的规矩：**前端只说这个功能是什么、怎么用**，
    /// 不转述任何人说过什么，也不解释为什么这么设计。
    /// 「这是什么」是口语，「说明」才是标题。
    var title: String = "说明"

    init(_ text: String, title: String = "说明") {
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
