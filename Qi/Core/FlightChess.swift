import Foundation

// MARK: - 一副棋盘

/// 一格
struct FCCell: Codable, Hashable {
    var text: String = ""
    /// 停在这儿要往回退几格（「后进 3 格」）
    var back: Int = 0
    /// 停在这儿直接跳到第几格（「退回到 40 格」）
    var jumpTo: Int? = nil

    init(text: String = "", back: Int = 0, jumpTo: Int? = nil) {
        self.text = text; self.back = back; self.jumpTo = jumpTo
    }

    /// 容错解码：这一串挂在棋盘上，棋盘又是 `try? … ?? []` 接住的。
    /// 以后多一个字段不补这儿的话，**她导进来的整副棋盘会一起消失**。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        back = (try? c.decodeIfPresent(Int.self, forKey: .back)) ?? 0
        jumpTo = try? c.decodeIfPresent(Int.self, forKey: .jumpTo)
    }
}

/// 一副棋盘（一个版本）
struct FCBoard: Codable, Hashable, Identifiable {
    var id: String = ""
    var name: String = ""
    var cells: [FCCell] = []
    /// 谁接受格子里写的那件事：
    /// `lander` 谁停谁接受（默认）／`her` 永远是她／`him` 永远是他。
    /// 这是**规则**不是内容，所以按版本的 key 认（女仆·SM → 她，男仆 → 他）。
    var receiver: String = "lander"

    init(id: String = "", name: String = "", cells: [FCCell] = [],
         receiver: String = "lander") {
        self.id = id; self.name = name; self.cells = cells; self.receiver = receiver
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        cells = (try? c.decodeIfPresent([FCCell].self, forKey: .cells)) ?? []
        receiver = (try? c.decodeIfPresent(String.self, forKey: .receiver)) ?? "lander"
    }
}

// MARK: - 棋盘是导进来的，不是写死在这儿的

/// 从一份 `index.html`（或者一段 JSON）里把棋盘抠出来。
///
/// **为什么棋盘不写死在代码里**：
/// 一，那些格子写的是他们俩之间的事，该由她定，不该由我替她写死；
/// 二，九副 × 五十格塞进 Swift 就再也改不动了——
/// 她想加一格、改一句、删掉一版，都得等下一次构建。
/// 导进来的存成 JSON，她随时能重导一份。
enum FCImporter {

    /// 认 `lili0926/player` 那份 `index.html` 里的 `const BOARDS = {...}`
    static func boards(fromHTML html: String) -> [FCBoard] {
        var out: [FCBoard] = []
        let pattern = #"(\w+)\s*:\s*\{\s*name\s*:\s*'([^']*)'\s*,\s*cells\s*:\s*makeCells\(\s*\[(.*?)\]\s*\)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return [] }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard m.numberOfRanges >= 4 else { continue }
            let key = ns.substring(with: m.range(at: 1))
            let name = ns.substring(with: m.range(at: 2))
            let body = ns.substring(with: m.range(at: 3))
            let cells = quoted(in: body).map { cell($0) }
            guard cells.count > 2 else { continue }
            out.append(FCBoard(id: key, name: name, cells: cells,
                               receiver: receiverRule(for: key)))
        }
        return out
    }

    /// 也认一份自己写的 JSON：`[{"id","name","receiver","cells":["起点", …]}]`
    static func boards(fromJSON text: String) -> [FCBoard] {
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { one in
            guard let list = one["cells"] as? [String], list.count > 2 else { return nil }
            let key = (one["id"] as? String) ?? UUID().uuidString.prefix(6).lowercased()
            return FCBoard(id: String(key),
                           name: (one["name"] as? String) ?? "没名字的一副",
                           cells: list.map { cell($0) },
                           receiver: (one["receiver"] as? String) ?? receiverRule(for: String(key)))
        }
    }

    /// 一格里写着「后进 N 格」「退回到 N 格」的话，把数字读出来。
    /// 这是走法，不是内容——照原版那份 `makeCells` 一模一样。
    static func cell(_ text: String) -> FCCell {
        var c = FCCell(text: text)
        if let n = number(in: text, pattern: #"后进\s*(\d+)\s*格"#) { c.back = n }
        else if let n = number(in: text, pattern: #"退回(?:到)?\s*(\d+)\s*格"#) { c.jumpTo = n }
        return c
    }

    /// 谁接受。README 里定死的三条，照抄。
    static func receiverRule(for key: String) -> String {
        switch key {
        case "maid", "sm": return "her"
        case "butler":     return "him"
        default:           return "lander"
        }
    }

    private static func number(in text: String, pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }

    /// 把 `'…'` 里的东西一条条取出来
    private static func quoted(in body: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inside = false
        var escaped = false
        for ch in body {
            if escaped { cur.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "'" {
                if inside {
                    let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { out.append(t) }
                    cur = ""
                }
                inside.toggle()
                continue
            }
            if inside { cur.append(ch) }
        }
        return out
    }
}

// MARK: - 一局

/// 飞行棋。**纯算术**：掷骰、走格、判停。不联网、不调模型、不花钱。
///
/// 照她给的 `lili0926/player` 那份 README 的规则做的：
///
/// 1. **停下才生效** —— 只有停在格子上才触发，路过不触发。
/// 2. **后进 / 退回** —— 「后进 X 格」真的往回走；「退回到 N 格」跳到第 N 格。
/// 3. **谁接受** —— 见 `FCBoard.receiver`。
/// 4. 「互相／一起／双方」按字面**两个人一起做**，不是各罚一次——
///    这句写进给他的提示里了，他容易理解偏。
/// 5. 她那一掷在 App 里按按钮；他那一掷他自己调工具。
///
/// 安全词 **404**：谁说都立刻停，不问理由。跟大富翁同一条。
@MainActor
final class FlightChess: ObservableObject {

    static let shared = FlightChess()

    struct State: Codable {
        var boardID: String = ""
        var herPos: Int = 0
        var himPos: Int = 0
        /// 轮到谁：`her` / `him`
        var turn: String = "her"
        var stopped: Bool = false
        var finished: Bool = false
        /// 最近这一下的事件（给他看的）
        var lastEvent: FCEvent? = nil
        var startedAt: Date? = nil

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            boardID = (try? c.decodeIfPresent(String.self, forKey: .boardID)) ?? ""
            herPos = (try? c.decodeIfPresent(Int.self, forKey: .herPos)) ?? 0
            himPos = (try? c.decodeIfPresent(Int.self, forKey: .himPos)) ?? 0
            turn = (try? c.decodeIfPresent(String.self, forKey: .turn)) ?? "her"
            stopped = (try? c.decodeIfPresent(Bool.self, forKey: .stopped)) ?? false
            finished = (try? c.decodeIfPresent(Bool.self, forKey: .finished)) ?? false
            lastEvent = try? c.decodeIfPresent(FCEvent.self, forKey: .lastEvent)
            startedAt = try? c.decodeIfPresent(Date.self, forKey: .startedAt)
        }
    }

    @Published private(set) var boards: [FCBoard] = []
    @Published private(set) var state = State()

    private init() {
        boards = Storage.load([FCBoard].self, from: "flight-boards.json") ?? []
        state = Storage.load(State.self, from: "flight-chess.json") ?? State()
    }

    // MARK: 存

    private func saveBoards() { Storage.save(boards, to: "flight-boards.json") }
    private func saveState() { Storage.save(state, to: "flight-chess.json") }

    var board: FCBoard? {
        boards.first { $0.id == state.boardID } ?? boards.first
    }

    var hasBoards: Bool { !boards.isEmpty }

    /// 导进来一批棋盘。**同名的顶掉旧的**，别的留着。
    @discardableResult
    func importBoards(_ list: [FCBoard]) -> Int {
        guard !list.isEmpty else { return 0 }
        for b in list {
            if let i = boards.firstIndex(where: { $0.id == b.id }) { boards[i] = b }
            else { boards.append(b) }
        }
        if state.boardID.isEmpty { state.boardID = boards.first?.id ?? "" }
        saveBoards(); saveState()
        return list.count
    }

    func removeBoard(_ id: String) {
        boards.removeAll { $0.id == id }
        if state.boardID == id { newGame(boardID: boards.first?.id ?? "") }
        saveBoards()
    }

    // MARK: 开局

    func newGame(boardID: String) {
        var s = State()
        s.boardID = boardID
        s.startedAt = Date()
        state = s
        saveState()
    }

    func stop() {
        state.stopped = true
        saveState()
    }

    // MARK: 掷

    /// 掷一次。`who` 是 `her` / `him`；不传就是轮到谁谁掷。
    /// 返回 nil = 这一下没掷成（没棋盘、停了、走完了、或者不是他的回合）。
    @discardableResult
    func roll(who: String? = nil, dice: Int? = nil) -> FCEvent? {
        guard let b = board, b.cells.count > 1 else { return nil }
        guard !state.stopped, !state.finished else { return nil }
        let side = who ?? state.turn
        guard side == state.turn else { return nil }

        let d = dice ?? Int.random(in: 1...6)
        let last = b.cells.count - 1
        // 走过终点就停在终点（不折返，原版没写折返那一套）
        let landed = min((side == "her" ? state.herPos : state.himPos) + d, last)
        var pos = landed

        // **停下才生效**：先落地，再看落的这一格让不让你留在这儿。
        // ⚠️ 终点那一格不再触发后退——不然永远走不完。
        let landCell = b.cells[landed]
        var note = ""
        if landed < last {
            if let jump = landCell.jumpTo {
                // 原版的格号是**从 0 数的**（起点＝第 0 格），
                // 「退回到 40 格」就是下标 40，不减一
                pos = max(0, min(last, jump))
                note = "（已经退回到第 \(pos) 格）"
            } else if landCell.back > 0 {
                pos = max(0, landed - landCell.back)
                note = "（已经后退 \(landCell.back) 格，现在在第 \(pos) 格）"
            }
        }

        if side == "her" { state.herPos = pos } else { state.himPos = pos }
        state.turn = side == "her" ? "him" : "her"
        if pos >= last { state.finished = true }

        // **格子原文取的是「落在哪一格」那一格**，不是退完之后那一格——
        // 退回本身就是这一格的效果，退到的地方不再触发一次
        let ev = FCEvent(
            at: Date(),
            lander: side,
            receiver: receiver(for: side, board: b),
            dice: d,
            pos: pos,
            landed: landed,
            note: note,
            total: b.cells.count,
            text: landCell.text,
            boardName: b.name,
            finished: state.finished
        )
        state.lastEvent = ev
        saveState()
        return ev
    }

    private func receiver(for lander: String, board: FCBoard) -> String {
        switch board.receiver {
        case "her": return "her"
        case "him": return "him"
        default:    return lander
        }
    }

    // MARK: 说给他听

    /// 给他的那一段。照原版 `injectPrompt` 的意思写：
    /// **骰子已经掷完了**，谁停的、谁接受、格子原文是什么——
    /// 并且明说不要再提掷骰这件事（不写这句他会再掷一遍，或者写一段掷骰代码）。
    func brief(_ ev: FCEvent, herName: String, himName: String) -> String {
        let landerName = ev.lander == "her" ? herName : himName
        var out = "【飞行棋 · 骰子已经掷完了】\n"
        out += "这一副：\(ev.boardName)。\(landerName)掷出 \(ev.dice)，"
        out += "停在第 \(ev.landed) 格（这一副一共到第 \(ev.total - 1) 格）。\n"
        out += "格子上写的是：「\(ev.text)」\n"
        if !ev.note.isEmpty { out += ev.note + "\n" }

        if ev.text.contains("互相") || ev.text.contains("一起") || ev.text.contains("双方") {
            out += "这一格写着互相／一起——**两个人一起做这一件事**，"
            out += "不是各自受一遍。\n"
        } else {
            let who = ev.receiver == "her" ? herName : himName
            out += "接受这一格的是：\(who)。\n"
        }
        if ev.finished {
            out += "这是终点，这一局走完了。\n"
        } else {
            let next = ev.lander == "her" ? himName : herName
            out += "下一个轮到 \(next)。\n"
        }
        out += "骰子和走格都已经算完了，**别再提掷骰、也别写掷骰的代码**，"
        out += "直接按格子上写的接着往下。她随时说 **404** 就立刻停。"
        return out
    }

    /// 现在什么局面
    func status(herName: String, himName: String) -> String {
        guard let b = board, !b.cells.isEmpty else {
            return "还没有棋盘。让她去「游戏 → 飞行棋」导一副进来（她手上有那份文件）。"
        }
        if state.stopped { return "这一局已经停了（404）。" }
        var out = "【飞行棋】这一副：\(b.name)，从第 0 格走到第 \(b.cells.count - 1) 格。\n"
        out += "\(herName)：第 \(state.herPos) 格　\(himName)：第 \(state.himPos) 格\n"
        out += state.finished
            ? "已经有人到终点了，这一局结束。"
            : "轮到 \(state.turn == "her" ? herName : himName)。"
        if state.turn == "him", !state.finished {
            out += "\n轮到你了：调 `flight_chess` 的 `roll` 掷一次。"
        }
        return out
    }
}

/// 掷出来那一下
struct FCEvent: Codable, Hashable {
    var at: Date = Date()
    /// 谁停在这一格：`her` / `him`
    var lander: String = "her"
    /// 谁接受这一格
    var receiver: String = "her"
    var dice: Int = 0
    /// 这一下走完之后人在哪一格（后退／退回之后的位置）
    var pos: Int = 0
    /// **落在**哪一格。格子上那句话是这一格的。
    var landed: Int = 0
    /// 「已经后退 3 格」这种话，没有就是空的
    var note: String = ""
    var total: Int = 0
    var text: String = ""
    var boardName: String = ""
    var finished: Bool = false

    init(at: Date = Date(), lander: String = "her", receiver: String = "her",
         dice: Int = 0, pos: Int = 0, landed: Int = 0, note: String = "",
         total: Int = 0, text: String = "", boardName: String = "",
         finished: Bool = false) {
        self.at = at; self.lander = lander; self.receiver = receiver
        self.dice = dice; self.pos = pos; self.landed = landed; self.note = note
        self.total = total
        self.text = text; self.boardName = boardName; self.finished = finished
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
        lander = (try? c.decodeIfPresent(String.self, forKey: .lander)) ?? "her"
        receiver = (try? c.decodeIfPresent(String.self, forKey: .receiver)) ?? "her"
        dice = (try? c.decodeIfPresent(Int.self, forKey: .dice)) ?? 0
        pos = (try? c.decodeIfPresent(Int.self, forKey: .pos)) ?? 0
        landed = (try? c.decodeIfPresent(Int.self, forKey: .landed)) ?? 0
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        boardName = (try? c.decodeIfPresent(String.self, forKey: .boardName)) ?? ""
        finished = (try? c.decodeIfPresent(Bool.self, forKey: .finished)) ?? false
    }
}
