// Standalone research sender; does not change the shipping logicctl/logicd.
// Compile: swiftc Tools/research-scripts/appleevent_probe.swift -o .build/appleevent-probe
// Dry run by default. Sending requires --send and the open LogicCLI-Test.logicx.
import AppKit
import Carbon
import Foundation

enum ProbeError: Error { case invalid(String) }
func fourCC(_ text: String) throws -> UInt32 {
    let bytes = Array(text.utf8)
    guard bytes.count == 4, bytes.allSatisfy({ $0 < 128 }) else {
        throw ProbeError.invalid("FourCC must contain four ASCII bytes: \(text)")
    }
    return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
}
func codeString(_ code: UInt32) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .ascii)
        ?? String(format: "0x%08x", code)
}
func output(_ json: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
func describe(_ descriptor: NSAppleEventDescriptor) -> [String: Any] {
    var result: [String: Any] = ["type": codeString(descriptor.descriptorType),
                               "data_hex": descriptor.data.map { String(format: "%02x", $0) }.joined()]
    if descriptor.descriptorType == typeSInt32 { result["int32"] = descriptor.int32Value }
    if descriptor.descriptorType == typeBoolean { result["boolean"] = descriptor.booleanValue }
    if [typeUnicodeText, typeUTF8Text, typeChar].contains(descriptor.descriptorType),
       let value = descriptor.stringValue { result["text"] = value }
    return result
}
let usage = """
usage: appleevent-probe [--send] [--bundle-id ID | --app PATH]
       [--class FOURCC] [--id FOURCC] [--timeout SECONDS]
       --project /absolute/path/LogicCLI-Test.logicx [FOURCC=long:INTEGER | FOURCC=text:TEXT ...]
Default event: aUeV/Spt2. Default operation: dry run. No parameters are implicit.
Sending checks exactly one open document and its full path before targeting the running PID.
Output separates AESendMessage status from the reply's errn; verified is always false.
"""
do {
    var bundleID: String?, appPath: String?, project: String?
    var eventClass = "aUeV", eventID = "Spt2", timeout = 10.0, send = false
    var parameters: [(String, NSAppleEventDescriptor)] = []
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        let arg = args[i]
        if arg == "--help" { print(usage); exit(0) }
        if arg == "--send" { send = true; i += 1; continue }
        if arg.hasPrefix("--") {
            guard i + 1 < args.count else { throw ProbeError.invalid("missing value for \(arg)") }
            let value = args[i + 1]
            switch arg {
            case "--bundle-id": bundleID = value
            case "--app": appPath = value
            case "--project": project = value
            case "--class": eventClass = value
            case "--id": eventID = value
            case "--timeout":
                guard let t = Double(value), t.isFinite, (0.1...60).contains(t) else {
                    throw ProbeError.invalid("timeout must be 0.1...60 seconds")
                }
                timeout = t
            default: throw ProbeError.invalid("unknown option: \(arg)")
            }
            i += 2; continue
        }
        let pair = arg.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2 else { throw ProbeError.invalid("invalid parameter: \(arg)") }
        let key = String(pair[0]); _ = try fourCC(key)
        guard !parameters.contains(where: { $0.0 == key }) else {
            throw ProbeError.invalid("duplicate parameter: \(key)")
        }
        let typed = pair[1].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard typed.count == 2 else { throw ProbeError.invalid("expected long:INTEGER or text:TEXT") }
        let descriptor: NSAppleEventDescriptor
        switch typed[0] {
        case "long":
            guard let n = Int32(typed[1]) else { throw ProbeError.invalid("invalid signed int32: \(typed[1])") }
            descriptor = NSAppleEventDescriptor(int32: n)
        case "text": descriptor = NSAppleEventDescriptor(string: String(typed[1]))
        default: throw ProbeError.invalid("unsupported descriptor type: \(typed[0])")
        }
        parameters.append((key, descriptor)); i += 1
    }
    guard let project, project.hasPrefix("/"), URL(fileURLWithPath: project).lastPathComponent == "LogicCLI-Test.logicx" else {
        throw ProbeError.invalid("--project must be the absolute path to LogicCLI-Test.logicx")
    }
    let canonicalProject = URL(fileURLWithPath: project).standardizedFileURL.resolvingSymlinksInPath()
    guard canonicalProject.lastPathComponent == "LogicCLI-Test.logicx",
          !send || FileManager.default.fileExists(atPath: canonicalProject.path) else {
        throw ProbeError.invalid("resolved --project must be an existing LogicCLI-Test.logicx for sends")
    }
    guard bundleID == nil || appPath == nil else { throw ProbeError.invalid("choose --bundle-id or --app") }
    if let path = appPath {
        guard let id = Bundle(path: path)?.bundleIdentifier else { throw ProbeError.invalid("app bundle not found") }
        bundleID = id
    }
    let candidates = NSWorkspace.shared.runningApplications.filter {
        if let id = bundleID { return $0.bundleIdentifier == id }
        let info = $0.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary }
        return (info?["CFBundleExecutable"] as? String)?.hasPrefix("Logic Pro") == true
    }
    guard candidates.count == 1, let app = candidates.first, let id = app.bundleIdentifier else {
        throw ProbeError.invalid("expected one running Logic application; use --app or --bundle-id")
    }
    let event = NSAppleEventDescriptor(eventClass: try fourCC(eventClass), eventID: try fourCC(eventID),
        targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    for (key, descriptor) in parameters { event.setParam(descriptor, forKeyword: try fourCC(key)) }
    var result: [String: Any] = ["event_class": eventClass, "event_id": eventID,
        "bundle_id": id, "pid": app.processIdentifier, "project": project,
        "parameters": Dictionary(uniqueKeysWithValues: parameters.map { ($0.0, describe($0.1)) }),
        "verified": false, "sent": false]
    if send {
        // Guard uses read-only standard scripting. Pass values as argv, never interpolate source.
        let guardScript = """
        on run argv
            tell application id (item 1 of argv)
                with timeout of 10 seconds
                    if (count «class docu») is not 1 then error "expected exactly one test document"
                    return «class ppth» of «class docu» 1
                end timeout
            end tell
        end run
        """
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", guardScript, id]
        let pipe = Pipe(), errors = Pipe(); process.standardOutput = pipe; process.standardError = errors
        try process.run(); process.waitUntilExit()
        let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0,
              URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() ==
              canonicalProject else {
            let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ProbeError.invalid("test project guard failed: \(path) \(error)")
        }
        var reply = AEDesc(descriptorType: typeNull, dataHandle: nil)
        let status = AESendMessage(event.aeDesc!, &reply,
            AESendMode(kAEWaitReply | kAENeverInteract | kAEDontRecord), Int(ceil(timeout * 60)))
        result["sent"] = true
        result["send_status"] = status
        var fields: [String: Any] = [:]
        let descriptor = NSAppleEventDescriptor(aeDescNoCopy: &reply)
        if descriptor.numberOfItems > 0 {
            for n in 1...descriptor.numberOfItems {
                if let field = descriptor.atIndex(n) {
                    fields[codeString(descriptor.keywordForDescriptor(at: n))] = describe(field)
                }
            }
        }
        for key in ["errn", "errs", "sPer", "sPsr", "sPfr", "sPso", "----"] {
            if let field = descriptor.paramDescriptor(forKeyword: try fourCC(key)) { fields[key] = describe(field) }
        }
        let replyError = Int(descriptor.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0)
        result["reply_error"] = replyError
        result["reply_type"] = codeString(descriptor.descriptorType)
        result["reply_parameters"] = fields
        result["ok"] = status == noErr && replyError == 0
    } else { result["ok"] = true }
    try output(result)
    if send && result["ok"] as? Bool != true { exit(1) }
} catch {
    try? output(["ok": false, "sent": false, "verified": false, "error": String(describing: error)])
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
