import SwiftUI

/// 输入框左边那个扳手，点开能快速开关这次对话要带哪些工具。
/// 跟「设置 → MCP」里改的是同一份数据，在这里改完立刻生效。
///
/// 排版是**折叠**的：一组一行，行上有这一组的总开关，
/// 一眼能看完手上有几摊东西；想动某一件再点开那一组。
/// 以前是把几十个工具全平铺出来，翻半天找不到要关的那个。
struct ToolToggleView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    /// 现在哪几组是展开的
    @State private var expanded: Set<String> = []

    var body: some View {
        // 这儿**不用 NavigationStack + .searchable**。
        //
        // iOS 26 把 searchable 的输入框挪到了屏幕底部，
        // 跟这张表自己的滚动内容叠在一起；再加上导航栏是透明的，
        // 标题和「完成」底下直接透出正在滚的文字——
        // 看着就是"所有字都掉下来了"。
        // 自己画一个顶栏和搜索框，这一整类问题就都没有了。
        ZStack {
            WallpaperBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {

                        if app.mcpServers.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("还没连 MCP")
                                    .font(.app(14, weight: .semibold))
                                    .foregroundStyle(Theme.textMain(scheme))
                                Text("连接后可使用查询记忆、写日记、记录经期等工具。在「设置 → MCP」中添加。")
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // 这块是空态提示，就几行高，玻璃没问题
                            .glassBackground(radius: 18, strength: app.settings.glassOpacity)
                        }

                        group("App 自带") {
                            nativeGroup
                        }

                        // 记忆库那批。它们跟 MCP 没有任何关系——小屋关着照样能用，
                        // 但以前这个面板只列 NativeTools，这三十个在这儿是**看不见**的，
                        // 于是看着像"关了 MCP 就没工具了"。现在单独列一组。
                        if app.settings.localMemory || app.settings.localPulse {
                            group("记忆库（本机）") {
                                memoryGroup
                            }
                        }

                        if !app.mcpServers.isEmpty {
                            group("MCP") {
                                VStack(spacing: 10) {
                                    ForEach($app.mcpServers) { $server in
                                        serverGroup($server)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    // MARK: 顶栏

    /// 标题 + 完成 + 搜索框，全是自己画的。
    /// 它有自己的玻璃底，滚动的内容从它下面过，不会透出来。
    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("工具")
                    .heading(17)
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Button("完成") { dismiss() }
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(app.settings.accentColor)
                    .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
                TextField("搜索工具", text: $search)
                    .font(.app(14))
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.app(13))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.softFillDeep))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        // 这里**不铺玻璃**。
        //
        // 铺了就是在壁纸上盖一块比周围亮一档的板，
        // 板的下沿跟壁纸之间会切出一道笔直的横线——就是那道分层。
        // 顶栏本来也不需要自己的底：整张表已经坐在壁纸上了，
        // 内容从它下面滚过去，靠一道极淡的分隔线交代边界就够。
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.textMuted(scheme).opacity(0.14))
                .frame(height: 0.6)
        }
    }

    // MARK: 一个大类

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.leading, 6)
            content()
        }
    }

    // MARK: 自带工具

    private var nativeGroup: some View {
        let list = nativeTools
        let key = "__native"
        let isOpen = expanded.contains(key)
        return VStack(spacing: 0) {
            groupHeader(
                title: "App 自带工具",
                count: list.count,
                isOpen: isOpen,
                toggle: Binding(
                    get: { app.settings.nativeToolsEnabled },
                    set: { app.settings.nativeToolsEnabled = $0 }
                ),
                onTap: { flip(key) })

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(list, id: \.name) { tool in
                        SettingsDivider()
                        toolRow(
                            name: tool.name,
                            desc: tool.desc,
                            on: Binding(
                                get: { !app.settings.disabledNativeTools.contains(tool.name) },
                                set: { on in
                                    if on {
                                        app.settings.disabledNativeTools.removeAll { $0 == tool.name }
                                    } else if !app.settings.disabledNativeTools.contains(tool.name) {
                                        app.settings.disabledNativeTools.append(tool.name)
                                    }
                                }),
                            enabled: app.settings.nativeToolsEnabled)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background { groupBack(isOpen) }
    }

    // MARK: 记忆库那批

    private var memoryGroup: some View {
        let list = memoryTools
        let key = "__memory"
        let isOpen = expanded.contains(key)
        return VStack(spacing: 0) {
            groupHeader(
                title: "记忆库工具",
                count: list.count,
                isOpen: isOpen,
                toggle: Binding(
                    get: { app.settings.localMemory },
                    set: { app.settings.localMemory = $0 }),
                onTap: { flip(key) })

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(list, id: \.name) { tool in
                        SettingsDivider()
                        toolRow(
                            name: tool.name,
                            desc: tool.desc,
                            on: Binding(
                                get: { !app.settings.disabledNativeTools.contains(tool.name) },
                                set: { on in
                                    if on {
                                        app.settings.disabledNativeTools.removeAll { $0 == tool.name }
                                    } else if !app.settings.disabledNativeTools.contains(tool.name) {
                                        app.settings.disabledNativeTools.append(tool.name)
                                    }
                                }),
                            // 记忆库这组跟自带工具共用总开关那一套过滤，
                            // 所以两个总开关任意一个关掉，这里都动不了
                            enabled: app.settings.nativeToolsEnabled && app.settings.localMemory)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background { groupBack(isOpen) }
    }

    // MARK: 一台 MCP

    private func serverGroup(_ server: Binding<MCPServer>) -> some View {
        let key = server.wrappedValue.id.uuidString
        let isOpen = expanded.contains(key)
        let indices = visibleIndices(of: server.wrappedValue)
        return VStack(spacing: 0) {
            groupHeader(
                title: server.wrappedValue.name.isEmpty ? "未命名" : server.wrappedValue.name,
                count: server.wrappedValue.tools.count,
                isOpen: isOpen,
                toggle: server.enabled,
                onTap: { flip(key) })

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(indices, id: \.self) { i in
                        SettingsDivider()
                        toolRow(
                            name: server.wrappedValue.tools[i].name,
                            desc: server.wrappedValue.tools[i].description,
                            on: server.tools[i].enabled,
                            enabled: server.wrappedValue.enabled)
                    }
                    if indices.isEmpty {
                        SettingsDivider()
                        Text(search.isEmpty ? "这台还没抓到工具清单" : "没有匹配的工具")
                            .font(.app(12))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background { groupBack(isOpen) }
    }

    // MARK: 零件

    /// 折起来时看到的那一行：三角 + 名字（几个） + 总开关
    private func groupHeader(title: String,
                             count: Int,
                             isOpen: Bool,
                             toggle: Binding<Bool>,
                             onTap: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.app(11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text("\(title)（\(count)）")
                        .font(.app(15, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: toggle)
                .labelsHidden()
                .tint(app.settings.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// 展开之后每一件工具各自那一行
    /// 一组工具的底。
    ///
    /// ⚠️⚠️ **展开之后不能再用玻璃。**
    ///
    /// 她报的：「工具那个静态的时候不显示气泡，动起来会显示，
    /// 但是到中间部分动起来也不显示了，头尾的时候动起来会显示，
    /// 而且只有 app 自带工具会吞气泡。」
    ///
    /// 那几句话精确地描述了**一块太大的 `Material` 被渲染器放弃采样**：
    /// 自带工具有 68 条，展开之后这块玻璃几千点高——
    /// 系统不会为这么大一片一直做实时模糊，于是它一会儿在一会儿不在，
    /// 滚到头尾（面积被裁小）反而又出来了。
    /// 别的组只有十几条，没到那个尺寸，所以「只有自带工具」会这样。
    ///
    /// `Theme.swift` 里 `GlassSurface` 那段已经记着一条相关的：
    /// **`Material` 上面不能套 `.shadow` / `.blur` / `.drawingGroup`**。
    /// 这一条是它的近亲：**也不能铺得太大**。
    ///
    /// 所以收起来的时候照旧是玻璃（就一行，很小），
    /// 展开之后换成一层实心的浅底——看着差一点，但它一定在。
    @ViewBuilder
    private func groupBack(_ isOpen: Bool) -> some View {
        if isOpen {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.softFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.softStroke, lineWidth: 0.8)
                }
        } else {
            GlassSurface(radius: 18, strength: app.settings.glassOpacity)
        }
    }

    private func toolRow(name: String, desc: String,
                         on: Binding<Bool>, enabled: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.app(13, design: .monospaced))
                    .foregroundStyle(Theme.textMain(scheme))
                if !desc.isEmpty {
                    Text(desc)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: on)
                .labelsHidden()
                .tint(app.settings.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // 总开关关着的时候，底下这些还看得见，但动不了也不生效
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

    private func flip(_ key: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
        }
    }

    /// 从工具定义里把名字和说明抠出来，光展示用
    /// 一件工具在这一页上显示的说明。
    ///
    /// ⚠️ **优先取 `ToolBlurb` 那份，不是模型描述。**
    ///
    /// 这一页原来直接显示 `fn["description"]` 的第一句——而那些是
    /// **写给模型的提示词**，按「触发 → 动机 → 行动」写的，
    /// 里面全是「她说『你看我批注的这句』」这种话。
    /// 于是这一页等于把他的提示词摊给她看。
    ///
    /// 那份描述一个字都不能改（改了就是改他的行为），
    /// 所以只能是两份：模型读那份，她看 `ToolBlurb` 这份。
    ///
    /// 表里没有的退回原来那条路——她自己连的 MCP 服务器上的工具
    /// 是别人写的说明，我们管不着，有总比没有强。
    private func blurb(_ short: String, modelDesc: String) -> String {
        if let s = ToolBlurb.of(short) { return s }
        return modelDesc.split(separator: "。").first.map(String.init) ?? modelDesc
    }

    private var nativeTools: [(name: String, desc: String)] {
        NativeTools.definitions(hasGroup: true, hasVoice: true).compactMap { item in
            guard let fn = item["function"] as? [String: Any],
                  let raw = fn["name"] as? String else { return nil }
            let short = NativeTools.shortName(raw)
            return (short, blurb(short, modelDesc: fn["description"] as? String ?? ""))
        }
        .filter { !search.isEmpty ? $0.name.localizedCaseInsensitiveContains(search) : true }
    }

    private var memoryTools: [(name: String, desc: String)] {
        MemoryTools.definitions(memory: app.settings.localMemory,
                                pulse: app.settings.localPulse).compactMap { item in
            guard let fn = item["function"] as? [String: Any],
                  let raw = fn["name"] as? String else { return nil }
            let short = NativeTools.shortName(raw)
            return (short, blurb(short, modelDesc: fn["description"] as? String ?? ""))
        }
        .filter { !search.isEmpty ? $0.name.localizedCaseInsensitiveContains(search) : true }
    }

    private func visibleIndices(of server: MCPServer) -> [Int] {
        server.tools.indices.filter { i in
            search.isEmpty
            || server.tools[i].name.localizedCaseInsensitiveContains(search)
            || server.tools[i].description.localizedCaseInsensitiveContains(search)
        }
    }
}
