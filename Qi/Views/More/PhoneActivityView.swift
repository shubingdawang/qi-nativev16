import SwiftUI
import UniformTypeIdentifiers

/// 今天手机上干了什么。
struct PhoneActivityView: View {

    @ObservedObject private var store = PhoneActivityStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var peek = ScreenPeek.shared
    /// 预览那一张。**不存进 ScreenPeek**——那是全局单例，
    /// 把一整张全屏图挂在上面等于永远占着那块内存，
    /// 而这张只有她停在这一页时才有用。
    @State private var peekShot: UIImage?
    @State private var peekAt: Date?
    @State private var peekWhy: String?
    @State private var showHelp = false
    /// 往回翻了几天。0 是今天。
    @State private var dayOffset = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                if store.bookmark == nil && store.events.isEmpty {
                    setupCard
                } else {
                    dayPager
                    summary
                    ranking
                    Text("一共读到 \(store.events.count) 条记录")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                if let err = store.lastError {
                    Text(err)
                        .font(.app(12))
                        .foregroundStyle(.orange)
                }

                Button {
                    showHelp.toggle()
                } label: {
                    Text(showHelp ? "收起说明" : "快捷指令怎么配")
                        .font(.app(12))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)

                screenPeekCard
                checkInCard

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
        .onAppear { store.reload() }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没连上")
                .font(.app(15, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            Text(MD.inline("由快捷指令将记录写入 txt 文件，本 App 直接读取该文件。全程不经网络。"))
                .font(.app(12))
                .foregroundStyle(Theme.textSoft(scheme))
            // 理由同上：这一页会被后台的任何一次改动重建，
            // 弹窗挂在这儿会自己关掉。
            ImportButton(title: "选那个 txt", icon: "doc.text",
                         types: [.plainText, .text, .data],
                         multiple: false) { result in
                if case .success(let urls) = result, let u = urls.first {
                    store.remember(u)
                }
            }
        }
        .glassCard()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SCREEN TIME")
                    .font(.app(9, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                // 理由同 setupCard 里那个：弹窗不能挂在这一页上
                ImportButton(title: "换文件", icon: "doc.text",
                             types: [.plainText, .text, .data],
                             multiple: false) { result in
                    if case .success(let urls) = result, let u = urls.first {
                        store.remember(u)
                    }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("总时长")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text(store.clock(store.total(on: shownDay)))
                        .font(HomeType.number(21, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    // 「正在用」只有看今天才成立，翻回昨天再说这个就是假的
                    if isToday, let now = store.currentApp {
                        Text("正在用：" + now)
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                VStack(alignment: .leading, spacing: 3) {
                    Text("拿起次数")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text("\(store.pickups(on: shownDay))")
                        .font(HomeType.number(21, weight: .medium))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("次")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            }
        }
        .glassCard()
    }

    // MARK: 让他看屏幕

    /// 她挑一个文件夹，快捷指令往里存截图，他就能看一眼。
    ///
    /// **不走那个教程里的邮件绕圈**——那是给官方客户端用的，
    /// 因为那种 App 没法自己触发手机做事，只能借邮件当信号线。
    /// 我们是她自己的 App，读本地文件夹就行，截图一个字节都不出这台手机。
    @State private var showPeekHow = false
    @State private var showCheckInHow = false
    @ObservedObject private var here = WhereaboutsService.shared
    @AppStorage("checkInPrecision") private var precision = "coarse"

    // MARK: 查岗

    /// 查岗。**不发邮件、不过服务器**——理由写在 `Whereabouts.swift` 开头。
    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("查岗")
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Toggle("", isOn: $app.settings.checkInEnabled)
                    .labelsHidden()
                    .tint(app.settings.accentColor)
            }

            Text(MD.inline("启用后，模型可读取当前处境信息：屏幕上的内容、所在城市、当地天气、今日手机使用时长。\n\n默认关闭。三项数据一并授权。"))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))

            if app.settings.checkInEnabled {
                HStack {
                    Text("位置给到")
                        .font(.app(13))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer(minLength: 8)
                    Picker("", selection: $precision) {
                        ForEach(WhereaboutsService.Precision.allCases) { p in
                            Text(p.label).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
                .padding(.top, 2)

                if precision != "off", !here.authorized {
                    Button {
                        here.ask()
                    } label: {
                        Text("还没给定位权限，点这儿给")
                            .font(.app(12))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }

                // 高德那把 key。**填了地名会更细**，不填也能用。
                if precision != "off" {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("高德 key（选填）")
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))
                        SecureField("lbs.amap.com 的 Web 服务 key",
                                    text: $app.settings.amapKey)
                            .font(.app(12))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.softFillDeep))
                        Text(MD.inline("留空时使用系统自带的地理编码，精度至省市区。填写后地名精度更高。"
                             + "**「只到城市」那一档照样只给城市**，这条线是你的，不是接口的。"
                             + "只有选「精确」的时候才会给街道和「靠近哪儿」。"
                             + "\nkey 只存在这台手机上，**一个字都不进仓库**（那个仓库是公开的）。导出备份的时候它会跟供应商密钥一起在包里，所以那份备份别乱发。"))
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .padding(.top, 2)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showCheckInHow.toggle() }
                } label: {
                    Text(showCheckInHow ? "收起说明" : "它到底会拿走什么")
                        .font(.app(12))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)

                if showCheckInHow {
                    Text(MD.inline("""
                    **只有他调那个工具的时候才会拿一次**，不是一直跟着你。

                    拿的是这几样：
                    · **屏幕** —— 你的快捷指令上一次截的那张（跟上面「让他看屏幕」同一个文件夹）。没配就没有这一样。
                    · **位置** —— 上面那一档说了算。「只到城市」就只有「日本 东京都 涩谷区」这种，没有街道；「不给位置」就一个字都没有。
                    · **天气** —— 拿位置去问 Open-Meteo。**这是整套里唯一离开这台手机的东西**，而且只发经纬度，不发你是谁；那个接口不用注册，所以也没有「谁在什么时候查过哪儿」这种记录。
                    · **手机用了多久** —— 本来就在这台手机上。

                    参考的那份教程是让 AI **发邮件**触发快捷指令、再**邮件回传**（因为 ChatGPT 那种客户端没法让手机做事，只能借邮件当信号线）。我们就在这台手机上，那一圈全省了——不用两个邮箱、不用授权码、不用 Caddy、不用跟 VPN 节点较劲。

                    ⚠️ 截图**永远不是实时的**。iOS 不许任何 App 主动截别的 App 的屏，他看到的是你上次按快捷指令那一刻的画面，返回值里会写着隔了多久。
                    """))
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .glassCard(padding: 0)
    }

    /// 他现在会看到的那一张。
    ///
    /// ⚠️ **只在这一页停留时刷**（`onAppear` 拿一次、每 4 秒再拿一次），
    /// 而且一离开就把定时器停掉。不停的话它会在后台一直读文件夹、
    /// 一直解码整张截图——那是纯烧电，而她根本没在看。
    @ViewBuilder
    private var peekPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("他会看到")
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textSoft(scheme))
                Spacer()
                if let at = peekAt {
                    Text(ScreenPeek.ageText(at))
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            if let img = peekShot {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.softStroke, lineWidth: 0.8)
                    }
            } else {
                Text(peekWhy ?? "文件夹里还没有截图。")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.softFill))
            }
        }
        // ⚠️ 走 `.task` 不走 `Timer` + `onReceive`。
        //
        // 我头一版写的是一个计算属性里 `Timer.publish(...).autoconnect()`，
        // 那是个漏：**计算属性每次重绘都造一个新的发布者**，
        // 定时器越堆越多，最后一秒钟读好几次文件夹。
        //
        // `.task` 视图一消失自己就取消了，不用手动收。
        .task {
            while !Task.isCancelled {
                refreshPeek()
                // 四秒一次。**不做得更快**——每一次都要读目录、
                // 读整个文件、解码一张全屏图。
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func refreshPeek() {
        let r = peek.fresh()
        peekShot = r.shot?.image
        peekAt = r.shot?.at
        peekWhy = r.why
    }

    private var screenPeekCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("让他看屏幕")
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                if peek.ready {
                    Text("已连上")
                        .font(.app(10))
                        .foregroundStyle(StatusTone.done.color)
                }
            }

            Text(MD.inline("指定一个文件夹，由快捷指令将截图存入。模型调用「看一眼屏幕」时读取其中最新的一张。\n\n⚠️ **非实时**：iOS 不允许 App 主动截取其他 App 的画面，读取到的始终是上一次保存的截图，返回结果中标注其时间。"))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))

            if peek.ready {
                Divider().padding(.vertical, 2)

                // ⚠️ 开关跟「选没选文件夹」是两回事。
                // 以前只要选过文件夹他就永远看得到——
                // 屏幕上什么都可能有，得有一个随手能关的闸。
                Toggle(isOn: $peek.sharing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("正在共享")
                            .font(.app(14))
                            .foregroundStyle(Theme.textMain(scheme))
                        Text(peek.sharing
                             ? "他现在可以看这个文件夹里最新的那张。"
                             : "关着的时候他看不了，会被告知你没开。")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .tint(app.settings.accentColor)

                HStack {
                    Text("超过这么久就不给他")
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                    Spacer()
                    Text("\(Int(peek.staleMinutes)) 分钟")
                        .font(.app(12, design: .monospaced))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                Slider(value: $peek.staleMinutes, in: 2...60, step: 1)
                    .tint(app.settings.accentColor)
                Text(MD.inline("⚠️ **一张过期的图比没有图更坏**：没有图他会问你，有旧图他会拿它当此刻讲。超过这个时间就直接不给，只告诉他「最近没有新的」。"))
                    .font(.app(10.5))
                    .foregroundStyle(Theme.textMuted(scheme))

                // 他看到的那一张，摆在这儿。
                // **她得看得见自己共享出去的是什么**——
                // 只给一个开关的话，她永远不知道那边到底收到了什么。
                peekPreview
            }

            // 她说「我并不知道该怎么使用」——只写「挑个文件夹」确实不够，
            // 真正要做的是**在快捷指令里配一条**，这儿把步骤写全。
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showPeekHow.toggle() }
            } label: {
                Text(showPeekHow ? "收起步骤" : "具体怎么弄")
                    .font(.app(12))
                    .foregroundStyle(app.settings.accentColor)
            }
            .buttonStyle(.plain)

            if showPeekHow {
                Text(MD.inline("""
                一共两步，五分钟。

                **第一步 · 在这儿挑个文件夹**
                点下面「挑文件夹」，在「文件」里随便新建一个（比如「给阿晏看的」），选它。选完这张卡上会写「已连上」。

                **第二步 · 在「快捷指令」App 里配一条**
                1. 打开快捷指令 → 右上角 ＋ 新建
                2. 加操作「拍摄屏幕快照」（搜「屏幕快照」）
                3. 再加操作「存储文件」→ 目标选**刚才那个文件夹**
                4. 「存储文件」那一步点开，把「询问存储位置」**关掉**，不然每次都要你点一下
                5. 给它起个名字，比如「给他看」

                **然后怎么用**
                想让他看你屏幕的时候，从控制中心或者小组件点一下那个快捷指令就行。截完他下次调「看一眼屏幕」读到的就是这张。

                ⚠️ **必须你自己按一下。** iOS 不许 App 在后台截别的 App 的屏——这是系统的规矩，绕不过去，谁都做不到「他想看就能看」。所以这更像是你**递给他一眼**，不是他自己去看。
                """))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                // ⚠️ 走 `ImportButton`，**不要在这一页上挂 `fileImporter`**。
                //
                // 她报的：「"让他看屏幕"点击挑文件夹无反应。」
                // 跟当初「导入备份要点五次」是**同一个病**：
                // 弹窗挂在整页上，而这一页订阅 `app`——
                // 后台存盘、身体推进、话题池抓完，任何一样都会重建这一页，
                // 正在弹的选择器当场被撤掉。
                //
                // `ImportButton` 自己拿着弹窗、不订阅任何东西，
                // 外面重建多少次都跟它无关。理由写在那个文件开头。
                ImportButton(title: peek.ready ? "换个文件夹" : "挑文件夹",
                             icon: "folder",
                             types: [.folder],
                             multiple: false) { result in
                    if case .success(let urls) = result, let u = urls.first {
                        peek.remember(u)
                    }
                }

                if peek.ready {
                    Button {
                        peek.forget()
                    } label: {
                        Text("断开")
                            .font(.app(13))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 11)
                                .fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let err = peek.lastError {
                Text(err)
                    .font(.app(11))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 翻天

    /// 现在看的是哪一天。`dayOffset` 是「往回数第几个有记录的日子」，
    /// 不是「往回数几天」——中间没记录的日子直接跳过，
    /// 不然一路翻过去全是空的。
    private var shownDay: Date {
        let list = store.days
        guard !list.isEmpty else { return Date() }
        return list[min(max(0, dayOffset), list.count - 1)]
    }

    private var isToday: Bool { Calendar.current.isDateInToday(shownDay) }

    private var dayPager: some View {
        HStack(spacing: 18) {
            Button {
                if dayOffset < store.days.count - 1 { dayOffset += 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.app(12, weight: .semibold))
                    .foregroundStyle(dayOffset < store.days.count - 1
                                     ? Theme.textSoft(scheme)
                                     : Theme.textMuted(scheme).opacity(0.3))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
            .disabled(dayOffset >= store.days.count - 1)

            VStack(spacing: 1) {
                Text(dayLabel(shownDay))
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                if store.days.count > 1 {
                    // days 是新的在前，dayOffset 0 就是今天。序号要从最早那天数起，
                    // 所以是 count - offset，不是 offset + 1（那样今天永远显示第 1 天）。
                    Text("有记录的第 \(store.days.count - min(dayOffset, store.days.count - 1)) / \(store.days.count) 天")
                        .font(.app(9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                if dayOffset > 0 { dayOffset -= 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.app(12, weight: .semibold))
                    .foregroundStyle(dayOffset > 0
                                     ? Theme.textSoft(scheme)
                                     : Theme.textMuted(scheme).opacity(0.3))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
            .disabled(dayOffset == 0)
        }
        // 左右滑也能翻，跟按钮一个效果
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    if v.translation.width > 0 {
                        if dayOffset < store.days.count - 1 { dayOffset += 1 }
                    } else {
                        if dayOffset > 0 { dayOffset -= 1 }
                    }
                }
        )
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year)
            ? "M月d日 EEEE" : "yyyy年M月d日"
        return f.string(from: d)
    }

    private var ranking: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最常使用")
                .font(.app(13, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))

            let list = store.byApp(on: shownDay)
            if list.isEmpty {
                Text(isToday ? "今天还没有记录" : "这天没有记录")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            let longest = list.first?.seconds ?? 1
            // ⚠️ 在循环外问一次。原来是每一行都问 `store.currentApp`，
            // 而它要翻一遍今天的记录——八行就是八遍。
            let nowApp = isToday ? store.currentApp : nil

            ForEach(list.prefix(8), id: \.app) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.app)
                            .font(.app(13))
                            .foregroundStyle(Theme.textMain(scheme))
                        if let nowApp, item.app == nowApp {
                            Text("使用中")
                                .font(.app(9))
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
                        .font(.app(9))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
        }
        .glassCard()
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在「快捷指令」App 里：")
                .font(.app(12, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            ForEach([
                "1. 自动化 → 新建 → 打开 App → 挑你想记的那些",
                "2. 加动作「文本」，内容写成：当前日期|App名字|open",
                "3. 加动作「追加到文件」，存成 phone-activity.txt",
                "4. 关掉「运行前询问」，不然每次都要点一下",
                "5. 回到这里，选那个 txt"
            ], id: \.self) { line in
                Text(line)
                    .font(.app(11))
                    .foregroundStyle(Theme.textSoft(scheme))
            }
            Text("想要更准的时长，就再建一组「关闭 App」的自动化，把 open 换成 close。只有 open 也能用，那样时长是按相邻两次打开的间隔估的。")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .padding(.top, 4)
        }
        .glassCard()
    }
}
