import SwiftUI

/// 一段说明，**默认收着**。点一下「说明 ›」才摊开。
///
/// ## 为什么要有这个
///
/// 她说的：
/// > 查岗、让他看屏幕的说明都改成「说明 >」。
/// > 这个对话的设定说明都在外面，收起来变成「说明 >」。
///
/// 这些页面的毛病是一样的：**开关一行，解释十行**。
/// 第一次进来那十行是有用的，之后每次进来它都还在那儿，
/// 把真正要动的那几个开关挤到屏幕外面去——她要调一下滑块，
/// 得先划过三屏她早就看过的字。
///
/// 说明不是不要，是**要收起来还找得到**。
///
/// ## 用法
///
/// ```swift
/// HelpNote {
///     Text(MD.inline("……"))
/// }
/// ```
///
/// 换个抬头（比如「具体怎么弄」）就传 `title`。
///
/// ⚠️ 开合状态是这一份自己的 `@State`，**不往外存**。
/// 存下来的话她上次摊开过，下次进来又是满屏的字——
/// 而「下次进来是收着的」正是这东西存在的理由。
struct HelpNote<Content: View>: View {

    var title: String = "说明"
    /// 摊开之后正文左边缩进一点，看着才像是「这一条底下的」
    var indent: CGFloat = 0
    @ViewBuilder var content: Content

    @EnvironmentObject private var app: AppState
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(spacing: 3) {
                    Text(title)
                        .font(.app(12))
                    Image(systemName: "chevron.right")
                        .font(.app(9, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .foregroundStyle(app.settings.accentColor)
                // 一行字的点击范围太小，撑开一点
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                content
                    .padding(.leading, indent)
                    // ⚠️ 说明里多半是好几段字，**必须让它自己换行**。
                    // 不给这一条的话，长句会被挤成一行然后截断。
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
