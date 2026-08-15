import SwiftUI

/// 工坊。只有一个固定的工作窗口，不需要对话列表，也不需要左侧边栏——
/// 那些是絮语那边的事。这里就两块：跟工坊那位说话，和放东西的地方。
struct WorkshopView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var tab = 0

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
