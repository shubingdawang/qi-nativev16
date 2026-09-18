import SwiftUI

/// 工坊。只有一个固定的工作窗口，不需要对话列表，也不需要左侧边栏——
/// 那些是絮语那边的事。这里就两块：跟工坊那位说话，和放东西的地方。
struct WorkshopView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var tab = 0
    @State private var pickingWindow = false
    /// 改了钉哪个窗口之后让那一栏重画（钉在 UserDefaults 里，SwiftUI 看不见它变）
    @State private var pinTick = 0

    /// 工坊那一段对话，和它用的供应商——是新桥才有「电脑窗口」这一栏
    private var agentHere: (conv: UUID, provider: Provider)? {
        guard let id = app.activeID(for: .workshop),
              let conv = app.conversations.first(where: { $0.id == id }),
              let p = app.providers.first(where: { $0.id == conv.providerID }),
              AgentBridge.isAgent(p) else { return nil }
        return (id, p)
    }

    /// 接着电脑上哪个窗口说。
    ///
    /// 她要的：「别忘记给工作区加上窗口列表。」——工作区选的是新桥（电脑上的 Claude Code）时，
    /// 这一栏挑接着电脑上哪个窗口；不挑就是这段对话自己一个会话，桥会一直接着它。
    @ViewBuilder
    private var windowBar: some View {
        if let here = agentHere {
            let _ = pinTick
            Button { pickingWindow = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                    Text("电脑窗口：" + (AgentBridge.pinnedTitle(here.conv).flatMap { $0.isEmpty ? nil : $0 }
                                        ?? "这段对话自己的"))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.app(12))
                .foregroundStyle(Theme.textSoft(scheme))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .sheet(isPresented: $pickingWindow) {
                CodeSessionPicker(link: AgentBridge.link(from: here.provider),
                                  current: AgentBridge.pinned(here.conv) ?? "") { picked in
                    AgentBridge.pin(picked, for: here.conv)
                    pinTick += 1
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            Picker("", selection: $tab) {
                Text("工作区").tag(0)
                Text("文件").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if tab == 0 {
                windowBar
                ChatView(space: .workshop, title: "工坊",
                         showsDrawer: false, showsSideMenu: false)
            } else {
                FileLibraryView()
            }
        }
        .onAppear {
            // 工坊永远只用同一个窗口，多出来的不去管它
            app.ensureActive(in: .workshop)
        }
    }
}
