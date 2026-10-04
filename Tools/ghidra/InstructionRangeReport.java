// Export bounded instruction ranges, including code omitted from function bodies.
// Usage: <output.txt> <program> <import-sha256> <start:end-exclusive>...
// @category logicctl
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Data;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.symbol.Reference;
import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

public class InstructionRangeReport extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 4 || !args[2].matches("[0-9a-fA-F]{64}"))
            throw new IllegalArgumentException("Expected output, program, import hash, and bounded ranges");
        if (!args[1].equals(currentProgram.getName()) ||
            !args[2].equalsIgnoreCase(currentProgram.getExecutableSHA256()))
            throw new IllegalArgumentException("Program/import SHA-256 mismatch");
        File output = new File(args[0]);
        if (output.getAbsoluteFile().getParentFile() != null)
            output.getAbsoluteFile().getParentFile().mkdirs();
        try (PrintWriter out = new PrintWriter(output, StandardCharsets.UTF_8)) {
            out.println("# Program: " + currentProgram.getName());
            out.println("# Imported executable SHA-256: " + currentProgram.getExecutableSHA256());
            out.println("# Existing listing only; no disassembly, analysis, or runtime calls.");
            for (int i = 3; i < args.length; i++) {
                String[] pair = args[i].split(":");
                if (pair.length != 2) throw new IllegalArgumentException("Expected start:end-exclusive");
                Address start = toAddr(pair[0].replaceFirst("^0[xX]", ""));
                Address end = toAddr(pair[1].replaceFirst("^0[xX]", ""));
                long length = end.subtract(start);
                if (length <= 0 || length > 4096 || length % 4 != 0 || start.getOffset() % 4 != 0)
                    throw new IllegalArgumentException("Expected aligned nonempty ARM64 range <=4096 bytes");
                out.println("\n# Range: " + start + ":" + end + " (end exclusive)");
                for (Address p = start; p.compareTo(end) < 0; p = p.add(4)) {
                    Instruction ins = currentProgram.getListing().getInstructionAt(p);
                    byte[] bytes = new byte[4];
                    if (currentProgram.getMemory().getBytes(p, bytes) != 4)
                        throw new IllegalArgumentException("Incomplete range read at " + p);
                    out.println(p + "\t" + HexFormat.of().formatHex(bytes) + "\t" +
                        (ins == null ? "<no defined instruction>" : ins.toString()));
                    if (ins == null) continue;
                    for (Reference ref : ins.getReferencesFrom()) {
                        var callee = getFunctionAt(ref.getToAddress());
                        if (callee != null) out.println("# Ref: " + ref.getToAddress() + " " + callee.getName(true));
                        Data d = currentProgram.getListing().getDefinedDataAt(ref.getToAddress());
                        if (d != null) {
                            StringDataInstance value = StringDataInstance.getStringDataInstance(d);
                            if (value != StringDataInstance.NULL_INSTANCE)
                                out.println("# String: " + ref.getToAddress() + " " + value.getStringValue());
                        }
                    }
                }
            }
            if (out.checkError()) throw new java.io.IOException("Failed to write " + output.getAbsolutePath());
        }
        println("InstructionRangeReport: exported " + output.getAbsolutePath());
    }
}
