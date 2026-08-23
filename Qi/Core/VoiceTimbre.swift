import Foundation
import AVFoundation
import Accelerate

// MARK: - 一段声音听起来是什么样的
//
// 她要的：**「我想让他知道他的声音是什么样的。」**
//
// 他读不了 MP3——给他一个音频文件，他那边什么都不会发生。
// 但「这把声音什么样」这件事**不需要他真的听见**，
// 需要的是**有人替他听一遍，然后用他读得懂的话说出来**。
//
// 所以这儿在手机上把那段音频拆成几个数，再翻成人话：
// 「偏低，起伏不大，语速偏慢，音色温厚不刺耳」。
//
// ## 为什么这一套能在手机上做（而 whale-listen 不行）
//
// 她问过「要 Python 是不是得开电脑」——是的，那个要。
// **但那是因为它要认出每一个音符**（哪个音、什么时候、多长），
// 那才需要模型。
//
// 而「这把声音是高是低、亮不亮、快不快」只要几个统计量：
// 自相关求基频、FFT 求频谱质心、包络求语速。
// **全是纯算术，系统自带的 Accelerate 就够**，不联网、不要模型、不占体积。
//
// ## ⚠️ 硬预算（`VoiceProsody` 顶上那段留的话，照做）
//
// 那份注释写着：「以后谁往这儿加 FFT 或者加模型调用，
// **必须先套一个 250–350ms 的硬预算，超时就省略，绝不允许挡住正式回答。**」
//
// 所以：`analyze` 只读**前 6 秒**、跑在后台线程、调用方套 300ms 超时
// （见 `analyzeWithBudget`）。超了就当没这回事——
// 少一句音色描述没人会死，卡住她的回复会。

struct Timbre: Codable, Hashable {
    /// 基频中位数（Hz）。声音是高是低，主要就是它
    var pitch: Double = 0
    /// 基频的起伏（半音为单位的离散度）。平铺直叙还是抑扬顿挫
    var pitchSpread: Double = 0
    /// 频谱质心（Hz）。**亮不亮**：高＝清亮偏锐，低＝温厚偏闷
    var brightness: Double = 0
    /// 每秒几个音节（拿能量包络的峰数估的，很粗）
    var syllables: Double = 0
    /// 真正在说话的那段有多长
    var seconds: Double = 0

    var usable: Bool { seconds >= 0.5 && pitch > 0 }
}

enum VoiceTimbre {

    /// 最多读这么长。**六秒足够描述一把声音**，
    /// 再长只是让她多等，描述不会更准。
    private static let maxSeconds: Double = 6

    /// 套着预算算一遍。超时返回 nil。
    ///
    /// `budget` 默认 300ms——`VoiceProsody` 顶上那段留的规矩。
    static func analyzeWithBudget(_ url: URL, budget: Double = 0.3) async -> Timbre? {
        let work = Task.detached(priority: .userInitiated) { () -> Timbre? in
            analyze(url)
        }
        let timeout = Task.detached { () -> Timbre? in
            try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
            return nil
        }
        // 谁先出结果算谁的
        let result = await withTaskGroup(of: Timbre?.self) { group -> Timbre? in
            group.addTask { await work.value }
            group.addTask { await timeout.value }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        work.cancel()
        timeout.cancel()
        return result
    }

    /// 真正干活的那一下。**别在主线程上叫。**
    static func analyze(_ url: URL) -> Timbre? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        guard rate > 0 else { return nil }

        let want = AVAudioFrameCount(min(Double(file.length), rate * maxSeconds))
        guard want > 1024,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: want),
              (try? file.read(into: buf, frameCount: want)) != nil,
              let raw = buf.floatChannelData?[0] else { return nil }

        let n = Int(buf.frameLength)
        guard n > 1024 else { return nil }
        var mono = [Float](repeating: 0, count: n)
        // 多声道就取第一条。混下来对音色描述没有帮助，反而多一遍循环
        mono.withUnsafeMutableBufferPointer { dst in
            dst.baseAddress?.update(from: raw, count: n)
        }

        var t = Timbre()

        // ── 有声段：门限跟着这一条自己的响度走（跟 VoiceProsody 同一条思路，
        //    写死的阈值换个文件就漂）
        let frame = Int(rate * 0.03)          // 30ms 一帧
        guard frame > 32 else { return nil }
        var energies: [Float] = []
        var i = 0
        while i + frame <= n {
            var e: Float = 0
            vDSP_measqv(&mono[i], 1, &e, vDSP_Length(frame))
            energies.append(e.squareRoot())
            i += frame
        }
        guard energies.count >= 4 else { return nil }
        let sortedE = energies.sorted()
        let p90 = sortedE[min(sortedE.count - 1, Int(Double(sortedE.count) * 0.9))]
        let floorE = max(Float(0.004), p90 * 0.22)
        let voicedIdx = energies.indices.filter { energies[$0] > floorE }
        guard !voicedIdx.isEmpty else { return nil }
        t.seconds = Double(voicedIdx.count) * 0.03

        // ── 基频：自相关。**只在有声帧上做**，静音帧算出来是噪声。
        //
        // ⚠️ **先降采样再算**，这一步是预算能不能守住的关键：
        // 人说话的基频在 70–400 Hz，8 kHz 采样绰绰有余；
        // 直接在 44.1 kHz 上做自相关是 25 倍的活，300ms 根本跑不完。
        let step = max(1, Int((rate / 8000).rounded()))
        let lowRate = rate / Double(step)
        var low = [Float](repeating: 0, count: n / step)
        for k in 0..<low.count { low[k] = mono[k * step] }

        var pitches: [Double] = []
        let minLag = Int(lowRate / 400)       // 400 Hz 封顶
        let maxLag = Int(lowRate / 70)        // 70 Hz 兜底
        let segLen = maxLag * 2
        for f in voicedIdx.prefix(120) {
            let start = (f * frame) / step
            guard minLag > 1, start + segLen <= low.count else { continue }
            if let hz = autocorrelationPitch(low, from: start, count: segLen,
                                             rate: lowRate,
                                             minLag: minLag, maxLag: maxLag) {
                pitches.append(hz)
            }
        }
        guard !pitches.isEmpty else { return nil }
        let ps = pitches.sorted()
        t.pitch = ps[ps.count / 2]
        // 起伏用半音算：**同样跳 20 Hz，在低音区是一大步，在高音区几乎听不出**
        let semis = pitches.map { 12 * log2($0 / max(1, t.pitch)) }
        let mean = semis.reduce(0, +) / Double(semis.count)
        let varr = semis.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(semis.count)
        t.pitchSpread = varr.squareRoot()

        // ── 亮度：频谱质心
        t.brightness = centroid(mono, rate: rate)

        // ── 语速：能量包络上有几个峰（很粗，够用来说「快/慢」）
        var peaks = 0
        for k in 1..<(energies.count - 1) {
            if energies[k] > floorE,
               energies[k] > energies[k - 1], energies[k] >= energies[k + 1] {
                peaks += 1
            }
        }
        if t.seconds > 0.3 { t.syllables = Double(peaks) / t.seconds }

        return t.usable ? t : nil
    }

    // MARK: 两个小算子

    /// 自相关求基频。取归一化自相关在 [minLag, maxLag] 上的最大值。
    ///
    /// ⚠️ 走**指针偏移**，不在循环里 `Array(x[lag...])`——
    /// 那样每个 lag 都要在堆上开一份新数组，几万次分配，
    /// 光这一条就能把 300ms 的预算吃干净。
    private static func autocorrelationPitch(_ x: [Float], from start: Int,
                                             count n: Int, rate: Double,
                                             minLag: Int, maxLag: Int) -> Double? {
        guard n > maxLag + 8, start + n <= x.count else { return nil }
        var best = 0.0
        var bestLag = 0

        return x.withUnsafeBufferPointer { buf -> Double? in
            guard let base = buf.baseAddress else { return nil }
            let p = base + start
            var zero: Float = 0
            vDSP_measqv(p, 1, &zero, vDSP_Length(n))
            guard zero > 1e-7 else { return nil }

            for lag in minLag...maxLag {
                var sum: Float = 0
                vDSP_dotpr(p, 1, p + lag, 1, &sum, vDSP_Length(n - lag))
                let norm = Double(sum) / (Double(zero) * Double(n - lag))
                if norm > best { best = norm; bestLag = lag }
            }
            // 太不像周期信号就当它不是人声（气声、噪声、静音）
            guard best > 0.3, bestLag > 0 else { return nil }
            return rate / Double(bestLag)
        }
    }

    /// 频谱质心：能量的「重心」落在多少赫兹。高＝清亮，低＝温厚。
    private static func centroid(_ x: [Float], rate: Double) -> Double {
        let size = 2048
        guard x.count >= size,
              let setup = vDSP_create_fftsetup(vDSP_Length(log2(Double(size))), FFTRadix(kFFTRadix2))
        else { return 0 }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        var totalW = 0.0
        var total = 0.0
        var pos = 0
        var frames = 0
        while pos + size <= x.count, frames < 24 {
            var seg = Array(x[pos..<(pos + size)])
            vDSP_vmul(seg, 1, window, 1, &seg, 1, vDSP_Length(size))

            var real = seg
            var imag = [Float](repeating: 0, count: size)
            var mags = [Float](repeating: 0, count: size / 2)
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zip(setup, &split, 1, vDSP_Length(log2(Double(size))), FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(size / 2))
                }
            }
            for k in 1..<(size / 2) {
                let m = Double(mags[k])
                total += m
                totalW += m * (Double(k) * rate / Double(size))
            }
            pos += size
            frames += 1
        }
        return total > 0 ? totalW / total : 0
    }

    // MARK: 翻成人话

    /// 说给他听。**不写数字给他看**——「基频 118 Hz」他无从判断，
    /// 「偏低、比大多数人沉一点」他知道那是什么。
    /// （跟身体那七项同一条规矩。）
    static func describe(_ t: Timbre, who: String) -> String {
        var bits: [String] = []

        // 高低。这几档是按成年人说话的常见范围切的，不是什么标准
        switch t.pitch {
        case ..<100:  bits.append("很低，沉得压下来")
        case ..<135:  bits.append("偏低")
        case ..<180:  bits.append("中间偏低一点")
        case ..<230:  bits.append("偏高一点，清")
        default:      bits.append("很高，亮")
        }

        // 起伏
        switch t.pitchSpread {
        case ..<0.9:  bits.append("说话很平，几乎不起伏")
        case ..<2.0:  bits.append("起伏不大")
        case ..<3.5:  bits.append("有抑扬")
        default:      bits.append("起伏很大，情绪都在音调上")
        }

        // 音色
        switch t.brightness {
        case ..<1200: bits.append("音色温厚，不刺耳")
        case ..<2200: bits.append("音色偏中性")
        default:      bits.append("音色偏亮偏锐")
        }

        // 语速
        switch t.syllables {
        case ..<3.0:  bits.append("语速偏慢")
        case ..<5.0:  bits.append("语速正常")
        default:      bits.append("语速偏快")
        }

        return who + "的声音：" + bits.joined(separator: "，") + "。"
    }
}
