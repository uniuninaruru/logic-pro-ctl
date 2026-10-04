import Foundation
@testable import LogicCore

// The compatibility report (docs/compatibility.md): an environment that was not checked is never
// shown as verified, and "cannot tell" is null, not false.
#if canImport(Testing)
import Testing

private func logic(_ version: String?, _ build: String?) -> LogicAppInfo {
    LogicAppInfo(pid: 1, bundleID: "test.logic", name: "Logic", version: version, build: build, path: nil)
}

private func macOS(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
    OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
}

@Test func theCheckedBuildOnTheCheckedMacOSIsVerified() {
    let report = CompatibilityProfile.assess(logic: logic("12.3.1", "6682"), macOS: macOS(27, 0))
    #expect(report["logic_build_verified"] == .bool(true))
    #expect(report["macos_verified"] == .bool(true))
    #expect(report["profile_verified"] == .bool(true))
}

@Test func anotherBuildOfTheSameVersionIsNotVerified() {
    let report = CompatibilityProfile.assess(logic: logic("12.3.1", "6700"), macOS: macOS(27, 0))
    #expect(report["logic_build_verified"] == .bool(false))
    #expect(report["profile_verified"] == .bool(false))
}

@Test func aNewerVersionIsNotVerifiedEvenIfTheBuildNumberMatches() {
    let report = CompatibilityProfile.assess(logic: logic("12.4", "6682"), macOS: macOS(27, 0))
    #expect(report["logic_build_verified"] == .bool(false))
}

@Test func theCheckedBuildOnAnotherMacOSIsReportedAsPartlyVerified() {
    let report = CompatibilityProfile.assess(logic: logic("12.3.1", "6682"), macOS: macOS(26, 5))
    #expect(report["logic_build_verified"] == .bool(true))
    #expect(report["macos_verified"] == .bool(false))
    #expect(report["profile_verified"] == .bool(false))  // the pair is what was checked
    #expect(report["host_macos"] == .string("26.5"))
}

@Test func aPatchReleaseOfTheCheckedMacOSStillCounts() {
    let host = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 3)
    #expect(CompatibilityProfile.assess(logic: logic("12.3.1", "6682"), macOS: host)["macos_verified"] == .bool(true))
}

@Test func whenTheBuildCannotBeReadTheAnswerIsNullNotFalseAndNotTrue() {
    for app in [logic(nil, nil), logic("12.3.1", nil), logic(nil, "6682")] {
        let report = CompatibilityProfile.assess(logic: app, macOS: macOS(27, 0))
        #expect(report["logic_build_verified"] == .null)
        #expect(report["profile_verified"] == .null)
    }
    let missing = CompatibilityProfile.assess(logic: nil, macOS: macOS(27, 0))
    #expect(missing["logic_build_verified"] == .null)
    #expect(missing["profile_verified"] == .null)
}

@Test func theListOfCheckedProfilesIsPartOfTheReport() {
    let report = CompatibilityProfile.assess(logic: nil, macOS: macOS(27, 0))
    #expect(report["verified_profiles"] == .array([["logic_version": "12.3.1", "logic_build": "6682", "macos": "27.0"]]))
}

@Test func statusCarriesTheReport() {
    let sim = FakeLogicMCU.project(tracks: 2)
    let backend = makeBackend(for: sim)
    sim.connect()
    withExtendedLifetime(sim) {
        let result = backend.execute(.status).result
        #expect(result?["compatibility"]?["verified_profiles"] != nil)
        // The fake reports Logic 12.3.1 (6682); whether the host macOS is the checked one depends on this machine.
        #expect(result?["compatibility"]?["logic_build_verified"] == .bool(true))
    }
}
#endif
