import Foundation

/// Turns `logicctl` argv (without the program name) into a Request.
///
/// `--json` is accepted anywhere and ignored: output is always JSON.
/// Negative numbers ("-6", "-0.25") are positional values, not flags.
public enum CLIParser {
    public static let usage = """
        使い方: logicctl <command> [--json] [--backend mcu|appleevent]
          status                         daemon・Logic・コントロールサーフェスの接続状態
          state                          再生状態と全トラック
          transport play|stop            再生・停止
          transport cycle on|off         サイクル（MCU の Cycle ボタン。LED で確認）
          transport click on|off         メトロノームのクリック（MCU の Click ボタン。LED で確認）
          track list                     チャンネルストリップの一覧
          track get <n>                  指定したストリップの状態
          track select <n>               選択
          track mute <n> on|off           ミュート
          track solo <n> on|off           ソロ
          track arm <n> on|off            録音待機（出力・Master など、待機できないストリップは確認に失敗します）
          track volume <n> <dB|-inf> [--tolerance <dB>]  音量（既定の許容差: 0.1 dB）
          track pan <n> <-1…1>           パン（左 -1、中央 0、右 1）
          daemon stop                    常駐プロセスを停止
          debug mcu <hex bytes>[; <hex bytes>…]   調査用: 生のMCUメッセージを送信
        トラック番号は1からです。操作後に状態を読み返します。
        "verified": true は、確認できた状態が要求と一致したことを表します。
        --backend appleevent は transport play|stop 専用です。状態はMCUで確認します。
        実行の安全装置（任意）:
          --idempotency-key <キー>   同じ操作の再送を1回の実行にまとめる（状態を変更するコマンドのみ）
          --expect-session <世代>    読み取りの observation.session.handshake_generation と一致するときだけ実行
          --expect-name <名前>       表示中のトラック名が一致するときだけ実行（track list が返した name をそのまま指定。
                                     track get|select|mute|solo|arm|volume|pan で使えます）
          --deadline-ms <ミリ秒>     待ち時間と実行の上限（既定 30000）
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
                guard ["tolerance", "backend", "idempotency-key", "expect-session", "deadline-ms", "expect-name"].contains(key) else {
                    throw CommandError("usage", "不明なオプションです: \(w)")
                }
                guard options[key] == nil else { throw CommandError("usage", "同じオプションは1回だけ指定してください: \(w)") }
                guard i + 1 < argv.count else { throw CommandError("usage", "\(w) の値を指定してください") }
                guard !argv[i + 1].hasPrefix("--") else {
                    throw CommandError("usage", "\(w) の値を指定してください")
                }
                options[key] = argv[i + 1]
                i += 2
                continue
            }
            words.append(w)
            i += 1
        }

        func need(_ n: Int, _ form: String) throws {
            guard words.count == n else { throw CommandError("usage", "使い方: logicctl \(form)") }
        }

        let backend = options["backend"]
        if let backend, backend != BackendKind.mcu.rawValue && backend != BackendKind.appleEvent.rawValue {
            throw CommandError("usage", "経路 \(backend) は使えません。mcu または appleevent を指定してください")
        }
        if backend == BackendKind.appleEvent.rawValue &&
            !(words.count == 2 && words[0] == "transport" && ["play", "stop"].contains(words[1])) {
            throw CommandError("usage", "--backend appleevent は transport play|stop で使えます")
        }
        if options["tolerance"] != nil && !(words.count >= 2 && words[0] == "track" && words[1] == "volume") {
            throw CommandError("usage", "--tolerance は track volume で使えます")
        }
        if let tolerance = options["tolerance"] {
            guard let value = Double(tolerance), value.isFinite, value >= 0 else {
                throw CommandError("usage", "--tolerance は0以上の有限の数で指定してください")
            }
        }

        func positiveInt(_ name: String) throws -> Int? {
            guard let text = options[name] else { return nil }
            guard let value = Int(text), value > 0 else {
                throw CommandError("usage", "--\(name) は1以上の整数で指定してください")
            }
            return value
        }
        let expectSession = try positiveInt("expect-session")
        let deadlineMs = try positiveInt("deadline-ms")
        let idempotencyKey = options["idempotency-key"]
        if let key = idempotencyKey, !WriteExecutor.isValidKey(key) {
            throw CommandError("usage", "--idempotency-key は英数字と . _ : - の1〜128文字で指定してください")
        }

        func request(_ command: String, args: [String: String] = [:]) throws -> Request {
            var args = args
            if let name = options["expect-name"] {
                guard LogicCommand.trackCommandNames.contains(command) else {
                    throw CommandError("usage", "--expect-name は track get|select|mute|solo|volume|pan で使えます")
                }
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw CommandError("usage", "--expect-name は空にできません。track list が返した name を指定してください")
                }
                args[LogicCommand.expectNameKey] = name
            }
            if idempotencyKey != nil && !LogicCommand.isWrite(named: command) {
                throw CommandError("usage", "--idempotency-key は状態を変更するコマンドだけで使えます")
            }
            if command == "daemon.stop" && (expectSession != nil || deadlineMs != nil) {
                throw CommandError("usage", "daemon stop では --expect-session / --deadline-ms は使えません")
            }
            return Request(command: command, args: args, backend: backend, idempotencyKey: idempotencyKey,
                           expectSession: expectSession, deadlineMs: deadlineMs)
        }

        switch (words.first, words.dropFirst().first) {
        case ("status", _):
            try need(1, "status")
            return try request("status")
        case ("state", _):
            try need(1, "state")
            return try request("state")
        case ("transport", "play"), ("transport", "stop"):
            try need(2, "transport play|stop")
            return try request("transport.\(words[1])")
        case ("transport", "cycle"), ("transport", "click"):
            try need(3, "transport \(words[1]) on|off")
            return try request("transport.\(words[1])", args: ["state": words[2]])
        case ("track", "list"):
            try need(2, "track list")
            return try request("track.list")
        case ("track", "get"), ("track", "select"):
            try need(3, "track \(words[1]) <n>")
            return try request("track.\(words[1])", args: ["track": words[2]])
        case ("track", "mute"), ("track", "solo"), ("track", "arm"):
            try need(4, "track \(words[1]) <n> on|off")
            return try request("track.\(words[1])", args: ["track": words[2], "state": words[3]])
        case ("track", "volume"):
            try need(4, "track volume <n> <dB>")
            var args = ["track": words[2], "db": words[3]]
            if let t = options["tolerance"] { args["tolerance"] = t }
            return try request("track.volume", args: args)
        case ("track", "pan"):
            try need(4, "track pan <n> <-1…1>")
            return try request("track.pan", args: ["track": words[2], "value": words[3]])
        case ("debug", "mcu"):
            guard words.count > 2 else { throw CommandError("usage", "使い方: logicctl debug mcu <hex bytes>") }
            return try request("debug.mcu", args: ["messages": words.dropFirst(2).joined(separator: " ")])
        case ("daemon", "stop"):
            try need(2, "daemon stop")
            return try request("daemon.stop")
        default:
            throw CommandError("usage", "不明なコマンドです: \(words.joined(separator: " "))")
        }
    }
}
