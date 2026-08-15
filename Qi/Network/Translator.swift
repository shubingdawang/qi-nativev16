import Foundation

/// 翻译。
///
/// **先走不花钱的路。** 翻一句话而已，为这个调一次模型不划算——
/// 一次调用的钱够翻几百句了。
///
/// 顺序是：
///   1. 原文本来就是中文 → 直接原样返回，一分钱不花，也不联网
///   2. 免费接口（Google 的 gtx，再退一步 MyMemory），都不要 key
///   3. 都不通了，才回到模型那条路（AppState 里做，会记账）
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
        // 太长的免费接口会截断，超过就别糟蹋了，交给模型
        guard source.count <= 1800 else { return nil }

        if let out = await google(source, to: target), !out.isEmpty { return out }
        if let out = await myMemory(source, to: target), !out.isEmpty { return out }
        return nil
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
        req.timeoutInterval = 12
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
        req.timeoutInterval = 12

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
