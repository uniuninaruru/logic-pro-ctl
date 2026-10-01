// Headless Ghidra post-script: exports the function list and decompiled C of
// functions whose name matches a regex.
//
//   analyzeHeadless <projDir> <projName> -process <program> \
//     -scriptPath Tools/ghidra -postScript ExportDecompiled.java <outDir> [nameRegex]
//
// Writes <outDir>/<program>.functions.tsv (entry, size, name, signature) and
// <outDir>/<program>.decompiled.c. Read-only: does not modify the program.
// @category logicctl

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;

import java.io.File;
import java.io.PrintWriter;
import java.util.regex.Pattern;

public class ExportDecompiled extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 1) {
            printerr("usage: ExportDecompiled.java <outDir> [nameRegex]");
            return;
        }
        File outDir = new File(args[0]);
        outDir.mkdirs();
        Pattern filter = Pattern.compile(args.length > 1 ? args[1] : ".*");
        String base = currentProgram.getName().replaceAll("[^A-Za-z0-9._-]", "_");

        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        int listed = 0, decompiled = 0;
        try (PrintWriter tsv = new PrintWriter(new File(outDir, base + ".functions.tsv"), "UTF-8");
             PrintWriter c = new PrintWriter(new File(outDir, base + ".decompiled.c"), "UTF-8")) {
            tsv.println("entry\tsize\tname\tsignature");
            c.println("// Decompiled by Ghidra " + getGhidraVersion() + " from " + currentProgram.getExecutablePath());
            c.println("// Filter: " + filter.pattern() + ". Generated; do not edit.");
            FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
            while (it.hasNext() && !monitor.isCancelled()) {
                Function f = it.next();
                String name = f.getName(true);
                tsv.printf("%s\t%d\t%s\t%s%n", f.getEntryPoint(), f.getBody().getNumAddresses(), name,
                           f.getSignature().getPrototypeString());
                listed++;
                if (!filter.matcher(name).find()) continue;
                DecompileResults r = decomp.decompileFunction(f, 60, monitor);
                c.println();
                c.println("// ==== " + name + " @ " + f.getEntryPoint());
                if (r != null && r.decompileCompleted()) {
                    c.println(r.getDecompiledFunction().getC());
                    decompiled++;
                } else {
                    c.println("// decompilation failed: " + (r == null ? "null" : r.getErrorMessage()));
                }
            }
        } finally {
            decomp.dispose();
        }
        println("ExportDecompiled: " + listed + " functions listed, " + decompiled + " decompiled -> " + outDir);
    }
}
