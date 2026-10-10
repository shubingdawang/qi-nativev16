import Foundation
import SoundAnalysis

/// 电话里**听出她的声音**：喘息、水声、震动、拍打这些。
///
/// 语音识别只认说出口的字，别的声音统统当成「没听清」丢掉，他那边一片安静。
/// 这里把她刚录完的那一段再过一遍系统自带的声音分类器（`SNClassifySoundRequest`
/// `.version1`，三百多类，本机跑，不上传），挑出白名单里的几种，
/// 变成一行「〔听到了喘息〕」跟她那句话一起交给他。
///
/// 参考的是 Aria & Claude 那篇「让 AI 在电话里听见你的身体」，
/// 他们用的 YAMNet；系统这个开箱就能用，不用转模型。
enum CallSounds {

    /// 报给他的名字 ← 分类器标识里出现的词。标识是 `slap_smack` 这种，按 `_` 拆开逐个比
    private static let table: [(name: String, words: Set<String>, gate: Double)] = [
        ("喘息", ["breathing", "pant", "panting"], 0.4),
        ("倒抽气", ["gasp"], 0.4),
        ("叹气", ["sigh"], 0.45),
        ("呻吟", ["moan", "groan", "wail"], 0.3),
        ("呜咽", ["whimper"], 0.35),
        ("哭声", ["crying", "sobbing"], 0.45),
        ("尖叫", ["screaming", "scream"], 0.5),
        ("水声", ["water", "liquid", "splash", "drip", "gurgling", "slosh", "squish",
                 "trickle", "pour", "faucet"], 0.35),
        ("拍打声", ["slap", "smack", "clapping", "thump"], 0.4),
        ("震动声", ["vibration", "buzz", "toothbrush", "shaver"], 0.4),
        ("冲马桶", ["toilet"], 0.5)
    ]

    /// 动物的叫声跟人的长得像（`whimper_dog`），一律不算
    private static let animals: Set<String> = [
        "dog", "cat", "bird", "cow", "horse", "pig", "sheep", "goat", "frog", "insect",
        "owl", "lion", "gorilla", "whale", "duck", "chicken", "turkey", "rooster",
        "cricket", "mosquito", "bee", "fly", "animal", "pigeon", "crow", "goose", "bark"
    ]

    private static func name(for identifier: String) -> (String, Double)? {
        let words = Set(identifier.lowercased().split(separator: "_").map(String.init))
        guard words.isDisjoint(with: animals) else { return nil }
        for row in table where !words.isDisjoint(with: row.words) {
            return (row.name, row.gate)
        }
        return nil
    }

    /// 听这一段，返回听出来的名字（按先后，不重复）。
    /// **连着两窗**（约一秒）都过门槛才算，一闪而过的杂音不报
    static func hear(_ url: URL) async -> [String] {
        await Task.detached(priority: .userInitiated) { () -> [String] in
            guard let analyzer = try? SNAudioFileAnalyzer(url: url),
                  let request = try? SNClassifySoundRequest(classifierIdentifier: .version1)
            else { return [] }
            let collector = Collector()
            guard (try? analyzer.add(request, withObserver: collector)) != nil else { return [] }
            analyzer.analyze()
            return pick(collector.windows)
        }.value
    }

    private static func pick(_ windows: [[String: Double]]) -> [String] {
        // 每一窗：名字 → 这一窗里属于它的最高分
        let named: [[String: Double]] = windows.map { w in
            var best: [String: Double] = [:]
            for (id, score) in w {
                guard let (n, gate) = name(for: id), score >= gate else { continue }
                best[n] = max(best[n] ?? 0, score)
            }
            return best
        }
        var out: [String] = []
        for i in named.indices.dropFirst() {
            for n in named[i].keys.sorted() where named[i - 1][n] != nil && !out.contains(n) {
                out.append(n)
            }
        }
        return out
    }

    private final class Collector: NSObject, SNResultsObserving {
        var windows: [[String: Double]] = []

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            var d: [String: Double] = [:]
            for c in r.classifications where c.confidence >= 0.2 {
                d[c.identifier] = c.confidence
            }
            windows.append(d)
        }
    }
}
