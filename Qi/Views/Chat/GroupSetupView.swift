import SwiftUI

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
                                Circle()
                                    .fill(member.enabled
                                          ? app.settings.accentColor.opacity(0.7)
                                          : Color.gray.opacity(0.35))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name.isEmpty ? "还没起名" : member.name)
                                        .foregroundStyle(.primary)
                                    Text(modelLabel(member))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: Icon.chevron)
                                    .font(.caption)
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
                    Text("按这个顺序轮流说话，后说的人能看到前面刚说完的。左滑删除，长按可以拖着换顺序。")
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

    var body: some View {
        NavigationStack {
            Form {
                Section("这一位") {
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
                                        Text(model.displayName).foregroundStyle(.primary)
                                        Text(provider.name)
                                            .font(.caption2)
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
                    Text("只对这一位生效，会接在群聊说明后面。不填就只按群里的公共设定来。")
                }
            }
            .transparentList()
            .listRowBackground(GlassRowBackground())
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
