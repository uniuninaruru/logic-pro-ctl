// Export selected functions' machine instructions without changing analysis.
// Usage: -postScript FunctionInstructionReport.java <output.txt> <program> <import-sha256> <entry>...
// Expected hash is the architecture-specific original import source.
// @category logicctl
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.data.StringDataInstance;
import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

public class FunctionInstructionReport extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 4 || !args[2].matches("[0-9a-fA-F]{64}"))
            throw new IllegalArgumentException("Expected output, program, import hash, and entries");
        if (!args[1].equals(currentProgram.getName()) ||
            !args[2].equalsIgnoreCase(currentProgram.getExecutableSHA256()))
            throw new IllegalArgumentException("Program/import SHA-256 mismatch");
        File output = new File(args[0]);
        File parent = output.getAbsoluteFile().getParentFile();
        if (parent != null) parent.mkdirs();
        try (PrintWriter out = new PrintWriter(output, StandardCharsets.UTF_8)) {
            out.println("# Program: " + currentProgram.getName());
            out.println("# Imported executable SHA-256: " + currentProgram.getExecutableSHA256());
            out.println("# Language: " + currentProgram.getLanguageID());
            out.println("# Instructions/bytes/references only; no runtime calls or type edits.");
            for (int i = 3; i < args.length; i++) {
                String entry = args[i].replaceFirst("^0[xX]", "");
                Function f = getFunctionAt(toAddr(entry));
                if (f == null) throw new IllegalArgumentException("No function at " + args[i]);
                out.println("\n# " + f.getName(true) + " @ " + f.getEntryPoint());
                for (Instruction ins : currentProgram.getListing().getInstructions(f.getBody(), true)) {
                    out.println(ins.getAddress() + "\t" + HexFormat.of().formatHex(ins.getBytes()) + "\t" + ins);
                    for (Reference ref : ins.getReferencesFrom()) {
                        Function callee = getFunctionAt(ref.getToAddress());
                        if (callee != null)
                            out.println("# Ref: " + ref.getToAddress() + " " + callee.getName(true));
                        Data d = currentProgram.getListing().getDefinedDataAt(ref.getToAddress());
                        if (d != null) {
                            StringDataInstance value = StringDataInstance.getStringDataInstance(d);
                            if (value != StringDataInstance.NULL_INSTANCE)
                                out.println("# String: " + ref.getToAddress() + " " + value.getStringValue());
                        }
                    }
                }
            }
        }
        println("FunctionInstructionReport: exported " + output.getAbsolutePath());
    }
}
