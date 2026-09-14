import Foundation

/// 在屋里绕着家具走：格子上的 A*。
///
/// 以前他从 A 点直线走到 B 点，中间隔着床就从床上穿过去。
/// 现在按地上家具占的格子（`ClawdStore.takenCells`）找一条绕开的路，
/// 再把路上能直着走通的拐点抹掉——一格一拐的路看着像机器人。
enum RoomPath {

    typealias Cell = (gx: Int, gy: Int)

    /// 从 `start` 到 `goal` 的一串拐点（不含起点，含终点）。
    /// 走不通返回 nil，外面就退回直线走。
    static func find(from start: Cell, to goal: Cell,
                     cols: Int, rows: Int, blocked: Set<String>) -> [Cell]? {
        func key(_ x: Int, _ y: Int) -> String { "\(x),\(y)" }
        func free(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < cols && y < rows
                && (!blocked.contains(key(x, y)) || (x == start.gx && y == start.gy)
                    || (x == goal.gx && y == goal.gy))
        }
        guard cols > 0, rows > 0 else { return nil }
        if start.gx == goal.gx && start.gy == goal.gy { return [goal] }

        let n = cols * rows
        func idx(_ x: Int, _ y: Int) -> Int { y * cols + x }
        var g = [Double](repeating: .infinity, count: n)
        var came = [Int](repeating: -1, count: n)
        var closed = [Bool](repeating: false, count: n)
        func h(_ x: Int, _ y: Int) -> Double {
            let dx = Double(abs(x - goal.gx)), dy = Double(abs(y - goal.gy))
            return max(dx, dy) + (2.0.squareRoot() - 1) * min(dx, dy)
        }
        // 屋子最多几百格，开放表用数组线性找最小就够了
        var open: [Int] = [idx(start.gx, start.gy)]
        g[open[0]] = 0
        let steps: [(Int, Int, Double)] = [(1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
                                           (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)]
        let target = idx(goal.gx, goal.gy)
        while !open.isEmpty {
            var bi = 0
            var best = Double.infinity
            for (i, c) in open.enumerated() {
                let f = g[c] + h(c % cols, c / cols)
                if f < best { best = f; bi = i }
            }
            let cur = open.remove(at: bi)
            if cur == target { break }
            if closed[cur] { continue }
            closed[cur] = true
            let cx = cur % cols, cy = cur / cols
            for (dx, dy, cost) in steps {
                let nx = cx + dx, ny = cy + dy
                guard free(nx, ny) else { continue }
                // 斜着走不许擦着家具的角切过去
                if dx != 0 && dy != 0 && (!free(cx + dx, cy) || !free(cx, cy + dy)) { continue }
                let ni = idx(nx, ny)
                let ng = g[cur] + cost
                if ng < g[ni] {
                    g[ni] = ng
                    came[ni] = cur
                    open.append(ni)
                }
            }
        }
        guard came[target] >= 0 else { return nil }
        var cells: [Cell] = []
        var c = target
        while c != idx(start.gx, start.gy) && c >= 0 {
            cells.append((c % cols, c / cols))
            c = came[c]
        }
        cells.reverse()
        return smooth(start: start, cells, free: free)
    }

    /// 能直线走通的就不拐
    private static func smooth(start: Cell, _ cells: [Cell],
                               free: (Int, Int) -> Bool) -> [Cell] {
        guard cells.count > 1 else { return cells }
        var out: [Cell] = []
        var from = start
        var i = 0
        while i < cells.count {
            var j = cells.count - 1
            while j > i && !clear(from, cells[j], free: free) { j -= 1 }
            out.append(cells[j])
            from = cells[j]
            i = j + 1
        }
        return out
    }

    /// 两格之间连线经过的格子都空着（按线段细采样）
    private static func clear(_ a: Cell, _ b: Cell, free: (Int, Int) -> Bool) -> Bool {
        let dx = Double(b.gx - a.gx), dy = Double(b.gy - a.gy)
        let steps = Int(max(abs(dx), abs(dy)) * 4) + 1
        for k in 0...steps {
            let t = Double(k) / Double(steps)
            // 他有身宽：左右各让出一点
            for off in [-0.3, 0.3] {
                let x = Double(a.gx) + dx * t + off
                let y = Double(a.gy) + dy * t - off
                if !free(Int(x.rounded()), Int(y.rounded())) { return false }
            }
        }
        return true
    }
}
