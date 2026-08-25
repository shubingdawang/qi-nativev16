import SwiftUI

/// 自定义主题。
///
/// 跟设置主页同一套皮：壁纸垫底 + 玻璃卡片。
/// 以前这页是系统的 Form，白底加灰分组线——从设置页点进来那一下
/// 像换了个 App。
struct AppearanceView: View {

    /// 背景那层光的开关。跟 `AuroraLayer` 读的是同一个键
    @AppStorage("auroraOn") private var auroraOn = true

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
                    fontCard
                    auroraCard
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
                                        .font(.app(12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(name)
                                .font(.app(11))
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
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer(minLength: 8)
                TextField("六位色号", text: $customHex)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.app(14, design: .monospaced))
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
                            .font(.app(10, weight: .medium))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .frame(width: 26, height: 26)
                .animation(.easeOut(duration: 0.15), value: previewColor)
                // 主题色也给一个调色盘：不知道要哪个色的时候，
                // 打色号是没法「试」出来的。调完直接生效，不用再按「用」。
                ColorPicker("", selection: Binding(
                    get: { Color(hexString: customHex) ?? app.settings.accentColor },
                    set: { c in
                        customHex = c.hexString
                        app.settings.accentHex = c.hexString
                    }
                ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30)
                Button("用") { applyCustom() }
                    .font(.app(14, weight: .medium))
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

    // ⚠️ 这儿原来有一整张「底」卡（图片 / 渐变 / 纯色 三选一）。**她说删掉。**
    // 原话：「主题已经全局了，「底」那张卡可以删，渐变的取色挪进「配色 → 渐变」」。
    //
    // 她是对的：主题接管底之后，同一件事有了两个开关——
    // 「配色」里选渐变是一条路，「底」里选渐变又是一条路，两条还能互相打架。
    // 现在只剩一条：**底跟着「配色」走**，
    // 渐变的两头颜色和方向就挂在「渐变」那一档下面，纯色挂在「原来的」下面。

    /// 一行颜色：**色号能打，也能直接在调色盘上调**。
    ///
    /// 她两样都要——打色号是知道自己要哪个色的时候最快，
    /// 调色盘是不知道要哪个、想试出来的时候唯一好使的东西。
    private func colorRow(_ title: String, hex: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.app(15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer(minLength: 8)
            TextField("六位色号", text: hex)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .font(.app(14, design: .monospaced))
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
        SettingsCard(title: "字体") {
            HStack(spacing: 10) {
                ForEach(AppSettings.fontDesigns, id: \.0) { key, title in
                    Button {
                        app.settings.fontDesign = key
                    } label: {
                        VStack(spacing: 3) {
                            Text("栖")
                                .font(.app(22))
                            Text(title)
                                .font(.app(10))
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

            SettingsNote("字形设置作用于全 App。\n\n可选项限于 iOS 提供的四种全局字形。")
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

    private var auroraCard: some View {
        SettingsCard(title: "光晕") {
            Toggle(isOn: $auroraOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("背景里的光")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("三团很淡的光，跟着主题色，四十秒漂一个来回")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsNote("""
            在壁纸之上、内容之下叠一层缓慢浮动的光晕，共三团，透明度极低。

            作用范围为全 App 背景，不影响卡片、文字与图标的对比度。

            实现方式为径向渐变，非高斯模糊，因此不产生逐帧重算，耗电可忽略。

            关闭后该层完全不绘制。
            """, title: "说明")
        }
    }

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
                               let img = ImageStore.cached(name) {
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
                                .font(.app(15, weight: .semibold))
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

            SettingsNote("三档的区别在表面质感：**磨砂**表面带细颗粒，**模糊**表面平整，**通透**使用系统液态玻璃，遮挡最少、以边缘光成形。\n\n设置作用于全 App 的卡片、气泡与导航条。模糊强度由下方「模糊程度」控制。")
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
                                .font(.app(15))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text(p.note)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        // 每一档自己报几个色（`ThemePreset.swatches`），
                        // 加一档主题不用回来改这儿
                        if !p.swatches.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(p.swatches, id: \.self) { c in
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

            // 以前这儿有个「把底也换成家的暖纸」的按钮——她没找到，
            // 所以看到的一直是「claude.ai 的字 + 自己那张照片」，
            // 于是两次说「家的全局主题还是不对」。
            //
            // 现在不用按了：**「家」和「渐变」直接接管底**（见 ThemePreset.ownsBackground）。
            // 想用自己那张照片就选「原来的」。
            // 渐变那一档的取色，直接挂在这一档下面——
            // 她要的就是这个：调什么和选什么在同一个地方。
            if app.settings.preset == .gradient {
                SettingsDivider()
                colorRow("从", hex: $app.settings.gradientFrom)
                colorRow("到", hex: $app.settings.gradientTo)
                slider(title: "方向",
                       value: $app.settings.gradientAngle,
                       range: 0...360, step: 5,
                       readout: "\(Int(app.settings.gradientAngle))°")
            }

            // 「原来的」那一档才轮得到自己铺底：一张图，或者一块纯色。
            if app.settings.preset == .original {
                SettingsDivider()
                HStack(spacing: 10) {
                    Text("底")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer(minLength: 8)
                    Picker("", selection: $app.settings.wallpaperMode) {
                        Text("图片").tag("image")
                        Text("纯色").tag("solid")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                if app.settings.wallpaperMode == "solid" {
                    colorRow("颜色", hex: $app.settings.solidHex)
                } else {
                    SettingsNote("壁纸图片在「设置 → 外观」中更换。选择纯色时背景为程序绘制，不占用存储空间。")
                }
            }

            if app.settings.preset.ownsBackground {
                SettingsDivider()
                // 每一档自己带着这句话（`ThemePreset.detail`）——
                // 摆在这儿写 if-else 的话，加一档就得回来补一次
                SettingsNote(app.settings.preset.detail,
                             title: "此主题的改动范围")
            }

            SettingsNote("「家」主题限制强调色的使用：每屏最多一处，仅用于发送键或主按钮。列表、图标与标题不使用强调色，强调通过字重和面板色实现。")
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

            SettingsNote("填写六位十六进制色号（如 4A3D2F）。留空则随深浅色自动取值。")
        }
    }

    private func hexRow(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.app(15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer(minLength: 8)
            TextField("默认", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .font(.app(14, design: .monospaced))
                .textFieldStyle(.plain)
                .frame(maxWidth: 110)
            // 填对了显示颜色，没填对显示一个空框，比"什么都不显示"好判断
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hexString: text.wrappedValue) ?? Color.clear)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.textMuted(scheme).opacity(0.3), lineWidth: 1)
            }
            .frame(width: 22, height: 22)
            // 她说「所有选择颜色的地方都加上调色盘」——字色这两行以前只能打色号。
            // 留空＝跟着深浅色自动走，所以取色器只在她真的调了之后才写值。
            ColorPicker("", selection: Binding(
                get: { Color(hexString: text.wrappedValue) ?? Theme.textMain(scheme) },
                set: { text.wrappedValue = $0.hexString }
            ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: 聊天

    private var chatCard: some View {
        SettingsCard(title: "聊天") {
            // 字号那根**边拖边生效**：她要的就是拖的时候整页的字当场跟着变。
            // 现在全 App 的字都乘 Theme.fontScale（Font.app），不再只有聊天气泡。
            slider(title: "字号",
                   value: $app.settings.fontSize,
                   range: 13...22, step: 1,
                   readout: "\(Int(app.settings.fontSize))",
                   note: "**整个 App 一起变**：设置页、侧边栏、札记、游戏里的字都跟着走，不只是聊天气泡。",
                   live: true)
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
                    .font(.app(15))
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
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
    }

    private func sampleTile(_ label: String, dark: Bool) -> some View {
        ZStack {
            sampleGround
            Text(label)
                .font(.app(12, weight: .medium))
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
        if let name = app.settings.wallpaperName, let img = ImageStore.cached(name) {
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
                        onDraft: ((Double?) -> Void)? = nil,
                        live: Bool = false) -> some View {
        SettingsSlider(title: title, value: value, range: range, step: step,
                       readout: readout, note: note,
                       tint: app.settings.accentColor,
                       scheme: scheme, onDraft: onDraft, live: live)
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
                                // **也吃草稿值**。以前这块只读全局，
                                // 所以拖滑块的时候「预览」是最后一个变的——
                                // 她说的「设置的玻璃显示效果比其他地方慢很多」。
                                GlassSurface(radius: 18,
                                             strength: (blurDraft ?? app.settings.glassOpacity)
                                                * app.settings.bubbleOpacity,
                                             extra: 0.35,
                                             dim: dimDraft ?? app.settings.glassDim)
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
                                         strength: (blurDraft ?? app.settings.glassOpacity)
                                            * app.settings.bubbleOpacity,
                                         dim: dimDraft ?? app.settings.glassDim)
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
