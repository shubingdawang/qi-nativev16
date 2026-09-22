import Foundation

/// 翻译。
///
/// **先走不花钱的路。** 翻一句话而已，为这个调一次模型不划算——
/// 一次调用的钱够翻几百句了。
///
/// 顺序是：
///   1. 原文本来就是中文 → 直接原样返回，一分钱不花，也不联网
///   2. **系统自带的翻译**（`AppleTranslate`）：离线、免费、没有额度。
///      她要的就是这个：「像苹果自带的翻译一样，不用调用模型」
///   3. 免费接口（Google 的 gtx，再退一步 MyMemory），都不要 key
///      ⚠️ Google 那个在国内连不上，所以它排在系统那套后面——
///      以前排第一，国内每次都超时，然后一路落到模型上
///   4. 思考链那种**到此为止**（翻不了就翻不了）；
///      长按正文翻译那条还留着模型兜底（AppState 里做，会记账）
enum Translator {

    /// 中文字符占比高就当它是中文
    static func looksChinese(_ text: String) -> Bool {
        var han = 0
        var letters = 0
        for ch in text.unicodeScalars {
            if ch.properties.isAlphabetic || ("\u{4E00}"..."\u{9FFF}").contains(ch) {
                letters += 1
                if ("\u{4E00}"..."\u{9FFF}").contains(ch) { han += 1 }
            }
        }
        guard letters > 0 else { return true }
        return Double(han) / Double(letters) > 0.35
    }

    /// 不花钱地翻一句。翻不了就返回 nil，让上面决定要不要用模型。
    static func free(_ text: String, to target: String = "zh-CN") async -> String? {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        // 一、系统自带的（离线、免费）。长文也不怕，它自己能吃
        if let out = await AppleTranslate.shared.translate(source), !out.isEmpty {
            return out
        }

        // 二、网上那两个。它们会截断长文，所以**切成段一段段翻**——
        // 以前超过 1800 字直接放弃、交给模型，而思考链恰恰常常超过
        //
        // ⚠️ 两个接口**各切各的**：Google 一段吃得下一千五，
        // MyMemory 一次只收五百字上下，按一千五切给它等于一段都翻不出来。
        // 她只要个大概意思，所以翻不动的那一段就留原文，不整段作废。
        if let g = await chunked(source, size: 1500, { await google($0, to: target) }) {
            return g
        }
        return await chunked(source, size: 450, { await myMemory($0, to: target) })
    }

    /// 切段、一段段翻、再拼回去。**第一段就翻不动**才算这个接口不通（返回 nil）；
    /// 翻到一半断了的，剩下那几段原样接在后面
    private static func chunked(_ text: String, size: Int,
                                _ one: (String) async -> String?) async -> String? {
        let pieces = cut(text, at: size)
        var out: [String] = []
        for (i, piece) in pieces.enumerated() {
            if let t = await one(piece), !t.isEmpty {
                out.append(t)
            } else if i == 0 {
                return nil
            } else {
                out.append(piece)
            }
        }
        return out.joined(separator: Self.br)
    }

    /// 换行**走这个常量**，别在上面那行里写字面量：
    /// 脚本改这段的时候反斜杠被吃掉一层，`"\n"` 落盘就变成真的换行，字符串跨行、编译不过
    static let br = "\n"

    /// 按空行／句号切成不超过 `limit` 个字的几段。免费接口一段段吃得下
    static func cut(_ text: String, at limit: Int) -> [String] {
        guard text.count > limit else { return [text] }
        var out: [String] = []
        var buf = ""
        for line in text.components(separatedBy: "\n") {
            if buf.count + line.count + 1 > limit, !buf.isEmpty {
                out.append(buf)
                buf = ""
            }
            if line.count > limit {
                // 单行就超长：硬切
                var rest = Substring(line)
                while rest.count > limit {
                    let at = rest.index(rest.startIndex, offsetBy: limit)
                    out.append(String(rest[rest.startIndex..<at]))
                    rest = rest[at...]
                }
                buf += (buf.isEmpty ? "" : "\n") + String(rest)
            } else {
                buf += (buf.isEmpty ? "" : "\n") + line
            }
        }
        if !buf.isEmpty { out.append(buf) }
        return out
    }

    // MARK: Google 那个不要 key 的端点

    private static func google(_ text: String, to target: String) async -> String? {
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        comps?.queryItems = [
            .init(name: "client", value: "gtx"),
            .init(name: "sl", value: "auto"),
            .init(name: "tl", value: target),
            .init(name: "dt", value: "t"),
            .init(name: "q", value: text)
        ]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        // ⚠️ 5 秒。国内连不上它，以前每段干等 12 秒才换 MyMemory——她说的「翻译有点慢」
        req.timeoutInterval = 5
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }

        // 返回长这样：[[["译文","原文",null,null,10],[...]],null,"en", …]
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let chunks = root.first as? [Any]
        else { return nil }

        var out = ""
        for chunk in chunks {
            if let pair = chunk as? [Any], let piece = pair.first as? String {
                out += piece
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: MyMemory，也不要 key

    private static func myMemory(_ text: String, to target: String) async -> String? {
        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")
        comps?.queryItems = [
            .init(name: "q", value: text),
            .init(name: "langpair", value: "en|\(target)")
        ]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["responseData"] as? [String: Any],
              let out = payload["translatedText"] as? String
        else { return nil }

        // 额度用完的时候它会把提示文本当译文返回，认出来就丢掉
        if out.uppercased().contains("MYMEMORY WARNING") { return nil }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
