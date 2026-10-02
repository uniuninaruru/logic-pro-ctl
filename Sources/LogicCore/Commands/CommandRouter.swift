import Foundation

/// Selects a supported backend before any operation. Requests from raw socket
/// clients receive the same validation as the CLI, with no implicit fallback.
public enum CommandBackendSelection {
    public static func resolve(_ backend: String?, for command: LogicCommand) throws -> BackendKind {
        switch backend ?? BackendKind.mcu.rawValue {
        case BackendKind.mcu.rawValue: return .mcu
        case BackendKind.appleEvent.rawValue:
            guard command == .transportPlay || command == .transportStop else {
                throw CommandError("unsupported_backend_command", "AppleEvent経路は transport play と transport stop で使えます。")
            }
            return .appleEvent
        default: throw CommandError("unsupported_backend", "使える経路は mcu と appleevent です。")
        }
    }
}

public struct RoutedOutcome {
    public var backend: String
    public var readbackBackend: String?
    public var outcome: Outcome

    public init(backend: String, readbackBackend: String?, outcome: Outcome) {
        self.backend = backend
        self.readbackBackend = readbackBackend
        self.outcome = outcome
    }
}

public final class CommandRouter {
    private let mcu: LogicBackend
    private let appleEvent: LogicBackend

    public init(mcu: LogicBackend, appleEvent: LogicBackend) {
        self.mcu = mcu
        self.appleEvent = appleEvent
    }

    public func execute(_ command: LogicCommand, backend: String?) -> RoutedOutcome {
        let kind: BackendKind
        do { kind = try CommandBackendSelection.resolve(backend, for: command) }
        catch let error as CommandError {
            return RoutedOutcome(backend: backend ?? BackendKind.mcu.rawValue,
                                 readbackBackend: backend == BackendKind.appleEvent.rawValue ? BackendKind.mcu.rawValue : nil,
                                 outcome: .failure(error.code, error.message))
        } catch {
            return RoutedOutcome(backend: backend ?? BackendKind.mcu.rawValue, readbackBackend: nil,
                                 outcome: .failure("internal", String(describing: error)))
        }
        var outcome = (kind == .appleEvent ? appleEvent : mcu).execute(command)
        if command == .status, case .object(var object) = outcome.result {
            object["capabilities"] = [
                "appleevent_transport": true,
                "transport_backends": [.string(BackendKind.mcu.rawValue), .string(BackendKind.appleEvent.rawValue)],
                "appleevent_readback_backend": .string(BackendKind.mcu.rawValue),
                "appleevent_supported_logic": [["version": .string(AppleEventTransportBackend.supportedVersion),
                                                "build": .string(AppleEventTransportBackend.supportedBuild)]]
            ]
            outcome.result = .object(object)
        }
        return RoutedOutcome(backend: kind.rawValue,
                             readbackBackend: kind == .appleEvent ? BackendKind.mcu.rawValue : nil,
                             outcome: outcome)
    }
}
