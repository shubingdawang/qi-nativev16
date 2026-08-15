import SwiftUI
import UniformTypeIdentifiers

/// 今天手机上干了什么。
struct PhoneActivityView: View {

    @ObservedObject private var store = PhoneActivityStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var picking = false
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                if store.bookmark == nil && store.events.isEmpty {
                    setupCard
                } else {
                    summary
                    ranking
                    Text("一共读到 \(store.events.count) 条记录")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                if let err = store.lastError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                Button {
                    showHelp.toggle()
                } label: {
                    Text(showHelp ? "收起说明" : "快捷指令怎么配")
                        .font(.system(size: 12))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)

                if showHelp { help }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 16)
        }
        .navigationTitle("手机")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.reload()
                } label: {
                    Image(systemName: Icon.refresh)
                }
            }
        }
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: [.plainText, .text, .data]) { result in
            if case .success(let url) = result {
                store.remember(url)
            }
        }
        .onAppear { store.reload() }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没连上")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            Text("让快捷指令把记录写进一个 txt，栖直接读那个文件——**全程不走网络**，不会再报网络错误。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSoft(scheme))
            Button {
                picking = true
            } label: {
                Text("选那个 txt")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 13)
                        .fill(app.settings.accentColor.opacity(0.28)))
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SCREEN TIME")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                Button {
                    picking = true
                } label: {
                    Text("换文件")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("总时长")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text(store.clock(store.todayTotal))
                        .font(HomeType.number(21, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    if let now = store.currentApp {
                        Text("正在用：" + now)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                VStack(alignment: .leading, spacing: 3) {
                    Text("拿起次数")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text("\(store.pickups)")
                        .font(HomeType.number(21, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("次")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            }
        }
        .glassCard()
    }

    private var ranking: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最常使用")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))

            let list = store.todayByApp()
            if list.isEmpty {
                Text("今天还没有记录")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            let longest = list.first?.seconds ?? 1

            ForEach(list.prefix(8), id: \.app) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.app)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMain(scheme))
                        if item.app == store.currentApp {
                            Text("使用中")
                                .font(.system(size: 9))
                                .foregroundStyle(StatusTone.done.color)
                        }
                        Spacer()
                        Text(store.clock(item.seconds))
                            .font(HomeType.number(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.textMuted(scheme).opacity(0.12))
                            Capsule()
                                .fill(app.settings.accentColor.opacity(0.55))
                                .frame(width: geo.size.width
                                       * max(0.02, item.seconds / max(longest, 1)))
                        }
                    }
                    .frame(height: 4)
                    Text("\(item.times) 次")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
        }
        .glassCard()
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在「快捷指令」App 里：")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            ForEach([
                "1. 自动化 → 新建 → 打开 App → 挑你想记的那些",
                "2. 加动作「文本」，内容写成：当前日期|App名字|open",
                "3. 加动作「追加到文件」，存成 phone-activity.txt",
                "4. 关掉「运行前询问」，不然每次都要点一下",
                "5. 回到这里，选那个 txt"
            ], id: \.self) { line in
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSoft(scheme))
            }
            Text("想要更准的时长，就再建一组「关闭 App」的自动化，把 open 换成 close。只有 open 也能用，那样时长是按相邻两次打开的间隔估的。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.top, 4)
        }
        .glassCard()
    }
}
