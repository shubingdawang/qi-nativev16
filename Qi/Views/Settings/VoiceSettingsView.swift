import SwiftUI

/// 语音服务。可以存好几套音色，同时只启用一个。
struct VoiceSettingsView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var editing: VoiceService?
    @State private var creatingNew = false
    @State private var testing = false
    @State private var notice: String?

    var body: some View {
        List {
            if app.voices.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有语音服务")
                            .font(.headline)
                        Text("配好之后，长按任意一句能让他念出来；他也能主动给你发语音条。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }

            ForEach(app.voices) { voice in
                Section {
                    Button {
                        editing = voice
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(voice.name.isEmpty ? "未命名" : voice.name)
                                    .foregroundStyle(.primary)
                                Text(voice.ready ? voice.voiceID : "还没填全")
                                    .font(.caption)
                                    .foregroundStyle(voice.ready ? Color.secondary : Color.orange)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: Icon.chevron)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Toggle("用这个", isOn: Binding(
                        get: { voice.enabled },
                        set: { on in
                            // 同一时刻只启用一个，免得不知道在用哪把嗓子
                            if on {
                                for i in app.voices.indices { app.voices[i].enabled = false }
                            }
                            if let i = app.voices.firstIndex(where: { $0.id == voice.id }) {
                                app.voices[i].enabled = on
                            }
                        }
                    ))

                    Button {
                        test(voice)
                    } label: {
                        HStack {
                            Label("试一句", systemImage: "waveform")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(!voice.ready || testing)
                }
            }
            .onDelete { offsets in
                app.voices.remove(atOffsets: offsets)
            }

            Section {
                Button {
                    creatingNew = true
                } label: {
                    Label("加一个音色", systemImage: Icon.add)
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("音色 ID 在 ElevenLabs 网站上每个声音的详情里能找到。同一个密钥下可以放好几个音色，随时切。")
            }
        }
        .transparentList()
        .listRowBackground(GlassRowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: Layout.tabBarExpanded)
        }
        .navigationTitle("语音")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { v in
            VoiceFormView(voice: v, isNew: false)
        }
        .sheet(isPresented: $creatingNew) {
            VoiceFormView(voice: VoiceService(), isNew: true)
        }
    }

    private func test(_ voice: VoiceService) {
        testing = true
        notice = nil
        Task {
            do {
                let data = try await TTSAPI.synthesize("在呢，听得见吗。", with: voice)
                if let file = VoiceStore.save(data) {
                    VoicePlayer.shared.toggle(file)
                    notice = "放出来了"
                }
            } catch {
                notice = error.localizedDescription
            }
            testing = false
        }
    }
}

struct VoiceFormView: View {

    @State var voice: VoiceService
    let isNew: Bool

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名字（自己看的）", text: $voice.name)
                    SecureField("API Key", text: $voice.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("https://api.elevenlabs.io", text: $voice.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("模型，比如 eleven_v3", text: $voice.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("音色 ID", text: $voice.voiceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("接口")
                } footer: {
                    Text("换别家服务的话，只要它也是「基址 + 密钥 + 模型 + 音色」这套，改个基址一般也能用。")
                }
            }
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .navigationTitle(isNew ? "加音色" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if let i = app.voices.firstIndex(where: { $0.id == voice.id }) {
                            app.voices[i] = voice
                        } else {
                            app.voices.append(voice)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
