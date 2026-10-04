// Read-only: list the constant CFStrings of an analyzed program with their real text.
// Ghidra labels them `cf_<text>` with spaces and punctuation removed, so a decompiled
// `cf_LearnnewControllerAssignment` hides the text "Learn new Controller Assignment".
//
//   -postScript CfStringReport.java <output.tsv>
//
// Output columns: label, address, flags, length, text (tab/newline escaped).
// Does not decompile, change types or labels, or touch the application.
// @category logicctl

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;

public class CfStringReport extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 1) throw new IllegalArgumentException("usage: CfStringReport.java <output.tsv>");
        File output = new File(args[0]);
        File parent = output.getAbsoluteFile().getParentFile();
        if (parent != null) parent.mkdirs();
        Memory memory = currentProgram.getMemory();
        int rows = 0, skipped = 0;
        try (PrintWriter out = new PrintWriter(output, StandardCharsets.UTF_8)) {
            out.println("# Program: " + currentProgram.getName());
            out.println("# Imported executable SHA-256: " + currentProgram.getExecutableSHA256());
            out.println("# label\taddress\tflags\tlength\ttext");
            SymbolIterator symbols = currentProgram.getSymbolTable().getAllSymbols(true);
            while (symbols.hasNext() && !monitor.isCancelled()) {
                Symbol symbol = symbols.next();
                String label = symbol.getName();
                if (!label.startsWith("cf_")) continue;
                try {
                    Address at = symbol.getAddress();
                    long flags = memory.getLong(at.add(8));
                    long chars = memory.getLong(at.add(16)) & 0xFFFFFFFFFL;
                    long length = memory.getLong(at.add(24));
                    if (length < 0 || length > 4096) { skipped++; continue; }
                    // Flags bit 0x10 marks a UTF-16 CFString, whose length counts UTF-16 units.
                    boolean utf16 = (flags & 0x10) != 0;
                    byte[] bytes = new byte[(int) length * (utf16 ? 2 : 1)];
                    memory.getBytes(toAddr(chars), bytes);
                    String text = new String(bytes, utf16 ? StandardCharsets.UTF_16LE : StandardCharsets.UTF_8);
                    out.println(label + "\t" + at + "\t0x" + Long.toHexString(flags) + "\t" + length + "\t"
                            + text.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n"));
                    rows++;
                } catch (Exception e) {
                    skipped++;
                }
            }
        }
        println("CfStringReport: " + rows + " rows, " + skipped + " skipped -> " + output);
    }
}
