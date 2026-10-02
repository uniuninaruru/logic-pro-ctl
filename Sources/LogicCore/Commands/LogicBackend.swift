import Foundation

/// Result of executing one command against Logic.
public struct Outcome {
    public var ok: Bool
    public var verified: Bool
    public var requested: JSONValue?
    public var observed: JSONValue?
    public var result: JSONValue?
    public var error: String?
    public var message: String?
    /// How complete, fresh and sourced a *read* is (docs/observation-contract.md).
    public var observation: JSONValue?

    public init(ok: Bool, verified: Bool = false, requested: JSONValue? = nil, observed: JSONValue? = nil,
                result: JSONValue? = nil, error: String? = nil, message: String? = nil,
                observation: JSONValue? = nil) {
        self.ok = ok
        self.verified = verified
        self.requested = requested
        self.observed = observed
        self.result = result
        self.error = error
        self.message = message
        self.observation = observation
    }

    public static func failure(_ error: String, _ message: String, requested: JSONValue? = nil,
                               observed: JSONValue? = nil) -> Outcome {
        Outcome(ok: false, requested: requested, observed: observed, error: error, message: message)
    }

    /// A write outcome: ok only if the readback matched.
    public static func write(matched: Bool, requested: JSONValue, observed: JSONValue,
                             result: JSONValue? = nil, message: String? = nil) -> Outcome {
        Outcome(ok: matched, verified: matched, requested: requested, observed: observed, result: result,
                error: matched ? nil : "verification_failed", message: message)
    }
}

/// One way of reaching Logic (MCU, Logic Remote, Accessibility, …).
public protocol LogicBackend: AnyObject {
    var kind: BackendKind { get }
    func execute(_ command: LogicCommand) -> Outcome
}
