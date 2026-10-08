import Darwin
import Foundation
import LogicMCP

// The MCP transport never writes diagnostics or child CLI output to stdout.
let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    let help = """
    logicmcp: local stdio MCP adapter (protocol 2025-11-25).
    Start with no arguments from an MCP client. Set LOGICCTL_PATH to override
    the sibling logicctl executable. Existing LOGICD_PATH/LOGICCTL_SOCKET apply.
    Tools use existing logicctl commands and preserve their readback results.
    """
    FileHandle.standardError.write(Data((help + "\n").utf8))
    exit(arguments == ["--help"] || arguments == ["-h"] ? 0 : 64)
}

let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
    .resolvingSymlinksInPath()
let cliURL = ProcessInfo.processInfo.environment["LOGICCTL_PATH"].map { URL(fileURLWithPath: $0) }
    ?? executable.deletingLastPathComponent().appendingPathComponent("logicctl")
let executor = CLIExecutor(executableURL: cliURL)
let server = MCPServer(execute: executor.execute)

func emit(_ line: String?) {
    guard let line else { return }
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

// Bound unfinished messages too; readLine() would allocate without a limit.
let maximumLineBytes = 1_048_576
var buffer = Data()
var droppingOversizedLine = false
while true {
    // A single POSIX read returns when a pipe has bytes available. Foundation's
    // read(upToCount:) may wait for the full count or EOF on an open MCP pipe.
    var bytes = [UInt8](repeating: 0, count: 4096)
    let count = bytes.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
    if count < 0 {
        if errno == EINTR { continue }
        FileHandle.standardError.write(Data("logicmcp: stdin read failed: \(String(cString: strerror(errno)))\n".utf8))
        exit(1)
    }
    if count == 0 { break }
    for byte in bytes.prefix(count) {
        if byte == 0x0a {
            if !droppingOversizedLine {
                if let line = String(data: buffer, encoding: .utf8) { emit(server.handleLine(line)) }
                else { emit(server.handleLine("invalid UTF-8")) }
            }
            buffer.removeAll(keepingCapacity: true)
            droppingOversizedLine = false
        } else if !droppingOversizedLine {
            buffer.append(byte)
            if buffer.count > maximumLineBytes {
                emit("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Message exceeds 1 MiB\"}}")
                buffer.removeAll(keepingCapacity: true)
                droppingOversizedLine = true
            }
        }
    }
}
if !buffer.isEmpty {
    emit("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Unterminated message\"}}")
}
