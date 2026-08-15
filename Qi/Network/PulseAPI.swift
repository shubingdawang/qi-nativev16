import Foundation

/// 连你电脑上跑的 PulseEngine（那个 FastAPI 服务）。
/// 关键设计：每次拿到数据就存一份在本地，
/// 电脑没开的时候显示最后一次的读数，而不是一片空白。
enum PulseAPI {

    struct Snapshot: Codable, Hashable {
        var heartRate: Int = 0
        var breathing: Int = 0
        var breathDepth: String = ""
        var temperature: Double = 0
        var chord: String = ""
        var fatigue: Double = 0
        var emotion: String = ""
        var nervous: String = ""
        var updatedAt: String = ""
        /// 这份数据是什么时候取回来的（本机时间）
        var fetchedAt: Date = Date()

        /// 服务器可能用中文键，也可能用英文键，两套都试一遍。
        /// 数据有时还包在 data / pulse 里面，也一起剥开。
        init(json raw: [String: Any]) {
            var json = raw
            for key in ["data", "pulse", "result", "state"] {
                if let inner = raw[key] as? [String: Any] { json = inner; break }
            }

            func num(_ keys: [String]) -> Double? {
                for k in keys {
                    if let n = json[k] as? NSNumber { return n.doubleValue }
                    if let s = json[k] as? String, let d = Double(s) { return d }
                }
                return nil
            }
            func str(_ keys: [String]) -> String {
                for k in keys {
                    if let s = json[k] as? String, !s.isEmpty { return s }
                    if let n = json[k] as? NSNumber { return n.stringValue }
                }
                return ""
            }

            heartRate = Int(num(["心跳", "heart_rate", "heartRate", "hr", "bpm"]) ?? 0)
            breathing = Int(num(["呼吸", "breathing", "breath_rate", "rr"]) ?? 0)
            breathDepth = str(["呼吸深度", "breath_depth", "breathDepth"])
            temperature = num(["体温", "temperature", "temp"]) ?? 0
            chord = str(["和弦", "chord"])
            // 疲劳有时给 0~1，有时给 0~100，统一成 0~1
            let f = num(["疲劳程度", "fatigue", "tired"]) ?? 0
            fatigue = f > 1 ? f / 100 : f
            emotion = str(["情绪状态", "emotion", "mood"])
            nervous = str(["身体紧张程度", "nervous", "tension"])
            updatedAt = str(["更新时间", "updated_at", "updatedAt", "time"])
            fetchedAt = Date()
        }

        init() {}
    }

    struct HistoryPoint: Hashable {
        var time: String
        var hr: Int
    }

    // MARK: 取数据

    private static func base(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// 可能的接口路径。挨个试，哪个给出数据就用哪个。
    ///
    /// 为什么要试这么多：你填的地址后面可能带着路径（比如 /heartbeat），
    /// 也可能就是个根地址；服务端的接口叫什么也不一定。
    /// 与其让你去猜该填哪个，不如让它自己找。
    /// 空串放第一个是有意的：你填的地址本身很可能就是那个页面
    /// （比如 .../heartbeat），先请求它，读到 HTML 就直接从页面上抠数字。
    /// 后面那几个是万一服务端另开了 JSON 接口。
    private static let paths = ["", "/pulse", "/api/pulse", "/status", "/state"]

    static func fetch(baseURL: String) async throws -> Snapshot {
        let root = base(baseURL)
        guard !root.isEmpty else {
            throw NSError(domain: "Pulse", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "心跳服务地址还没填"])
        }

        // 只用你填的这个地址，**不去试剥掉路径的根地址**——
        // 那台机器的根路径上跑的是记忆库，不是心跳，
        // 去打它既没意义，还可能拿到一份看着像但其实不相干的 JSON。
        let roots = [root]

        var lastNote = ""
        for r in roots {
            for path in paths {
                guard let url = URL(string: r + path) else { continue }
                var req = URLRequest(url: url)
                req.timeoutInterval = 10
                req.setValue("application/json", forHTTPHeaderField: "Accept")

                guard let (data, response) = try? await URLSession.shared.data(for: req),
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else { continue }

                // 先按 JSON 读
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let err = json["error"] as? String { lastNote = err; continue }
                    let snap = Snapshot(json: json)
                    if snap.heartRate > 0 || !snap.emotion.isEmpty {
                        Storage.save(snap, to: "pulse_cache.json")
                        return snap
                    }
                }

                // 读不出 JSON 就当网页解析。
                // 那个页面上心跳、呼吸、体温、和弦都明明白白写着，
                // 与其报"没有正常回应"，不如把数字直接抠出来。
                if let html = String(data: data, encoding: .utf8),
                   let snap = fromHTML(html) {
                    Storage.save(snap, to: "pulse_cache.json")
                    return snap
                }
            }
        }

        throw NSError(domain: "Pulse", code: -2, userInfo: [
            NSLocalizedDescriptionKey: lastNote.isEmpty
                ? "连上了但没读到数据。地址填根地址就行，后面的路径它会自己找。"
                : lastNote
        ])
    }

    /// 从网页里把数字抠出来
    private static func fromHTML(_ html: String) -> Snapshot? {
        func number(_ pattern: String) -> Double? {
            guard let r = html.range(of: pattern, options: .regularExpression) else { return nil }
            let piece = String(html[r])
            guard let n = piece.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression)
            else { return nil }
            return Double(piece[n])
        }
        func text(_ pattern: String) -> String? {
            guard let r = html.range(of: pattern, options: .regularExpression) else { return nil }
            return String(html[r])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var snap = Snapshot()
        // 数字后面跟着单位，按单位找最准
        snap.heartRate = Int(number(#"[0-9]+\s*BPM"#) ?? 0)
        snap.breathing = Int(number(#"[0-9]+\s*次/分"#) ?? 0)
        snap.temperature = number(#"[0-9]+\.?[0-9]*\s*°?\s*C"#) ?? 0

        // 和弦是个音名，比如 C6 / Am
        if let r = html.range(of: #"和弦[\s\S]{0,120}?>([A-G][#b]?m?[0-9]?)<"#,
                              options: .regularExpression) {
            let piece = String(html[r])
            if let m = piece.range(of: #"[A-G][#b]?m?[0-9]?(?=<)"#, options: .regularExpression) {
                snap.chord = String(piece[m])
            }
        }

        // 情绪那两个字在"当前状态"底下
        if let r = html.range(of: #"当前状态[\s\S]{0,200}?"#, options: .regularExpression) {
            let block = String(html[r.lowerBound...].prefix(400))
            let stripped = block
                .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            for line in stripped.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // 找一个纯中文的短词，那就是状态
                if t.count >= 2, t.count <= 6, t != "当前状态",
                   t.range(of: #"^[\u4e00-\u9fa5]+$"#, options: .regularExpression) != nil {
                    snap.emotion = t
                    break
                }
            }
        }

        snap.fetchedAt = Date()
        // 一个数都没抠到就当失败，别拿空壳糊弄
        guard snap.heartRate > 0 || snap.breathing > 0 || !snap.emotion.isEmpty else { return nil }
        return snap
    }

    static var cached: Snapshot? {
        Storage.load(Snapshot.self, from: "pulse_cache.json")
    }

    static func history(baseURL: String, limit: Int = 200) async throws -> [HistoryPoint] {
        guard let url = URL(string: base(baseURL) + "/pulse/history?limit=\(limit)") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let points = json["points"] as? [[String: Any]] else { return [] }
        return points.compactMap { p in
            let hr = (p["hr"] as? NSNumber)?.intValue
                ?? (p["heart_rate"] as? NSNumber)?.intValue
            guard let hr else { return nil }
            let t = (p["time"] as? String) ?? (p["t"] as? String) ?? ""
            return HistoryPoint(time: t, hr: hr)
        }
    }

    // MARK: 控制

    @discardableResult
    private static func post(_ baseURL: String, path: String, body: [String: Any]?) async throws -> [String: Any] {
        guard let url = URL(string: base(baseURL) + path) else {
            throw NSError(domain: "Pulse", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "地址不对"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Pulse", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "服务器拒绝了这次修改"])
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// 情绪：calm / happy / sad / angry / nervous / tired
    static func setEmotion(_ baseURL: String, emotion: String, reason: String = "") async throws {
        _ = try await post(baseURL, path: "/emotion",
                           body: ["emotion": emotion, "reason": reason])
    }

    /// 心跳突然一跳，magnitude 是幅度
    static func spike(_ baseURL: String, magnitude: Int) async throws {
        _ = try await post(baseURL, path: "/spike", body: ["magnitude": magnitude])
    }

    static func setWeather(_ baseURL: String, condition: String, temperature: Double) async throws {
        _ = try await post(baseURL, path: "/weather",
                           body: ["condition": condition, "temperature": temperature])
    }

    static let emotions: [(String, String)] = [
        ("calm", "平静"), ("happy", "开心"), ("sad", "难过"),
        ("angry", "生气"), ("nervous", "紧张"), ("tired", "疲惫")
    ]
}
