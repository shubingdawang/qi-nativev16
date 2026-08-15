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
                    .frame(maxWidth: 110)
                    .onSubmit { applyCustom() }
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

            SettingsNote("换的是做法不是浓度：磨砂糊得最狠、表面带一层几乎看不见的颗粒；通透几乎不挡东西，只留一道边光；模糊是均匀一片、没有边。整个 App 的卡片、气泡、导航条都跟着变。")
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
            if let c = Color(hexString: text.wrappedValue) {
                Circle().fill(c).frame(width: 18, height: 18)
            }
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
            slider(title: "玻璃浓度",
                   value: $app.settings.glassOpacity,
                   range: 0...1, step: nil,
                   readout: "\(Int(app.settings.glassOpacity * 100))%",
                   note: "调低更透，壁纸看得更清楚；调高更实，字更好读。")
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

    @ViewBuilder
    private func slider(title: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        step: Double?,
                        readout: String,
                        note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Text(readout)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            if let step {
                Slider(value: value, in: range, step: step)
                    .tint(app.settings.accentColor)
            } else {
                Slider(value: value, in: range)
                    .tint(app.settings.accentColor)
            }
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
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

    private func applyCustom() {
        var hex = customHex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard Color(hexString: hex) != nil else { return }
        app.settings.accentHex = hex.uppercased()
    }
}
