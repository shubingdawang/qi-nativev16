import SwiftUI

/// 终端那一页。
///
/// 一条一条摆着：几点几分 · 哪一类 · 一句话 · 底下一行细节。
/// **等宽字**——这一页是拿来对齐着看的，不是拿来读的。
///
/// 上面一排是筛子（请求／工具／用量／唤醒／出错），
/// 出错那一档单独一个色，因为她八成是为了它才点进来的。
struct TerminalView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var console = Console.shared

    /// 选中的筛子。空 = 全都要。
    @State private var picked: Set<Console.Kind> = []
    @State private var toBottom = true
    @State private var copied = false

    private var shown: [Console.Line] {
        picked.isEmpty ? console.lines : console.lines.filter { picked.contains($0.kind) }
    }

    var body: some View {
        VStack(spacing: 0) {
            filters

            if shown.isEmpty {
                EmptyNote(icon: "terminal",
                          title: console.lines.isEmpty ? "还什么都没发生" : "这一档是空的",
                          hint: console.lines.isEmpty
                              ? "跟他说句话、或者让他动一下工具，这儿就会有东西。\n只记在这台手机上，不上传，他也看不见这一页。"
                              : "换一档看看。")
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(shown) { row($0) }
                            Color.clear.frame(height: 1).id("底")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: console.lines.count) { _, _ in
                        guard toBottom else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("底", anchor: .bottom) }
                    }
                    .onAppear { proxy.scrollTo("底", anchor: .bottom) }
                }
            }
        }
        .background { WallpaperBackground() }
        .navigationTitle("终端")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = console.plainText(picked.isEmpty ? nil : picked)
                        copied = true
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Label("复制这些", systemImage: "doc.on.doc")
                    }
                    Toggle(isOn: $toBottom) {
                        Label("跟着滚到底", systemImage: "arrow.down.to.line")
                    }
                    Divider()
                    Button(role: .destructive) {
                        console.clear()
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("复制好了", isPresented: $copied) {
            Button("好") { copied = false }
        } message: {
            Text("贴给我看就行。里面没有密钥，也没有整段聊天记录。")
        }
    }

    // MARK: 筛子

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(nil, "全部", count: console.lines.count)
                ForEach(Console.Kind.allCases, id: \.self) { k in
                    let n = console.lines.filter { $0.kind == k }.count
                    if n > 0 { chip(k, k.rawValue, count: n) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private func chip(_ kind: Console.Kind?, _ label: String, count: Int) -> some View {
        let on = kind == nil ? picked.isEmpty : picked.contains(kind!)
        let tint = kind == .warn ? StatusTone.remind.color : app.settings.accentColor
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                guard let kind else { picked.removeAll(); return }
                if picked.contains(kind) { picked.remove(kind) } else { picked.insert(kind) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.app(11.5, weight: on ? .semibold : .regular))
                Text("\(count)").font(.app(9.5, design: .monospaced)).opacity(0.75)
            }
            .foregroundStyle(on ? .white : Theme.textSoft(scheme))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(on ? tint.opacity(0.85) : Theme.softFillDeep))
        }
        .buttonStyle(.plain)
    }

    // MARK: 一行

    private func row(_ line: Console.Line) -> some View {
        let tint = line.kind == .warn ? StatusTone.remind.color : Theme.textMuted(scheme)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Self.clock.string(from: line.at))
                    .font(.app(10, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                Image(systemName: line.kind.icon)
                    .font(.app(9))
                    .foregroundStyle(tint)
                Text(line.title)
                    .font(.app(12, design: .monospaced))
                    .foregroundStyle(line.kind == .warn
                                     ? StatusTone.remind.color
                                     : Theme.textMain(scheme))
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            if !line.detail.isEmpty {
                Text(line.detail)
                    .font(.app(10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .padding(.leading, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = line.title
                    + (line.detail.isEmpty ? "" : "\n" + line.detail)
            } label: {
                Label("复制这一条", systemImage: "doc.on.doc")
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
