// Lists CoreMIDI sources and destinations. Read-only.
// Usage: swift Tools/research-scripts/midi-endpoints.swift
import CoreMIDI
func s(_ o: MIDIObjectRef, _ k: CFString) -> String { var u: Unmanaged<CFString>?; MIDIObjectGetStringProperty(o, k, &u); return (u?.takeRetainedValue() as String?) ?? "-" }
func i(_ o: MIDIObjectRef, _ k: CFString) -> Int32 { var v: Int32 = 0; MIDIObjectGetIntegerProperty(o, k, &v); return v }
print("sources:"); for n in 0..<MIDIGetNumberOfSources() { let e = MIDIGetSource(n); print("  \(s(e, kMIDIPropertyDisplayName)) | owner=\(s(e, kMIDIPropertyManufacturer)) uid=\(i(e, kMIDIPropertyUniqueID)) offline=\(i(e, kMIDIPropertyOffline))") }
print("destinations:"); for n in 0..<MIDIGetNumberOfDestinations() { let e = MIDIGetDestination(n); print("  \(s(e, kMIDIPropertyDisplayName)) | owner=\(s(e, kMIDIPropertyManufacturer)) uid=\(i(e, kMIDIPropertyUniqueID)) offline=\(i(e, kMIDIPropertyOffline))") }
