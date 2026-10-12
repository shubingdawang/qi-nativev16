import AVFoundation

/// 语音条录好以后再修一遍：停顿太长的缩短、突然冲上去的那几下压回来。
///
/// 她说的：「你的语音还可以再改进下，停顿太长了，让语音显得很漫长，可以适当缩减掉一些句子中间的停顿。」
/// 停顿长短是合成那边决定的，提示词管不到毫秒——所以录完由手机自己剪：
///   · 每 10 毫秒量一次响度，比整段说话声小很多的算「没声」
///   · 中间连着没声超过 0.45 秒的，剪到 0.28 秒（两头各留一截，接缝处淡入淡出，不咔哒）
///   · 开头的空白留 0.12 秒，结尾留 0.25 秒
///   · 每 50 毫秒一块，比整段中位数响出一大截的块压回来，两边慢慢过渡
/// 出来存成 m4a。哪一步出问题就原样返回，绝不把一条语音弄坏。
enum VoiceTidy {

    static func tidy(_ data: Data, ext: String = "mp3") async -> (data: Data, ext: String) {
        await Task.detached(priority: .userInitiated) { () -> (Data, String) in
            (try? process(data, ext: ext)) ?? (data, ext)
        }.value
    }

    private static func process(_ data: Data, ext: String) throws -> (Data, String)? {
        let tmp = FileManager.default.temporaryDirectory
        let inURL = tmp.appendingPathComponent(UUID().uuidString + "." + ext)
        let outURL = tmp.appendingPathComponent(UUID().uuidString + ".m4a")
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: outURL)
        }
        try data.write(to: inURL)
        let file = try AVAudioFile(forReading: inURL)
        let format = file.processingFormat            // 解出来是 Float32、不交错
        let total = AVAudioFrameCount(file.length)
        guard total > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
        try file.read(into: buf)
        guard let ch = buf.floatChannelData else { return nil }
        let channels = Int(format.channelCount), n = Int(buf.frameLength)
        let sr = format.sampleRate
        guard n > Int(sr * 0.5) else { return nil }

        // ── 每 10 毫秒的响度（几个声道取平均）
        let hop = max(1, Int(sr * 0.01))
        let frames = n / hop
        var rms = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var acc: Float = 0
            for c in 0..<channels {
                let p = ch[c]
                for i in (f * hop)..<((f + 1) * hop) { acc += p[i] * p[i] }
            }
            rms[f] = (acc / Float(hop * channels)).squareRoot()
        }
        let sorted = rms.sorted()
        let loudish = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.7))]
        let quiet = max(0.004, loudish * 0.08)
        let silent = rms.map { $0 < quiet }

        // ── 要留下的段（按采样位置）：中间长停顿剪短，开头结尾空白收一收
        var keep: [(Int, Int)] = []
        let longGap = Int(0.45 / 0.01), keepGap = Int(0.28 / 0.01)
        var f = 0
        var start = 0
        // 开头的空白
        var lead = 0
        while lead < frames && silent[lead] { lead += 1 }
        start = max(0, lead - Int(0.12 / 0.01)) * hop
        f = lead
        var tail = frames
        while tail > 0 && silent[tail - 1] { tail -= 1 }
        let end = min(n, (tail + Int(0.25 / 0.01)) * hop)
        while f < tail {
            if silent[f] {
                var g = f
                while g < tail && silent[g] { g += 1 }
                if g - f > longGap {
                    // 这段停顿太长：前半截留一点、后半截留一点，中间剪掉
                    let half = keepGap / 2
                    keep.append((start, (f + half) * hop))
                    start = (g - half) * hop
                }
                f = g
            } else {
                f += 1
            }
        }
        keep.append((start, end))
        let outLen = keep.reduce(0) { $0 + max(0, $1.1 - $1.0) }
        guard outLen > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(outLen)),
              let oc = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(outLen)
        let fade = Int(sr * 0.012)
        var w = 0
        for (a, b) in keep where b > a {
            let len = b - a
            for c in 0..<channels {
                let src = ch[c], dst = oc[c]
                for i in 0..<len {
                    var g: Float = 1
                    if keep.count > 1 {
                        // 每一段两头淡入淡出，接缝不咔哒
                        if i < fade { g = Float(i) / Float(fade) }
                        if len - i < fade { g = min(g, Float(len - i) / Float(fade)) }
                    }
                    dst[w + i] = src[a + i] * g
                }
            }
            w += len
        }

        // ── 突然冲上去的那几块压回来
        let block = max(1, Int(sr * 0.05))
        let blocks = outLen / block
        if blocks > 4 {
            var br = [Float](repeating: 0, count: blocks)
            for k in 0..<blocks {
                var acc: Float = 0
                for c in 0..<channels {
                    let p = oc[c]
                    for i in (k * block)..<((k + 1) * block) { acc += p[i] * p[i] }
                }
                br[k] = (acc / Float(block * channels)).squareRoot()
            }
            let voiced = br.filter { $0 > quiet }.sorted()
            if !voiced.isEmpty {
                let med = voiced[voiced.count / 2]
                let ceiling = med * 1.7
                var gains = br.map { $0 > ceiling ? ceiling / $0 : 1 }
                // 平滑一下，增益不跳
                for _ in 0..<2 {
                    var s = gains
                    for k in 1..<(blocks - 1) { s[k] = min(gains[k], (gains[k - 1] + gains[k] * 2 + gains[k + 1]) / 4) }
                    gains = s
                }
                for k in 0..<blocks where gains[k] < 0.999 {
                    let g0 = k > 0 ? gains[k - 1] : 1, g1 = gains[k]
                    for c in 0..<channels {
                        let p = oc[c]
                        for i in 0..<block {
                            let t = Float(i) / Float(block)
                            p[k * block + i] *= g0 + (g1 - g0) * t
                        }
                    }
                }
            }
        }

        // ── 存成 m4a
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: channels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        // 单独一层作用域：写完 writer 就释放，文件才落盘收尾
        do {
            let writer = try AVAudioFile(forWriting: outURL, settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            try writer.write(from: out)
        }
        let result = try Data(contentsOf: outURL)
        return result.count > 1000 ? (result, "m4a") : nil
    }
}
