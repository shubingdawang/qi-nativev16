import AVFoundation

/// 通话期间的音频会话。**接通开一次，挂断关一次，中间谁都不许动它。**
///
/// ## 为什么切出去就断
///
/// iOS 只在「正在出声或正在录音」的时候让一个 App 在后台活着。
/// 以前这条链路每一步都在拆台：
///   · 录完一句 `VoiceRecorder.stop()` 就把会话关了
///   · 放他的语音 `VoicePlayer` 把类型切成只放不录
///   · 他在想的那几秒，既没出声也没在录
/// 这三个缝里任何一个落在后台，App 当场被挂起，电话就哑了。
///
/// ## 现在
///
///   · 整通电话一个 `.playAndRecord` 会话，录音、放语音、系统合成都在里面，
///     录音机和播放器看见 `inCall` 就不再自己改类型、不再关会话
///   · 垫一个**静音循环**贯穿整通电话，把「他在想」「在识别」那几秒的缝填上
///   · 被真电话、闹钟打断之后，打断一结束自己重新开起来
///
/// 后台录音时系统状态栏会亮起麦克风标记，点它回到 App。
@MainActor
enum CallAudio {

    /// 正在通话。录音机、播放器看这个决定要不要碰会话。
    private(set) static var inCall = false

    private static var keepAlive: AVAudioPlayer?
    private static var observer: NSObjectProtocol?

    static func begin() {
        guard !inCall else { return }
        inCall = true
        activate()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            MainActor.assumeIsolated {
                if inCall { activate() }
            }
        }
    }

    static func end() {
        guard inCall else { return }
        inCall = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        keepAlive?.stop()
        keepAlive = nil
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func activate() {
        let s = AVAudioSession.sharedInstance()
        // 外放；连着蓝牙耳机的话从耳机出声（麦克风仍用手机的）。
        // `.voiceChat` 开系统的回声消除：他从扬声器出来的声音
        // 不会被麦克风当成她在说话——插话全靠这个。
        try? s.setCategory(.playAndRecord, mode: .voiceChat,
                           options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setActive(true)

        if keepAlive == nil, let p = try? AVAudioPlayer(data: silentWAV()) {
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            keepAlive = p
        }
        keepAlive?.play()
    }

    /// 把录音从第 `start` 秒剪到结尾。剪不了返回 nil，调用方用原文件。
    ///
    /// 插话时录音机在他说话那段就开着了，前面录进去的是他的声音残响，
    /// 送去识别会被当成她说的。
    static func trim(_ url: URL, from start: Double) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-cut-" + UUID().uuidString + ".m4a")
        export.outputURL = out
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       end: .positiveInfinity)
        // 同 VideoDigest：老写法，闭包里只 resume，出来看文件在不在
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        return FileManager.default.fileExists(atPath: out.path) ? out : nil
    }

    /// 一秒钟的静音 WAV，8kHz 16 位单声道，在内存里现拼，不带资源文件。
    private static func silentWAV() -> Data {
        let rate: UInt32 = 8000
        let samples = Data(count: Int(rate) * 2)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + UInt32(samples.count))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(samples.count))
        d.append(samples)
        return d
    }
}
