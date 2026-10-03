import SwiftUI
import PhotosUI

/// 群成员。每位挂各自的模型，所以阿晏和工坊那边的模型能在同一个群里说话。
/// 发言顺序就是这个列表的顺序，能拖着调。
struct GroupSetupView: View {

    let conversationID: UUID
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var editing: GroupMember?

    private var conversation: Conversation? { app.conversation(conversationID) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("群名", text: Binding(
                        get: { conversation?.title ?? "" },
                        set: { newValue in
                            if let i = app.index(of: conversationID) {
                                app.conversations[i].title = newValue
                            }
                        }
                    ))
                } header: {
                    Text("名字")
                }

                Section {
                    ForEach(conversation?.members ?? []) { member in
                        Button {
                            editing = member
                        } label: {
                            HStack(spacing: 10) {
                                AvatarView(name: member.name.isEmpty ? "?" : member.name,
                                           image: member.avatarName.flatMap { ImageStore.cached($0) },
                                           size: 30)
                                    .opacity(member.enabled ? 1 : 0.45)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name.isEmpty ? "还没起名" : member.name)
                                        .foregroundStyle(Theme.mainText)
                                    Text(modelLabel(member))
                                        .font(.app(12))
                                        .foregroundStyle(Theme.softText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: Icon.chevron)
                                    .font(.app(12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onMove { from, to in
                        guard let i = app.index(of: conversationID) else { return }
                        app.conversations[i].members.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        guard let i = app.index(of: conversationID) else { return }
                        app.conversations[i].members.remove(atOffsets: offsets)
                    }

                    Button {
                        guard let i = app.index(of: conversationID) else { return }
                        var m = GroupMember(name: "")
                        if let p = app.providers.first(where: { $0.enabled && !$0.enabledModels.isEmpty }) {
                            m.providerID = p.id
                            m.modelID = p.enabledModels.first?.id
                        }
                        app.conversations[i].members.append(m)
                        editing = m
                    } label: {
                        Label("添加成员", systemImage: Icon.add)
                    }
                } header: {
                    Text("群里有谁")
                } footer: {
                    Text("不 @ 任何人时由排第一的成员回复；@ 谁就由谁回复，成员之间 @ 对方也会叫起对方。左滑删除，长按拖动可调整顺序。")
                }

                Section {
                    Stepper(value: Binding(
                        get: { conversation?.groupChainLimit ?? 4 },
                        set: { v in
                            if let i = app.index(of: conversationID) { app.conversations[i].groupChainLimit = v }
                        }), in: 1...10) {
                        Text("成员之间最多来回 \(conversation?.groupChainLimit ?? 4) 轮")
                    }
                } footer: {
                    Text("成员互相 @ 着接话时，一次最多来回这么多轮，到了就停下；他们也会被提醒在这几轮内聊完。")
                }
            }
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .navigationTitle("群聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(item: $editing) { member in
                GroupMemberFormView(conversationID: conversationID, member: member)
            }
        }
    }

    private func modelLabel(_ member: GroupMember) -> String {
        guard let p = app.provider(member.providerID), let mid = member.modelID else {
            return "还没挑模型"
        }
        let m = p.models.first { $0.id == mid }
        return m?.displayName ?? mid
    }
}

// MARK: - 编辑一位成员

struct GroupMemberFormView: View {

    let conversationID: UUID
    @State var member: GroupMember

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pickingAvatar: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("这一位") {
                    // 头像：点一下从相册挑
                    HStack(spacing: 14) {
                        AvatarView(name: member.name.isEmpty ? "?" : member.name,
                                   image: member.avatarName.flatMap { ImageStore.cached($0) },
                                   size: 56)
                        PhotosPicker(selection: $pickingAvatar, matching: .images) {
                            Text(member.avatarName == nil ? "设置头像" : "换头像")
                        }
                        if member.avatarName != nil {
                            Button("移除", role: .destructive) { member.avatarName = nil }
                                .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("名字", text: $member.name)
                    Toggle("参与说话", isOn: $member.enabled)
                }

                Section {
                    ForEach(app.providers.filter { $0.enabled && !$0.enabledModels.isEmpty }) { provider in
                        ForEach(provider.enabledModels) { model in
                            Button {
                                member.providerID = provider.id
                                member.modelID = model.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName).foregroundStyle(Theme.mainText)
                                        Text(provider.name)
                                            .font(.app(11))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if member.providerID == provider.id && member.modelID == model.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(app.settings.accentColor)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("用哪个模型")
                }

                Section {
                    TextEditor(text: $member.persona)
                        .frame(minHeight: 140)
                } header: {
                    Text("单独的设定")
                } footer: {
                    Text("仅对该成员生效，附加在群聊说明之后。留空时仅按群聊公共设定执行。")
                }
            }
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .onChange(of: pickingAvatar) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data),
                       let name = ImageStore.save(ImageStore.downscale(img, maxSide: 512)) {
                        member.avatarName = name
                    }
                    pickingAvatar = nil
                }
            }
            .navigationTitle(member.name.isEmpty ? "新成员" : member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if let i = app.index(of: conversationID),
                           let j = app.conversations[i].members.firstIndex(where: { $0.id == member.id }) {
                            app.conversations[i].members[j] = member
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
