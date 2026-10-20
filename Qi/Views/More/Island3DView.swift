import SwiftUI
import SceneKit
import simd

// MARK: - 3D 小岛
//
// 同一座岛，换成能走进去的样子：地是一块块的方砖（草、路、沙、田、石板各自的颜色，
// 岸边露出一截土坡，外面是海），树、房子、花、摆的东西和两个人都是立着的像素画，
// 永远朝着镜头（像纸片做的小镇）。
//
// - 左下摇杆走路；在空白处拖动转镜头，两指捏合拉远拉近
// - 第三人称 / 第一人称；第三人称时她可以看前进的方向，或者一直看镜头
// - 拍照：换她的表情和动作、他的样子，按快门存进相册
// - 从 2D 切进来时镜头从头顶俯冲下来，退出时升回头顶再换回 2D
//
// 坐标：岛上第 (x, y) 格 → 场景里 (x + 0.5, 高度, y + 0.5)，一格是一个单位。

@MainActor
final class Island3DController: NSObject, ObservableObject {

    enum Person: String { case third, first }
    enum Gaze: String { case forward, screen }

    enum HerAction: String, CaseIterable, Identifiable {
        case stand = "站着", sit = "坐下", jump = "蹦一下", spin = "转圈"
        var id: String { rawValue }
    }

    enum HimPose: String, CaseIterable, Identifiable {
        case idle = "平常", happy = "开心", wave = "挥手", love = "冒爱心", sleep = "打盹", think = "想事情"
        var id: String { rawValue }
        var mood: ClawdMood {
            switch self {
            case .idle: return .idle
            case .happy, .wave: return .happy
            case .love: return .loving
            case .sleep: return .sleeping
            case .think: return .thinking
            }
        }
    }

    /// 她的表情：0 平常，1 笑，2 眨眼，3 惊讶（`island_girl.png` 第五行）
    static let faces = ["平常", "笑", "眨眼", "惊讶"]

    @Published var person: Person = .third
    @Published var gaze: Gaze = .forward
    @Published var photoMode = false
    @Published var herFace = 0
    @Published var herAction: HerAction = .stand
    @Published var himPose: HimPose = .idle { didSet { refreshHim() } }
    @Published var flash = false
    @Published var toast: String?

    let scene = SCNScene()
    let cameraNode = SCNNode()
    weak var view: SCNView?

    private let herNode = SCNNode()
    private let himNode = SCNNode()
    private let herPlane = SCNPlane(width: 1.0, height: 25.0 / 16.0)
    private let himPlane = SCNPlane(width: 1.15, height: 1.15)
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    private var her = SIMD2<Float>(0, 0)
    private var him = SIMD2<Float>(0, 0)
    private var herDir = SIMD2<Float>(0, 1)
    private var yaw: Float = 0
    private var pitch: Float = 0.5
    private var dist: Float = 7
    /// 摇杆（-1…1，往上推是 y 负）
    var stick = SIMD2<Float>(0, 0)
    private var moving = false
    private var himMoving = false
    private var clock: Double = 0
    private var actionStart: Double = 0
    private var blocked = Set<Int>()
    private var grounds: [WorldGround] = []
    private var w = 0, h = 0
    private var wornIDs: [String] = []
    private var lastHerKey = ""
    private var himFlip = false
    /// 镜头从一组参数慢慢过渡到另一组（进出 3D 那一下）
    private var anim: (from: SIMD3<Float>, to: SIMD3<Float>, t0: Double, dur: Double, done: (() -> Void)?)?
    /// 俯视（跟 2D 一样从头顶往下看）
    private static let topDown = SIMD3<Float>(0.001, 1.45, 22)

    // MARK: 搭场景

    func build(world: WorldStore, wornIDs: [String]) {
        self.wornIDs = wornIDs
        let s = world.save
        w = s.width; h = s.height
        grounds = s.ground
        blocked = world.blockedCells()
        scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }

        let night = WorldStore.isNight
        let season = world.season
        sky(night: night)
        scene.rootNode.addChildNode(terrain())
        scene.rootNode.addChildNode(sea())
        lights(night: night, decor: s.decor ?? [])
        weather(season: season, night: night)

        for d in s.decor ?? [] { if let n = decorNode(d, season: season) { scene.rootNode.addChildNode(n) } }
        for o in s.objects { if let n = objectNode(o) { scene.rootNode.addChildNode(n) } }

        her = SIMD2(Float(s.herX) + 0.5, Float(s.herY) + 0.5)
        him = SIMD2(Float(s.himX) + 0.5, Float(s.himY) + 0.5)
        setupBillboard(herNode, herPlane, bottomTrim: 0)
        setupBillboard(himNode, himPlane, bottomTrim: 5.0 / 36.0 * 1.15)
        herNode.addChildNode(blob(0.75))
        himNode.addChildNode(blob(0.8))
        scene.rootNode.addChildNode(herNode)
        scene.rootNode.addChildNode(himNode)
        refreshHim()

        let cam = SCNCamera()
        cam.fieldOfView = 55
        cam.zNear = 0.05
        cam.zFar = 220
        cam.wantsHDR = true
        cam.bloomIntensity = 0.25
        cam.bloomThreshold = 0.85
        cam.vignettingIntensity = 0.25
        cam.vignettingPower = 0.6
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        // 镜头先放在她背后（朝北看）
        yaw = 0
        updateCamera()
    }

    func start() {
        guard link == nil else { return }
        last = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// 从头顶俯冲到她身后
    func intro() {
        let to = SIMD3<Float>(yaw, 0.5, 7)
        let from = SIMD3<Float>(yaw + Self.topDown.x, Self.topDown.y, Self.topDown.z)
        (yaw, pitch, dist) = (from.x, from.y, from.z)
        anim = (from, to, clock, 1.5, nil)
    }

    /// 升回头顶，再换回 2D
    func outro(_ done: @escaping () -> Void) {
        person = .third
        let from = SIMD3<Float>(yaw, pitch, dist)
        let to = SIMD3<Float>(yaw, Self.topDown.y, Self.topDown.z)
        anim = (from, to, clock, 0.9, done)
    }

    private func sky(night: Bool) {
        let top = night ? UIColor(hex: "1C2546") : UIColor(hex: "9ED2EE")
        let low = night ? UIColor(hex: "3C4270") : UIColor(hex: "FCEBD4")
        let size = CGSize(width: 4, height: 256)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [top.cgColor, low.cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        scene.background.contents = img
        scene.fogColor = low
        scene.fogStartDistance = 26
        scene.fogEndDistance = 70
    }

    private func lights(night: Bool, decor: [WorldDecor]) {
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.color = night ? UIColor(hex: "6670A8") : UIColor(hex: "FFF3E2")
        amb.light?.intensity = night ? 380 : 620
        scene.rootNode.addChildNode(amb)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = night ? UIColor(hex: "AFC0FF") : UIColor(hex: "FFE7C4")
        sun.light?.intensity = night ? 260 : 900
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowSampleCount = 8
        sun.light?.shadowRadius = 3
        sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.22)
        sun.light?.orthographicScale = CGFloat(max(w, h))
        sun.eulerAngles = SCNVector3(-0.95, 0.6, 0)
        sun.position = SCNVector3(Float(w) / 2, 20, Float(h) / 2)
        scene.rootNode.addChildNode(sun)

        // 夜里屋前亮一盏暖灯
        guard night else { return }
        for d in decor.prefix(40) {
            guard let k = WorldDecorKind.resolve(d.kind), k.isHouse else { continue }
            let l = SCNNode()
            l.light = SCNLight()
            l.light?.type = .omni
            l.light?.color = UIColor(hex: "FFC98A")
            l.light?.intensity = 260
            l.light?.attenuationStartDistance = 0.5
            l.light?.attenuationEndDistance = 4.5
            l.position = SCNVector3(Float(d.x) + Float(k.cells.w) / 2, 1.0, Float(d.y) + 1.2)
            scene.rootNode.addChildNode(l)
        }
    }

    /// 春天飘花瓣，冬天下雪，夏天夜里萤火虫
    private func weather(season: WorldSeason, night: Bool) {
        let p = SCNParticleSystem()
        switch season {
        case .winter:
            p.particleColor = .white
            p.particleSize = 0.05
            p.birthRate = 180
            p.particleVelocity = 0.6
            p.acceleration = SCNVector3(0.05, -0.25, 0)
        case .spring:
            p.particleColor = UIColor(hex: "F6B8C8")
            p.particleSize = 0.045
            p.birthRate = 40
            p.particleVelocity = 0.3
            p.acceleration = SCNVector3(0.15, -0.12, 0.05)
            p.particleAngularVelocity = 90
        case .summer where night:
            p.particleColor = UIColor(hex: "F7F2A0")
            p.particleSize = 0.035
            p.birthRate = 20
            p.particleVelocity = 0.15
            p.acceleration = SCNVector3(0, 0.02, 0)
            p.blendMode = .additive
        default:
            return
        }
        p.particleLifeSpan = 9
        p.emitterShape = SCNBox(width: CGFloat(w), height: 0.1, length: CGFloat(h), chamferRadius: 0)
        p.birthLocation = .volume
        p.isAffectedByGravity = false
        let n = SCNNode()
        n.position = SCNVector3(Float(w) / 2, season == .summer ? 0.6 : 6, Float(h) / 2)
        n.addParticleSystem(p)
        scene.rootNode.addChildNode(n)
    }

    // MARK: 地

    private static func top(_ g: WorldGround) -> Float? {
        switch g {
        case .sea: return nil
        case .water: return -0.24
        case .sand: return -0.07
        case .path: return -0.02
        case .wood: return -0.04
        case .soil: return 0.03
        case .stone: return 0.01
        case .grass, .flowers: return 0
        }
    }

    private static let bottom: Float = -1.4

    private func topAt(_ x: Int, _ y: Int) -> Float? {
        guard x >= 0, y >= 0, x < w, y < h else { return nil }
        return Self.top(grounds[y * w + x])
    }

    /// 某个位置脚下多高（站在哪一格的地面上）
    private func floor(_ p: SIMD2<Float>) -> Float {
        topAt(Int(p.x.rounded(.down)), Int(p.y.rounded(.down))) ?? -0.32
    }

    private func sideColor(_ g: WorldGround) -> UIColor {
        switch g {
        case .sand: return UIColor(hex: "D8C49A")
        case .stone: return UIColor(hex: "A79FA8")
        case .wood: return UIColor(hex: "9C7552")
        case .water: return UIColor(hex: "7FB2C4")
        default: return UIColor(hex: "9A7A60")
        }
    }

    private func terrain() -> SCNNode {
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], cols: [Float] = []
        var idx: [UInt32] = []
        func quad(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3, _ d: SCNVector3, _ n: SCNVector3, _ col: UIColor) {
            let i = UInt32(verts.count)
            verts += [a, b, c, d]
            norms += [n, n, n, n]
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
            col.getRed(&r, green: &g, blue: &bl, alpha: &al)
            for _ in 0..<4 { cols += [Float(r), Float(g), Float(bl), 1] }
            idx += [i, i + 1, i + 2, i, i + 2, i + 3]
        }
        for y in 0..<h {
            for x in 0..<w {
                let g = grounds[y * w + x]
                guard let t = Self.top(g) else { continue }
                // 一格一点点深浅，像一块块铺的
                let n = Float((x &* 73856093 ^ y &* 19349663) & 0xFF) / 255
                let base = UIColor(g.color).adjusted(1.0 + CGFloat(n - 0.5) * 0.07)
                let x0 = Float(x), x1 = Float(x + 1), z0 = Float(y), z1 = Float(y + 1)
                quad(SCNVector3(x0, t, z0), SCNVector3(x0, t, z1), SCNVector3(x1, t, z1), SCNVector3(x1, t, z0),
                     SCNVector3(0, 1, 0), base)
                // 四边：旁边比这格低就露出一截侧面（木桥只有薄薄一层）
                let floorY: (Float?) -> Float = { nt in
                    let b = g == .wood ? t - 0.16 : Self.bottom
                    return max(nt ?? Self.bottom, b)
                }
                let side = sideColor(g)
                let lipColor = base.adjusted(0.82)
                let edges: [(Int, Int, SCNVector3)] = [(0, -1, SCNVector3(0, 0, -1)), (0, 1, SCNVector3(0, 0, 1)),
                                                        (-1, 0, SCNVector3(-1, 0, 0)), (1, 0, SCNVector3(1, 0, 0))]
                for (dx, dy, nrm) in edges {
                    let nt = topAt(x + dx, y + dy)
                    let lo = floorY(nt)
                    guard lo < t - 0.001 else { continue }
                    // 上面一窄条跟地面同色（草皮边），下面是土
                    let lip = max(lo, t - 0.12)
                    let pts: (SCNVector3, SCNVector3, SCNVector3, SCNVector3, SCNVector3, SCNVector3, SCNVector3, SCNVector3)
                    switch (dx, dy) {
                    case (0, -1):
                        pts = (SCNVector3(x0, t, z0), SCNVector3(x1, t, z0), SCNVector3(x1, lip, z0), SCNVector3(x0, lip, z0),
                               SCNVector3(x0, lip, z0), SCNVector3(x1, lip, z0), SCNVector3(x1, lo, z0), SCNVector3(x0, lo, z0))
                    case (0, 1):
                        pts = (SCNVector3(x1, t, z1), SCNVector3(x0, t, z1), SCNVector3(x0, lip, z1), SCNVector3(x1, lip, z1),
                               SCNVector3(x1, lip, z1), SCNVector3(x0, lip, z1), SCNVector3(x0, lo, z1), SCNVector3(x1, lo, z1))
                    case (-1, 0):
                        pts = (SCNVector3(x0, t, z1), SCNVector3(x0, t, z0), SCNVector3(x0, lip, z0), SCNVector3(x0, lip, z1),
                               SCNVector3(x0, lip, z1), SCNVector3(x0, lip, z0), SCNVector3(x0, lo, z0), SCNVector3(x0, lo, z1))
                    default:
                        pts = (SCNVector3(x1, t, z0), SCNVector3(x1, t, z1), SCNVector3(x1, lip, z1), SCNVector3(x1, lip, z0),
                               SCNVector3(x1, lip, z0), SCNVector3(x1, lip, z1), SCNVector3(x1, lo, z1), SCNVector3(x1, lo, z0))
                    }
                    quad(pts.0, pts.1, pts.2, pts.3, nrm, lipColor)
                    if lip > lo + 0.001 { quad(pts.4, pts.5, pts.6, pts.7, nrm, side) }
                }
            }
        }
        let vs = SCNGeometrySource(vertices: verts)
        let ns = SCNGeometrySource(normals: norms)
        let cdata = cols.withUnsafeBufferPointer { Data(buffer: $0) }
        let cs = SCNGeometrySource(data: cdata, semantic: .color, vectorCount: verts.count, usesFloatComponents: true,
                                   componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
                                   dataOffset: 0, dataStride: MemoryLayout<Float>.size * 4)
        let el = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vs, ns, cs], elements: [el])
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = UIColor.white
        m.isDoubleSided = true
        geo.materials = [m]
        let node = SCNNode(geometry: geo)
        node.castsShadow = false
        return node
    }

    private func sea() -> SCNNode {
        let root = SCNNode()
        let pad: CGFloat = 90
        let water = SCNPlane(width: CGFloat(w) + pad, height: CGFloat(h) + pad)
        let wm = SCNMaterial()
        wm.diffuse.contents = UIColor(hex: "72C8DD").withAlphaComponent(0.88)
        wm.specular.contents = UIColor.white.withAlphaComponent(0.4)
        wm.shininess = 0.6
        wm.lightingModel = .blinn
        wm.writesToDepthBuffer = false
        water.materials = [wm]
        let wn = SCNNode(geometry: water)
        wn.eulerAngles.x = -.pi / 2
        wn.position = SCNVector3(Float(w) / 2, -0.32, Float(h) / 2)
        wn.renderingOrder = 5
        // 海面一起一伏
        let up = SCNAction.moveBy(x: 0, y: 0.04, z: 0, duration: 1.8)
        up.timingMode = .easeInEaseOut
        wn.runAction(.repeatForever(.sequence([up, up.reversed()])))
        root.addChildNode(wn)

        let bed = SCNPlane(width: CGFloat(w) + pad, height: CGFloat(h) + pad)
        let bm = SCNMaterial()
        bm.diffuse.contents = UIColor(hex: "3D86A6")
        bm.lightingModel = .constant
        bed.materials = [bm]
        let bn = SCNNode(geometry: bed)
        bn.eulerAngles.x = -.pi / 2
        bn.position = SCNVector3(Float(w) / 2, -1.5, Float(h) / 2)
        root.addChildNode(bn)
        return root
    }

    // MARK: 立着的像素画

    private func spriteMaterial(_ img: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = img
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.diffuse.mipFilter = .none
        m.lightingModel = .lambert
        m.isDoubleSided = true
        // 透明的像素直接丢掉：不然它会挡住后面的东西（深度先写进去了）
        m.shaderModifiers = [.fragment: "if (_output.color.a < 0.45) { discard_fragment(); }"]
        return m
    }

    /// 底边落在节点原点上、永远转过来朝着镜头（只绕竖轴转）
    private func setupBillboard(_ node: SCNNode, _ plane: SCNPlane, bottomTrim: CGFloat) {
        node.geometry = nil
        node.childNodes.forEach { $0.removeFromParentNode() }
        let body = SCNNode(geometry: plane)
        body.name = "body"
        body.position = SCNVector3(0, Float(plane.height / 2 - bottomTrim), 0)
        node.addChildNode(body)
        let c = SCNBillboardConstraint()
        c.freeAxes = .Y
        node.constraints = [c]
    }

    private func billboard(_ img: UIImage, width: CGFloat, height: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        plane.materials = [spriteMaterial(img)]
        let node = SCNNode()
        setupBillboard(node, plane, bottomTrim: 0)
        return node
    }

    /// 脚底下一团软影子
    private static let blobImage: UIImage = {
        let s = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: s).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [UIColor.black.withAlphaComponent(0.32).cgColor,
                                        UIColor.black.withAlphaComponent(0).cgColor] as CFArray,
                               locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                             endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }()

    private func blob(_ size: CGFloat) -> SCNNode {
        let p = SCNPlane(width: size, height: size * 0.55)
        let m = SCNMaterial()
        m.diffuse.contents = Self.blobImage
        m.lightingModel = .constant
        m.writesToDepthBuffer = false
        p.materials = [m]
        let n = SCNNode(geometry: p)
        n.eulerAngles.x = -.pi / 2
        n.position = SCNVector3(0, 0.012, 0)
        n.renderingOrder = 10
        n.constraints = []
        return n
    }

    private func decorNode(_ d: WorldDecor, season: WorldSeason) -> SCNNode? {
        guard let k = WorldDecorKind.resolve(d.kind), let img = IslandArt.sprite(k.sprite, season: season) else { return nil }
        let sz = IslandArt.size(of: k.sprite)
        let px = CGFloat(IslandArt.px)
        let pw = sz.width / px, ph = sz.height / px
        let cx = Float(d.x) + Float(k.cells.w) / 2
        let ground = topAt(d.x, d.y) ?? 0
        if k == .lily {
            // 睡莲平躺在水面上
            let p = SCNPlane(width: pw, height: ph)
            p.materials = [spriteMaterial(img)]
            let n = SCNNode(geometry: p)
            n.eulerAngles.x = -.pi / 2
            n.position = SCNVector3(cx, ground + 0.02, Float(d.y) + 0.5)
            return n
        }
        let n = billboard(img, width: pw, height: ph)
        n.position = SCNVector3(cx, ground + (k.underwater ? -0.1 : 0), Float(d.y) + 0.55)
        if d.flip == true { n.scale = SCNVector3(-1, 1, 1) }
        if k.underwater { n.opacity = 0.6 }
        if k.blocks && !k.underwater { n.addChildNode(blob(pw * 0.8)) }
        return n
    }

    private func objectNode(_ o: WorldObject) -> SCNNode? {
        guard o.source.hasPrefix("f:"), let k = FurnitureCatalog.kind(String(o.source.dropFirst(2))),
              let img = FurnitureCatalog.artImage(of: k.id, flat: true), img.size.width > 0 else { return nil }
        let wdt = CGFloat(o.w) * 0.95
        var hgt = wdt * img.size.height / img.size.width
        var width = wdt
        if hgt > 1.5 { width *= 1.5 / hgt; hgt = 1.5 }
        let n = billboard(img, width: width, height: hgt)
        n.position = SCNVector3(Float(o.x) + Float(o.w) / 2, topAt(o.x, o.y) ?? 0, Float(o.y) + 0.6)
        n.addChildNode(blob(width * 0.8))
        return n
    }

    // MARK: 两个人

    private func herImage() -> (UIImage?, Bool) {
        // 坐着：第四行
        if herAction == .sit {
            let side = gaze == .forward && !(abs(herDir.x) < 0.5)
            return (IslandArt.girl(side ? 1 : 0, 3), side && facingRight())
        }
        // 换了表情：朝前那一行的表情帧
        if herFace > 0 && !moving && herAction != .spin {
            return (IslandArt.girl(herFace - 1, 4), false)
        }
        let col = moving ? [0, 1, 0, 2][Int(clock / 0.14) % 4] : 0
        if herAction == .spin {
            let k = Int((clock - actionStart) / 0.14) % 4
            return (IslandArt.girl(0, [0, 2, 1, 2][k]), k == 3)
        }
        if gaze == .screen { return (IslandArt.girl(col, 0), false) }
        let f = SIMD2<Float>(-sin(yaw), -cos(yaw)), r = SIMD2<Float>(cos(yaw), -sin(yaw))
        let df = simd_dot(herDir, f), dr = simd_dot(herDir, r)
        if abs(df) >= abs(dr) {
            return (IslandArt.girl(col, df > 0 ? 1 : 0), false)
        }
        return (IslandArt.girl(col, 2), dr > 0)
    }

    private func facingRight() -> Bool {
        let r = SIMD2<Float>(cos(yaw), -sin(yaw))
        return simd_dot(herDir, r) > 0
    }

    private func updateHer() {
        let (img, flip) = herImage()
        let key = "\(String(describing: img?.hash)),\(flip)"
        if key != lastHerKey, let img {
            lastHerKey = key
            herPlane.materials = [spriteMaterial(img)]
            herNode.childNode(withName: "body", recursively: false)?.scale = SCNVector3(flip ? -1 : 1, 1, 1)
        }
        var y = floor(her)
        if herAction == .jump {
            let t = clock - actionStart
            if t < 0.55 { y += Float(sin(t / 0.55 * .pi)) * 0.55 } else { herAction = .stand }
        }
        if herAction == .sit { y -= 0.12 }
        herNode.position = SCNVector3(her.x, y, her.y)
        herNode.isHidden = person == .first && !photoMode
    }

    func refreshHim() {
        let pose: CarryPose = himPose == .wave ? .wave : .none
        let view = ClawdView(mood: himMoving ? .walking : himPose.mood, scale: 4, wornIDs: wornIDs, pose: pose)
            .frame(width: 144, height: 144)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let img = r.uiImage else { return }
        himPlane.materials = [spriteMaterial(img)]
    }

    private func updateHim(_ dt: Float) {
        // 跟在她身后半步
        let back = simd_length(herDir) > 0.01 ? simd_normalize(herDir) : SIMD2<Float>(0, 1)
        let target = her - back * 1.0 + SIMD2(back.y, -back.x) * 0.45
        let d = target - him
        let len = simd_length(d)
        let wasMoving = himMoving
        if simd_distance(him, her) > 1.3 || (len > 0.35 && moving) {
            let step = min(len, 2.7 * dt)
            var next = him + simd_normalize(d) * step
            if !free(next) { next = free(SIMD2(next.x, him.y)) ? SIMD2(next.x, him.y) : (free(SIMD2(him.x, next.y)) ? SIMD2(him.x, next.y) : him) }
            if simd_distance(next, her) > 7 { next = target }
            let r = SIMD2<Float>(cos(yaw), -sin(yaw))
            himFlip = simd_dot(d, r) > 0.05 ? false : (simd_dot(d, r) < -0.05 ? true : himFlip)
            him = next
            himMoving = len > 0.05
        } else {
            himMoving = false
        }
        if wasMoving != himMoving { refreshHim() }
        let bob: Float = himMoving ? abs(Float(sin(clock * 9))) * 0.05 : 0
        himNode.position = SCNVector3(him.x, floor(him) + bob, him.y)
        himNode.childNode(withName: "body", recursively: false)?.scale = SCNVector3(himFlip ? -1 : 1, 1, 1)
    }

    private func free(_ p: SIMD2<Float>) -> Bool {
        let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
        guard x >= 0, y >= 0, x < w, y < h, p.x > 0.2, p.y > 0.2 else { return false }
        if grounds[y * w + x] == .sea { return false }
        return !blocked.contains(y * w + x)
    }

    // MARK: 每一帧

    @objc private func step(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = Float(min(0.05, max(0, now - last)))
        last = now
        clock += Double(dt)

        if let a = anim {
            let t = min(1, (clock - a.t0) / a.dur)
            let e = Float(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
            let v = a.from + (a.to - a.from) * e
            (yaw, pitch, dist) = (v.x, v.y, v.z)
            if t >= 1 { anim = nil; a.done?() }
        }

        let mag = simd_length(stick)
        if mag > 0.08, anim == nil, herAction != .sit {
            let f = SIMD2<Float>(-sin(yaw), -cos(yaw)), r = SIMD2<Float>(cos(yaw), -sin(yaw))
            var m = r * stick.x + f * (-stick.y)
            if simd_length(m) > 1 { m = simd_normalize(m) }
            var next = her + m * 2.6 * dt
            if !free(next) {
                let ax = SIMD2(next.x, her.y), az = SIMD2(her.x, next.y)
                next = free(ax) ? ax : (free(az) ? az : her)
            }
            her = next
            herDir = simd_normalize(m)
            moving = true
        } else if moving {
            moving = false
            syncSave()
        }

        updateHer()
        updateHim(dt)
        updateCamera()
    }

    private func updateCamera() {
        let base = SCNVector3(her.x, floor(her), her.y)
        if person == .first && !photoMode && anim == nil {
            let eye = SCNVector3(base.x, base.y + 1.25, base.z)
            cameraNode.position = eye
            let dir = SIMD3<Float>(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
            cameraNode.look(at: SCNVector3(eye.x + dir.x, eye.y + dir.y, eye.z + dir.z))
            cameraNode.camera?.fieldOfView = 68
            return
        }
        let target = SCNVector3(base.x, base.y + 0.75, base.z)
        let c = cos(pitch)
        cameraNode.position = SCNVector3(target.x + sin(yaw) * c * dist, target.y + sin(pitch) * dist, target.z + cos(yaw) * c * dist)
        cameraNode.look(at: target)
        cameraNode.camera?.fieldOfView = 55
    }

    // MARK: 操作

    func look(dx: Float, dy: Float) {
        guard anim == nil else { return }
        yaw -= dx * 0.008
        if person == .first && !photoMode {
            pitch = min(0.9, max(-0.8, pitch + dy * 0.005))
        } else {
            pitch = min(1.35, max(0.08, pitch + dy * 0.005))
        }
    }

    func zoom(_ k: Float) {
        guard anim == nil, person == .third || photoMode else { return }
        dist = min(16, max(2.4, dist / k))
    }

    func togglePerson() {
        person = person == .third ? .first : .third
        pitch = person == .first ? 0.08 : 0.5
        // 第一人称看她正对着的方向
        if person == .first, simd_length(herDir) > 0.1 { yaw = atan2(-herDir.x, -herDir.y) }
    }

    func act(_ a: HerAction) {
        herAction = a
        actionStart = clock
        lastHerKey = ""
        if a == .spin {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if self.herAction == .spin { self.herAction = .stand; self.lastHerKey = "" }
            }
        }
    }

    func setFace(_ i: Int) {
        herFace = i
        lastHerKey = ""
    }

    /// 走完了：存档里也挪过去（回 2D 时人在这儿）
    private func syncSave() {
        WorldStore.shared.walkHer(Int(her.x.rounded(.down)), Int(her.y.rounded(.down)))
        WorldStore.shared.walkHim(Int(him.x.rounded(.down)), Int(him.y.rounded(.down)))
    }

    func leave() {
        syncSave()
        stop()
    }

    /// 快门：只拍画面，不拍按钮
    func shoot() {
        guard let v = view else { return }
        let img = v.snapshot()
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(.easeOut(duration: 0.35)) { self.flash = false }
            self.toast = "存进相册了"
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if self.toast == "存进相册了" { withAnimation { self.toast = nil } }
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        let c = Color(hexString: hex) ?? .gray
        self.init(c)
    }

    /// 亮一点 / 暗一点（k > 1 变亮）
    func adjusted(_ k: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r * k), green: min(1, g * k), blue: min(1, b * k), alpha: a)
    }
}

/// 装 SceneKit 画面的那一层。手势不在这儿收，在上面那层透明的上面收
struct Island3DHost: UIViewRepresentable {
    let ctl: Island3DController

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = ctl.scene
        v.pointOfView = ctl.cameraNode
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        ctl.view = v
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - 页面

struct Island3DView: View {
    /// 退出（镜头升回头顶以后叫）
    let exit: () -> Void

    @StateObject private var ctl = Island3DController()
    @ObservedObject private var world = WorldStore.shared
    @ObservedObject private var room = ClawdStore.shared
    @EnvironmentObject private var app: AppState
    @State private var lastDrag: CGSize = .zero
    @State private var lastMag: CGFloat = 1
    @State private var leaving = false

    private var accent: Color { app.settings.accentColor }

    var body: some View {
        ZStack {
            Island3DHost(ctl: ctl)
                .ignoresSafeArea()
            // 空白处拖：转镜头；两指：拉远拉近
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            ctl.look(dx: Float(v.translation.width - lastDrag.width),
                                     dy: Float(v.translation.height - lastDrag.height))
                            lastDrag = v.translation
                        }
                        .onEnded { _ in lastDrag = .zero }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { v in
                            ctl.zoom(Float(v.magnification / lastMag))
                            lastMag = v.magnification
                        }
                        .onEnded { _ in lastMag = 1 }
                )

            if ctl.photoMode {
                photoControls
            } else {
                walkControls
            }

            if ctl.flash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
            if let t = ctl.toast {
                Text(t)
                    .font(.app(13))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(.regularMaterial))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .onAppear {
            ctl.build(world: world, wornIDs: room.wornIDs)
            ctl.start()
            ctl.intro()
        }
        .onDisappear { ctl.leave() }
    }

    private func back() {
        guard !leaving else { return }
        leaving = true
        ctl.photoMode = false
        ctl.outro { exit() }
    }

    // MARK: 走路时

    private var walkControls: some View {
        VStack {
            HStack(spacing: 8) {
                roundButton("square.grid.3x3", "回到 2D") { back() }
                Spacer()
                pill(ctl.person == .third ? "第三人称" : "第一人称", "person.crop.circle") { ctl.togglePerson() }
                if ctl.person == .third {
                    pill(ctl.gaze == .forward ? "看前面" : "看镜头", ctl.gaze == .forward ? "arrow.up.forward" : "eye") {
                        ctl.gaze = ctl.gaze == .forward ? .screen : .forward
                    }
                }
                roundButton("camera", "拍照") { ctl.photoMode = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            HStack(alignment: .bottom) {
                Joystick(value: Binding(get: { CGPoint(x: CGFloat(ctl.stick.x), y: CGFloat(ctl.stick.y)) },
                                        set: { ctl.stick = SIMD2(Float($0.x), Float($0.y)) }))
                Spacer()
                Text("拖空白处转镜头 · 两指拉远拉近")
                    .font(.app(10.5))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    // MARK: 拍照时

    private var photoControls: some View {
        VStack(spacing: 0) {
            HStack {
                roundButton("xmark", "收起") { ctl.photoMode = false }
                Spacer()
                pill(ctl.gaze == .forward ? "看前面" : "看镜头", ctl.gaze == .forward ? "arrow.up.forward" : "eye") {
                    ctl.gaze = ctl.gaze == .forward ? .screen : .forward
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                row("她的表情", Island3DController.faces.indices.map { i in
                    (Island3DController.faces[i], ctl.herFace == i, { ctl.setFace(i) })
                })
                row("她的动作", Island3DController.HerAction.allCases.map { a in
                    (a.rawValue, ctl.herAction == a, { ctl.act(a) })
                })
                row(app.settings.aiName.isEmpty ? "他" : app.settings.aiName, Island3DController.HimPose.allCases.map { p in
                    (p.rawValue, ctl.himPose == p, { ctl.himPose = p })
                })
                HStack {
                    Spacer()
                    Button { ctl.shoot() } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 3).frame(width: 66, height: 66)
                            Circle().fill(.white).frame(width: 54, height: 54)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .padding(.horizontal, 12)
            .padding(.bottom, 26)
        }
    }

    private func row(_ title: String, _ items: [(String, Bool, () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.app(11)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        let it = items[i]
                        Button(action: it.2) {
                            Text(it.0)
                                .font(.app(12, weight: it.1 ? .semibold : .regular))
                                .foregroundStyle(it.1 ? Color.white : Color.primary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(it.1 ? accent : Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func roundButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.app(12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
    }
}

/// 摇杆：按住拖，松手回中间
struct Joystick: View {
    @Binding var value: CGPoint
    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: radius * 2, height: radius * 2)
            Circle().stroke(.white.opacity(0.5), lineWidth: 1).frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .offset(knob)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    var t = v.translation
                    let len = sqrt(t.width * t.width + t.height * t.height)
                    if len > radius { t = CGSize(width: t.width / len * radius, height: t.height / len * radius) }
                    knob = t
                    value = CGPoint(x: t.width / radius, y: t.height / radius)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { knob = .zero }
                    value = .zero
                }
        )
    }
}
