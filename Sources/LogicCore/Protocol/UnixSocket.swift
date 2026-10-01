import Darwin
import Foundation

public enum SocketError: Error, CustomStringConvertible {
    case pathTooLong(String)
    case system(String, Int32)
    case closed

    public var description: String {
        switch self {
        case .pathTooLong(let p): return "ソケットのパスが長すぎます: \(p)"
        case .system(let call, let err): return "\(call) に失敗しました: \(String(cString: strerror(err)))"
        case .closed: return "接続が閉じられました"
        }
    }
}

/// A connected stream socket carrying newline-delimited JSON.
public final class LineSocket {
    public let fd: Int32
    private var buffer = [UInt8]()

    public init(fd: Int32) { self.fd = fd }
    deinit { close(fd) }

    public static func connect(path: String) throws -> LineSocket {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }
        var addr = try makeAddress(path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let err = errno
            close(fd)
            throw SocketError.system("connect", err)
        }
        return LineSocket(fd: fd)
    }

    /// Reads one line (without the newline). Throws `.closed` at EOF.
    public func readLine() throws -> String {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            if n < 0 { throw SocketError.system("read", errno) }
            if n == 0 { throw SocketError.closed }
            buffer.append(contentsOf: chunk[..<n])
        }
    }

    public func writeLine(_ line: String) throws {
        var bytes = Array(line.utf8)
        bytes.append(0x0A)
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 { throw SocketError.system("write", errno) }
            offset += n
        }
    }
}

/// Listening Unix domain socket. Removes a stale socket file before binding
/// and restricts it to the current user.
public final class SocketListener {
    public let fd: Int32
    public let path: String

    public init(path: String) throws {
        self.path = path
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }
        var addr = try makeAddress(path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { throw SocketError.system("bind", errno) }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { throw SocketError.system("listen", errno) }
    }

    deinit {
        close(fd)
        unlink(path)
    }

    public func accept() throws -> LineSocket {
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { throw SocketError.system("accept", errno) }
        return LineSocket(fd: client)
    }
}

private func makeAddress(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count < capacity else { throw SocketError.pathTooLong(path) }
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        buf.copyBytes(from: bytes)
        buf[bytes.count] = 0
    }
    return addr
}
