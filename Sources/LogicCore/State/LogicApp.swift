import AppKit
import Foundation

/// The running Logic Pro process, found by bundle ID (the app name carries
/// an edition suffix in 12.x, e.g. "Logic Pro Creator Studio").
public struct LogicAppInfo {
    public var pid: Int32
    public var bundleID: String
    public var name: String
    public var version: String?
    public var build: String?
    public var path: String?

    public var json: JSONValue {
        ["pid": .int(Int(pid)), "bundle_id": .string(bundleID), "name": .string(name),
         "version": .string(version), "build": .string(build), "path": .string(path)]
    }
}

public enum LogicApp {
    /// 12.x ships as com.apple.mobilelogic; 10.x/11.x used com.apple.logic10.
    public static let bundleIDs = ["com.apple.mobilelogic", "com.apple.logic10"]

    public static func running() -> LogicAppInfo? {
        for id in bundleIDs {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
                  !app.isTerminated else { continue }
            let info = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary }
            return LogicAppInfo(
                pid: app.processIdentifier, bundleID: id,
                name: app.localizedName ?? id,
                version: info?["CFBundleShortVersionString"] as? String,
                build: info?["CFBundleVersion"] as? String,
                path: app.bundleURL?.path)
        }
        return nil
    }
}
