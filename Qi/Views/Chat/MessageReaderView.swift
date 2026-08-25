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
                                .font(.app(13, weight: .semibold))
                                .foregroundStyle(app.settings.accentColor)
                            Text(stamp)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Spacer()
                        }

                        // 幕外那几行。**全屏这一页里心里话是摊开的**——
                        // 她特地点进来看这一条，就没有再让她多点一次的道理
                        ForEach(message.displayBeats) { beat in
                            HStack(alignment: .top, spacing: 6) {
                                if beat.isMind {
                                    Capsule()
                                        .fill(Theme.textMuted(scheme).opacity(0.28))
                                        .frame(width: 2)
                                }
                                Text(beat.text)
                                    .font(.app(14))
                                    .italic(!beat.isMind)
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
                            .font(.app(14))
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
                            .font(.app(14))
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
                    .font(.app(14, weight: .medium))
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
    /// 按钮上那个动词。默认「复制」。
    ///
    /// ⚠️ **这个按钮做什么是 `onPick` 说了算的，
    /// 所以标题也必须由调用方定。**
    ///
    /// 上一版把「复制」写死在这儿，而写批注那条路上
    /// 它实际是「确定」。她的原话：
    /// 「我挑了原句，只是按钮是复制选中的字，我以为功能是复制…」
    ///
    /// 于是她从来没真正挑中过原句，而我花了两窗去查
    /// 「为什么没有红色下划线」。
    /// **按钮上的字就是功能本身——写错了等于功能不存在。**
    var confirmVerb: String = "复制"

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
            Text(MD.inline(hint))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))

            // 用 flow 布局把字铺开，每个字一个可点的小格
            FlowLayout(spacing: 1) {
                ForEach(chars.indices, id: \.self) { i in
                    let inRange = range?.contains(i) ?? false
                    let ch = chars[i]
                    // 空格和换行**不能直接画**：`Text(" ")` 会被排版当成可拉伸的空白，
                    // `Text("\n")` 更狠，直接顶出一整行高。
                    // 她说的「偶尔选中空格时会变得很长」就是这两个。
                    // 换行画成一个淡淡的 ⏎，空格给一个固定窄宽度。
                    Text(ch == "\n" ? "⏎" : (ch == " " ? "·" : String(ch)))
                        .font(.system(size: ch.isWhitespace
                                      ? app.settings.fontSize - 4
                                      : app.settings.fontSize))
                        .foregroundStyle(ch.isWhitespace
                                         ? Theme.textMuted(scheme).opacity(0.45)
                                         : Theme.textMain(scheme))
                        .frame(minWidth: ch.isWhitespace ? 10 : 0)
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
                    Text(confirmVerb + "选中的 \(r.count) 个字")
                        .font(.app(13))
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
