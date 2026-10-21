// Research-only, read-only AX value reader for one Logic window (no press, focus, key, MIDI or setting writes).
// Prints JSON with AXValue / AXValueDescription / min / max of elements whose title or description equals <label>
// exactly, inside the one window whose title equals <window-title>. Label "*" lists text fields, pop-ups, check boxes and sliders.
//   swift Tools/research-scripts/ax-value-read.swift <pid> <window-title> <label>
// Used in EXP-CA-006 (Channel EQ "Gain": AX value 0-480, description "0.0 dB"). No document guard: check the window yourself.
import ApplicationServices
import Foundation

let a = CommandLine.arguments
guard a.count == 4, let pid = Int32(a[1]) else { print("{\"ok\":false,\"error\":\"usage\"}"); exit(2) }
guard AXIsProcessTrusted() else { print("{\"ok\":false,\"error\":\"not_trusted\"}"); exit(1) }
let app = AXUIElementCreateApplication(pid)

func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ n: String) -> String? { attr(e, n) as? String }
func num(_ e: AXUIElement, _ n: String) -> Double? { (attr(e, n) as? NSNumber)?.doubleValue }

var out: [[String: Any]] = []
var visited = 0
func walk(_ e: AXUIElement, _ path: [Int]) {
    visited += 1
    if visited > 3000 || path.count > 14 { return }
    let title = str(e, kAXTitleAttribute) ?? str(e, kAXDescriptionAttribute) ?? ""
    if (a[3] == "*" && ["AXTextField","AXPopUpButton","AXStaticText","AXCheckBox","AXSlider"].contains(str(e, kAXRoleAttribute) ?? "")) || title == a[3] {
        var row: [String: Any] = ["path": path, "role": str(e, kAXRoleAttribute) ?? "", "title": title]
        if let v = num(e, kAXValueAttribute) { row["value"] = v } else if let s = str(e, kAXValueAttribute) { row["value_text"] = s }
        if let d = str(e, "AXValueDescription") { row["value_description"] = d }
        if let lo = num(e, kAXMinValueAttribute) { row["min"] = lo }
        if let hi = num(e, kAXMaxValueAttribute) { row["max"] = hi }
        out.append(row)
    }
    for (i, c) in ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).enumerated() { walk(c, path + [i]) }
}
let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
let matches = windows.filter { str($0, kAXTitleAttribute) == a[2] }
guard !matches.isEmpty else {
    print("{\"ok\":false,\"error\":\"window_not_found\"}"); exit(1)
}
// Several windows can share a title (for example two plug-in windows of one track): read each and tag it.
var perWindow: [[String: Any]] = []
for (index, window) in matches.enumerated() {
    out = []
    walk(window, [])
    var position: [Double] = []
    if let v = attr(window, kAXPositionAttribute) {
        var p = CGPoint.zero
        if AXValueGetValue(v as! AXValue, .cgPoint, &p) { position = [Double(p.x), Double(p.y)] }
    }
    perWindow.append(["window_index": index, "position": position, "matches": out])
}
let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let result: [String: Any] = ["ok": true, "read_only": true, "observed_at_utc": iso.string(from: Date()),
                             "window": a[2], "label": a[3], "visited": visited, "window_count": matches.count,
                             "matches": perWindow.count == 1 ? (perWindow[0]["matches"] ?? []) : [], "windows": perWindow]
print(String(data: try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
