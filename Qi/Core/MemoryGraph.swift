import Foundation
import SwiftUI

// MARK: - 记忆星图：这些事之间是怎么连着的
//
// 出处：ClaraShafiq/MemoryConstellations。它把记忆库画成一张星图——
// 几个主题星系绕着「你和他」这个核心，点一颗星看它牵着哪些事，
// 星系之间的桥就是共享的记忆。
//
// **它自己文档里写着：星图目前只有桌面端，手机端还没做。**
// 而我们的记忆库本来就长在手机上，所以这一版是原生的。
//
// ## 为什么值得画
//
// 记忆库现在只能**搜**。搜的前提是她已经知道要搜什么——
// 可她想看的常常是另一件事：**「日本」这条线上都牵着些什么」**。
// 那不是一次检索，那是一张图。
//
// ## 全是算的，一分钱不花
//
// 星星＝实体（`MemoryItem.entities`，本来就在，抠实体那步也不调模型）。
// 连线＝两个实体**在同一条记忆里出现过**。
// 星系＝这个实体最常出现在哪个标签底下——**分类从她自己标的 tag 里长出来**，
// 比我硬塞五个「社交／地点／事件」的类目诚实得多。

struct StarNode: Identifiable, Hashable {
    var id: String { name }
    let name: String
    /// 出现在多少条记忆里。星星的大小看它。
    let weight: Int
    /// 归在哪个星系（就是她自己的 tag）
    let galaxy: String
    /// 在屏幕上的位置，0~1 的比例
    var x: Double = 0.5
    var y: Double = 0.5
}

struct StarEdge: Hashable {
    let a: String
    let b: String
    /// 一起出现过几次。线的深浅看它。
    let times: Int
}

struct MemoryGraph {
    var nodes: [StarNode] = []
    var edges: [StarEdge] = []
    /// 星系名 → 那一团的中心，画标题用
    var galaxies: [(name: String, x: Double, y: Double)] = []
}

// MARK: - 从记忆里把图算出来

enum MemoryMap {

    /// 一张图最多摆这么多颗星。
    ///
    /// 多了就成了一团糊。她要看的是「这条线上牵着谁」，
    /// **不是「我一共记过多少东西」**——那个数在记忆库首页就有。
    static let maxStars = 44

    /// 一颗星至少要出现在这么多条记忆里才上图。
    /// 只出现过一次的实体多半是抠错的（引号里随手一个词），
    /// 摆上去只会让图变脏。
    static let minWeight = 2

    static func build(_ memories: [MemoryItem]) -> MemoryGraph {
        // 只看现在还成立的。作废的那些是「那会儿是真的」，
        // 摆在图上会让她以为现在还是那样。
        let live = memories.filter { $0.isLive }

        // ① 每个实体出现在几条记忆里 + 它常跟哪个 tag 一起出现
        var weight: [String: Int] = [:]
        var tagVotes: [String: [String: Int]] = [:]
        for m in live {
            let ents = Set(m.entities ?? [])
            for e in ents {
                weight[e, default: 0] += 1
                for t in m.tags {
                    tagVotes[e, default: [:]][t, default: 0] += 1
                }
            }
        }

        // ② 挑上图的那些
        let picked = weight
            .filter { $0.value >= minWeight }
            .sorted { $0.value > $1.value }
            .prefix(maxStars)
        let names = Set(picked.map { $0.key })
        guard !names.isEmpty else { return MemoryGraph() }

        // ③ 共现：同一条记忆里出现过的两个，连一条
        var pairs: [String: Int] = [:]
        for m in live {
            let ents = (m.entities ?? []).filter { names.contains($0) }.sorted()
            guard ents.count >= 2 else { continue }
            for i in 0..<ents.count {
                for j in (i + 1)..<ents.count {
                    pairs[ents[i] + "@" + ents[j], default: 0] += 1
                }
            }
        }

        // ④ 归星系：这个实体最常出现在哪个 tag 底下
        func galaxy(of name: String) -> String {
            guard let votes = tagVotes[name],
                  let top = votes.max(by: { $0.value < $1.value })?.key,
                  !top.isEmpty else { return "散落" }
            return top
        }

        var byGalaxy: [String: [(String, Int)]] = [:]
        for (name, w) in picked {
            byGalaxy[galaxy(of: name), default: []].append((name, w))
        }
        // 星系按大小排，大的排前面——**顺序要稳**，
        // 不然每次进来整张图都在转，看着像坏了
        let order = byGalaxy.keys.sorted {
            let a = byGalaxy[$0]?.count ?? 0, b = byGalaxy[$1]?.count ?? 0
            return a != b ? a > b : $0 < $1
        }

        // ⑤ 摆位置。
        //
        // 不做力导向：那东西每次跑出来都不一样，她今天记住的位置明天就没了。
        // 改成**算出来的**：星系绕着中心排一圈，星星再绕着自己的星系排一圈。
        // **同一颗星永远在同一个地方**——这比「布局好看」重要得多。
        var graph = MemoryGraph()
        let gCount = max(1, order.count)
        for (gi, gname) in order.enumerated() {
            let ga = Double(gi) / Double(gCount) * 2 * .pi - .pi / 2
            // 星系离中心多远：只有一个星系时摆正中，多了就散开
            let gr = gCount == 1 ? 0.0 : 0.30
            let gx = 0.5 + cos(ga) * gr
            let gy = 0.5 + sin(ga) * gr * 0.92    // 竖着压一点，手机是长的
            graph.galaxies.append((gname, gx, gy))

            let stars = (byGalaxy[gname] ?? []).sorted { $0.1 > $1.1 }
            for (si, item) in stars.enumerated() {
                // 一圈摆满就往外再摆一圈
                let ring = si / 6
                let posInRing = si % 6
                let angle = Double(posInRing) / 6 * 2 * .pi + Double(gi) * 0.7
                let radius = stars.count == 1 ? 0 : 0.075 + Double(ring) * 0.055
                var n = StarNode(name: item.0, weight: item.1, galaxy: gname)
                n.x = min(0.94, max(0.06, gx + cos(angle) * radius))
                n.y = min(0.94, max(0.06, gy + sin(angle) * radius * 0.92))
                graph.nodes.append(n)
            }
        }

        graph.edges = pairs.compactMap { key, times in
            let parts = key.components(separatedBy: "@")
            guard parts.count == 2 else { return nil }
            return StarEdge(a: parts[0], b: parts[1], times: times)
        }
        .sorted { $0.times > $1.times }
        return graph
    }
}
