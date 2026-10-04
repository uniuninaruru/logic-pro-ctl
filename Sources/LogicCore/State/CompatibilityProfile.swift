import Foundation

/// The environments `logicctl` has actually been checked on (docs/compatibility.md).
///
/// A Logic build or macOS version that is not listed here is not "unsupported" by this alone: it is
/// *unverified*. `status` says so, so that an agent does not read a result from an unchecked
/// environment as if it had been verified. Nothing here blocks a command.
public struct VerifiedProfile: Equatable {
    public var logicVersion: String
    public var logicBuild: String
    /// "major.minor" of macOS, for example "27.0".
    public var macOS: String

    public init(logicVersion: String, logicBuild: String, macOS: String) {
        self.logicVersion = logicVersion
        self.logicBuild = logicBuild
        self.macOS = macOS
    }

    var json: JSONValue {
        ["logic_version": .string(logicVersion), "logic_build": .string(logicBuild), "macos": .string(macOS)]
    }
}

public enum CompatibilityProfile {
    /// Logic 12.3.1 (6682) on macOS 27.0, arm64: the only environment the live experiments
    /// (Research/experiments/EXP-MCU-*) were run on.
    public static let verified = [VerifiedProfile(logicVersion: "12.3.1", logicBuild: "6682", macOS: "27.0")]

    /// What `status` reports under `compatibility`. `null` means "cannot tell" (Logic is not running, or
    /// its version could not be read), never "verified".
    public static func assess(logic: LogicAppInfo?, macOS: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
                              profiles: [VerifiedProfile] = verified) -> JSONValue {
        let host = "\(macOS.majorVersion).\(macOS.minorVersion)"
        var logicVerified: Bool?
        if let version = logic?.version, let build = logic?.build {
            logicVerified = profiles.contains { $0.logicVersion == version && $0.logicBuild == build }
        }
        let macOSVerified = profiles.contains { $0.macOS == host }
        let combined: Bool? = logic == nil ? nil : (logic?.version == nil || logic?.build == nil ? nil
            : profiles.contains { $0.logicVersion == logic?.version && $0.logicBuild == logic?.build && $0.macOS == host })
        let note: String
        switch combined {
        case true?: note = "検証済みの組み合わせです。"
        case false?: note = "この Logic の build と macOS の組み合わせは検証していません。結果は参考として扱い、書き込みは読み戻しで確認してください。"
        case nil: note = "Logic の起動または版を確認できないため、検証済みかどうかは分かりません。"
        }
        return [
            "verified_profiles": .array(profiles.map(\.json)),
            "host_macos": .string(host),
            "logic_build_verified": .bool(logicVerified),
            "macos_verified": .bool(macOSVerified),
            "profile_verified": .bool(combined),
            "note": .string(note),
        ]
    }
}
