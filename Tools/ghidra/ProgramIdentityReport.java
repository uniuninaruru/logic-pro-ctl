// Read-only identity report for an existing Ghidra program.
// Usage: -postScript ProgramIdentityReport.java <output.json> <program-name> <import-sha256>
// The expected digest is the selected architecture slice, not the universal container.
// Does not decompile, change types, attach to Logic, or send application messages.
// @category logicctl

import ghidra.app.script.GhidraScript;
import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;

public class ProgramIdentityReport extends GhidraScript {
    private static String quote(String value) {
        if (value == null) return "null";
        StringBuilder out = new StringBuilder("\"");
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"': out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (c < 0x20) out.append(String.format("\\u%04x", (int) c));
                    else out.append(c);
            }
        }
        return out.append('"').toString();
    }

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 3 || !args[2].matches("[0-9a-fA-F]{64}"))
            throw new IllegalArgumentException("Expected output file, program name, import SHA-256");
        String sha = currentProgram.getExecutableSHA256();
        if (!args[1].equals(currentProgram.getName()) || !args[2].equalsIgnoreCase(sha))
            throw new IllegalArgumentException("Program name/import SHA-256 mismatch; no report written");
        File output = new File(args[0]);
        File parent = output.getAbsoluteFile().getParentFile();
        if (parent != null) parent.mkdirs();
        try (PrintWriter out = new PrintWriter(output, StandardCharsets.UTF_8)) {
            out.println("{");
            out.println("  \"schema_version\": 1,");
            out.println("  \"program_name\": " + quote(currentProgram.getName()) + ",");
            out.println("  \"executable_path\": " + quote(currentProgram.getExecutablePath()) + ",");
            out.println("  \"imported_executable_sha256\": " + quote(sha) + ",");
            out.println("  \"executable_format\": " + quote(currentProgram.getExecutableFormat()) + ",");
            out.println("  \"image_base\": " + quote(currentProgram.getImageBase().toString()) + ",");
            out.println("  \"language_id\": " + quote(currentProgram.getLanguageID().toString()) + ",");
            out.println("  \"compiler_spec_id\": " + quote(currentProgram.getCompilerSpec().getCompilerSpecID().toString()) + ",");
            out.println("  \"ghidra_version\": " + quote(getGhidraVersion()) + ",");
            out.println("  \"expected_name_and_hash_match\": true");
            out.println("}");
        }
        println("ProgramIdentityReport: exported " + output.getAbsolutePath());
    }
}
