import Foundation

/// Turns `logicctl` argv (without the program name) into a Request.
///
/// `--json` is accepted anywhere and ignored: output is always JSON.
/// Negative numbers ("-6", "-0.25") are positional values, not flags.
public enum CLIParser {
    public static let usage = """
        usage: logicctl <command> [--json]
          status                         daemon, Logic and control-surface status
          state                          transport + all tracks
          transport play|stop
          track list
          track get <n>
          track select <n>
          track mute <n> on|off
          track solo <n> on|off
          track volume <n> <dB|-inf> [--tolerance <dB>]
          track pan <n> <-1…1>
          daemon stop
          debug mcu <hex bytes>[; <hex bytes>…]   research: raw MCU messages
        Tracks are 1-based. Every write reads the state back; "verified": true
        means the readback matched the request.
        """

    public static func parse(_ argv: [String]) throws -> Request {
        var words: [String] = []
        var options: [String: String] = [:]
        var i = 0
        while i < argv.count {
            let w = argv[i]
            if w == "--json" {
                i += 1
                continue
            }
            if w.hasPrefix("--") {
                let key = String(w.dropFirst(2))
                guard key == "tolerance" else { throw CommandError("usage", "unknown option \(w)") }
                guard i + 1 < argv.count else { throw CommandError("usage", "\(w) needs a value") }
                options[key] = argv[i + 1]
                i += 2
                continue
            }
            words.append(w)
            i += 1
        }

        func need(_ n: Int, _ form: String) throws {
            guard words.count == n else { throw CommandError("usage", "expected: logicctl \(form)") }
        }

        switch (words.first, words.dropFirst().first) {
        case ("status", _):
            try need(1, "status")
            return Request(command: "status")
        case ("state", _):
            try need(1, "state")
            return Request(command: "state")
        case ("transport", "play"), ("transport", "stop"):
            try need(2, "transport play|stop")
            return Request(command: "transport.\(words[1])")
        case ("track", "list"):
            try need(2, "track list")
            return Request(command: "track.list")
        case ("track", "get"), ("track", "select"):
            try need(3, "track \(words[1]) <n>")
            return Request(command: "track.\(words[1])", args: ["track": words[2]])
        case ("track", "mute"), ("track", "solo"):
            try need(4, "track \(words[1]) <n> on|off")
            return Request(command: "track.\(words[1])", args: ["track": words[2], "state": words[3]])
        case ("track", "volume"):
            try need(4, "track volume <n> <dB>")
            var args = ["track": words[2], "db": words[3]]
            if let t = options["tolerance"] { args["tolerance"] = t }
            return Request(command: "track.volume", args: args)
        case ("track", "pan"):
            try need(4, "track pan <n> <-1…1>")
            return Request(command: "track.pan", args: ["track": words[2], "value": words[3]])
        case ("debug", "mcu"):
            guard words.count > 2 else { throw CommandError("usage", "expected: logicctl debug mcu <hex bytes>") }
            return Request(command: "debug.mcu", args: ["messages": words.dropFirst(2).joined(separator: " ")])
        case ("daemon", "stop"):
            try need(2, "daemon stop")
            return Request(command: "daemon.stop")
        default:
            throw CommandError("usage", "unknown command: \(words.joined(separator: " "))")
        }
    }
}
