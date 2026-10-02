// Read-only references and nearby method-pointer candidates; no inferred IMP promotion.
// Usage: -postScript ReferenceDataReport.java <out> <program> <import-sha256> <address>...
// @category logicctl
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;
import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

public class ReferenceDataReport extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 4 || !args[2].matches("[0-9a-fA-F]{64}") ||
            !args[1].equals(currentProgram.getName()) ||
            !args[2].equalsIgnoreCase(currentProgram.getExecutableSHA256()))
            throw new IllegalArgumentException("Expected output, matching program/import hash, addresses");
        File output = new File(args[0]);
        File parent = output.getAbsoluteFile().getParentFile();
        if (parent != null) parent.mkdirs();
        try (PrintWriter out = new PrintWriter(output, StandardCharsets.UTF_8)) {
            out.println("# Program: " + currentProgram.getName());
            out.println("# Imported executable SHA-256: " + currentProgram.getExecutableSHA256());
            out.println("# References and nearby pointer candidates, not runtime method resolution.");
            for (int i = 3; i < args.length; i++) {
                Address target = toAddr(args[i].replaceFirst("^0[xX]", ""));
                out.println("\n# Target " + target);
                for (Reference ref : getReferencesTo(target)) {
                    Address from = ref.getFromAddress();
                    MemoryBlock block = currentProgram.getMemory().getBlock(from);
                    Function owner = getFunctionContaining(from);
                    Data data = currentProgram.getListing().getDefinedDataContaining(from);
                    out.println("Ref " + from + " " + ref.getReferenceType() + " block=" +
                        (block == null ? "?" : block.getName()) + " function=" +
                        (owner == null ? "-" : owner.getName(true)));
                    if (data != null) out.println("Data " + data.getAddress() + " " + data.getDataType().getName());
                    byte[] bytes = new byte[32];
                    try {
                        currentProgram.getMemory().getBytes(from, bytes);
                        out.println("Bytes " + HexFormat.of().formatHex(bytes));
                        if (block == null || block.isExecute()) continue;
                        for (int offset = -16; offset <= 32; offset += 8) {
                            Address field = from.add(offset);
                            if (!block.contains(field) || !block.contains(field.add(7))) continue;
                            long value = currentProgram.getMemory().getLong(field);
                            if (value < 0 || !currentProgram.getMemory().contains(toAddr(value))) continue;
                            Function f = getFunctionAt(toAddr(value));
                            if (f != null) out.println("Absolute candidate " + field + " -> " + f.getEntryPoint() + " " + f.getName(true));
                        }
                        for (int offset = 0; offset <= 16; offset += 4) {
                            Address field = from.add(offset);
                            if (!block.contains(field) || !block.contains(field.add(3))) continue;
                            long value = field.getOffset() + currentProgram.getMemory().getInt(field);
                            if (value < 0 || !currentProgram.getMemory().contains(toAddr(value))) continue;
                            Function f = getFunctionAt(toAddr(value));
                            if (f != null) out.println("Relative candidate " + field + " -> " + f.getEntryPoint() + " " + f.getName(true));
                        }
                    } catch (Exception e) { out.println("Unreadable neighborhood: " + e.getClass().getSimpleName()); }
                }
            }
        }
        println("ReferenceDataReport: exported " + output.getAbsolutePath());
    }
}
