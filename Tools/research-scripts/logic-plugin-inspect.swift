import AppKit
import ApplicationServices
import Foundation

// Research-only, read-only AX discovery. No focus, press, key, MIDI or setting writes.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func text(_ element: AXUIElement, _ name: String) -> String {
    (attribute(element, name) as? String) ?? ""
}
func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
guard AXIsProcessTrusted() else {
    emit(["ok": false, "read_only": true, "error": "accessibility_unavailable"])
    exit(1)
}
guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--pid",
      let pid = Int32(CommandLine.arguments[2]), pid > 0,
      let process = NSRunningApplication(processIdentifier: pid), !process.isTerminated else {
    FileHandle.standardError.write(Data("Usage: swift logic-plugin-inspect.swift --pid <observed Logic PID>\n".utf8))
    emit(["ok": false, "read_only": true, "error": "observed_pid_required"])
    exit(64)
}
let info = process.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary }
let types = info?["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
guard types.contains(where: { ($0["CFBundleTypeExtensions"] as? [String] ?? []).contains("logicx") }) else {
    emit(["ok": false, "read_only": true, "error": "logic_document_support_unconfirmed"])
    exit(1)
}
let app = AXUIElementCreateApplication(process.processIdentifier)
AXUIElementSetMessagingTimeout(app, 0.2)
let windows = (attribute(app, "AXWindows") as? [AXUIElement]) ?? []
let testWindows = windows.filter {
    let title = text($0, "AXTitle")
    let document = text($0, "AXDocument")
    return title == "LogicCLI-Test" || title.hasPrefix("LogicCLI-Test - ") ||
        URL(string: document)?.lastPathComponent == "LogicCLI-Test.logicx"
}
guard testWindows.count == 1 else {
    emit(["ok": false, "read_only": true, "error": "test_project_window_unconfirmed",
          "matching_windows": testWindows.count, "window_count": windows.count])
    exit(1)
}
let started = Date()
var visited = 0
var truncated = false
var candidates: [[String: Any]] = []
func walk(_ element: AXUIElement, _ path: [Int], _ windowIndex: Int, _ depth: Int) {
    guard depth <= 12, visited < 2000, Date().timeIntervalSince(started) < 6 else {
        truncated = true; return
    }
    visited += 1
    let role = text(element, "AXRole")
    if ["AXSlider", "AXTextField", "AXIncrementor", "AXPopUpButton"].contains(role) {
        var row: [String: Any] = ["window_index": windowIndex, "path": path, "role": role]
        for name in ["AXTitle", "AXDescription", "AXIdentifier", "AXValue", "AXValueDescription", "AXMinValue", "AXMaxValue"] {
            let value = attribute(element, name)
            if let value = value as? String { row[name] = String(value.prefix(256)) }
            else if let value = value as? NSNumber { row[name] = value }
        }
        candidates.append(row)
    }
    for (index, child) in ((attribute(element, "AXChildren") as? [AXUIElement]) ?? []).enumerated() {
        walk(child, path + [index], windowIndex, depth + 1)
        if truncated { break }
    }
}
// Only plug-in windows are inspected; a path/index is a discovery aid, not stable identity.
var pluginWindows: [[String: Any]] = []
for (index, window) in windows.enumerated() {
    let title = text(window, "AXTitle")
    if title.localizedCaseInsensitiveContains("Channel EQ") {
        pluginWindows.append(["index": index, "title": title])
        walk(window, [], index, 0)
    }
}
emit(["ok": true, "read_only": true, "pid": process.processIdentifier,
      "bundle_id": process.bundleIdentifier ?? "", "test_project_window_present": true,
      "plugin_instance_identity_verified": false, "plugin_windows": pluginWindows,
      "parameter_candidates": candidates, "visited_nodes": visited, "truncated": truncated])
