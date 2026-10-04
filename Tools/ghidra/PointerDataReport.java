// Read-only bounded data/pointer report. No type changes or runtime interaction.
// Usage: -postScript PointerDataReport.java <output.txt> <program> <import-sha256> <address>...
// @category logicctl
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.mem.MemoryAccessException;
import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;
import java.util.HexFormat;

public class PointerDataReport extends GhidraScript {
    private PrintWriter out;
    private final Set<String> seen = new HashSet<>();
    private void emit(Address address, int depth) throws Exception {
        if (!seen.add(address.toString())) return;
        MemoryBlock block = currentProgram.getMemory().getBlock(address);
        if (block == null || !block.isInitialized() || !block.contains(address.add(31))) {
            out.println("\n# Skipped unreadable 32-byte range @ " + address);
            return;
        }
        byte[] bytes = new byte[32];
        try {
            if (currentProgram.getMemory().getBytes(address, bytes) != bytes.length) {
                out.println("\n# Skipped incomplete 32-byte range @ " + address);
                return;
            }
        } catch (MemoryAccessException error) {
            out.println("\n# Skipped unreadable 32-byte range @ " + address);
            return;
        }
        out.println("\n# Data @ " + address + ": " + HexFormat.of().formatHex(bytes));
        Data d = currentProgram.getListing().getDefinedDataAt(address);
        if (d == null) { out.println("# No defined data"); return; }
        out.println("# " + d.getDataType().getName() + ": " + d.getDefaultValueRepresentation());
        StringDataInstance text = StringDataInstance.getStringDataInstance(d);
        if (text != StringDataInstance.NULL_INSTANCE) out.println("# String: " + text.getStringValue());
        Object value = d.getValue();
        if (depth > 0 && value instanceof Address) emit((Address) value, depth - 1);
        for (int i = 0; i < d.getNumComponents(); i++) {
            Data c = d.getComponent(i);
            out.println("# Component " + c.getAddress() + " " + c.getDataType().getName() + ": " + c.getDefaultValueRepresentation());
            Object v = c.getValue();
            if (depth > 0 && v instanceof Address) emit((Address) v, depth - 1);
        }
    }
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 4 || !args[1].equals(currentProgram.getName()) ||
            !args[2].equalsIgnoreCase(currentProgram.getExecutableSHA256()))
            throw new IllegalArgumentException("Expected matching output/program/import hash/addresses");
        File output = new File(args[0]);
        File parent = output.getAbsoluteFile().getParentFile();
        if (parent != null) parent.mkdirs();
        try (PrintWriter writer = new PrintWriter(output, StandardCharsets.UTF_8)) {
            out = writer;
            out.println("# Program: " + currentProgram.getName());
            out.println("# Imported executable SHA-256: " + currentProgram.getExecutableSHA256());
            out.println("# Defined data/pointers/strings only; depth <= 2, no mutations.");
            for (int i = 3; i < args.length; i++) emit(toAddr(args[i].replaceFirst("^0[xX]", "")), 2);
        }
        println("PointerDataReport: exported " + output.getAbsolutePath());
    }
}
