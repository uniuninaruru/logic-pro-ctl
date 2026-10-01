import Foundation
import LogicCore

// Placeholder: prints the request that would be sent to logicd.
// Socket transport is added once Phase A research is done.
let argv = Array(CommandLine.arguments.dropFirst())
guard let command = argv.first else {
    FileHandle.standardError.write("usage: logicctl <command> [key=value ...]\n".data(using: .utf8)!)
    exit(64)
}

var args: [String: String] = [:]
for pair in argv.dropFirst() {
    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
    if parts.count == 2 { args[parts[0]] = parts[1] }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(Request(command: command, args: args))
print(String(decoding: data, as: UTF8.self))
