import SwiftUI

// MARK: - MCP 列表

struct MCPListView: View {

    @EnvironmentObject var app: AppState
    @State private var editing: MCPServer?
    @State private var creatingNew = false

    var body: some View {
        List {
            if app.mcpServers.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有连 MCP")
                            .font(.headline)
                        Text("MCP 用于向模型提供可调用的工具，如查询记忆、写日记、记录经期。点击右上角的 + 填写服务地址。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }

            ForEach(app.mcpServers) { server in
                Button {
                    editing = server
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(server.enabled ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(server.name.isEmpty ? "未命名" : server.name)
                                .foregroundStyle(.primary)
                            Text(server.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let err = server.lastError {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text("\(server.enabledTools.count)/\(server.tools.count) 个工具")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        app.mcpServers.removeAll { $0.id == server.id }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .transparentList()
        .listRowBackground(GlassRowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: Layout.tabBarExpanded)
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
