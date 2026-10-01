import Foundation
@testable import LogicCore

#if canImport(Testing)
import Testing

private final class RoutingBackend: LogicBackend {
    let kind: BackendKind
    var commands: [LogicCommand] = []
    init(_ kind: BackendKind) { self.kind = kind }
    func execute(_ command: LogicCommand) -> Outcome {
        commands.append(command)
        return Outcome(ok: true, result: [:])
    }
}

@Test func explicitAppleEventRouteAndLegacyMCUDefault() {
    let mcu = RoutingBackend(.mcu), appleEvent = RoutingBackend(.appleEvent)
    let router = CommandRouter(mcu: mcu, appleEvent: appleEvent)
    let legacy = router.execute(.transportPlay, backend: nil)
    #expect(legacy.backend == "mcu")
    #expect(legacy.readbackBackend == nil)
    let native = router.execute(.transportStop, backend: "appleevent")
    #expect(native.backend == "appleevent")
    #expect(native.readbackBackend == "mcu")
    #expect(mcu.commands == [.transportPlay])
    #expect(appleEvent.commands == [.transportStop])
}

@Test func rawSocketBackendRequestsCannotFallbackOrStopDaemon() {
    let mcu = RoutingBackend(.mcu), appleEvent = RoutingBackend(.appleEvent)
    let router = CommandRouter(mcu: mcu, appleEvent: appleEvent)
    let invalid = router.execute(.transportPlay, backend: "invalid")
    #expect(invalid.outcome.error == "unsupported_backend")
    let track = router.execute(.trackMute(track: 1, on: true), backend: "appleevent")
    #expect(track.outcome.error == "unsupported_backend_command")
    #expect(track.backend == "appleevent")
    #expect(!track.outcome.ok && !track.outcome.verified)
    #expect(throws: CommandError.self) {
        try CommandBackendSelection.resolve("appleevent", for: .daemonStop)
    }
    #expect(mcu.commands.isEmpty && appleEvent.commands.isEmpty)
}

@Test func statusAdvertisesDaemonSupportSeparatelyFromConnection() {
    let mcu = RoutingBackend(.mcu), appleEvent = RoutingBackend(.appleEvent)
    let router = CommandRouter(mcu: mcu, appleEvent: appleEvent)
    let routed = router.execute(.status, backend: nil)
    #expect(routed.outcome.result?["capabilities"]?["appleevent_transport"] == true)
    #expect(routed.outcome.result?["capabilities"]?["appleevent_readback_backend"] == "mcu")
    #expect(appleEvent.commands.isEmpty)
}
#endif
