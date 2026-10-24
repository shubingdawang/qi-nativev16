import SwiftUI
import WebKit

// MARK: - 3D 小岛
//
// 画面是一页网页（`Resources/Island3D/`，three.js 画的）：建筑、花园、草地、天和云、她和他都在里面。
// 这边只管把岛的数据塞进去、把按钮和手势传过去：
// - 左下摇杆走路；空白处拖动转视角，两指缩放
// - 第三人称 / 第一人称；第三人称时她可以看前进的方向，或者一直看镜头
// - 拍照：换她的表情和动作、他的样子，按快门存进相册
// - clawd 在 3D 里不穿衣服（衣服只在 2D 里穿）；岛上摆的家具不进 3D
//
// ⚠️ 资源在安装包里是**摊平**的（同步文件夹，子目录不保留），网页里 `./lib/three.module.min.js`
// 这种路径要靠 `Island3DFiles` 按文件名去包里找。

/// 给网页喂文件：`qi3d://app/<任意路径>` → 安装包里同名的那个文件
final class Island3DFiles: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let name = url.lastPathComponent
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        guard let file = Bundle.main.url(forResource: base, withExtension: ext),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime: String
        switch ext {
        case "js": mime = "text/javascript; charset=utf-8"
        case "html": mime = "text/html; charset=utf-8"
        case "json": mime = "application/json; charset=utf-8"
        case "png": mime = "image/png"
        default: mime = "application/octet-stream"
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime, "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"])!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// 网页发回来的消息转一手（`WKUserContentController` 会一直拽着它，不能直接拽住控制器）
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: Island3DController?
    init(_ t: Island3DController) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in self.target?.received(message.body) }
    }
}

@MainActor
final class Island3DController: NSObject, ObservableObject {

    enum Person: String { case third, first }
    enum Gaze: String { case forward, screen }

    enum HerAction: String, CaseIterable, Identifiable {
        case stand = "站立", sit = "坐下", jump = "跳跃", spin = "转圈"
        var id: String { rawValue }
        var key: String {
            switch self {
            case .stand: return "stand"
            case .sit: return "sit"
            case .jump: return "jump"
            case .spin: return "spin"
            }
        }
    }

    enum HimPose: String, CaseIterable, Identifiable {
        case idle = "默认", happy = "开心", wave = "挥手", love = "爱心", sleep = "小憩", think = "思考"
        var id: String { rawValue }
        var key: String {
            switch self {
            case .idle: return "idle"
            case .happy: return "happy"
            case .wave: return "wave"
            case .love: return "love"
            case .sleep: return "sleep"
            case .think: return "think"
            }
        }
    }

    static let faces = ["默认", "微笑", "眨眼", "惊讶"]

    @Published var person: Person = .third
    @Published var gaze: Gaze = .forward { didSet { js("I3D.gaze('\(gaze.rawValue)')") } }
    @Published var photoMode = false { didSet { js("I3D.photo(\(photoMode))") } }
    @Published var herFace = 0
    @Published var herAction: HerAction = .stand
    @Published var himPose: HimPose = .idle { didSet { js("I3D.him('\(himPose.key)')") } }
    @Published var flash = false
    @Published var toast: String?
    /// 网页搭好了（搭之前盖一层「正在搭建小岛」）
    @Published var ready = false

    let web: WKWebView
    private var lastStick = CGPoint.zero

    init(payload: String) {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(Island3DFiles(), forURLScheme: "qi3d")
        let ucc = WKUserContentController()
        // 岛的数据在网页一开头就放好（`window.ISLAND`），网页读它来搭
        ucc.addUserScript(WKUserScript(source: "window.ISLAND = \(payload);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc
        cfg.allowsInlineMediaPlayback = true
        web = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        ucc.add(WeakHandler(self), name: "i3d")
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isUserInteractionEnabled = false
        web.load(URLRequest(url: URL(string: "qi3d://app/index.html")!))
    }

    func received(_ body: Any) {
        if let s = body as? String, s == "ready" {
            withAnimation(.easeOut(duration: 0.35)) { ready = true }
        }
    }

    private func js(_ s: String) {
        web.evaluateJavaScript("window.I3D && " + s, completionHandler: nil)
    }

    // MARK: 操作

    func stick(_ p: CGPoint) {
        guard p != lastStick else { return }
        lastStick = p
        js("I3D.stick(\(Double(p.x)), \(Double(p.y)))")
    }

    func look(dx: CGFloat, dy: CGFloat) { js("I3D.look(\(Double(dx)), \(Double(dy)))") }
    func zoom(_ k: CGFloat) { js("I3D.zoom(\(Double(k)))") }

    func togglePerson() {
        person = person == .third ? .first : .third
        js("I3D.person('\(person.rawValue)')")
    }

    func act(_ a: HerAction) {
        herAction = a
        js("I3D.act('\(a.key)')")
        if a == .jump || a == .spin {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if self.herAction == a { self.herAction = .stand }
            }
        }
    }

    func setFace(_ i: Int) {
        herFace = i
        js("I3D.face(\(i))")
    }

    /// 走完了：存档里也挪过去（回 2D 时人在这儿）
    func leave(_ done: @escaping () -> Void) {
        web.evaluateJavaScript("window.I3D ? I3D.state() : ''") { result, _ in
            Task { @MainActor in
                if let s = result as? String, let d = s.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: [Int]] {
                    if let h = obj["her"], h.count == 2 { WorldStore.shared.walkHer(h[0], h[1]) }
                    if let m = obj["him"], m.count == 2 { WorldStore.shared.walkHim(m[0], m[1]) }
                }
                self.web.stopLoading()
                self.web.configuration.userContentController.removeScriptMessageHandler(forName: "i3d")
                done()
            }
        }
    }

    /// 快门：只拍画面，不拍按钮
    func shoot() {
        web.takeSnapshot(with: nil) { img, _ in
            Task { @MainActor in
                guard let img else { return }
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                withAnimation(.easeOut(duration: 0.08)) { self.flash = true }
                try? await Task.sleep(nanoseconds: 140_000_000)
                withAnimation(.easeOut(duration: 0.35)) { self.flash = false }
                self.toast = "已保存到相册"
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if self.toast == "已保存到相册" { withAnimation { self.toast = nil } }
            }
        }
    }

    // MARK: 塞进网页的数据

    /// 地、景、走不进去的格子、两个人在哪（家具不进 3D；clawd 在 3D 里不穿衣服，衣服只在 2D 里穿）
    static func payload(world: WorldStore) -> String {
        let s = world.save
        var dict: [String: Any] = [
            "w": s.width, "h": s.height,
            "ground": s.ground.map(\.rawValue),
            "her": [s.herX, s.herY], "him": [s.himX, s.himY],
            "season": world.season.rawValue, "night": WorldStore.isNight,
            "blocked": Array(world.blockedCells()),
        ]
        dict["decor"] = (s.decor ?? []).compactMap { d -> [String: Any]? in
            guard let k = WorldDecorKind.resolve(d.kind) else { return nil }
            return ["kind": k.rawValue, "x": d.x, "y": d.y, "w": k.cells.w, "h": k.cells.h]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return "null" }
        return str
    }
}

/// 装网页的那一层。手势不在这儿收，在上面那层透明的上面收
struct Island3DHost: UIViewRepresentable {
    let ctl: Island3DController
    func makeUIView(context: Context) -> WKWebView { ctl.web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - 页面

struct Island3DView: View {
    /// 退出
    let exit: () -> Void

    @StateObject private var ctl: Island3DController
    @EnvironmentObject private var app: AppState
    @State private var lastDrag: CGSize = .zero
    @State private var lastMag: CGFloat = 1
    @State private var leaving = false

    init(exit: @escaping () -> Void) {
        self.exit = exit
        _ctl = StateObject(wrappedValue: Island3DController(
            payload: Island3DController.payload(world: WorldStore.shared)))
    }

    private var accent: Color { app.settings.accentColor }

    var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.85, blue: 0.76).ignoresSafeArea()
            Island3DHost(ctl: ctl)
                .ignoresSafeArea()
            // 空白处拖：转镜头；两指：拉远拉近
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            ctl.look(dx: v.translation.width - lastDrag.width, dy: v.translation.height - lastDrag.height)
                            lastDrag = v.translation
                        }
                        .onEnded { _ in lastDrag = .zero }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { v in
                            ctl.zoom(v.magnification / lastMag)
                            lastMag = v.magnification
                        }
                        .onEnded { _ in lastMag = 1 }
                )

            if !ctl.ready {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在搭建小岛").font(.app(13)).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            if ctl.photoMode {
                photoControls
            } else {
                walkControls
            }

            if ctl.flash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
            if let t = ctl.toast {
                Text(t)
                    .font(.app(13))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(.regularMaterial))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
    }

    private func back() {
        guard !leaving else { return }
        leaving = true
        ctl.photoMode = false
        ctl.leave { exit() }
    }

    // MARK: 走路时

    private var walkControls: some View {
        VStack {
            HStack(spacing: 8) {
                roundButton("square.grid.3x3", "返回 2D") { back() }
                Spacer()
                pill(ctl.person == .third ? "第三人称" : "第一人称", "person.crop.circle") { ctl.togglePerson() }
                if ctl.person == .third {
                    pill(ctl.gaze == .forward ? "注视前方" : "注视镜头", ctl.gaze == .forward ? "arrow.up.forward" : "eye") {
                        ctl.gaze = ctl.gaze == .forward ? .screen : .forward
                    }
                }
                roundButton("camera", "拍照") { ctl.photoMode = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            HStack(alignment: .bottom) {
                Joystick(value: Binding(get: { .zero }, set: { ctl.stick($0) }))
                Spacer()
                Text("拖动空白处旋转视角 · 双指缩放")
                    .font(.app(10.5))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    // MARK: 拍照时

    private var photoControls: some View {
        VStack(spacing: 0) {
            HStack {
                roundButton("xmark", "退出拍照") { ctl.photoMode = false }
                Spacer()
                pill(ctl.gaze == .forward ? "注视前方" : "注视镜头", ctl.gaze == .forward ? "arrow.up.forward" : "eye") {
                    ctl.gaze = ctl.gaze == .forward ? .screen : .forward
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                row("表情", Island3DController.faces.indices.map { i in
                    (Island3DController.faces[i], ctl.herFace == i, { ctl.setFace(i) })
                })
                row("动作", Island3DController.HerAction.allCases.map { a in
                    (a.rawValue, ctl.herAction == a, { ctl.act(a) })
                })
                row(app.settings.aiName.isEmpty ? "他" : app.settings.aiName, Island3DController.HimPose.allCases.map { p in
                    (p.rawValue, ctl.himPose == p, { ctl.himPose = p })
                })
                HStack {
                    Spacer()
                    Button { ctl.shoot() } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 3).frame(width: 66, height: 66)
                            Circle().fill(.white).frame(width: 54, height: 54)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .padding(.horizontal, 12)
            .padding(.bottom, 26)
        }
    }

    private func row(_ title: String, _ items: [(String, Bool, () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.app(11)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        let it = items[i]
                        Button(action: it.2) {
                            Text(it.0)
                                .font(.app(12, weight: it.1 ? .semibold : .regular))
                                .foregroundStyle(it.1 ? Color.white : Color.primary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(it.1 ? accent : Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func roundButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.app(12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
    }
}

/// 摇杆：按住拖，松手回中间
struct Joystick: View {
    @Binding var value: CGPoint
    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: radius * 2, height: radius * 2)
            Circle().stroke(.white.opacity(0.5), lineWidth: 1).frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .offset(knob)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    var t = v.translation
                    let len = sqrt(t.width * t.width + t.height * t.height)
                    if len > radius { t = CGSize(width: t.width / len * radius, height: t.height / len * radius) }
                    knob = t
                    value = CGPoint(x: t.width / radius, y: t.height / radius)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { knob = .zero }
                    value = .zero
                }
        )
    }
}
