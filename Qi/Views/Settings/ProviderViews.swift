import SwiftUI

// MARK: - 供应商列表

struct ProviderListView: View {

    @EnvironmentObject var app: AppState
    @State private var editing: Provider?
    @State private var creatingNew = false

    var body: some View {
        List {
            if app.providers.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有供应商")
                            .font(.headline)
                        Text("点右上角的 + 加一个。需要填接口地址和密钥，跟你在网页版里填的一样。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }

            ForEach(app.providers) { provider in
                Button {
                    editing = provider
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider.name.isEmpty ? "未命名" : provider.name)
                                .foregroundStyle(.primary)
                            Text(provider.baseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(provider.enabledModels.count) 个模型")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        app.providers.removeAll { $0.id == provider.id }
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
        .navigationTitle("供应商")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creatingNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { provider in
            ProviderFormView(provider: provider, isNew: false)
        }
        .sheet(isPresented: $creatingNew) {
            ProviderFormView(provider: Provider(), isNew: true)
        }
    }
}

// MARK: - 新建 / 编辑供应商

struct ProviderFormView: View {

    @State var provider: Provider
    let isNew: Bool

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var loadingModels = false
    @State private var loadError: String?
    @State private var modelFilter = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名字（自己看的，比如 OpenAI）", text: $provider.name)
                    TextField("接口地址", text: $provider.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API Key", text: $provider.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("启用", isOn: $provider.enabled)
                }

                Section {
                    TextField("/chat/completions", text: $provider.apiPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("接口路径")
                } footer: {
                    Text("一般不用改。地址填到 /v1 为止，路径保持 /chat/completions 就对了。")
                }

                Section {
                    Button {
                        loadModels()
                    } label: {
                        HStack {
                            Label("从服务器拉取模型列表", systemImage: "arrow.down.circle")
                            Spacer()
                            if loadingModels { ProgressView() }
                        }
                    }
                    .disabled(loadingModels || provider.baseURL.isEmpty)

                    Button {
                        provider.models.append(AIModel(id: ""))
                    } label: {
                        Label("手动加一个模型", systemImage: "plus")
                    }

                    if let loadError {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("模型")
                } footer: {
                    Text("拉不到列表也没关系，手动填模型名一样能用。")
                }

                if !provider.models.isEmpty {
                    Section {
                        TextField("筛选模型", text: $modelFilter)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        HStack {
                            Button("全部打开") { setAll(true) }
                            Spacer()
                            Button("全部关掉") { setAll(false) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    } header: {
                        Text("已打开 \(provider.enabledModels.count) / \(provider.models.count)")
                    } footer: {
                        Text("在这里打开的模型，才会出现在聊天页的「选择模型」里。左滑可以删掉不需要的。")
                    }

                    ForEach(brandGroups, id: \.brand) { group in
                        Section(group.brand) {
                            ForEach(group.indices, id: \.self) { i in
                                Toggle(isOn: $provider.models[i].enabled) {
                                    TextField("模型名", text: $provider.models[i].id)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .font(.app(14, design: .monospaced))
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        let target = provider.models[i].id
                                        provider.models.removeAll { $0.id == target }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .navigationTitle(isNew ? "新增供应商" : "编辑供应商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// 按 AI 牌子把模型分组，返回每组在 provider.models 里的下标
    private var brandGroups: [(brand: String, indices: [Int])] {
        var buckets: [String: [Int]] = [:]
        for (i, m) in provider.models.enumerated() {
            if !modelFilter.isEmpty,
               !m.id.localizedCaseInsensitiveContains(modelFilter) { continue }
            buckets[ModelBrand.name(for: m.id), default: []].append(i)
        }
        return buckets
            .map { (brand: $0.key, indices: $0.value) }
            .sorted { ModelBrand.sortIndex(of: $0.brand) < ModelBrand.sortIndex(of: $1.brand) }
    }

    private func setAll(_ on: Bool) {
        for i in provider.models.indices { provider.models[i].enabled = on }
    }

    private func save() {
        var p = provider
        p.models = p.models.filter { !$0.id.trimmingCharacters(in: .whitespaces).isEmpty }
        for i in p.models.indices where p.models[i].displayName.isEmpty {
            p.models[i].displayName = p.models[i].id
        }
        if let index = app.providers.firstIndex(where: { $0.id == p.id }) {
            app.providers[index] = p
        } else {
            app.providers.append(p)
        }
        dismiss()
    }

    private func loadModels() {
        guard let endpoint = provider.modelsEndpoint else {
            loadError = "地址填得不对。"
            return
        }
        loadingModels = true
        loadError = nil
        Task {
            do {
                let remote = try await ChatAPI.fetchModels(endpoint: endpoint, apiKey: provider.apiKey)
                await MainActor.run {
                    let existing = Set(provider.models.map { $0.id })
                    for m in remote where !existing.contains(m.id) {
                        // 拉回来的默认不打开，免得列表里塞满几百个用不上的
                        provider.models.append(AIModel(id: m.id, enabled: false))
                    }
                    if remote.isEmpty { loadError = "服务器没返回模型列表，手动填一个吧。" }
                    loadingModels = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    loadingModels = false
                }
            }
        }
    }
}
