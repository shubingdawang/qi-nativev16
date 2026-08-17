import SwiftUI

/// 自定义主题。
///
/// 跟设置主页同一套皮：壁纸垫底 + 玻璃卡片。
/// 以前这页是系统的 Form，白底加灰分组线——从设置页点进来那一下
/// 像换了个 App。
struct AppearanceView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var customHex = ""
    /// 那两根玻璃滑块拖到一半的值。只喂给底下那两块样品——
    /// 全局那份等松手才改（不然拖一下就要重画全屏的玻璃，手感直接死掉）
    @State private var blurDraft: Double?
    @State private var dimDraft: Double?

    /// 设置页那张外观卡片也要用同一组色，所以放成 static
    static let accentPresets: [(String, String)] = [
        ("雾青", "677E9C"),
        ("黛紫", "6F6396"),
        ("苔绿", "5F8768"),
        ("赭石", "A2664B"),
        ("绛红", "9C5464"),
        ("墨灰", "555B66"),
        ("琥珀", "B08040"),
        ("靛蓝", "3F6FA8")
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
            WallpaperBackground()

            ScrollView {
                VStack(spacing: 18) {
                    accentCard
                    backdropCard
                    fontCard
                    glassCard
                    presetCard
                    textColorCard
                    chatCard
                    previewCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("自定义主题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { customHex = app.settings.accentHex }
    }

    // MARK: 主题色

    private var accentCard: some View {
        SettingsCard(title: "主题色") {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Self.accentPresets, id: \.1) { name, hex in
                    Button {
                        app.settings.accentHex = hex
                        customHex = hex
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(Color(hexString: hex) ?? .gray)
                                    .frame(width: 34, height: 34)
                                if app.settings.accentHex.uppercased() == hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(name)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            SettingsDivider()

            HStack(spacing: 8) {
                Text("自定义")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                TextField("六位色号", text: $customHex)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14, design: .monospaced))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 100)
                    .onSubmit { applyCustom() }

                // 边打边看。光看六位十六进制没人知道那是什么颜色，
                // 打错一位也看得出来——填不满六位就画一个空框。
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(previewColor ?? Color.clear)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(previewColor == nil
                                      ? Theme.textMuted(scheme).opacity(0.35)
                                      : Color.white.opacity(0.5),
                                      lineWidth: 1)
                    if previewColor == nil {
                        Image(systemName: "questionmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .frame(width: 26, height: 26)
                .animation(.easeOut(duration: 0.15), value: previewColor)
                Button("用") { applyCustom() }
                    .font(.system(size: 14, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(app.settings.accentColor)
                    .disabled(Color(hexString: customHex) == nil)
                    .opacity(Color(hexString: customHex) == nil ? 0.4 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    // MARK: 底

    /// 整个 App 的底：一张图 / 一块纯色 / 一道渐变。
    ///
    /// 「可调节的渐变主题」是她点名要的。做成三档而不是「壁纸 + 一个渐变开关」，
    /// 是因为纯色那一档本来也缺——想要一块干净的底以前只能不设壁纸，
    /// 而那样拿到的是主题写死的颜色，她说了不算。
    private var backdropCard: some View {
        SettingsCard(title: "底") {
            HStack(spacing: 10) {
                ForEach([("image", "图片"), ("gradient", "渐变"), ("solid", "纯色")],
                        id: \.0) { key, title in
                    Button {
                        app.settings.wallpaperMode = key
                    } label: {
                        VStack(spacing: 6) {
                            backdropSample(key)
                                .frame(height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 10,
                                                            style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(app.settings.accentColor,
                                                      lineWidth:
                                                        app.settings.wallpaperMode == key ? 2 : 0)
                                }
                            Text(title)
                                .font(.system(size: 11))
                                .foregroundStyle(app.settings.wallpaperMode == key
                                                 ? Theme.textMain(scheme)
                                                 : Theme.textMuted(scheme))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if app.settings.wallpaperMode == "gradient" {
                SettingsDivider()
                colorRow("从", hex: $app.settings.gradientFrom)
                colorRow("到", hex: $app.settings.gradientTo)
                slider(title: "方向",
                       value: $app.settings.gradientAngle,
                       range: 0...360, step: 5,
                       readout: "\(Int(app.settings.gradientAngle))°")
            }

            if app.settings.wallpaperMode == "solid" {
                SettingsDivider()
                colorRow("颜色", hex: $app.settings.solidHex)
            }

            if app.settings.wallpaperMode == "image" {
                SettingsNote("图片那档在「设置 → 外观」里换。这儿只管选用哪一种底。")
            } else {
                SettingsNote("渐变和纯色是**画出来的**，不占空间、也不会被深色模式压糊。深浅色下都会跟着「壁纸压暗」那根滑块走。")
            }
        }
    }

    @ViewBuilder
    private func backdropSample(_ key: String) -> some View {
        switch key {
        case "gradient":
            LinearGradient(
                colors: [Color(hexString: app.settings.gradientFrom) ?? .gray,
                         Color(hexString: app.settings.gradientTo) ?? .gray],
                startPoint: WallpaperBackground.point(app.settings.gradientAngle),
                endPoint: WallpaperBackground.point(app.settings.gradientAngle + 180))
        case "solid":
            (Color(hexString: app.settings.solidHex) ?? Theme.pageBackground(scheme))
        default:
            if let name = app.settings.wallpaperName, let img = ImageStore.load(name) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Theme.pageBackground(scheme)
            }
        }
    }

    /// 一行颜色：**色号能打，也能直接在调色盘上调**。
    ///
    /// 她两样都要——打色号是知道自己要哪个色的时候最快，
    /// 调色盘是不知道要哪个、想试出来的时候唯一好使的东西。
    private func colorRow(_ title: String, hex: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer(minLength: 8)
            TextField("六位色号", text: hex)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, design: .monospaced))
                .textFieldStyle(.plain)
                .frame(maxWidth: 96)
            // 系统那个取色器就是调色盘：能拖色相、能吸屏幕上的颜色。
            // 自己画一个不会比它好用。
            ColorPicker("", selection: Binding(
                get: { Color(hexString: hex.wrappedValue) ?? .gray },
                set: { hex.wrappedValue = $0.hexString }
            ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: 字

    private var fontCard: some View {
        SettingsCard(title: "字") {
            HStack(spacing: 10) {
                ForEach(AppSettings.fontDesigns, id: \.0) { key, title in
                    Button {
                        app.settings.fontDesign = key
                    } label: {
                        VStack(spacing: 3) {
                            Text("栖")
                                .font(.system(size: 22))
                            Text(title)
                                .font(.system(size: 10))
                        }
                        .fontDesign(designOf(key))
                        .foregroundStyle(app.settings.fontDesign == key
                                         ? Theme.textMain(scheme)
                                         : Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if app.settings.fontDesign == key {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(app.settings.accentColor.opacity(0.22))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            SettingsNote("**整个 App 一起换**，不只是这一页。\n\niOS 只给了这四种能全局生效的字形——换一整套字库的话，工程里那几百处写死的系统字号不会跟着变，得一处处改，那是另一件事。")
        }
    }

    private func designOf(_ key: String) -> Font.Design {
        switch key {
        case "rounded":    return .rounded
        case "serif":      return .serif
        case "monospaced": return .monospaced
        default:           return .default
        }
    }

    // MARK: 玻璃

    private var glassCard: some View {
        SettingsCard(title: "玻璃") {
            // 三块样品直接摆出来，各自用各自那套玻璃画，
            // 底下垫着当前壁纸——光看名字选不出来，得看见才知道差在哪。
            HStack(spacing: 10) {
                ForEach(GlassStyle.allCases) { s in
                    Button {
                        app.settings.glassStyle = s
                    } label: {
                        ZStack {
                            if let name = app.settings.wallpaperName,
                               let img = ImageStore.load(name) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                LinearGradient(
                                    colors: [app.settings.accentColor.opacity(0.75),
                                             app.settings.accentColor.opacity(0.25)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
                            }

                            Text(s.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .glassBackground(radius: 16, strength: app.settings.glassOpacity,
                                                 style: s)
                                .padding(9)
                        }
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(app.settings.accentColor,
                                              lineWidth: app.settings.glassStyle == s ? 2 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            SettingsNote("磨砂和模糊糊得一样狠，**区别只有一样：磨砂表面有砂，模糊是平的**。凑近看磨砂那块能看出细颗粒。通透走的是系统的液态玻璃，几乎不挡东西，靠一道边光成形。\n\n整个 App 的卡片、气泡、导航条都跟着变。糊到什么程度由下面那根「模糊程度」定。")
        }
    }

    // MARK: 配色

    private var presetCard: some View {
        SettingsCard(title: "配色") {
            ForEach(Array(ThemePreset.allCases.enumerated()), id: \.element) { i, p in
                if i > 0 { SettingsDivider() }
                Button {
                    app.settings.preset = p
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: app.settings.preset == p
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(app.settings.accentColor)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text(p.note)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        if p == .home {
                            HStack(spacing: 3) {
                                ForEach([HomePalette.sage, HomePalette.amber,
                                         HomePalette.bodyPink, HomePalette.orange],
                                        id: \.self) { c in
                                    Circle().fill(c).frame(width: 9, height: 9)
                                }
                            }
                            .padding(.top, 3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // 「家」要真的是全局的，**底也得跟着换**。
            //
            // 配色那几档本来只管字色和面板色，底还是各归各的——
            // 所以选了「家」屏幕上却还是原来那张壁纸，看着就不是一套东西。
            // 这个按钮把底也换成那张暖纸，一按到位。
            //
            // 做成按钮而不是自动跟着切，是因为**不该替她把壁纸盖掉**：
            // 她可能就想要「家」的字配自己那张照片。
            if app.settings.preset == .home {
                SettingsDivider()
                Button {
                    app.settings.wallpaperMode = "solid"
                    app.settings.solidHex = scheme == .dark ? "1C1B19" : "FAF9F5"
                } label: {
                    SettingsRowLabel(title: "把底也换成「家」的暖纸",
                                     value: app.settings.wallpaperMode == "solid"
                                        ? "已经是了" : nil,
                                     tint: app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }

            SettingsNote("「家」那套里橘是限量的——一屏最多一处，留给发送键或者唯一的主按钮。列表、图标、标题一律不用橘，要强调靠字重和面板色。")
        }
    }

    // MARK: 字色

    private var textColorCard: some View {
        SettingsCard(title: "字色") {
            hexRow(title: "浅色下的字", text: $app.settings.textHex)
            SettingsDivider()
            hexRow(title: "深色下的字", text: $app.settings.textHexDark)
            SettingsDivider()
            Button {
                app.settings.textHex = ""
                app.settings.textHexDark = ""
            } label: {
                SettingsRowLabel(title: "恢复默认字色", tint: app.settings.accentColor)
            }
            .buttonStyle(.plain)

            SettingsNote("填六位色号，比如 4A3D2F。留空就跟着深浅色自动走，晚上那套通常要更淡一些。")
        }
    }

    private func hexRow(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer(minLength: 8)
            TextField("默认", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, design: .monospaced))
                .textFieldStyle(.plain)
                .frame(maxWidth: 110)
            // 字色这两行同理，一直摆一个方块：填对了显示颜色，
            // 没填对显示一个空框，比"什么都不显示"好判断
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hexString: text.wrappedValue) ?? Color.clear)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.textMuted(scheme).opacity(0.3), lineWidth: 1)
            }
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: 聊天

    private var chatCard: some View {
        SettingsCard(title: "聊天") {
            slider(title: "字号",
                   value: $app.settings.fontSize,
                   range: 13...22, step: 1,
                   readout: "\(Int(app.settings.fontSize))")
            SettingsDivider()
            slider(title: "模糊程度",
                   value: $app.settings.glassOpacity,
                   range: 0...1, step: nil,
                   readout: "\(Int(app.settings.glassOpacity * 100))%",
                   note: "往右越糊，背后的壁纸化成色块，玻璃看着越实；往左越清楚，能看出壁纸原来是什么。\n\n这根滑块以前调的是整层的透明度——往左只是让玻璃越来越淡、直到快没了，那不是玻璃变了，是玻璃不见了。",
                   onDraft: { blurDraft = $0 })
            SettingsDivider()
            slider(title: "深色下压暗",
                   value: $app.settings.glassDim,
                   range: 0...0.5, step: nil,
                   readout: "\(Int(app.settings.glassDim * 100))%",
                   note: "只在深色模式下生效。压的是一层黑，**不动底下那块玻璃**——磨砂还是磨砂、模糊还是模糊，只是整体沉下去。拉到 0 就是完全不压，深色下玻璃跟浅色一样亮。",
                   onDraft: { dimDraft = $0 })
            liveSample
            SettingsDivider()
            slider(title: "自己的气泡染色",
                   value: $app.settings.bubbleTint,
                   range: 0...1, step: nil,
                   readout: app.settings.bubbleTint < 0.01
                        ? "纯玻璃" : "\(Int(app.settings.bubbleTint * 100))%",
                   note: "默认纯玻璃，跟对方的一样透，靠左右位置区分。")
            SettingsDivider()
            slider(title: "气泡不透明度",
                   value: $app.settings.bubbleOpacity,
                   range: 0.3...1, step: nil,
                   readout: "\(Int(app.settings.bubbleOpacity * 100))%")
            SettingsDivider()
            Toggle(isOn: $app.settings.haptics) {
                Text("发送时震动")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
    }

    // MARK: 上面两根滑块的现场样品

    /// 两块样品，浅色一块深色一块，底下垫的是当前壁纸。
    ///
    /// 摆这个是因为上面两根滑块拉起来"没有即时反馈"：
    ///   · 「深色下压暗」按设计**只在深色模式下生效**——她要是正用着浅色，
    ///     拉到底屏幕上也一点变化都没有，看着就跟坏了一样。
    ///     右边这块钉死成深色，拉到哪儿它就沉到哪儿，当场看得见。
    ///   · 「模糊程度」两块一起变，往右糊、往左清楚。
    ///
    /// （另外那个真的 bug 在 Theme 里：压暗以前读的是一个 static，
    ///   不在 GlassSurface 的参数里，SwiftUI 一比较觉得没变就跳过重画。）
    private var liveSample: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                sampleTile("浅色", dark: false)
                sampleTile("深色", dark: true)
            }
            // 她说「底下那个深色浅色的预览其实我没懂是什么作用」——那就写清楚。
            Text("这两块是上面两根滑块的样品：左边钉死浅色、右边钉死深色。"
                 + "「压暗」只在深色下生效，所以拉它的时候只有右边那块会沉下去——"
                 + "你要是正用着浅色，屏幕上看不出变化，看这儿就行。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
    }

    private func sampleTile(_ label: String, dark: Bool) -> some View {
        ZStack {
            sampleGround
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(dark ? Color.white : Color.black.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                // 拖的时候用草稿值：全局那份要等松手才改，
                // 但这两块小的必须当场跟着动，不然拉了半天没反馈
                .glassBackground(radius: 14,
                                 strength: blurDraft ?? app.settings.glassOpacity,
                                 dim: dimDraft ?? app.settings.glassDim)
                .padding(9)
                // 钉死这块的深浅。GlassSurface 那层黑看的就是这个。
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        .frame(height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 样品底下垫的东西：有壁纸用壁纸，没有就用主题色拉个渐变。
    /// 纯色底下是糊不出东西的，所以一定要垫点有花纹的。
    @ViewBuilder
    private var sampleGround: some View {
        if let name = app.settings.wallpaperName, let img = ImageStore.load(name) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [app.settings.accentColor.opacity(0.75),
                         app.settings.accentColor.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private func slider(title: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        step: Double?,
                        readout: String,
                        note: String? = nil,
                        onDraft: ((Double?) -> Void)? = nil) -> some View {
        SettingsSlider(title: title, value: value, range: range, step: step,
                       readout: readout, note: note,
                       tint: app.settings.accentColor,
                       scheme: scheme, onDraft: onDraft)
    }

    // MARK: 预览

    private var previewCard: some View {
        SettingsCard(title: "预览") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer(minLength: 40)
                    Text("今天天气真好")
                        .font(.system(size: app.settings.fontSize))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background {
                            ZStack {
                                GlassSurface(radius: 18,
                                             strength: app.settings.glassOpacity
                                                * app.settings.bubbleOpacity,
                                             extra: 0.35)
                                if app.settings.bubbleTint > 0.01 {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(app.settings.accentColor
                                            .opacity(0.30 * app.settings.bubbleTint))
                                }
                            }
                        }
                }
                HStack {
                    Text("是啊，要不要出去走走？")
                        .font(.system(size: app.settings.fontSize))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .glassBackground(radius: 18,
                                         strength: app.settings.glassOpacity
                                            * app.settings.bubbleOpacity)
                    Spacer(minLength: 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    /// 她正在打的那串色号对应什么颜色。打不全或者打错就是 nil。
    private var previewColor: Color? {
        var hex = customHex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        return Color(hexString: hex)
    }

    private func applyCustom() {
        var hex = customHex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard Color(hexString: hex) != nil else { return }
        app.settings.accentHex = hex.uppercased()
    }
}
