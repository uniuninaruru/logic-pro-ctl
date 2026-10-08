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
func stringRead(_ element: AXUIElement, _ name: String) -> (String, AXError) {
    var value: CFTypeRef?
    let code = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return ((value as? String) ?? "", code)
}
func emit(_ value: [String: Any]) {
    var result = value
    result["observed_at_utc"] = ISO8601DateFormatter().string(from: Date())
    result["verified"] = false
    result["plugin_instance_identity_verified"] = false
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
func testDocumentTitle(_ title: String) -> Bool {
    title.range(of: #"^LogicCLI-Test(?:\.logicx)?(?:\s+[-–—]\s+.*)?$"#,
                options: .regularExpression) != nil
}
guard AXIsProcessTrusted() else {
    emit(["ok": false, "read_only": true, "error": "accessibility_unavailable"])
    exit(1)
}
var options: [String: String] = [:]
let arguments = Array(CommandLine.arguments.dropFirst())
var argumentIndex = 0
while argumentIndex + 1 < arguments.count,
      ["--pid", "--window-title", "--parameter-label"].contains(arguments[argumentIndex]),
      options[arguments[argumentIndex]] == nil {
    options[arguments[argumentIndex]] = arguments[argumentIndex + 1]
    argumentIndex += 2
}
guard argumentIndex == arguments.count,
      let pidText = options["--pid"], let pid = Int32(pidText), pid > 0,
      let process = NSRunningApplication(processIdentifier: pid), !process.isTerminated else {
    FileHandle.standardError.write(Data("Usage: swift logic-plugin-inspect.swift --pid <observed Logic PID> [--window-title <observed title>] [--parameter-label <observed label>]\n".utf8))
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
// Trust alone does not attest that returned elements are usable window objects.
// Keep a malformed AX tree distinct from a missing document or missing EQ value.
let windowMetadata: [[String: Any]] = windows.enumerated().map { index, window in
    ["index": index, "role": text(window, "AXRole"), "title": text(window, "AXTitle"),
     "equals_application": CFEqual(window, app)]
}
guard !windows.isEmpty,
      windowMetadata.allSatisfy({ ($0["role"] as? String) == "AXWindow" &&
          ($0["equals_application"] as? Bool) == false }) else {
    // Independent compositor metadata corroborates visibility only. It cannot
    // replace the document/track/slot/instance binding or provide parameter values.
    let compositor = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] ?? [])
        .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        .map { row -> [String: Any] in
            ["title": row[kCGWindowName as String] as? String ?? "",
             "window_number": row[kCGWindowNumber as String] as? Int ?? -1,
             "layer": row[kCGWindowLayer as String] as? Int ?? -1]
        }
    emit(["ok": false, "read_only": true, "verified": false,
          "accessibility_trusted": true, "error": "ax_window_tree_unusable",
          "ax_windows": windowMetadata, "compositor_windows": compositor,
          "plugin_instance_identity_verified": false])
    exit(1)
}
let testWindows = windows.filter {
    let title = text($0, "AXTitle")
    let document = text($0, "AXDocument")
    return testDocumentTitle(title) ||
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
var treeErrors: [[String: Any]] = []
var candidates: [[String: Any]] = []
var labels: [[String: Any]] = []
var parameterLabels: [[String: Any]] = []
func walk(_ element: AXUIElement, _ path: [Int], _ windowIndex: Int, _ depth: Int,
          _ parentRole: String = "") {
    guard depth <= 12, visited < 2000, Date().timeIntervalSince(started) < 6 else {
        truncated = true; return
    }
    visited += 1
    let (role, roleCode) = stringRead(element, "AXRole")
    guard roleCode == .success && !role.isEmpty else {
        truncated = true
        treeErrors.append(["window_index": windowIndex, "path": path,
                           "attribute": "AXRole", "result_code": roleCode.rawValue])
        return
    }
    let (title, titleCode) = stringRead(element, "AXTitle")
    let (description, descriptionCode) = stringRead(element, "AXDescription")
    let (valueText, valueCode) = stringRead(element, "AXValue")
    if role == "AXStaticText" {
        for (name, code) in [("AXTitle", titleCode), ("AXDescription", descriptionCode), ("AXValue", valueCode)]
            where code != .success && code != .attributeUnsupported && code != .noValue {
            truncated = true
            treeErrors.append(["window_index": windowIndex, "path": path, "role": role,
                               "attribute": name, "result_code": code.rawValue])
        }
    }
    if role == "AXStaticText" && (!title.isEmpty || !description.isEmpty || !valueText.isEmpty) {
        parameterLabels.append(["window_index": windowIndex, "path": path,
                                "parent_role": parentRole,
                                "title": String(title.prefix(256)),
                                "description": String(description.prefix(256)),
                                "value": String(valueText.prefix(256))])
    }
    if role == "AXStaticText", !path.isEmpty,
       [title, description, valueText].contains(where: { $0 == "Channel EQ" }) {
        labels.append(["window_index": windowIndex, "path": path, "role": role,
                       "title": title, "description": description, "value": valueText])
    }
    if ["AXSlider", "AXTextField", "AXIncrementor", "AXPopUpButton", "AXValueIndicator"].contains(role) {
        var row: [String: Any] = ["window_index": windowIndex, "path": path, "role": role]
        var codes: [String: Int32] = [:]
        for name in ["AXTitle", "AXDescription", "AXIdentifier", "AXValue", "AXValueDescription", "AXMinValue", "AXMaxValue"] {
            var value: CFTypeRef?
            let code = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            codes[name] = code.rawValue
            if code != .success && code != .attributeUnsupported && code != .noValue {
                truncated = true
                treeErrors.append(["window_index": windowIndex, "path": path, "role": role,
                                   "attribute": name, "result_code": code.rawValue])
            }
            if let value = value as? String { row[name] = String(value.prefix(256)) }
            else if let value = value as? NSNumber { row[name] = value }
        }
        row["attribute_result_codes"] = codes
        if let titleElement = attribute(element, "AXTitleUIElement"),
           CFGetTypeID(titleElement) == AXUIElementGetTypeID() {
            let label = unsafeBitCast(titleElement, to: AXUIElement.self)
            row["title_element"] = ["role": text(label, "AXRole"),
                                     "title": text(label, "AXTitle"),
                                     "description": text(label, "AXDescription"),
                                     "value": text(label, "AXValue")]
        }
        candidates.append(row)
    }
    var childrenValue: CFTypeRef?
    let childrenCode = AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenValue)
    let children = childrenValue as? [AXUIElement]
    if (childrenCode == .success && children == nil) ||
        (childrenCode != .success && childrenCode != .attributeUnsupported && childrenCode != .noValue) ||
        (childrenCode != .success && role == "AXWindow") {
        truncated = true
        treeErrors.append(["window_index": windowIndex, "path": path, "role": role,
                           "attribute": "AXChildren", "result_code": childrenCode.rawValue])
    }
    for (index, child) in (children ?? []).enumerated() {
        walk(child, path + [index], windowIndex, depth + 1, role)
        if truncated { break }
    }
}
// A plug-in window may be titled after its track. Inspect auxiliary windows and
// find the plug-in's label inside; an explicit observed title only narrows discovery.
// Neither that label nor a path/index proves stable instance identity.
var pluginWindows: [[String: Any]] = []
for (index, window) in windows.enumerated() {
    if testWindows.contains(where: { CFEqual($0, window) }) { continue }
    let title = text(window, "AXTitle")
    if let observedTitle = options["--window-title"], title != observedTitle { continue }
    let start = candidates.count
    let labelStart = labels.count
    let parameterLabelStart = parameterLabels.count
    walk(window, [], index, 0)
    let labelObserved = labels.count > labelStart
    if labelObserved || title.localizedCaseInsensitiveContains("Channel EQ") || options["--window-title"] != nil {
        pluginWindows.append(["index": index, "title": title,
                              "plugin_label_observed": labelObserved,
                              "discovery_only": true])
    } else {
        candidates.removeSubrange(start...)
        parameterLabels.removeSubrange(parameterLabelStart...)
    }
    if truncated { break }
}
func normalizedLabel(_ label: String) -> String {
    label.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
        .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}
var parameterReadbacks: [[String: Any]] = []
var parameterSelection: [String: Any] = ["state": "not_requested"]
if let requestedLabel = options["--parameter-label"] {
    let matched = parameterLabels.filter { label in
        pluginWindows.contains { window in
            window["index"] as? Int == label["window_index"] as? Int &&
                window["plugin_label_observed"] as? Bool == true
        } && ["title", "description", "value"].contains { key in
            normalizedLabel(label[key] as? String ?? "") == normalizedLabel(requestedLabel)
        }
    }
    parameterSelection = ["requested_label": requestedLabel,
                          "matching_labels": matched.count,
                          "state": truncated ? "incomplete_tree" :
                              matched.isEmpty ? "label_not_found" : "ambiguous_label"]
    // Correlate an observed label with controls in the same immediate row.
    // This is a tree relationship, not an assertion of plug-in instance identity.
    if !truncated, matched.count == 1,
       let labelPath = matched[0]["path"] as? [Int], labelPath.count > 1,
       matched[0]["parent_role"] as? String == "AXGroup" {
        let parentPath = Array(labelPath.dropLast())
        let windowIndex = matched[0]["window_index"] as? Int
        let rowLabels = parameterLabels.filter { label in
            guard label["window_index"] as? Int == windowIndex,
                  let path = label["path"] as? [Int] else { return false }
            return path.count > parentPath.count && Array(path.prefix(parentPath.count)) == parentPath
        }
        parameterSelection["row_labels"] = rowLabels.count
        for candidate in candidates where rowLabels.count == 1 {
            guard candidate["window_index"] as? Int == windowIndex,
                  let path = candidate["path"] as? [Int],
                  path.count > parentPath.count,
                  Array(path.prefix(parentPath.count)) == parentPath,
                  let valueDescription = candidate["AXValueDescription"] as? String,
                  !valueDescription.isEmpty else { continue }
            parameterReadbacks.append(["label": matched[0], "control": candidate,
                                       "display_value": valueDescription,
                                       "association": "same_immediate_ax_row",
                                       "plugin_instance_identity_verified": false])
        }
        parameterSelection["controls_with_value_description"] = parameterReadbacks.count
        parameterSelection["state"] = rowLabels.count != 1 ? "ambiguous_row_labels" :
            parameterReadbacks.count == 1 ? "observed_row_value" :
            parameterReadbacks.isEmpty ? "value_unavailable" : "ambiguous_controls"
        if parameterReadbacks.count != 1 { parameterReadbacks.removeAll() }
    } else if !truncated && matched.count == 1 {
        parameterSelection["state"] = "row_unconfirmed"
    }
}
emit(["ok": true, "read_only": true, "pid": process.processIdentifier,
      "bundle_id": process.bundleIdentifier ?? "", "test_project_window_present": true,
      "plugin_instance_identity_verified": false, "plugin_windows": pluginWindows,
      "parameter_candidates": candidates, "plugin_label_candidates": labels,
      "parameter_label_candidates": parameterLabels,
      "parameter_selection": parameterSelection,
      "parameter_readback_candidates": parameterReadbacks,
      "verified": false, "visited_nodes": visited, "truncated": truncated,
      "tree_errors": treeErrors])
