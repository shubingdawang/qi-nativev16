import SwiftUI
import WebKit

/// 娃娃那张能点的卡片。
///
/// 这是 gist 里那个 widget 的本地版：**HTML 只负责画和传操作**，
/// 一个字的状态都不存在它里面（原文档反复强调的那条：
/// 「服务器保存游戏事实，Widget 只负责展示和传操作」）。
///
/// 桥是 `window.qi.act(action, args)`：
/// 原版走 `window.openai.callTool`，这版走 WKWebView 的消息通道，
/// 一样是「点一下 → 那边改状态 → 回一份完整快照 → 原地重画」。
///
/// 同一个 View 用在两个地方：
/// · 游戏里的娃娃房（整页）
/// · 聊天气泡里的卡片（`inline: true`，矮一点、少两排按钮）
///
/// **两边是同一份状态**——在聊天里点完，进娃娃房看到的就是刚才那个样子。
struct DollWebView: UIViewRepresentable {

    var inline: Bool = false
    var accentHex: String
    var dark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        // 带回复的消息通道：JS 那边 await 得到一份完整快照
        ucc.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "doll")
        config.userContentController = ucc

        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.bounces = false
        web.scrollView.isScrollEnabled = !inline
        web.isOpaque = false
        web.backgroundColor = .clear
        context.coordinator.web = web
        web.loadHTMLString(DollWidget.page(inline: inline, accentHex: accentHex, dark: dark),
                           baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // 他在聊天里动了娃娃、或者另一边点了什么——把新快照推进去重画。
        // **推的是完整快照**，不是增量（原文档第 13 节头一个坑）。
        let snap = DollStore.shared.snapshotJSON()
        if context.coordinator.lastPushed != snap {
            context.coordinator.lastPushed = snap
            web.evaluateJavaScript("window.applySnapshot && window.applySnapshot(\(snap));")
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply {
        weak var web: WKWebView?
        var lastPushed: String = ""

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            let body = message.body as? [String: Any] ?? [:]
            let action = (body["action"] as? String) ?? ""
            // 状态那边是 @MainActor 的，绕一趟主线程再回话
            Task { @MainActor in
                // ready 只是要一份当前状态，不改任何东西
                if !action.isEmpty && action != "ready" {
                    _ = DollStore.shared.act(action,
                                             zone: body["zone"] as? String,
                                             pose: body["pose"] as? String,
                                             camera: body["camera"] as? String,
                                             narration: body["narration"] as? String)
                }
                let snap = DollStore.shared.snapshotJSON()
                self.lastPushed = snap
                replyHandler(snap, nil)
            }
        }
    }
}

// MARK: - 那张 HTML

enum DollWidget {

    /// 整页。用原始字符串写（`#"""..."""#`），里面的引号和反斜杠都不用转义——
    /// **别用脚本改这段**，`\n` 会被写成真换行、整个字符串就断了（这坑踩过两次）。
    static func page(inline: Bool, accentHex: String, dark: Bool) -> String {
        let css = #"""
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        body {
          margin: 0; padding: 10px;
          font: 13px/1.5 -apple-system, "PingFang SC", sans-serif;
          color: var(--ink); background: transparent;
          user-select: none;
        }
        .stage {
          position: relative; width: 100%; aspect-ratio: 1 / 1;
          max-height: var(--stage-max);
          margin: 0 auto; border-radius: 18px; overflow: hidden;
          background: linear-gradient(160deg, var(--bg1), var(--bg2));
        }
        .stage svg { width: 100%; height: 100%; display: block; }
        .hotspot {
          position: absolute; border: 0; padding: 0; margin: 0;
          background: var(--accent); opacity: 0; border-radius: 50%;
          transition: opacity .18s ease, transform .18s ease;
        }
        .hotspot.touched { opacity: .5; transform: scale(1.35); }
        .hint .hotspot { opacity: .16; }
        .row { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
        button.chip {
          font: 12px/1 -apple-system, "PingFang SC", sans-serif;
          padding: 8px 11px; min-height: 34px;
          border-radius: 999px; border: 0;
          color: var(--ink); background: var(--fill);
        }
        button.chip.on { background: var(--accent); color: #fff; }
        .bars { margin-top: 10px; display: grid; gap: 5px; }
        .bar { display: flex; align-items: center; gap: 7px; font-size: 11px; }
        .bar span.k { width: 30px; color: var(--muted); }
        .bar .track { flex: 1; height: 5px; border-radius: 3px; background: var(--fill); overflow: hidden; }
        .bar .fill { height: 100%; background: var(--accent); border-radius: 3px; transition: width .3s ease; }
        .bar span.v { width: 26px; text-align: right; color: var(--muted); font-variant-numeric: tabular-nums; }
        .shots { margin-top: 10px; display: grid; gap: 4px; }
        .shots p { margin: 0; font-size: 12px; color: var(--soft); }
        .shots p:last-child { color: var(--ink); }
        .meta { margin-top: 8px; font-size: 10px; color: var(--muted); }
        @media (prefers-reduced-motion: reduce) {
          .hotspot, .bar .fill { transition: none; }
        }
        """#

        let js = #"""
        // 桥。原版是 window.openai.callTool，这版是 App 的消息通道，
        // 形状一样：传一个动作，拿回一份完整快照。
        window.qi = {
          act: function (action, args) {
            return window.webkit.messageHandlers.doll.postMessage(
              Object.assign({ action: action }, args || {})
            );
          }
        };

        var S = null;

        // 四个姿势。用同一副骨架，只改几段 path / 角度——
        // 手上没有立绘素材，与其用镜像翻转硬凑，不如画得简单但一致。
        function figure(pose, camera) {
          var poses = {
            sit:   { spine: "M100,96 C100,140 100,168 100,196", legs: "M100,196 C86,224 74,238 62,250 M100,196 C114,222 124,240 136,252", arms: "M100,120 C80,136 70,152 66,170 M100,120 C120,136 130,152 134,170", head: 0 },
            lean:  { spine: "M100,96 C108,140 112,168 116,196", legs: "M116,196 C104,226 92,240 78,252 M116,196 C132,220 142,238 152,250", arms: "M104,120 C84,132 70,142 58,150 M104,120 C126,138 138,156 142,176", head: -8 },
            curl:  { spine: "M100,100 C96,134 92,158 94,182", legs: "M94,182 C74,196 62,210 60,228 M94,182 C110,200 118,216 116,234", arms: "M98,122 C82,132 72,146 74,162 M98,122 C114,132 122,146 120,162", head: 10 },
            reach: { spine: "M100,96 C100,140 100,168 100,196", legs: "M100,196 C88,226 78,240 68,252 M100,196 C112,224 122,240 132,252", arms: "M100,118 C78,110 62,100 52,86 M100,118 C122,134 132,152 136,172", head: -4 }
          };
          var p = poses[pose] || poses.sit;
          // 机位：整体缩放和平移，不是换素材
          var cam = { front: "translate(0,0) scale(1)", side: "translate(10,0) scale(1) rotate(-6 100 150)",
                      close: "translate(0,-26) scale(1.28)", top: "translate(0,10) scale(0.94) rotate(3 100 150)" };
          var t = cam[camera] || cam.front;
          return '<svg viewBox="0 0 200 280" xmlns="http://www.w3.org/2000/svg">' +
            '<g transform="' + t + '" fill="none" stroke="var(--line)" stroke-width="6" stroke-linecap="round">' +
              '<g transform="rotate(' + p.head + ' 100 78)">' +
                '<circle cx="100" cy="74" r="24" fill="var(--skin)" stroke="var(--line)"/>' +
                '<path d="M78,62 C84,44 116,44 122,62" stroke="var(--hair)" stroke-width="10"/>' +
              '</g>' +
              '<path d="' + p.spine + '" stroke="var(--skin2)" stroke-width="20"/>' +
              '<path d="' + p.arms + '"/>' +
              '<path d="' + p.legs + '"/>' +
            '</g></svg>';
        }

        // 热区。位置是百分比，跟着舞台缩放走；
        // 平时不显示，点下去闪一下就收——原文档第 9 节那套。
        var ZONE_XY = {
          hair:  [50, 20], cheek: [58, 27], neck: [50, 35],
          hand:  [30, 45], waist: [50, 60], knee: [42, 76]
        };

        function render(s) {
          S = s;
          document.getElementById("art").innerHTML = figure(s.pose, s.camera);

          var hs = document.getElementById("spots");
          if (hs.childElementCount !== s.zones.length) {
            hs.innerHTML = "";
            s.zones.forEach(function (z) {
              var xy = ZONE_XY[z.id] || [50, 50];
              var b = document.createElement("button");
              b.className = "hotspot";
              b.style.left = "calc(" + xy[0] + "% - 26px)";
              b.style.top = "calc(" + xy[1] + "% - 26px)";
              b.style.width = "52px"; b.style.height = "52px";
              b.setAttribute("aria-label", z.label);
              b.onclick = function () {
                b.classList.add("touched");
                setTimeout(function () { b.classList.remove("touched"); }, 600);
                act("touch_zone", { zone: z.id });
              };
              hs.appendChild(b);
            });
          }

          fillRow("poses", s.poses, s.pose, function (id) { act("change_pose", { pose: id }); });
          fillRow("cameras", s.cameras, s.camera, function (id) { act("change_camera", { camera: id }); });

          var b = s.body;
          setBar("sen", "敏感", b.sensitivity);
          setBar("war", "热", b.warmth);
          setBar("tre", "抖", b.tremor);
          setBar("voi", "声", b.voice);
          setBar("int", "强度", s.intensity);

          var shots = document.getElementById("shots");
          shots.innerHTML = "";
          (s.take.shots || []).slice(-3).forEach(function (t) {
            var p = document.createElement("p"); p.textContent = t; shots.appendChild(p);
          });

          document.getElementById("meta").textContent =
            s.name + "· " + s.take.title + "· 节奏 " + s.rhythm +
            (s.poseLocked ? "· 姿势锁着" : "") +
            (s.archiveCount ? "· 收着 " + s.archiveCount + " 段" : "");

          var lock = document.getElementById("lockbtn");
          if (lock) lock.className = "chip" + (s.poseLocked ? " on" : "");
        }

        function fillRow(id, list, current, onPick) {
          var row = document.getElementById(id);
          if (!row) return;
          if (row.childElementCount !== list.length) {
            row.innerHTML = "";
            list.forEach(function (item) {
              var b = document.createElement("button");
              b.textContent = item.label;
              b.dataset.id = item.id;
              b.onclick = function () { onPick(item.id); };
              row.appendChild(b);
            });
          }
          Array.prototype.forEach.call(row.children, function (b) {
            b.className = "chip" + (b.dataset.id === current ? " on" : "");
          });
        }

        function setBar(id, label, v) {
          var el = document.getElementById("b_" + id);
          if (!el) return;
          el.querySelector(".fill").style.width = Math.max(0, Math.min(100, v)) + "%";
          el.querySelector(".v").textContent = v;
        }

        async function act(action, args) {
          var snap = await window.qi.act(action, args);
          if (typeof snap === "string") { snap = JSON.parse(snap); }
          render(snap);
        }

        // App 那边主动推进来的（比如他在聊天里动了娃娃）
        window.applySnapshot = function (s) {
          if (!S || s.version !== S.version) { render(s); }
        };

        act("ready");
        """#

        let stageMax = inline ? "230px" : "420px"
        let ink = dark ? "#EDEDED" : "#2B2B2B"
        let soft = dark ? "#B8B8B8" : "#5A5A5A"
        let muted = dark ? "#8A8A8A" : "#8E8E8E"
        let fill = dark ? "rgba(255,255,255,.10)" : "rgba(0,0,0,.06)"
        let bg1 = dark ? "rgba(255,255,255,.06)" : "rgba(255,255,255,.55)"
        let bg2 = dark ? "rgba(255,255,255,.02)" : "rgba(255,255,255,.18)"
        let line = dark ? "rgba(255,255,255,.55)" : "rgba(60,50,50,.45)"
        let skin = dark ? "rgba(255,225,215,.22)" : "rgba(255,225,215,.75)"
        let skin2 = dark ? "rgba(255,225,215,.16)" : "rgba(255,225,215,.55)"

        // 整页比卡片多两排：锁姿势、收起来、重新来过。
        // 卡片里不放「重新来过」——手一滑在聊天里把一整段清了，太亏。
        let extraRow = inline
            ? #"<button class="chip" onclick="act('save')">收起来</button>"#
            : #"""
              <button class="chip" id="lockbtn" onclick="act('lock')">锁住姿势</button>
              <button class="chip" onclick="act('save')">收起这一段</button>
              <button class="chip" onclick="act('reset')">重新来过</button>
              """#

        return #"""
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        :root {
          --accent: \#(accentHex);
          --ink: \#(ink); --soft: \#(soft); --muted: \#(muted);
          --fill: \#(fill); --bg1: \#(bg1); --bg2: \#(bg2);
          --line: \#(line); --skin: \#(skin); --skin2: \#(skin2);
          --hair: \#(accentHex);
          --stage-max: \#(stageMax);
        }
        \#(css)
        </style></head><body>
          <div class="stage" id="stage">
            <div id="art"></div>
            <div id="spots"></div>
          </div>
          <div class="row" id="poses"></div>
          <div class="row" id="cameras"></div>
          <div class="row">
            <button class="chip" onclick="act('slower')">慢一点</button>
            <button class="chip" onclick="act('faster')">快一点</button>
            <button class="chip" onclick="document.getElementById('stage').classList.toggle('hint')">哪儿能点</button>
            \#(extraRow)
          </div>
          <div class="bars">
            <div class="bar" id="b_sen"><span class="k">敏感</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
            <div class="bar" id="b_war"><span class="k">热</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
            <div class="bar" id="b_tre"><span class="k">抖</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
            <div class="bar" id="b_voi"><span class="k">声</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
            <div class="bar" id="b_int"><span class="k">强度</span><span class="track"><span class="fill"></span></span><span class="v">0</span></div>
          </div>
          <div class="shots" id="shots"></div>
          <div class="meta" id="meta"></div>
        <script>
        \#(js)
        </script></body></html>
        """#
    }
}
