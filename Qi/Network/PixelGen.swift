import Foundation
import UIKit

/// 生成的一张像素图。
struct PixelArt: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 你给的描述
    var prompt: String = ""
    /// 本地文件名
    var fileName: String = ""
    /// 抠掉背景之后的那张
    var cutoutName: String = ""
    /// 参考图（如果有）
    var referenceName: String = ""
    /// 改过几次
    var revisions: [String] = []
    var createdAt: Date = Date()
    var author: String = ""

    var displayName: String { String(prompt.prefix(20)) }
}

enum PixelGen {

    enum GenError: LocalizedError {
        case notConfigured
        case badStatus(Int, String)
        case noImage

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "还没配好画图的模型，去「设置 → 供应商」里挑一个"
            case .badStatus(let code, let body):
                if code == 401 { return "密钥不对（401）" }
                if code == 404 { return "这个模型名不对，或者供应商不支持画图（404）" }
                return "画图接口返回 \(code)：\(body.prefix(140))"
            case .noImage: return "返回里没有图"
            }
        }
    }

    /// 背景用这个颜色。
    ///
    /// 挑品红是因为它几乎不会出现在正经画面里，
    /// 抠的时候不会误伤主体——这是像素画的老办法。
    static let keyColorPrompt =
        "on a solid pure magenta background (#FF00FF), the background must be one flat uniform color with no gradient, no shadow, no texture"

    /// 把描述包装成一段像素画的提示词。
    ///
    /// 关键几条：明确说 pixel art、限定调色板、要求硬边不要抗锯齿，
    /// 还要说"不要网格线"——不然模型经常画一张带格子的示意图出来。
    static func buildPrompt(_ text: String, animated: Bool = false) -> String {
        var s = """
        pixel art, 16-bit retro game sprite style, crisp hard pixel edges, \
        no anti-aliasing, no blur, limited color palette, clean readable silhouette, \
        centered single subject, no grid lines, no checkerboard pattern, no watermark, no text
        """
        s += ", " + keyColorPrompt
        s += ". Subject: " + text
        if animated {
            s += ". Neutral idle pose, symmetrical, suitable as a base frame for a breathing loop."
        }
        return s
    }

    /// 画一张。
    ///
    /// 中转站两种接口格式都试一遍：先按 OpenAI 的画图接口发，
    /// 不认就退回聊天接口（Gemini 那类模型走的是这条）。
    static func generate(prompt: String,
                         reference: UIImage?,
                         provider: Provider,
                         model: String) async throws -> UIImage {
        guard let base = provider.trimmedURL else { throw GenError.notConfigured }

        // 有参考图的话只能走聊天接口，画图接口那边传参考图各家都不一样
        if reference == nil {
            if let image = try? await viaImagesAPI(prompt: prompt, base: base,
                                                   key: provider.apiKey, model: model) {
                Task { @MainActor in UsageStore.shared.recordCall(.image) }
                return image
            }
        }
        let out = try await viaChatAPI(prompt: prompt, reference: reference,
                                       base: base, key: provider.apiKey, model: model)
        Task { @MainActor in UsageStore.shared.recordCall(.image) }
        return out
    }

    /// OpenAI 那套 /v1/images/generations
    private static func viaImagesAPI(prompt: String, base: String,
                                     key: String, model: String) async throws -> UIImage {
        guard let url = URL(string: base + "/images/generations") else {
            throw GenError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024"
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GenError.noImage }
        guard (200..<300).contains(http.statusCode) else {
            throw GenError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]], let first = list.first
        else { throw GenError.noImage }

        if let b64 = first["b64_json"] as? String,
           let raw = Data(base64Encoded: b64),
           let image = UIImage(data: raw) {
            return image
        }
        if let link = first["url"] as? String, let u = URL(string: link),
           let (raw, _) = try? await URLSession.shared.data(from: u),
           let image = UIImage(data: raw) {
            return image
        }
        throw GenError.noImage
    }

    /// 聊天接口那条路。Gemini 那类模型把图放在回复里返回。
    private static func viaChatAPI(prompt: String, reference: UIImage?,
                                   base: String, key: String, model: String) async throws -> UIImage {
        guard let url = URL(string: base + "/chat/completions") else {
            throw GenError.notConfigured
        }

        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let reference, let dataURL = ImageStore.base64DataURL(reference) {
            content.insert(["type": "image_url",
                            "image_url": ["url": dataURL] as [String: Any]], at: 0)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": content]],
            "modalities": ["image", "text"]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GenError.noImage }
        guard (200..<300).contains(http.statusCode) else {
            throw GenError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let image = extractImage(data) else { throw GenError.noImage }
        return image
    }

    /// 各家把图塞在不同位置，能找的地方都翻一遍
    private static func extractImage(_ data: Data) -> UIImage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var candidates: [String] = []

        func dig(_ any: Any) {
            if let s = any as? String {
                if s.hasPrefix("data:image") || s.count > 2000 { candidates.append(s) }
                if s.hasPrefix("http"), s.contains("image") || s.contains("png") {
                    candidates.append(s)
                }
            } else if let d = any as? [String: Any] {
                for (_, v) in d { dig(v) }
            } else if let a = any as? [Any] {
                for v in a { dig(v) }
            }
        }
        dig(json)

        for c in candidates {
            var raw = c
            if let comma = raw.range(of: "base64,") {
                raw = String(raw[comma.upperBound...])
            }
            if let d = Data(base64Encoded: raw, options: .ignoreUnknownCharacters),
               let image = UIImage(data: d) {
                return image
            }
        }
        return nil
    }

    // MARK: 抠背景

    /// 把品红背景换成透明。
    ///
    /// 照片抠图不能用这种"删掉某个颜色"的办法——会误删主体里相近的颜色，
    /// 边上还会留一圈毛。但**像素画是个例外**：它本来就是硬边、色块少、
    /// 没有抗锯齿的过渡像素，所以按颜色削背景反而干净。
    ///
    /// 边上那圈被模型抹出来的过渡像素，用一点容差一起削掉。
    static func removeKeyColor(_ image: UIImage, tolerance: CGFloat = 0.30) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        let t = tolerance * 255
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]), g = CGFloat(pixels[i + 1]), b = CGFloat(pixels[i + 2])
            // 品红的特征：红蓝都高、绿很低
            if r > 255 - t && b > 255 - t && g < t {
                pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            }
        }

        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    /// 裁掉四周透明的空白，居中的主体才不会飘
    static func trim(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                if pixels[(y * w + x) * 4 + 3] > 10 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX > minX, maxY > minY else { return image }
        let pad = 4
        let rect = CGRect(
            x: max(0, minX - pad), y: max(0, minY - pad),
            width: min(w, maxX - minX + pad * 2),
            height: min(h, maxY - minY + pad * 2))
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

@MainActor
final class PixelStore: ObservableObject {

    static let shared = PixelStore()

    @Published var items: [PixelArt] = [] {
        didSet { if loaded { Storage.save(items, to: "pixels.json") } }
    }
    private var loaded = false

    init() {
        items = Storage.load([PixelArt].self, from: "pixels.json") ?? []
        loaded = true
    }

    func add(_ art: PixelArt) { items.insert(art, at: 0) }

    func update(_ art: PixelArt) {
        guard let i = items.firstIndex(where: { $0.id == art.id }) else { return }
        items[i] = art
    }

    func remove(_ art: PixelArt) {
        ImageStore.delete(art.fileName)
        if !art.cutoutName.isEmpty { ImageStore.delete(art.cutoutName) }
        items.removeAll { $0.id == art.id }
    }
}
