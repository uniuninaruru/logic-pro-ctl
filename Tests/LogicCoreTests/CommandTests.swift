import Foundation
@testable import LogicCore

#if canImport(Testing)
import Testing

@Test func parsesNegativeVolumeAsValue() throws {
    let r = try CLIParser.parse(["track", "volume", "1", "-6", "--json"])
    #expect(r.command == "track.volume")
    #expect(r.args == ["track": "1", "db": "-6"])
}

@Test func parsesToleranceOption() throws {
    let r = try CLIParser.parse(["track", "volume", "2", "-3.5", "--tolerance", "0.2"])
    #expect(r.args == ["track": "2", "db": "-3.5", "tolerance": "0.2"])
}

@Test func parsesNegativePan() throws {
    let r = try CLIParser.parse(["track", "pan", "3", "-0.25"])
    #expect(r.args == ["track": "3", "value": "-0.25"])
    #expect(try LogicCommand(request: r) == .trackPan(track: 3, pan: -0.25))
}

@Test func parsesMuteAndTransport() throws {
    #expect(try LogicCommand(request: CLIParser.parse(["track", "mute", "1", "on"])) == .trackMute(track: 1, on: true))
    #expect(try LogicCommand(request: CLIParser.parse(["transport", "stop", "--json"])) == .transportStop)
}

@Test func rejectsBadUsage() {
    #expect(throws: CommandError.self) { try CLIParser.parse(["track", "mute", "1"]) }
    #expect(throws: CommandError.self) { try CLIParser.parse(["track", "volume", "1", "-6", "--fast"]) }
    #expect(throws: CommandError.self) { try CLIParser.parse(["fly"]) }
}

@Test func parsesExplicitTransportBackendsAnywhere() throws {
    for argv in [
        ["--backend", "appleevent", "transport", "play"],
        ["transport", "--backend", "appleevent", "play"],
        ["transport", "play", "--backend", "appleevent", "--json"],
    ] {
        let request = try CLIParser.parse(argv)
        #expect(request.command == "transport.play")
        #expect(request.backend == "appleevent")
        #expect(request.args.isEmpty)
    }
    let stop = try CLIParser.parse(["transport", "stop", "--backend", "appleevent"])
    #expect(stop.command == "transport.stop")
    #expect(stop.backend == "appleevent")
    #expect(try CLIParser.parse(["transport", "play"]).backend == nil)
    #expect(try CLIParser.parse(["--backend", "mcu", "track", "list"]).backend == "mcu")
}

@Test func rejectsInvalidBackendAndOptionUsage() {
    for argv in [
        ["transport", "play", "--backend", "native-ipc"],
        ["transport", "play", "--backend"],
        ["transport", "play", "--backend", "--json"],
        ["transport", "play", "--backend", "appleevent", "--backend", "mcu"],
        ["track", "volume", "1", "-6", "--tolerance", "0.1", "--tolerance", "0.2"],
        ["track", "volume", "1", "-6", "--tolerance", "typo"],
        ["track", "volume", "1", "-6", "--tolerance", "-0.1"],
        ["track", "volume", "1", "-6", "--tolerance", "inf"],
        ["track", "volume", "1", "-6", "--tolerance", "nan"],
        ["transport", "play", "--tolerance", "0.1"],
        ["status", "--backend", "appleevent"],
        ["state", "--backend", "appleevent"],
        ["track", "mute", "1", "on", "--backend", "appleevent"],
        ["daemon", "stop", "--backend", "appleevent"],
        ["debug", "mcu", "90 5E 7F", "--backend", "appleevent"],
        ["transport", "record", "--backend", "appleevent"],
    ] {
        do {
            _ = try CLIParser.parse(argv)
            Issue.record("expected a usage error for \(argv)")
        } catch let error as CommandError {
            #expect(error.code == "usage")
        } catch {
            Issue.record("unexpected error for \(argv): \(error)")
        }
    }
}

@Test func validatesArguments() throws {
    func cmd(_ c: String, _ a: [String: String]) throws -> LogicCommand {
        try LogicCommand(request: Request(command: c, args: a))
    }
    #expect(throws: CommandError.self) { try cmd("track.volume", ["track": "1", "db": "7"]) }
    #expect(throws: CommandError.self) { try cmd("track.pan", ["track": "1", "value": "1.5"]) }
    #expect(throws: CommandError.self) { try cmd("track.mute", ["track": "0", "state": "on"]) }
    #expect(throws: CommandError.self) { try cmd("track.mute", ["track": "1", "state": "maybe"]) }
    #expect(try cmd("track.volume", ["track": "1", "db": "-inf"]) == .trackVolume(track: 1, db: -.infinity, tolerance: 0.1))
}
#endif
