import SwiftUI

// MARK: - MCP 列表

struct MCPListView: View {

    @EnvironmentObject var app: AppState
    @State private var editing: MCPServer?
    @State private var creatingNew = false

    // ⚠️⚠️ **这一页原来是 `List`，换成了跟设置页一样的卡片。**
    //
    // 她报的：「我跟你说的设置白底你没弄成玻璃。」
    //
    // 玻璃**其实一直挂着**（`.listRowBackground(GlassRowBackground())`），
    // 可它盖不住：`List` 默认是 `insetGrouped`，那一层白圆角是
    // **分组容器自己画的**，行背景压在它上面，白底照样透出来。
    // 自动唤醒那一页当初也是这个病，换成 `SettingsCard` 之后就对了。
    //
    // 记一句：**`listRowBackground` 管的是「行」，管不了分组的底。**
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WallpaperBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    if app.mcpServers.isEmpty {
                        SettingsCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("还没有连 MCP")
                                    .font(.app(15, weight: .semibold))
                                    .foregroundStyle(Theme.textMain(scheme))
                                Text("MCP 用于向模型提供可调用的工具，如查询记忆、写日记、记录经期。点击右上角的 + 填写服务地址。")
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    } else {
                        SettingsCard {
                            ForEach(Array(app.mcpServers.enumerated()), id: \.element.id) { i, server in
                                if i > 0 { SettingsDivider() }
                                serverRow(server)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("MCP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creatingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { server in
            MCPFormView(server: server, isNew: false)
        }
        .sheet(isPresented: $creatingNew) {
            MCPFormView(server: MCPServer(), isNew: true)
        }
    }
    private func serverRow(_ server: MCPServer) -> some View {
        Button {
            editing = server
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(server.enabled ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name.isEmpty ? "未命名" : server.name)
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(server.url)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                    if let err = server.lastError {
                        Text(err)
                            .font(.app(10))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text("\(server.enabledTools.count)/\(server.tools.count) 个工具")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Image(systemName: "chevron.right")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            // ⚠️ 整行都要能点。`buttonStyle(.plain)` 认的是真画出来的像素，
            // 中间那一大片空白本来是点不着的（这病栽过六次）。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 换成卡片之后没有 `swipeActions` 了，删掉走长按
        .contextMenu {
            Button(role: .destructive) {
                app.mcpServers.removeAll { $0.id == server.id }
            } label: {
                Label("删掉", systemImage: Icon.trash)
            }
        }
    }
}

// MARK: - 新建 / 编辑

struct MCPFormView: View {

    @State var server: MCPServer
    let isNew: Bool

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var testing = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名字（比如：小屋）", text: $server.name)
                    TextField("地址 https://…/mcp", text: $server.url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Toggle("启用", isOn: $server.enabled)
                    Stepper("超时 \(server.timeoutSec) 秒", value: $server.timeoutSec, in: 5...120, step: 5)
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Label(server.tools.isEmpty ? "连接并获取工具" : "重新获取工具", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || server.url.isEmpty)

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(messageIsError ? .red : .green)
                    }
                } footer: {
                    Text("要先连一次把工具清单抓下来，模型才知道自己能干什么。地址改了记得重新抓。")
                }

                if !server.tools.isEmpty {
                    Section {
                        TextField("筛选工具", text: $filter)
                            .textInputAutocapitalization(.never)
                        HStack {
                            Button("全部打开") { setAll(true) }
                            Spacer()
                            Button("全部关掉") { setAll(false) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    } header: {
                        Text("已打开 \(server.enabledTools.count) / \(server.tools.count)")
                    } footer: {
                        Text("工具开得越多，每次对话要带的说明就越长，也就越费 token。用不上的可以关掉。")
                    }

                    Section {
                        ForEach(visibleIndices, id: \.self) { i in
                            Toggle(isOn: $server.tools[i].enabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.tools[i].name)
                                        .font(.app(14, weight: .medium, design: .monospaced))
                                    if !server.tools[i].description.isEmpty {
                                        Text(server.tools[i].description)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "新增 MCP" : "编辑 MCP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var visibleIndices: [Int] {
        server.tools.indices.filter { i in
            filter.isEmpty
            || server.tools[i].name.localizedCaseInsensitiveContains(filter)
            || server.tools[i].description.localizedCaseInsensitiveContains(filter)
        }
    }

    private func setAll(_ on: Bool) {
        for i in server.tools.indices { server.tools[i].enabled = on }
    }

    private func save() {
        if let i = app.mcpServers.firstIndex(where: { $0.id == server.id }) {
            app.mcpServers[i] = server
        } else {
            app.mcpServers.append(server)
        }
        dismiss()
    }

    private func connect() {
        testing = true
        message = nil
        let snapshot = server
        Task {
            do {
                let tools = try await MCPClient(server: snapshot).listTools()
                await MainActor.run {
                    let disabled = Set(server.tools.filter { !$0.enabled }.map { $0.name })
                    server.tools = tools.map { tool in
                        var t = tool
                        t.enabled = !disabled.contains(tool.name)
                        return t
                    }
                    server.lastError = nil
                    message = "连上了，拿到 \(tools.count) 个工具。别忘了点右上角保存。"
                    messageIsError = false
                    testing = false
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    messageIsError = true
                    testing = false
                }
            }
        }
    }
}
