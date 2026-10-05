import Compression
import Foundation

// Logic Remote application frames, read from MACore 12.3.1 (6682):
// MAPeerRouter processReceivedData:fromPeer: (decode), the serializer at 0x000f98c8
// (encode) and NSData maUncompressedData / maCompressedDataWithCompressionLevel:.
// Read by static analysis (Research/static-analysis/SA-REMOTE-FRAME-001.md) and checked once against a
// real reception (EXP-REMOTE-001, 2026-10-05: all 5,947 frames from Logic decoded). One reception of one
// project is not proof for every message Logic can send; the test fixtures are still synthetic.
//
//   frame       = tag payload
//   tag         = bit 7: payload is a MAZP container;  bits 0-6: 1 plist, 4 JSON, other = keyed archive (writer uses 2)
//   MAZP        = "MAZP" u16be header_length u32be uncompressed_length zlib_stream(at header_length)
//   decoded     = dictionary {address: argument}  |  array of such dictionaries (ordered batch)

/// A decoded argument. Dictionary keys keep their type because a keyed archive may use numbers.
public indirect enum RemoteValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case url(String)
    case indexPath([Int])
    case array([RemoteValue])
    /// Entries are sorted by key so equal dictionaries are equal: Logic does not define a key order.
    case dictionary([RemoteEntry])
}

public struct RemoteEntry: Equatable, Sendable {
    public var key: RemoteValue
    public var value: RemoteValue
    public init(key: RemoteValue, value: RemoteValue) { self.key = key; self.value = value }
}

public struct RemoteMessage: Equatable, Sendable {
    public var address: String
    public var argument: RemoteValue
    public init(address: String, argument: RemoteValue) { self.address = address; self.argument = argument }
}

public struct RemoteFrame: Equatable, Sendable {
    public enum Format: Equatable, Sendable { case propertyList, json, keyedArchive }
    public enum Container: Equatable, Sendable {
        case plain
        /// A MAZP container that inflated to exactly `declaredSize` bytes.
        case mazp(declaredSize: Int)
        /// Bit 7 set but the payload does not start with "MAZP": Logic passes it through unchanged.
        case flaggedWithoutHeader
    }

    public var format: Format
    public var container: Container
    /// True when the top level was an array: the groups keep the sender's order.
    /// Within one group (one dictionary) the order of messages is not defined.
    public var ordered: Bool
    public var groups: [[RemoteMessage]]
    public var messages: [RemoteMessage] { groups.flatMap { $0 } }
}

public enum RemoteFrameError: Error, Equatable, Sendable {
    case empty
    case tooLarge(Int)
    /// A tag whose low 7 bits are not 1, 2 or 4. Logic would hand any such value to the keyed unarchiver.
    case unknownFormat(UInt8)
    case truncatedContainer
    case badContainerHeader
    case declaredSizeTooLarge(Int)
    case decompressionFailed
    case sizeMismatch(declared: Int, actual: Int)
    case decodeFailed(String)
    case tooDeep
    case unsupportedType(String)
    case unexpectedTopLevel
    case arrayElementNotDictionary(index: Int)
    case nonStringAddress(RemoteValue)
}

public struct RemoteFrameLimits: Sendable {
    public var maxFrameBytes = 16 << 20
    /// Logic's own decoder has no upper bound on the declared size; a parser must.
    public var maxUncompressedBytes = 16 << 20
    public var maxDepth = 32
    public static let `default` = RemoteFrameLimits()
    public init() {}
}

public enum RemoteFrameParser {
    public static func decode(_ frame: Data, limits: RemoteFrameLimits = .default) -> Result<RemoteFrame, RemoteFrameError> {
        do { return .success(try decodeOrThrow(frame, limits: limits)) } catch let e as RemoteFrameError { return .failure(e) }
        catch { return .failure(.decodeFailed("\(error)")) }
    }

    static func decodeOrThrow(_ frame: Data, limits: RemoteFrameLimits) throws -> RemoteFrame {
        let bytes = Data(frame)  // rebase indices to 0
        guard let tag = bytes.first else { throw RemoteFrameError.empty }
        guard bytes.count <= limits.maxFrameBytes else { throw RemoteFrameError.tooLarge(bytes.count) }
        let compressed = tag & 0x80 != 0
        let format: RemoteFrame.Format
        switch tag & 0x7F {
        case 1: format = .propertyList
        case 4: format = .json
        case 2: format = .keyedArchive
        default: throw RemoteFrameError.unknownFormat(tag & 0x7F)
        }

        var payload = Data(bytes.dropFirst())
        var container = RemoteFrame.Container.plain
        if compressed {
            guard payload.count >= 10 else { throw RemoteFrameError.truncatedContainer }
            if payload.prefix(4) == Data("MAZP".utf8) {
                let headerLength = Int(payload[4]) << 8 | Int(payload[5])
                let declared = Int(payload[6]) << 24 | Int(payload[7]) << 16 | Int(payload[8]) << 8 | Int(payload[9])
                guard headerLength >= 10, headerLength <= payload.count else { throw RemoteFrameError.badContainerHeader }
                guard declared <= limits.maxUncompressedBytes else { throw RemoteFrameError.declaredSizeTooLarge(declared) }
                let inflated = try inflateZlib(Data(payload.dropFirst(headerLength)), expected: declared)
                payload = inflated
                container = .mazp(declaredSize: declared)
            } else {
                container = .flaggedWithoutHeader
            }
        }

        let object = try decodeObject(payload, format: format)
        let value = try convert(object, depth: 0, limits: limits)
        let (ordered, groups) = try messageGroups(value)
        return RemoteFrame(format: format, container: container, ordered: ordered, groups: groups)
    }

    // MARK: - Container

    /// zlib stream = 2-byte header, raw deflate, big-endian Adler-32. Apple's COMPRESSION_ZLIB is the raw deflate part.
    static func inflateZlib(_ stream: Data, expected: Int) throws -> Data {
        guard stream.count >= 6 else { throw RemoteFrameError.decompressionFailed }
        let cmf = Int(stream[0]), flg = Int(stream[1])
        guard cmf & 0x0F == 8, cmf >> 4 <= 7, (cmf << 8 | flg) % 31 == 0, flg & 0x20 == 0 else {
            throw RemoteFrameError.decompressionFailed
        }
        let raw = Data(stream.dropFirst(2).dropLast(4))
        let adler = UInt32(stream[stream.count - 4]) << 24 | UInt32(stream[stream.count - 3]) << 16
            | UInt32(stream[stream.count - 2]) << 8 | UInt32(stream[stream.count - 1])
        var out = Data(count: expected + 1)  // one spare byte shows a stream that is longer than declared
        let written = out.withUnsafeMutableBytes { dst in
            raw.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, expected + 1,
                                          src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 || expected == 0 else { throw RemoteFrameError.decompressionFailed }
        guard written == expected else { throw RemoteFrameError.sizeMismatch(declared: expected, actual: written) }
        out.removeLast(out.count - written)
        guard adler32(out) == adler else { throw RemoteFrameError.decompressionFailed }
        return out
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        return b << 16 | a
    }

    // MARK: - Objects

    private static func decodeObject(_ payload: Data, format: RemoteFrame.Format) throws -> Any {
        do {
            switch format {
            case .propertyList:
                return try PropertyListSerialization.propertyList(from: payload, options: [], format: nil)
            case .json:
                return try JSONSerialization.jsonObject(with: payload, options: [])
            case .keyedArchive:
                let classes: [AnyClass] = [NSDictionary.self, NSString.self, NSURL.self, NSNumber.self,
                                           NSArray.self, NSIndexPath.self, NSData.self]
                guard let object = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: payload) else {
                    throw RemoteFrameError.decodeFailed("empty archive")
                }
                return object
            }
        } catch let error as RemoteFrameError {
            throw error
        } catch {
            throw RemoteFrameError.decodeFailed((error as NSError).localizedDescription)
        }
    }

    private static func convert(_ any: Any, depth: Int, limits: RemoteFrameLimits) throws -> RemoteValue {
        guard depth <= limits.maxDepth else { throw RemoteFrameError.tooDeep }
        if any is NSNull { return .null }
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            switch CFNumberGetType(number) {
            case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
                return .double(number.doubleValue)
            default:
                guard number.uint64Value <= UInt64(Int.max) || number.int64Value < 0 else {
                    throw RemoteFrameError.unsupportedType("integer above Int.max")
                }
                return .int(number.intValue)
            }
        }
        if let string = any as? String { return .string(string) }
        if let data = any as? Data { return .data(data) }
        if let url = any as? URL { return .url(url.absoluteString) }
        if let path = any as? IndexPath { return .indexPath(path.map { $0 }) }
        if let array = any as? [Any] { return .array(try array.map { try convert($0, depth: depth + 1, limits: limits) }) }
        if let dictionary = any as? [AnyHashable: Any] {
            let entries = try dictionary.map { key, value in
                RemoteEntry(key: try convert(key, depth: depth + 1, limits: limits),
                            value: try convert(value, depth: depth + 1, limits: limits))
            }
            return .dictionary(entries.sorted { RemoteValue.keyOrder($0.key, $1.key) })
        }
        throw RemoteFrameError.unsupportedType(String(describing: type(of: any)))
    }

    private static func messageGroups(_ value: RemoteValue) throws -> (ordered: Bool, groups: [[RemoteMessage]]) {
        func group(_ entries: [RemoteEntry]) throws -> [RemoteMessage] {
            try entries.map { entry in
                guard case .string(let address) = entry.key else { throw RemoteFrameError.nonStringAddress(entry.key) }
                return RemoteMessage(address: address, argument: entry.value)
            }
        }
        switch value {
        case .dictionary(let entries):
            return (false, [try group(entries)])
        case .array(let elements):
            var groups: [[RemoteMessage]] = []
            for (index, element) in elements.enumerated() {
                guard case .dictionary(let entries) = element else {
                    throw RemoteFrameError.arrayElementNotDictionary(index: index)
                }
                groups.append(try group(entries))
            }
            return (true, groups)
        default:
            throw RemoteFrameError.unexpectedTopLevel
        }
    }
}

extension RemoteValue {
    /// Orders dictionary keys deterministically: numbers (by value), then strings, then anything else.
    fileprivate static func keyOrder(_ a: RemoteValue, _ b: RemoteValue) -> Bool {
        switch (a, b) {
        case (.int(let x), .int(let y)): return x < y
        case (.string(let x), .string(let y)): return x < y
        case (.int, _): return true
        case (_, .int): return false
        case (.string, _): return true
        case (_, .string): return false
        default: return "\(a)" < "\(b)"
        }
    }
}
