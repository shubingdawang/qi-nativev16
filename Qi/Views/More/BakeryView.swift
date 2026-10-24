import SwiftUI
import WebKit

// MARK: - 甜品屋
//
// 一个经营甜品店的小游戏，画面和玩法都在网页里（`Resources/Bakery/`，canvas 画的）：
// 集市进货、厨房自己设计甜点（坯底 → 奶油 → 搅拌 → 烘烤 → 随便装饰）、摆进展示柜定价、
// 开门营业（客人说一句含糊的要求，可以推荐）、装修、升级、常客故事、每七天一次甜品大赛。
//
// 这边只管：把存档塞进网页（`window.BAKERY_SAVE`），网页存档时写回 `bakery.json`，点返回时关掉。
// 文件跟 3D 小岛一样按文件名从安装包里取（`Island3DFiles`），所以网页那几个文件名都带 bakery 前缀，不跟别的撞。

/// 网页发回来的：`{save: "<json>"}` 存档，`{exit: true}` 返回
final class BakeryHandler: NSObject, WKScriptMessageHandler {
    var onExit: () -> Void = {}
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let json = body["save"] as? String, let data = json.data(using: .utf8) {
            // 写盘放后台，营业时每十秒存一次也不卡画面
            DispatchQueue.global(qos: .utility).async {
                try? data.write(to: Storage.fileURL("bakery.json"), options: .atomic)
            }
        }
        if body["exit"] != nil { Task { @MainActor in self.onExit() } }
    }
}

struct BakeryWeb: UIViewRepresentable {
    let onExit: () -> Void

    func makeCoordinator() -> BakeryHandler { BakeryHandler() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(Island3DFiles(), forURLScheme: "qibake")
        let ucc = WKUserContentController()
        let saved = (try? String(contentsOf: Storage.fileURL("bakery.json"), encoding: .utf8)) ?? "null"
        ucc.addUserScript(WKUserScript(source: "window.BAKERY_SAVE = \(saved.isEmpty ? "null" : saved);",
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        context.coordinator.onExit = onExit
        ucc.add(context.coordinator, name: "bake")
        cfg.userContentController = ucc
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.94, green: 0.90, blue: 0.85, alpha: 1)
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.load(URLRequest(url: URL(string: "qibake://app/bakery.html")!))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: BakeryHandler) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "bake")
    }
}

struct BakeryView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        BakeryWeb(onExit: { dismiss() })
            .ignoresSafeArea()
            .statusBarHidden(false)
    }
}
