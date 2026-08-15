import SwiftUI
import SafariServices

/// App 里直接开网页，不跳出去。
/// 用系统的 Safari 视图，阅读器、分享、Cookie 都跟 Safari 一样。
struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// 包一层，好用 sheet(item:) 打开
struct BrowserLink: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - 全屏看一条消息

/// 双击气泡进来的。他写长东西的时候，在小气泡里读很累。
/// 底下两个动作：整段拷走，或者自己圈一段。
struct MessageReaderView: View {

    let message: ChatMessage
    let senderName: String

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var picking = false
    @State private var copied = false

    var body: some View {
        ZStack {
            WallpaperBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Text(senderName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(app.settings.accentColor)
                            Text(stamp)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Spacer()
                        }

                        if !message.actionText.isEmpty {
                            Text(message.actionText)
                                .font(.system(size: 14))
                                .italic()
                                .foregroundStyle(Theme.textMuted(scheme))
                        }

                        if picking {
                            // 逐字选：点头一个字，再点尾一个字，中间自动连上
                            CharacterPicker(text: message.content) { picked in
                                UIPasteboard.general.string = picked
                                copied = true
                                picking = false
                            }
                        } else {
                            Text(message.content)
                                .font(.system(size: app.settings.fontSize + 1))
                                .foregroundStyle(Theme.textMain(scheme))
                                .lineSpacing(7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }

                Divider().opacity(0.4)

                HStack(spacing: 0) {
                    Button {
                        UIPasteboard.general.string = message.content
                        copied = true
                        if app.settings.haptics {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    } label: {
                        Text(copied ? "已拷贝" : "复制全文")
                            .font(.system(size: 14))
                            .foregroundStyle(copied ? Theme.textMuted(scheme) : app.settings.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Theme.textMuted(scheme).opacity(0.25))
                        .frame(width: 1, height: 18)

                    Button {
                        picking.toggle()
                        copied = false
                    } label: {
                        Text(picking ? "退出选择" : "选一段复制")
                            .font(.system(size: 14))
                            .foregroundStyle(app.settings.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.plain)
                }
                .glassBackground(radius: 0, strength: app.settings.glassOpacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: Icon.close)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .frame(width: 34, height: 34)
                    .glassBackground(radius: 17, strength: app.settings.glassOpacity)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .padding(.top, 6)
        }
    }

    private var stamp: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: message.createdAt)
    }
}

// MARK: - 逐字选择

/// 每个字一个小方块。点第一个字,再点最后一个字,中间就全选上了。
/// 系统自带的选择手柄在长文里很难拖准,这个是给手指用的。
struct CharacterPicker: View {

    let text: String
    var onPick: (String) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var start: Int?
    @State private var end: Int?

    private var chars: [Character] { Array(text) }

    private var range: ClosedRange<Int>? {
        guard let s = start else { return nil }
        guard let e = end else { return s...s }
        return min(s, e)...max(s, e)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted(scheme))

            // 用 flow 布局把字铺开，每个字一个可点的小格
            FlowLayout(spacing: 1) {
                ForEach(chars.indices, id: \.self) { i in
                    let inRange = range?.contains(i) ?? false
                    Text(String(chars[i]))
                        .font(.system(size: app.settings.fontSize))
                        .foregroundStyle(Theme.textMain(scheme))
                        .padding(.horizontal, 1)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(inRange
                                      ? app.settings.accentColor.opacity(0.35)
                                      : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { tap(i) }
                }
            }

            if let r = range, r.count > 0 {
                Button {
                    onPick(String(chars[r]))
                } label: {
                    Text("复制选中的 \(r.count) 个字")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMain(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(app.settings.accentColor.opacity(0.3)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hint: String {
        if start == nil { return "点一下开头那个字" }
        if end == nil { return "再点一下结尾那个字" }
        return "再点别处可以重新选"
    }

    private func tap(_ i: Int) {
        if app.settings.haptics {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        if start == nil {
            start = i
        } else if end == nil {
            end = i
        } else {
            start = i
            end = nil
        }
    }
}

/// 一个够用的流式布局：装不下就换行。
///
/// 这里必须写 SwiftUI.Layout 的全名——项目里另有一个 enum Layout（放导航条高度的），
/// 直接写 Layout 会继承到那个枚举上去。
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: SwiftUI.LayoutSubviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: SwiftUI.LayoutSubviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
