import SwiftUI
import PhotosUI

struct AppearanceView: View {

    @EnvironmentObject var app: AppState
    @State private var wallpaperItem: PhotosPickerItem?
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

    var body: some View {
        Form {
            Section("主题色") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                    ForEach(Self.accentPresets, id: \.1) { name, hex in
                        Button {
                            app.settings.accentHex = hex
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hexString: hex) ?? .gray)
                                        .frame(width: 34, height: 34)
                                    if app.settings.accentHex.uppercased() == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                Text(name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)

                HStack {
                    Text("自定义")
                    Spacer()
                    TextField("六位色号", text: $customHex)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { applyCustom() }
                    Button("用") { applyCustom() }
                        .buttonStyle(.borderless)
                        .disabled(Color(hexString: customHex) == nil)
                }
            }

            Section {
                if let name = app.settings.wallpaperName, let image = ImageStore.load(name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                PhotosPicker(selection: $wallpaperItem, matching: .images) {
                    Label(wallpaperButtonTitle, systemImage: "photo")
                }

                if !app.settings.wallpaperHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("换过的")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(app.settings.wallpaperHistory, id: \.self) { name in
                                    if let img = ImageStore.load(name) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 54, height: 78)
                                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8)
                                            )
                                            .onTapGesture {
                                                let current = app.settings.wallpaperName
                                                app.settings.wallpaperName = name
                                                app.settings.wallpaperHistory.removeAll { $0 == name }
                                                if let current,
                                                   !app.settings.wallpaperHistory.contains(current) {
                                                    app.settings.wallpaperHistory.insert(current, at: 0)
                                                }
                                            }
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
                        }
                    }
                }

                if app.settings.wallpaperName != nil {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("压暗")
                            Spacer()
                            Text("\(Int(app.settings.wallpaperDim * 100))%")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Slider(value: $app.settings.wallpaperDim, in: 0...0.6)
                    }
                    Button {
                        if let name = app.settings.wallpaperName,
                           !app.settings.wallpaperHistory.contains(name) {
                            app.settings.wallpaperHistory.insert(name, at: 0)
                        }
                        app.settings.wallpaperName = nil
                        app.settings.wallpaperDim = 0
                    } label: {
                        Label("先不用壁纸", systemImage: "photo.badge.arrow.down")
                    }
                }
            } header: {
                Text("壁纸")
            } footer: {
                Text("壁纸太花的话，把气泡透明度调低一点会更好读。")
            }

            Section {
                ForEach(ThemePreset.allCases) { p in
                    Button {
                        app.settings.preset = p
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: app.settings.preset == p
                                  ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(app.settings.accentColor)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).foregroundStyle(.primary)
                                Text(p.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
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
                    }
                }
            } header: {
                Text("配色")
            } footer: {
                Text("「家」那套里橘是限量的——一屏最多一处，留给发送键或者唯一的主按钮。列表、图标、标题一律不用橘，要强调靠字重和面板色。这条守住了才不花。")
            }

            Section {
                HStack {
                    Text("浅色下的字")
                    Spacer()
                    TextField("默认", text: $app.settings.textHex)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                        .font(.system(.body, design: .monospaced))
                    if let c = Color(hexString: app.settings.textHex) {
                        Circle().fill(c).frame(width: 18, height: 18)
                    }
                }
                HStack {
                    Text("深色下的字")
                    Spacer()
                    TextField("默认", text: $app.settings.textHexDark)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                        .font(.system(.body, design: .monospaced))
                    if let c = Color(hexString: app.settings.textHexDark) {
                        Circle().fill(c).frame(width: 18, height: 18)
                    }
                }
                Button("恢复默认字色") {
                    app.settings.textHex = ""
                    app.settings.textHexDark = ""
                }
                .font(.footnote)
            } header: {
                Text("字色")
            } footer: {
                Text("填六位色号，比如 4A3D2F。留空就跟着深浅色自动走。深浅色可以分别设，晚上那套通常要更淡一些。")
            }

            Section {
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
                            .frame(height: 92)
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
                .padding(.vertical, 4)

                Text(app.settings.glassStyle.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("玻璃")
            } footer: {
                Text("换的是做法不是浓度：磨砂糊得厉害还带颗粒，通透几乎不糊只留一道边光，模糊是均匀一片、没有边。整个 App 的卡片、气泡、导航条都跟着变。")
            }

            Section("聊天") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("字号")
                        Spacer()
                        Text("\(Int(app.settings.fontSize))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Slider(value: $app.settings.fontSize, in: 13...22, step: 1)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("玻璃浓度")
                        Spacer()
                        Text("\(Int(app.settings.glassOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Slider(value: $app.settings.glassOpacity, in: 0...1)
                    Text("调低更透，壁纸看得更清楚；调高更实，字更好读。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("自己的气泡染色")
                        Spacer()
                        Text(app.settings.bubbleTint < 0.01 ? "纯玻璃" : "\(Int(app.settings.bubbleTint * 100))%")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Slider(value: $app.settings.bubbleTint, in: 0...1)
                    Text("默认纯玻璃，跟对方的气泡一样透，靠左右位置区分。想让自己的带点主题色就往右拉。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("气泡不透明度")
                        Spacer()
                        Text("\(Int(app.settings.bubbleOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Slider(value: $app.settings.bubbleOpacity, in: 0.3...1)
                }
                Toggle("发送时震动", isOn: $app.settings.haptics)
            }

            Section("预览") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer()
                        Text("今天天气真好")
                            .font(.system(size: app.settings.fontSize))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(app.settings.accentColor.opacity(app.settings.bubbleOpacity))
                            )
                    }
                    HStack {
                        Text("是啊，要不要出去走走？")
                            .font(.system(size: app.settings.fontSize))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Theme.softFill.opacity(app.settings.bubbleOpacity))
                            )
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .transparentList()
        .listRowBackground(GlassRowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: Layout.tabBarExpanded)
        }
        .navigationTitle("主题与壁纸")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { customHex = app.settings.accentHex }
        .onChange(of: wallpaperItem) { _, item in
            loadWallpaper(item)
        }
    }

    private var wallpaperButtonTitle: String {
        app.settings.wallpaperName == nil ? "选一张壁纸" : "换一张"
    }

    private func applyCustom() {
        var hex = customHex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard Color(hexString: hex) != nil else { return }
        app.settings.accentHex = hex.uppercased()
    }

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
}
