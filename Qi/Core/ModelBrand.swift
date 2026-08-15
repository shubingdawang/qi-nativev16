import Foundation

/// 把一堆模型名（gpt-4o、claude-sonnet-4-5、deepseek-chat…）按厂商归类，
/// 这样几百个模型的列表也能一眼找到要的那个。
enum ModelBrand {

    /// 排在前面的优先匹配，所以要把更具体的写在前面
    private static let rules: [(keyword: [String], name: String)] = [
        (["claude"], "Claude"),
        (["gpt", "chatgpt", "o1-", "o3-", "o4-", "davinci"], "ChatGPT"),
        (["gemini", "gemma"], "Gemini"),
        (["deepseek"], "DeepSeek"),
        (["qwen", "qwq", "tongyi"], "通义千问"),
        (["glm", "chatglm"], "智谱 GLM"),
        (["kimi", "moonshot"], "Kimi"),
        (["grok"], "Grok"),
        (["doubao", "ep-"], "豆包"),
        (["hunyuan"], "混元"),
        (["ernie", "wenxin"], "文心"),
        (["minimax", "abab"], "MiniMax"),
        (["yi-"], "零一万物"),
        (["step"], "阶跃星辰"),
        (["llama"], "Llama"),
        (["mistral", "mixtral", "codestral"], "Mistral"),
        (["command"], "Cohere"),
        (["sonar", "perplexity"], "Perplexity"),
        (["flux", "sd-", "stable-diffusion", "dall-e", "midjourney"], "画图"),
        (["whisper", "tts-", "speech"], "语音")
    ]

    static func name(for modelID: String) -> String {
        let lower = modelID.lowercased()
        for rule in rules {
            for keyword in rule.keyword where lower.contains(keyword) {
                return rule.name
            }
        }
        return "其他"
    }

    /// 分组的显示顺序：认识的牌子按上面的顺序排，"其他"永远垫底
    static func sortIndex(of brand: String) -> Int {
        if brand == "其他" { return 999 }
        if let i = rules.firstIndex(where: { $0.name == brand }) { return i }
        return 998
    }

    /// 把模型分组，返回 [(品牌, 模型数组)]，已经排好序
    static func group<T>(_ items: [T], id: (T) -> String) -> [(brand: String, items: [T])] {
        var buckets: [String: [T]] = [:]
        for item in items {
            buckets[name(for: id(item)), default: []].append(item)
        }
        return buckets
            .map { (brand: $0.key, items: $0.value) }
            .sorted { sortIndex(of: $0.brand) < sortIndex(of: $1.brand) }
    }
}
