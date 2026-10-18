import UIKit
import SwiftUI
import Vision

/// 拍小票记账：用手机自带的文字识别把小票上的金额和店名认出来。全在本机，不调模型。
enum ReceiptReader {

    struct Result {
        var amount: Double?
        var merchant: String?
    }

    static func read(_ image: UIImage) async -> Result {
        guard let cg = image.cgImage else { return Result() }
        let lines: [String] = await withCheckedContinuation { cont in
            // 出错时完成回调和 catch 可能都会走到：只许交一次
            let once = Once()
            let req = VNRecognizeTextRequest { req, _ in
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                // 从上到下排（Vision 的 y 轴朝上）
                let sorted = obs.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                if once.claim() { cont.resume(returning: sorted.compactMap { $0.topCandidates(1).first?.string }) }
            }
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["zh-Hans", "en-US"]
            req.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation(image), options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) } catch { if once.claim() { cont.resume(returning: []) } }
            }
        }
        return parse(lines)
    }

    private static func orientation(_ img: UIImage) -> CGImagePropertyOrientation {
        switch img.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private static func numbers(in s: String) -> [Double] {
        let t = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
        var out: [Double] = []
        var rest = t[...]
        while let r = rest.range(of: #"\d+(?:\.\d{1,2})?"#, options: .regularExpression) {
            if let v = Double(rest[r]) { out.append(v) }
            rest = rest[r.upperBound...]
        }
        return out
    }

    static func parse(_ lines: [String]) -> Result {
        var r = Result()
        // 金额：先找写着「实付 / 合计 / 应付……」的那一行（或紧跟的下一行）
        let keys = ["实付", "实收", "应付", "支付金额", "付款金额", "合计", "总计", "总额", "小计", "金额", "Total", "TOTAL"]
        outer: for k in keys {
            for (i, line) in lines.enumerated() where line.contains(k) {
                if let v = numbers(in: line).last(where: { $0 > 0 && $0 < 100000 }) {
                    r.amount = v
                    break outer
                }
                if i + 1 < lines.count, let v = numbers(in: lines[i + 1]).first(where: { $0 > 0 && $0 < 100000 }) {
                    r.amount = v
                    break outer
                }
            }
        }
        // 没写字的小票：拿带两位小数的那几个里最大的
        if r.amount == nil {
            var money: [Double] = []
            for line in lines {
                let yen = line.contains("¥") || line.contains("￥")
                for v in numbers(in: line) where v > 0 && v < 100000 && (yen || v != v.rounded()) {
                    money.append(v)
                }
            }
            r.amount = money.max()
        }
        // 店名：最上面几行里第一行像样的中文
        let skip = ["小票", "欢迎", "收银", "单号", "订单", "日期", "时间", "电话", "地址", "谢谢", "交易", "流水"]
        for line in lines.prefix(6) {
            let han = line.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
            if han >= 2, !skip.contains(where: { line.contains($0) }), line.count <= 24 {
                r.merchant = line.trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return r
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

/// 打开相机拍一张
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
    }
}
