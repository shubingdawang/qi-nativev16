import Foundation

/// MCP 的工具参数结构是服务器现给的，事先不知道长什么样，
/// 所以需要一个能装下任意 JSON 的类型。
enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// 转成 JSONSerialization 能用的普通对象
    var rawValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .number(let v): return v == v.rounded() && abs(v) < 1e15 ? Int(v) : v
        case .string(let v): return v
        case .array(let v): return v.map { $0.rawValue }
        case .object(let v): return v.mapValues { $0.rawValue }
        }
    }

    /// 从 JSONSerialization 解出来的普通对象转过来
    static func make(_ any: Any?) -> JSONValue {
        guard let any, !(any is NSNull) else { return .null }
        if let v = any as? Bool, (any as? NSNumber)?.objCType.pointee == 0x63 { return .bool(v) }
        if let v = any as? NSNumber {
            if CFGetTypeID(v) == CFBooleanGetTypeID() { return .bool(v.boolValue) }
            return .number(v.doubleValue)
        }
        if let v = any as? String { return .string(v) }
        if let v = any as? [Any] { return .array(v.map { JSONValue.make($0) }) }
        if let v = any as? [String: Any] { return .object(v.mapValues { JSONValue.make($0) }) }
        return .null
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    /// 压成一行文本，给模型看的
    var compactText: String {
        if case .string(let s) = self { return s }
        guard let data = try? JSONSerialization.data(withJSONObject: rawValue),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
}
