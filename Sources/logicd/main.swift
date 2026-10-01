import Foundation
import LogicCore

// Placeholder daemon. Socket server and backends come after Phase A.
print("logicd: socket=\(defaultSocketPath)")
print("logicd: backends=\(BackendKind.allCases.map(\.rawValue).joined(separator: ","))")
